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
--
--tx_selector = '0' --> TX1
--tx_selector = '1' --> TX2 

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library UNISIM;
use UNISIM.VComponents.all;
library xpm;
use xpm.vcomponents.all;

entity ads6422_lvds_if is
    generic(
        Adc_Wire_Interface:         integer := 1;
        Adc_Num_Channels:           integer := 4;
        OnChip_LVDS_Termination:    integer := 1;
        Adc_Resolution:             integer := 12;
        Adc_Valid_Start_Time:       integer := 5000;--5 us = 5000 ns
        Adc_Sample_Period:          integer := 50--50 ns
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
        
        tx_selector:            out std_logic;--Transmisor que debe utilizar el proximo chirp
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
end ads6422_lvds_if;

architecture Behavioral of ads6422_lvds_if is

--Constant Declaration
constant Low: integer:= 0;
constant High: integer:=1;
constant NUM_DATA_LANES: integer:= (Adc_Num_Channels*Adc_Wire_Interface);
constant PAIRS_PER_SAMPLE : integer := Adc_Resolution / 2;
constant N_Invalid: integer:= Adc_Valid_Start_Time / Adc_Sample_Period;

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
signal data_rising_edge: std_logic_vector(NUM_DATA_LANES-1 downto 0);
signal data_falling_edge: std_logic_vector(NUM_DATA_LANES-1 downto 0);

--reset signal synchronization signals
signal sync_aresetn_dclk_bufg: std_logic;

--bufg synchronization signals
signal data_rising_edge_bufg: std_logic_vector((Adc_Num_Channels * Adc_Wire_Interface)-1 downto 0);
signal data_falling_edge_bufg: std_logic_vector((Adc_Num_Channels * Adc_Wire_Interface)-1 downto 0);

--shift register signals
type sample_array_t is array (0 to 3) of std_logic_vector((Adc_Resolution - 1) downto 0);

---------------------------------------------------------------------------
-- Sincronización de muxout y selección TDM
---------------------------------------------------------------------------
signal muxout_sync_reg: std_logic_vector(1 downto 0);
attribute ASYNC_REG : string;
attribute ASYNC_REG of muxout_sync_reg : signal is "TRUE";--Este atributo informa a vivado que estos registros
signal muxout_dclk_bufg: std_logic;                       --forman un sincronizador y ayuda a mantener los FFs juntos
signal muxout_reg:  std_logic;                            
signal mux_select: std_logic:= '0';--Selector del multiplexador TDM
signal muxout_valid: std_logic:='0';
---------------------------------------------------------------------------
--Alineamiento de FCLK con DCLK
---------------------------------------------------------------------------
signal fclk_rising_edge, fclk_falling_edge: std_logic;
signal fclk_rising_edge_bufg, fclk_falling_edge_bufg: std_logic;
signal frame_start: std_logic;
signal fclk_sample_bufg   : std_logic := '0';
signal fclk_sample_bufg_d : std_logic := '0';
signal fclk_edge_armed: std_logic:='0';
---------------------------------------------------------------------------
-- Reconstrucción de muestras
---------------------------------------------------------------------------
signal collecting: std_logic;
signal shift_reg: sample_array_t;
signal pair_count   : integer range 0 to 6;
signal sample:  sample_array_t;
signal sample_counter: integer range 0 to (N_invalid - 1);
signal ADC_Sampling: std_logic:='0';--Indica si las muestras son válidas, es decir, nos encontramos dentro del ADC Sampling Time

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
--=========================================================================================================
--Los reset asíncronos pueden ser problemáticos, sobre todo durante la liberación del reset. 
--Si la señal de reset se desactiva / libera cerca del flanco del reloj no queda claro si la lógica
--responderá al flanco de reloj. Además, debido al delay existente entre registros, puede ser 
--que algunos registros se actualicen con la señal de reloj y otros no. 
--Para solucionar esto podemos emplear un reloj que sea asíncrono en assertation, pero síncrono con 
--el reloj de turno en deassertation. Podemos emplear para ello un macro llamado XPM_CDC_ASYNC_RST 
--=========================================================================================================
RESET_SYNC_DCLK_BUFG_inst : xpm_cdc_async_rst
generic map (
  DEST_SYNC_FF => 4,    -- DECIMAL; range: 2-10
  INIT_SYNC_FF => 0,    -- DECIMAL; 0=disable simulation init values, 1=enable simulation init values
  RST_ACTIVE_HIGH => 0  -- DECIMAL; 0=active low reset, 1=active high reset
)
port map (
  dest_arst => sync_aresetn_dclk_bufg, -- 1-bit output: src_arst asynchronous reset signal synchronized to destination
                          -- clock domain. This output is registered. NOTE: Signal asserts asynchronously
                          -- but deasserts synchronously to dest_clk. Width of the reset signal is at least
                          -- (DEST_SYNC_FF*dest_clk) period.

  dest_clk => dclk_bufg,   -- 1-bit input: Destination clock.
  src_arst => aresetn    -- 1-bit input: Source asynchronous reset signal.
);
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
      R => '0',
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
      R => '0',
      S => '0'    -- 1-bit set
      );
      
 --Detección de inicio de frame
 --No podemos usar dclk_bufio, necesitamos registrarlos en el dominio de BUFG
 
FRAME_START_process :--Detecta el flanco de subida de FCLK
process(dclk_bufg, sync_aresetn_dclk_bufg)
begin
    if sync_aresetn_dclk_bufg = '0' then

        fclk_sample_bufg   <= '0';
        fclk_sample_bufg_d <= '0';
        frame_start        <= '0';
        fclk_edge_armed    <= '0';
    elsif rising_edge(dclk_bufg) then

        fclk_sample_bufg <= fclk_rising_edge;
        fclk_sample_bufg_d <= fclk_sample_bufg;

        if fclk_edge_armed = '0' then
        --Miramos si fclk está a nivel bajo, si lo está activamos el detector de flanco
            if fclk_sample_bufg = '0' then
                fclk_edge_armed <= '1';
            end if;
        else
            if fclk_sample_bufg = '1' and fclk_sample_bufg_d = '0' then
                frame_start <= '1';
            else
                frame_start <= '0';
            end if;
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

tx_selector <= mux_select;--Escribimos desde el PS por SPI los registros del ADF5902 para alternar la antena transmisora
MUX_Select_Process: process(dclk_bufg, sync_aresetn_dclk_bufg)
begin
    if sync_aresetn_dclk_bufg = '0' then
        muxout_sync_reg  <= (others => '0');
        muxout_dclk_bufg <= '0';
        muxout_reg       <= '0';
        mux_select       <= '0';--Estamos suponiendo que si reseteamos la primera rampa se corresponderá con TX1. Debemos alinear el reset con el ADF5902
        muxout_valid     <= '0';
    elsif rising_edge(dclk_bufg) then
        
        muxout_valid <= '0';
        muxout_sync_reg(0) <= muxout;
        muxout_sync_reg(1) <= muxout_sync_reg(0);
        muxout_dclk_bufg   <= muxout_sync_reg(1);
        muxout_reg <= muxout_dclk_bufg;
        
        if muxout_dclk_bufg = '1' and muxout_reg = '0' then
            mux_select <= not mux_select;
            muxout_valid <= '1';--Inicia el AVST
        end if;
    end if;
end process;
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
        shift_reg  <= (others => (others => '0'));
        sample     <= (others => (others => '0'));
        pair_count <= 0;

        sample_counter <= 0;
        Adc_Sampling   <= '0';

        adc_data_valid_tx1 <= '0';
        adc_data_valid_tx2 <= '0';

    elsif rising_edge(dclk_bufg) then

        -- Los pulsos de validación duran un único ciclo.
        adc_data_valid_tx1 <= '0';
        adc_data_valid_tx2 <= '0';

        next_shift := shift_reg;

        ----------------------------------------------------------------
        -- Inicio de una nueva rampa.
        -- Se reinicia el AVST y se cancela cualquier muestra incompleta.
        ----------------------------------------------------------------
        if muxout_valid = '1' then

            Adc_Sampling   <= '0';
            sample_counter <= 0;
            collecting     <= '0';
            pair_count     <= 0;

        ----------------------------------------------------------------
        -- Primera pareja de bits de una muestra nueva.
        ----------------------------------------------------------------
        elsif frame_start = '1' then

            next_shift := (others => (others => '0'));

            for channel in 0 to Adc_Num_Channels - 1 loop
                next_shift(channel) :=
                    next_shift(channel)(Adc_Resolution - 3 downto 0) &
                    data_rising_edge_bufg(channel) &
                    data_falling_edge_bufg(channel);
            end loop;

            shift_reg <= next_shift;
            collecting <= '1';

            -- Ya se ha capturado la primera pareja de bits.
            pair_count <= 1;

        ----------------------------------------------------------------
        -- Continuación de la reconstrucción de la muestra.
        ----------------------------------------------------------------
        elsif collecting = '1' then

            for channel in 0 to Adc_Num_Channels - 1 loop
                next_shift(channel) :=
                    next_shift(channel)(Adc_Resolution - 3 downto 0) &
                    data_rising_edge_bufg(channel) &
                    data_falling_edge_bufg(channel);
            end loop;

            shift_reg <= next_shift;

            ----------------------------------------------------------------
            -- El par actual completa la muestra.
            ----------------------------------------------------------------
            if pair_count = PAIRS_PER_SAMPLE - 1 then

                sample <= next_shift;

                ------------------------------------------------------------
                -- Durante el AVST se descartan muestras completas.
                ------------------------------------------------------------
                if Adc_Sampling = '0' then

                    if sample_counter = N_Invalid - 1 then

                        -- Esta es la última muestra descartada.
                        -- La siguiente muestra será válida.
                        sample_counter <= 0;
                        Adc_Sampling   <= '1';

                    else
                        sample_counter <= sample_counter + 1;
                    end if;

                ------------------------------------------------------------
                -- AVST terminado: la muestra actual es válida.
                ------------------------------------------------------------
                else

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
