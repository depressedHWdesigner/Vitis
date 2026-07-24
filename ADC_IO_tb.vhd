
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library UNISIM;
use UNISIM.VComponents.all;

entity ADC_IO_tb is
--  Port ( );
end ADC_IO_tb;

architecture Behavioral of ADC_IO_tb is

--Component declaration

component ADC_IO is 
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
  end component;

--Constant declaration
constant Adc_Wire_Interface: integer:= 1;
constant Adc_Num_Channels: integer:=4;
constant Adc_Resolution: integer:=12;
constant fclk_period     : time := 50 ns;
constant dclk_period     : time := fclk_period / 6;
constant data_bit_period : time := fclk_period / 12;
constant dclk_phase      : time := dclk_period / 4;
constant muxout_pulse_width : time := fclk_period / 2;
constant aresetn_assert  : time := 20 ns;

--Patrones de prueba
constant DATA_0A : std_logic_vector(11 downto 0) := x"A01";--Dato que deberia de aparecer en la salida data_CH1_TX1
constant DATA_1A : std_logic_vector(11 downto 0) := x"A02";--Dato que deberia de aparecer en la salida data_CH2_TX1
constant DATA_2A : std_logic_vector(11 downto 0) := x"A03";--Dato que deberia de aparecer en la salida data_CH3_TX1
constant DATA_3A : std_logic_vector(11 downto 0) := x"A04";--Dato que deberia de aparecer en la salida data_CH4_TX1

constant DATA_0B : std_logic_vector(11 downto 0) := x"B01";--Dato que deberia de aparecer en la salida data_CH1_TX2
constant DATA_1B : std_logic_vector(11 downto 0) := x"B02";--Dato que deberia de aparecer en la salida data_CH2_TX2
constant DATA_2B : std_logic_vector(11 downto 0) := x"B03";--Dato que deberia de aparecer en la salida data_CH3_TX2
constant DATA_3B : std_logic_vector(11 downto 0) := x"B04";--Dato que deberia de aparecer en la salida data_CH4_TX2

--Signal declaration
signal fclk_p    : std_logic := '0';
signal fclk_n    : std_logic := '1';
signal dclk_p    : std_logic := '0';
signal dclk_n    : std_logic := '1';

signal aresetn   : std_logic := '0';
signal tb_muxout : std_logic := '0';
signal tb_data_p : std_logic_vector((Adc_Num_Channels * Adc_Wire_Interface) - 1 downto 0) := (others => '0');
signal tb_data_n : std_logic_vector((Adc_Num_Channels * Adc_Wire_Interface) - 1 downto 0) := (others => '1');

signal dclk_buffered: std_logic;
signal tb_data_ch1_tx1: std_logic_vector((Adc_Resolution - 1) downto 0);
signal tb_data_ch1_tx2: std_logic_vector((Adc_Resolution - 1) downto 0);
signal tb_data_ch2_tx1: std_logic_vector((Adc_Resolution - 1) downto 0);
signal tb_data_ch2_tx2: std_logic_vector((Adc_Resolution - 1) downto 0);
signal tb_data_ch3_tx1: std_logic_vector((Adc_Resolution - 1) downto 0);
signal tb_data_ch3_tx2: std_logic_vector((Adc_Resolution - 1) downto 0);
signal tb_data_ch4_tx1: std_logic_vector((Adc_Resolution - 1) downto 0);
signal tb_data_ch4_tx2: std_logic_vector((Adc_Resolution - 1) downto 0);
signal tb_adc_data_valid_tx1: std_logic;
signal tb_adc_data_valid_tx2: std_logic;

--Procedimiento de muxout
procedure generate_muxout_pulse (
    signal muxout_signal : out std_logic
) is
begin
    muxout_signal <=
        '1',
        '0' after muxout_pulse_width;
end procedure;
--Procedimiento para cargar datos en el modulo ADC_IO
procedure send_adc_sample (
    signal fclk   : in  std_logic;
    signal data_p : out std_logic_vector(
        (Adc_Num_Channels * Adc_Wire_Interface) - 1 downto 0
    );

    constant ch1_word : in std_logic_vector(Adc_Resolution - 1 downto 0);
    constant ch2_word : in std_logic_vector(Adc_Resolution - 1 downto 0);
    constant ch3_word : in std_logic_vector(Adc_Resolution - 1 downto 0);
    constant ch4_word : in std_logic_vector(Adc_Resolution - 1 downto 0)
) is
begin
    -- El flanco ascendente de FCLK marca el comienzo del MSB.
    wait until rising_edge(fclk);

    -- Transmisión MSB first.
    for bit_index in Adc_Resolution - 1 downto 0 loop

        data_p(0) <= ch1_word(bit_index);
        data_p(1) <= ch2_word(bit_index);
        data_p(2) <= ch3_word(bit_index);
        data_p(3) <= ch4_word(bit_index);

        -- No esperamos después del último bit.
        -- Así el procedimiento termina antes del siguiente FCLK.
       if bit_index > 0 then
            -- Avanzar hasta el comienzo del siguiente bit
            wait for data_bit_period;
       else
            -- Esperar hasta el centro del LSB, donde lo captura DCLK
            wait for data_bit_period / 2;
    end if;

    end loop;
end procedure;

begin

--Mapping
ADC_Module: ADC_IO 
    generic map (
        Adc_Wire_Interface      => Adc_Wire_Interface,
        Adc_Num_Channels        => Adc_Num_Channels,
        OnChip_LVDS_Termination => 1,
        Adc_Resolution          => Adc_Resolution
    )
    port map(
        aresetn            => aresetn,
        muxout             => tb_muxout,
        fclk_p_IN          => fclk_p,
        fclk_n_IN          => fclk_n,
        dclk_p_IN          => dclk_p, 
        dclk_n_IN          => dclk_n, 
        data_p_IN          => tb_data_p,
        data_n_IN          => tb_data_n,
        dclk_buffered      => dclk_buffered, 
        data_ch1_tx1       => tb_data_ch1_tx1,
        data_ch1_tx2       => tb_data_ch1_tx2,
        data_ch2_tx1       => tb_data_ch2_tx1,
        data_ch2_tx2       => tb_data_ch2_tx2,  
        data_ch3_tx1       => tb_data_ch3_tx1,
        data_ch3_tx2       => tb_data_ch3_tx2,
        data_ch4_tx1       => tb_data_ch4_tx1,
        data_ch4_tx2       => tb_data_ch4_tx2,
        adc_data_valid_tx1 => tb_adc_data_valid_tx1,
        adc_data_valid_tx2 => tb_adc_data_valid_tx2
);
--FCLK generation 20 MHz
fclk_process: process
begin
    fclk_p <= '0';
    wait for fclk_period/2;
    fclk_p <= '1';
    wait for fclk_period/2;
end process fclk_process;
fclk_n <= not(fclk_p);

-- DCLK generation: 120 MHz, synchronized with FCLK
-- First rising edge occurs one quarter DCLK period after FCLK rising edge.
dclk_process : process
    variable dclk_value : std_logic;
begin
    dclk_value := '0';
    dclk_p     <= '0';

    loop
        -- Beginning of a new ADC sample
        wait until rising_edge(fclk_p);

        dclk_value := '0';
        dclk_p     <= '0';

        -- Place first DCLK rising edge in the middle of the MSB
        wait for dclk_phase;

        -- Twelve DCLK edges capture twelve DDR bits
        for edge_index in 0 to Adc_Resolution - 1 loop
            dclk_value := not dclk_value;
            dclk_p     <= dclk_value;

            if edge_index < Adc_Resolution - 1 then
                wait for data_bit_period;
            end if;
        end loop;
    end loop;
end process dclk_process;

dclk_n <= not dclk_p;

--Asynchronous reset generation
aresetn_process : process
begin
    aresetn <= '0';
    wait for aresetn_assert;
    wait until rising_edge(dclk_p);
    -- Este instante queda justo entre dos flancos de DCLK.
    wait for dclk_period / 4;
    aresetn <= '1';
    wait;
end process aresetn_process;

-- Data generation
data_process : process
begin
    tb_data_p <= (others => '0');
    tb_muxout <= '0';

    ----------------------------------------------------------------
    -- Esperar a que termine el reset
    ----------------------------------------------------------------
    wait until aresetn = '1';

    ----------------------------------------------------------------
    -- Fuente inicial: TX1
    ----------------------------------------------------------------
    for sample_index in 0 to 3 loop
        send_adc_sample(
            fclk     => fclk_p,
            data_p   => tb_data_p,
            ch1_word => DATA_0A,
            ch2_word => DATA_1A,
            ch3_word => DATA_2A,
            ch4_word => DATA_3A
        );
    end loop;

    ----------------------------------------------------------------
    -- Cambio TX1 -> TX2
    ----------------------------------------------------------------
    generate_muxout_pulse(tb_muxout);

    for sample_index in 0 to 3 loop
        send_adc_sample(
            fclk     => fclk_p,
            data_p   => tb_data_p,
            ch1_word => DATA_0B,
            ch2_word => DATA_1B,
            ch3_word => DATA_2B,
            ch4_word => DATA_3B
        );
    end loop;

    ----------------------------------------------------------------
    -- Cambio TX2 -> TX1
    ----------------------------------------------------------------
    generate_muxout_pulse(tb_muxout);

    for sample_index in 0 to 3 loop
        send_adc_sample(
            fclk     => fclk_p,
            data_p   => tb_data_p,
            ch1_word => DATA_0A,
            ch2_word => DATA_1A,
            ch3_word => DATA_2A,
            ch4_word => DATA_3A
        );
    end loop;

    ----------------------------------------------------------------
    -- Fin de la prueba
    ----------------------------------------------------------------
    wait until rising_edge(fclk_p);
    tb_data_p <= (others => '0');

    wait;
end process data_process;

tb_data_n <= not tb_data_p;


end Behavioral;
