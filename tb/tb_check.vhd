library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_check is
end entity;

architecture rtl of tb_check is
  constant CLKPER : time := 10 ns;
  signal clk_sig : std_logic := '0';
  signal rst_sig : std_logic := '1';
  signal test_out : std_logic := '0';
begin

  clk_sig <= not clk_sig after CLKPER/2;

  process
  begin
    wait for 25 ns;
    rst_sig <= '0';
    wait for 10 ns;

    for i in 0 to 9 loop
      wait until rising_edge(clk_sig);
      test_out <= not test_out;
      report "cycle=" & integer'image(i) & " test_out=" & std_logic'image(test_out) severity note;
    end loop;
    wait;
  end process;

end architecture;
