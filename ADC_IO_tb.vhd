--Se generan 5 valores de datos para cada canal del ADC que se incrementan en 1 en cada ciclo de reloj
--data_p_in(0): 0,1,2,3,4; data_p_in(1): 5,6,7,8,9; data_p_in(2): 10,11,12,13,14; data_p_in(3): 15,16,17,18,19


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
        fclk_p_IN:          in std_logic;
        fclk_n_IN:          in std_logic;
        dclk_p_IN:          in std_logic;
        dclk_n_IN:          in std_logic;
        data_p_IN:          in std_logic_vector((Adc_Num_Channels*Adc_Wire_Interface)-1 downto 0);
        data_n_IN:          in std_logic_vector((Adc_Num_Channels*Adc_Wire_Interface)-1 downto 0);
        aresetn:            in std_logic;
        dclk_buffered:      out std_logic;--Buffered 120 MHz clock 
        data_a_OUT:         out std_logic_vector((Adc_Resolution - 1) downto 0);--Sampled data from channel A
        data_b_OUT:         out std_logic_vector((Adc_Resolution - 1) downto 0);--Sampled data from channel A
        data_c_OUT:         out std_logic_vector((Adc_Resolution - 1) downto 0);--Sampled data from channel A
        data_d_OUT:         out std_logic_vector((Adc_Resolution - 1) downto 0);--Sampled data from channel A       
        adc_data_valid:     out std_logic
  );
  end component;

--Constant declaration
constant Adc_Wire_Interface: integer:= 1;
constant Adc_Num_Channels: integer:=4;
constant Adc_Resolution: integer:=12;
constant fclk_period: time:=50ns;
constant dclk_period: time:=8.33ns;
constant data_bit_period: time:=dclk_period/2;
constant aresetn_assert: time:=20ns;
--constant muestra_canal_a: std_logic_vector(11 downto 0):= "000000000000";
--constant muestra_canal_b: std_logic_vector(11 downto 0):= "000000000011";
--constant muestra_canal_c: std_logic_vector(11 downto 0):= "000000000110";


--Signal declaration
signal fclk_p, fclk_n: std_logic;  
signal dclk_p, dclk_n: std_logic;    
signal aresetn: std_logic;
signal tb_data_p: std_logic_vector((Adc_Num_Channels*Adc_Wire_Interface)-1 downto 0);
signal tb_data_n: std_logic_vector((Adc_Num_Channels*Adc_Wire_Interface)-1 downto 0);
signal dclk_buffered: std_logic;
signal tb_data_a_out: std_logic_vector((Adc_Resolution - 1) downto 0);
signal tb_data_b_out: std_logic_vector((Adc_Resolution - 1) downto 0);
signal tb_data_c_out: std_logic_vector((Adc_Resolution - 1) downto 0);
signal tb_data_d_out: std_logic_vector((Adc_Resolution - 1) downto 0);
signal adc_data_valid: std_logic;
signal muestra_canal_a: unsigned(11 downto 0) := (others => '0');
signal muestra_canal_b: unsigned(11 downto 0) := to_unsigned(5, 12);
signal muestra_canal_c: unsigned(11 downto 0) := to_unsigned(10, 12);
signal muestra_canal_d: unsigned(11 downto 0) := to_unsigned(15, 12);

signal sample_counter: unsigned(3 downto 0) := (others => '0');
begin

--Mapping
ADC_Module: ADC_IO port map(
    fclk_p_IN => fclk_p,
    fclk_n_IN => fclk_n,
    dclk_p_IN => dclk_p, 
    dclk_n_IN => dclk_n, 
    data_p_IN => tb_data_p,
    data_n_IN => tb_data_n,
    aresetn   => aresetn,
    dclk_buffered => dclk_buffered, 
    data_a_OUT    => tb_data_a_out,
    data_b_OUT    => tb_data_b_out,
    data_c_OUT    => tb_data_c_out,
    data_d_OUT    => tb_data_d_out,  
    adc_data_valid => adc_data_valid 
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

--DCLK generation 120 MHz
dclk_process: process
begin
    dclk_p <= '0';
    wait for dclk_period/2;
    dclk_p <= '1';
    wait for dclk_period/2;
end process dclk_process;
dclk_n <= not(dclk_p);

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

--Data generation 
tb_data_n<= not(tb_data_p);

Data_Generation_process : process
    variable bit_index : integer range 0 to Adc_Resolution - 1;

    variable sample_a : unsigned(Adc_Resolution - 1 downto 0);
    variable sample_b : unsigned(Adc_Resolution - 1 downto 0);
    variable sample_c : unsigned(Adc_Resolution - 1 downto 0);
    variable sample_d : unsigned(Adc_Resolution - 1 downto 0);
begin
    ----------------------------------------------------------------
    -- Estado inicial
    ----------------------------------------------------------------
    tb_data_p <= (others => '0');

    bit_index := Adc_Resolution - 1;

    sample_a := to_unsigned(0,  Adc_Resolution);
    sample_b := to_unsigned(5,  Adc_Resolution);
    sample_c := to_unsigned(10, Adc_Resolution);
    sample_d := to_unsigned(15, Adc_Resolution);

    muestra_canal_a <= sample_a;
    muestra_canal_b <= sample_b;
    muestra_canal_c <= sample_c;
    muestra_canal_d <= sample_d;

    ----------------------------------------------------------------
    -- La liberación del reset marca una frontera de bit.
    ----------------------------------------------------------------
    wait until aresetn = '1';

    while aresetn = '1' loop

        -- El dato cambia en la frontera del bit.
        tb_data_p(0) <= std_logic(sample_a(bit_index));
        tb_data_p(1) <= std_logic(sample_b(bit_index));
        tb_data_p(2) <= std_logic(sample_c(bit_index));
        tb_data_p(3) <= std_logic(sample_d(bit_index));

        -- Un bit DDR dura medio periodo de DCLK.
        -- El siguiente flanco de DCLK aparece a mitad de este intervalo.
        wait for data_bit_period;

        if bit_index = 0 then
            bit_index := Adc_Resolution - 1;

            sample_a := sample_a + 1;
            sample_b := sample_b + 1;
            sample_c := sample_c + 1;
            sample_d := sample_d + 1;

            -- Señales auxiliares para observar las muestras en la waveform.
            muestra_canal_a <= sample_a;
            muestra_canal_b <= sample_b;
            muestra_canal_c <= sample_c;
            muestra_canal_d <= sample_d;
        else
            bit_index := bit_index - 1;
        end if;

    end loop;
end process Data_Generation_process;
end Behavioral;
