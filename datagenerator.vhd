 library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity data_generator is
  Port ( 
    clk:    in std_logic;
    reset:  in std_logic;
    FIFO_s_axis_tdata: out std_logic_vector(31 downto 0);
    FIFO_s_axis_tlast: out std_logic;
    FIFO_s_axis_tready: in std_logic;
    FIFO_s_axis_tvalid: out std_logic
  );
end data_generator;

architecture Behavioral of data_generator is

  constant BD_length : integer := 10;
  constant data0 : std_logic_vector(31 downto 0) := x"00000000";
  constant data1 : std_logic_vector(31 downto 0) := x"0000FFFF";
  constant data2 : std_logic_vector(31 downto 0) := x"FFFFFFFF";

  signal datacounter  : unsigned(4 downto 0) := (others => '0');
  signal dataselector : unsigned(1 downto 0) := (others => '0');  -- Solo 0-2 necesarios
  
  -- <--- Señales internas para los puertos de salida que quieres monitorear --->
  signal s_tdata_internal: std_logic_vector(31 downto 0);
  signal s_tvalid_internal: std_logic;
  signal s_tlast_internal: std_logic;
  -- <----------------------------------------------------------------------->

--ILA DECLARATION (no necesita cambios si probeN son 'in')
component ila_data_gen is
    Port(
        clk:    in std_logic;
        probe0: in std_logic_vector(31 downto 0);
        probe1: in std_logic;
        probe2: in std_logic;
        probe3: in std_logic;
        probe4: in unsigned(4 downto 0);
        probe5: in unsigned(1 downto 0)
    );
end component;    

begin

-- <--- Asigna las señales internas a los puertos de salida --->
FIFO_s_axis_tdata <= s_tdata_internal;
FIFO_s_axis_tvalid <= s_tvalid_internal;
FIFO_s_axis_tlast <= s_tlast_internal;
-- <----------------------------------------------------------->


  process(clk, reset)
  begin
    if reset = '0' then
      datacounter      <= (others => '0');
      dataselector     <= (others => '0');
      s_tvalid_internal <= '0'; -- Usa la señal interna
      s_tlast_internal <= '0';   -- Usa la señal interna
      s_tdata_internal <= (others => '0');  -- Usa la señal interna

    elsif rising_edge(clk) then

      -- Por defecto
      s_tvalid_internal <= '0'; -- Usa la señal interna
      s_tlast_internal  <= '0'; -- Usa la señal interna

      if datacounter < BD_length then
        s_tvalid_internal <= '1'; -- Usa la señal interna

        -- Selección de dato a enviar
        case dataselector is
          when "00" => s_tdata_internal <= data0; -- Usa la señal interna
          when "01" => s_tdata_internal <= data1; -- Usa la señal interna
          when "10" => s_tdata_internal <= data2; -- Usa la señal interna
          when others => s_tdata_internal <= (others => '0'); -- Usa la señal interna
          
        end case;

        if FIFO_s_axis_tready = '1' then 
      
          if datacounter = BD_length - 1 then
            s_tlast_internal <= '1'; -- Usa la señal interna
            -- Rollover del dataselector (0 → 1 → 2 → 0)
            if dataselector = "10" then
              dataselector <= (others => '0');
            else
              dataselector <= dataselector + 1;
            end if;

            datacounter <= (others => '0');  -- Reset contador
          else
            datacounter <= datacounter + 1;
          end if;
        end if;

      else
        -- No enviar nada si estamos fuera de BD_length
        s_tvalid_internal <= '0'; -- Usa la señal interna
      end if;
    end if;
  end process;


--ILA INSTANTIATION
ILA_DG: ila_data_gen 
    port map(
        clk    => clk,
        probe0 => s_tdata_internal,   -- ¡Conecta la señal interna!
        probe1 => s_tvalid_internal,  -- ¡Conecta la señal interna!
        probe2 => FIFO_s_axis_tready, -- Esta es una entrada a tu módulo, así que se conecta directamente
        probe3 => s_tlast_internal,   -- ¡Conecta la señal interna!
        probe4 => datacounter,
        probe5 => dataselector
        
    );
end Behavioral;