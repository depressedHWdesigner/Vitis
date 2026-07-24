--Empleamos TDM para multiplexar chirps de la antena TX1 con chirps de la antena TX2
--El IC ADF5904 proporciona cuatro canales diferenciales, pero virtualmente debemos de generar 
--8 salidas de datos: 4 canales de IF de TX1 y 4 canales de IF de TX2
--Convierte señales de entrada differential a single-ended.
--Registra los bits de cada canal empleando IDDR.
--Combina las salidas de cada IDDR en muestras para cada canal.
--ADC configurado para sacar los datos MSB first
--TDM:
--     mux_select = '0' -> TX1
--     mux_select = '1' -> TX2
--
--|      /|        /|
--|    /  |      /  |
--|  /    |    /    |
--|/  TX1 |--/  TX2 |
--|--------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library UNISIM;
use UNISIM.VComponents.all;

entity ADC_IO is
    generic(
        Adc_Wire_Interface:         integer:= 1;--2 = 2-Wire, 1 = 1-Wire
        Adc_Num_Channels:           integer:=4;--El adc saca 4 canales diferenciales
        OnChip_LVDS_Termination:    integer:=1;--0 = No termination, 1-Termination ON. Activa o desactiva resistencia de terminación paralela   
        Adc_Resolution:             integer:=12
    );
    Port (
        aresetn:                in std_logic;
        muxout:                 in std_logic;--Indica inicio de cada rampa
        fclk_p_IN:              in std_logic;--FCLK. Frame Clock
        fclk_n_IN:              in std_logic;
        dclk_p_IN:              in std_logic;--DCLK. Data Clock
        dclk_n_IN:              in std_logic;
        data_p_IN:              in std_logic_vector((Adc_Num_Channels*Adc_Wire_Interface)-1 downto 0);
        data_n_IN:              in std_logic_vector((Adc_Num_Channels*Adc_Wire_Interface)-1 downto 0);
        
        dclk_buffered:          out std_logic;--Buffered 120 MHz clock 
        data_ch1_tx1:           out std_logic_vector((Adc_Resolution - 1) downto 0);--Sampled data from ch1 corresponding to tx1 antenna
        data_ch1_tx2:           out std_logic_vector((Adc_Resolution - 1) downto 0);--Sampled data from ch1 corresponding to tx2 antenna
        data_ch2_tx1:           out std_logic_vector((Adc_Resolution - 1) downto 0);--Sampled data from ch2 corresponding to tx1 antenna
        data_ch2_tx2:           out std_logic_vector((Adc_Resolution - 1) downto 0);--Sampled data from ch2 corresponding to tx2 antenna     
        data_ch3_tx1:           out std_logic_vector((Adc_Resolution - 1) downto 0);--Sampled data from ch3 corresponding to tx1 antenna
        data_ch3_tx2:           out std_logic_vector((Adc_Resolution - 1) downto 0);--Sampled data from ch3 corresponding to tx2 antenna
        data_ch4_tx1:           out std_logic_vector((Adc_Resolution - 1) downto 0);--Sampled data from ch4 corresponding to tx1 antenna
        data_ch4_tx2:           out std_logic_vector((Adc_Resolution - 1) downto 0);--Sampled data from ch4 corresponding to tx2 antenna
        adc_data_valid_tx1:     out std_logic;  
        adc_data_valid_tx2:     out std_logic
  );
end ADC_IO;

architecture Behavioral of ADC_IO is

--Constant Declaration
constant Low: integer:= 0;
constant High: integer:=1;
constant NUM_DATA_LANES: integer:= (Adc_Num_Channels*Adc_Wire_Interface);
constant PAIRS_PER_SAMPLE : integer := Adc_Resolution / 2;

function ConvTrueFalse(Term: integer) return boolean is -- Esta funcion la empleamos para automatizar si hay terminacion o no al instanciar los buffers
begin
    if (Term = 0) then
        return FALSE;
    else
        return TRUE;
    end if;   
end ConvTrueFalse;

--Signal Declaration
signal dclk: std_logic;--Bit Clk single ended
signal fclk: std_logic;--Frame Clk single ended
signal data_ibuf: std_logic_vector((Adc_Num_Channels * Adc_Wire_Interface)-1 downto 0);

signal dclk_bufio: std_logic;
signal dclk_bufg: std_logic;

--IDDR
signal IDDR_reset: std_logic;
signal data_rising_edge: std_logic_vector(NUM_DATA_LANES-1 downto 0);
signal data_falling_edge: std_logic_vector(NUM_DATA_LANES-1 downto 0);

--reset signal synchronization signals
signal aresetn_reg_dclk_bufio, aresetn_reg_dclk_bufg, aresetn_reg_fclk: std_logic_vector(1 downto 0):=(others => '0');
signal sync_aresetn_dclk_bufio, sync_aresetn_dclk_bufg,sync_resetn_fclk: std_logic;

--bufg synchronization signals
signal data_rising_edge_bufg: std_logic_vector((Adc_Num_Channels * Adc_Wire_Interface)-1 downto 0);
signal data_falling_edge_bufg: std_logic_vector((Adc_Num_Channels * Adc_Wire_Interface)-1 downto 0);

--shift register signals
type shift_reg_array_t is array (0 to 3) of std_logic_vector((Adc_Resolution - 1) downto 0);
signal shift_reg_array : shift_reg_array_t := (others => (others => '0'));
type sample_array_t is array (0 to 3) of std_logic_vector((Adc_Resolution - 1) downto 0);
signal sample_array : sample_array_t := (others => (others => '0'));
---------------------------------------------------------------------------
-- Sincronización de muxout y selección TDM
---------------------------------------------------------------------------
signal muxout_sync_reg: std_logic_vector(1 downto 0);
signal muxout_dclk_bufg: std_logic;
signal muxout_reg:  std_logic;
signal muxout_valid:    std_logic;
signal mux_select: std_logic:= '0';--Selector del multiplexador TDM

---------------------------------------------------------------------------
--Alineamiento de FCLK con DCLK
---------------------------------------------------------------------------
signal fclk_rising_edge, fclk_falling_edge: std_logic;
signal fclk_rising_edge_bufg, fclk_falling_edge_bufg: std_logic;
signal frame_start: std_logic;
signal fclk_sample_bufg   : std_logic := '0';
signal fclk_sample_bufg_d : std_logic := '0';
---------------------------------------------------------------------------
-- Reconstrucción de muestras
---------------------------------------------------------------------------
signal collecting: std_logic;
--signal shift_reg: std_logic_vector(11 downto 0);
signal shift_reg: sample_array_t;
signal pair_count   : integer range 0 to 6;
--signal sample        : std_logic_vector(11 downto 0);
signal sample:  sample_array_t;
signal sample_valid  : std_logic;
signal bit_index : integer range 0 to 10 := 0;
signal sample_buffer : sample_array_t;



begin

--Instanciamos elecrtical converters para pasar de una señal diferencial a una single ended interna en la PL fabric
--1) Clock Buffers
IBUFGDS_dclk: IBUFDS
   generic map (
      DIFF_TERM => ConvTrueFalse(OnChip_LVDS_Termination), -- Differential Termination 
      IBUF_LOW_PWR => FALSE, -- Low power (TRUE) vs. performance (FALSE) setting for referenced I/O standards
      IOSTANDARD => "LVDS_25")
   port map (
      O =>  dclk,       -- Buffer output
      I =>  dclk_p_IN,  -- Diff_p buffer input (connect directly to top-level port)
      IB => dclk_n_IN   -- Diff_n buffer input (connect directly to top-level port)
   );
   
IBUFGDS_fclk: IBUFDS
   generic map (
      DIFF_TERM => ConvTrueFalse(OnChip_LVDS_Termination), -- Differential Termination 
      IBUF_LOW_PWR => FALSE, -- Low power (TRUE) vs. performance (FALSE) setting for referenced I/O standards
      IOSTANDARD => "LVDS_25")
   port map (
      O =>  fclk,       -- Buffer output
      I =>  fclk_p_IN,  -- Diff_p buffer input (connect directly to top-level port)
      IB => fclk_n_IN   -- Diff_n buffer input (connect directly to top-level port)
   );
   
--Las señales de reloj se distribuyen a parte de las señales internas de la FPGA. 
--=========================================================================================================
--Estrategia para clock buffering en la interfaz source-synchronous   
--
--BUFIO: Proporciona un camino corto y de bajo skew del reloj a los recursos de captura IO
--       El reloj DCLK alcanza los registros IDDR a través de enrutado de reloj IO dedicado
--  
--BUFG/R: El BUFIO solo puede drivear recursos en el mismo banco, para el resto de lógica empleamos BUFG/R
--=========================================================================================================

BUFIO_inst : BUFIO
port map (
      O => dclk_bufio, -- 1-bit output: Clock output (connect to I/O clock loads).
      I => dclk        -- 1-bit input: Clock input (connect to an IBUF or BUFMR).
);
BUFG_dclk : BUFG
   port map (
      O => dclk_bufg, -- 1-bit output: Clock output
      I => dclk       -- 1-bit input: Clock input
);

dclk_buffered <= dclk_bufg;

--Proceso de sincronización de reset con el dominio del reloj
reset_dclk_bufio_process: process(dclk_bufio)
begin
    if rising_edge(dclk_bufio) then
        aresetn_reg_dclk_bufio(0)<= aresetn;
        aresetn_reg_dclk_bufio(1) <= aresetn_reg_dclk_bufio(0);
    end if;
end process reset_dclk_bufio_process;
sync_aresetn_dclk_bufio <= aresetn_reg_dclk_bufio(1);
IDDR_reset <= not(sync_aresetn_dclk_bufio);--Reset IDDR es activo a nivel alto

reset_dclk_bufg_process: process(dclk_bufg)
begin
    if rising_edge(dclk_bufg) then
        aresetn_reg_dclk_bufg(0)<= aresetn;
        aresetn_reg_dclk_bufg(1) <= aresetn_reg_dclk_bufg(0);
    end if;
end process reset_dclk_bufg_process;
sync_aresetn_dclk_bufg <= aresetn_reg_dclk_bufg(1);

--2) Data Buffers
--Generamos los data buffers usando un bucle for
DATA_IBUFDS: for channel in (NUM_DATA_LANES - 1) downto 0 generate
    ADC_IBUFDS_DATA_IN: IBUFDS
        generic map(
            DIFF_TERM => ConvTrueFalse(OnChip_LVDS_Termination),
            IOSTANDARD =>"LVDS_25"
            )
        port map(
            I => data_p_IN(channel),
            IB => data_n_IN(channel),
            O => data_ibuf(channel)--data_ibuf(0) será la señal single ended del canal 0
        );
end generate DATA_IBUFDS;


--IDDR para capturar datos DDR
DATA_IDDR: for channel in (NUM_DATA_LANES - 1) downto 0 generate--Necesitamos 6 ciclos de reloj de DCLK para registrar los 12 bits de cada sample
   IDDR_inst : IDDR 
   generic map (
      DDR_CLK_EDGE => "SAME_EDGE_PIPELINED", -- "OPPOSITE_EDGE", "SAME_EDGE" 
                                       -- or "SAME_EDGE_PIPELINED" 
      INIT_Q1 => '0', -- Initial value of Q1: '0' or '1'
      INIT_Q2 => '0', -- Initial value of Q2: '0' or '1'
      SRTYPE => "SYNC") -- Set/Reset type: "SYNC" or "ASYNC" 
   port map (
      Q1 => data_rising_edge(channel), -- 1-bit output for positive edge of clock 
      Q2 => data_falling_edge(channel), -- 1-bit output for negative edge of clock
      C => dclk_bufio,   -- 1-bit clock input
      CE => '1' , -- 1-bit clock enable input
      D => data_ibuf(channel),   -- 1-bit DDR data input
      R => IDDR_reset,   -- 1-bit reset
      S => '0'    -- 1-bit set
      );
 end generate DATA_IDDR;   
 
--Necesitamos alinear FCLK con DCLK para construir cada muestra
--Empleamos para ello otro IDDR que emplea DCLK como reloj y tratamos FCLK como un dato

FCKL_IDDR:  IDDR 
   generic map (
      DDR_CLK_EDGE => "OPPOSITE_EDGE", -- "OPPOSITE_EDGE", "SAME_EDGE" 
                                       -- or "SAME_EDGE_PIPELINED" 
      INIT_Q1 => '0', -- Initial value of Q1: '0' or '1'
      INIT_Q2 => '0', -- Initial value of Q2: '0' or '1'
      SRTYPE => "SYNC") -- Set/Reset type: "SYNC" or "ASYNC" 
   port map (
      Q1 => fclk_rising_edge, -- 1-bit output for positive edge of clock 
      Q2 => fclk_falling_edge, -- 1-bit output for negative edge of clock
      C => dclk_bufio,   -- 1-bit clock input
      CE => '1' , -- 1-bit clock enable input
      D => fclk,   -- 1-bit DDR data input
      R => IDDR_reset,   -- 1-bit reset
      S => '0'    -- 1-bit set
      );
      
 --Detección de inicio de frame
 --No podemos usar dclk_bufio, necesitamos registrarlos en el dominio de BUFG
 
FRAME_START_process :
process(dclk_bufg, sync_aresetn_dclk_bufg)
begin
    if sync_aresetn_dclk_bufg = '0' then

        fclk_sample_bufg   <= '0';
        fclk_sample_bufg_d <= '0';
        frame_start        <= '0';

    elsif rising_edge(dclk_bufg) then

        -- Registrar una de las salidas del IDDR
        fclk_sample_bufg <= fclk_rising_edge;

        -- Guardar la muestra anterior
        fclk_sample_bufg_d <= fclk_sample_bufg;

        -- Detectar transición 0 -> 1 entre muestras consecutivas
        if fclk_sample_bufg = '1' and
           fclk_sample_bufg_d = '0' then

            frame_start <= '1';

        else
            frame_start <= '0';
        end if;

    end if;
end process FRAME_START_process;

 --============================================================================================================
 --Re-registramos las salidas de los IDDR en el dominio de reloj BUFG
 --IDDR configurado como SAME_EDGE_PIPELINED produce salidas estables durante un cyclo completo de reloj
 --BUFIO y BUFG se derivan de la misma fuente DCLK de modo que tienen la misma frecuencia. Este nuevo registro
 --transfiere de IOB (BUFIO) a FPGA fabric (BUFG)
 --============================================================================================================
BUFG_Synchronization_process: process(dclk_bufg)
begin 
    if rising_edge(dclk_bufg) then
        data_rising_edge_bufg  <= data_rising_edge;
        data_falling_edge_bufg <= data_falling_edge;
    end if;
end process BUFG_Synchronization_process;


MUX_Select_Process: process(dclk_bufg, sync_aresetn_dclk_bufg)--Alterna la salida de un multiplexor 1:2 en funcion de la señal muxout para habilitar TDM   
begin
    if sync_aresetn_dclk_bufg = '0' then
        muxout_reg <= '0';
        muxout_valid <= '0';
        muxout_sync_reg <= (others => '0');
        muxout_dclk_bufg <= '0';
    elsif rising_edge(dclk_bufg) then
    --3 FF Synchronization
        muxout_sync_reg(0) <= muxout;
        muxout_sync_reg(1) <= muxout_sync_reg(0);
        muxout_dclk_bufg <= muxout_sync_reg(1);
        muxout_reg <= muxout_dclk_bufg;
        
        if muxout_valid = '1' then
            mux_select <= not(mux_select);
        end if;
    end if;
    muxout_valid <= muxout_dclk_bufg and not(muxout_reg);
end process MUX_Select_Process;

--============================================================================================================
--Combinamos rising y falling edge en una sola palabra
--IDDR saca los bits pares en Q1 y los impares en Q2. Empleando un shift register metemos en cada ciclo
--2 pares de bits de modo que al cabo de 6 ciclos tenemos una muestra completa
--============================================================================================================

SAMPLER_FORMER_process :
process(dclk_bufg, sync_aresetn_dclk_bufg)
    variable next_shift : sample_array_t;
begin
    if sync_aresetn_dclk_bufg = '0' then

        collecting <= '0';

        shift_reg <= (others => (others => '0'));
        sample    <= (others => (others => '0'));

        pair_count <= 0;

        adc_data_valid_tx1 <= '0';
        adc_data_valid_tx2 <= '0';

    elsif rising_edge(dclk_bufg) then

        adc_data_valid_tx1 <= '0';
        adc_data_valid_tx2 <= '0';

        -- Valor inicial de trabajo para este ciclo.
        next_shift := shift_reg;

        if frame_start = '1' then

            --------------------------------------------------------
            -- Primera pareja de bits de una muestra nueva
            --------------------------------------------------------

            next_shift := (others => (others => '0'));

            for channel in 0 to Adc_Num_Channels - 1 loop
                next_shift(channel) :=
                    next_shift(channel)(Adc_Resolution - 3 downto 0) &
                    data_rising_edge_bufg(channel) &
                    data_falling_edge_bufg(channel);
            end loop;

            shift_reg <= next_shift;

            collecting <= '1';

            -- Ya hemos capturado el primer par.
            pair_count <= 1;

        elsif collecting = '1' then

            --------------------------------------------------------
            -- Parejas de bits restantes
            --------------------------------------------------------

            for channel in 0 to Adc_Num_Channels - 1 loop
                next_shift(channel) :=
                    next_shift(channel)(Adc_Resolution - 3 downto 0) &
                    data_rising_edge_bufg(channel) &
                    data_falling_edge_bufg(channel);
            end loop;

            shift_reg <= next_shift;

            --------------------------------------------------------
            -- Antes de este ciclo ya había cinco pares.
            -- El par actual completa los 12 bits.
            --------------------------------------------------------

            if pair_count = PAIRS_PER_SAMPLE - 1 then

                sample <= next_shift;

                if mux_select = '0' then

                    data_ch1_tx1 <= next_shift(0);
                    data_ch2_tx1 <= next_shift(1);
                    data_ch3_tx1 <= next_shift(2);
                    data_ch4_tx1 <= next_shift(3);

                    adc_data_valid_tx1 <= '1';

                else

                    data_ch1_tx2 <= next_shift(0);
                    data_ch2_tx2 <= next_shift(1);
                    data_ch3_tx2 <= next_shift(2);
                    data_ch4_tx2 <= next_shift(3);

                    adc_data_valid_tx2 <= '1';

                end if;

                collecting <= '0';
                pair_count <= 0;

            else
                pair_count <= pair_count + 1;
            end if;

        end if;
    end if;
end process SAMPLER_FORMER_process;

end Behavioral;
