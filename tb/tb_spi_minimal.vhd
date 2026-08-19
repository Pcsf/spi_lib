-------------------------------------------------------------------------------
-- Minimal testbench to diagnose master/slave behavior
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.spi_master_pkg.all;
use work.spi_slave_pkg.all;

entity tb_spi_minimal is
end entity tb_spi_minimal;

architecture rtl of tb_spi_minimal is

  constant CLK_PERIOD : time := 10 ns;
  signal clk          : std_logic := '0';
  signal rst          : std_logic := '1';

  signal s_mosi, s_miso, s_sclk, s_cs_n : std_logic := '0';

  signal mi : spi_master_in_type := (
    start       => '0',
    mode        => "00",
    sclk_div    => (others => '0'),
    data_width  => to_unsigned(8, 6),
    tx_data     => x"AA"
  );
  signal mo : spi_master_out_type;

  signal si : spi_slave_in_type := (
    mode       => "00",
    data_width => to_unsigned(8, 6),
    tx_data    => x"AA",
    cs_n       => '1',
    sclk       => '0',
    mosi       => '0'
  );
  signal so : spi_slave_out_type;

begin

  clk <= not clk after CLK_PERIOD / 2;

  u_slave : spi_slave port map (clk, rst, si, so);
  si.cs_n <= s_cs_n; si.sclk <= s_sclk; si.mosi <= s_mosi;

  u_master : spi_master port map (clk, rst, s_miso, mi, mo);
  s_mosi <= mo.mosi; s_sclk <= mo.sclk; s_cs_n <= mo.cs_n; s_miso <= so.miso;

  driver : process
  begin
    wait for 30 ns;
    rst <= '0';
    wait for 20 ns;

    mi.start <= '1';
    wait until rising_edge(clk);
    mi.start <= '0';

    -- Debug: wait and print state
    for i in 1 to 5000 loop
      wait until rising_edge(clk);
      if (i mod 500) = 0 then
        report "cycle=" & integer'image(i)
               & " state=" & state_name(mo.busy)
               & " busy=" & std_logic'image(mo.busy)
               & " sclk=" & std_logic'image(mo.sclk)
               & " cs=" & std_logic'image(mo.cs_n)
               severity note;
      end if;
      if mo.rx_valid = '1' then
        report "rx_valid at cycle " & integer'image(i) & " rx=" & std_logic_vector'image(mo.rx_data) severity note;
        exit;
      end if;
    end loop;

    wait;
  end process;

  function state_name(busy_s : std_logic) return string is
  begin
    if busy_s = '1' then return "ACTIVE";
    else return "IDLE";
    end if;
  end function;

end architecture rtl;
