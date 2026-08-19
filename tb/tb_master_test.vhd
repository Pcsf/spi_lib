-- Simple master-only test: check if SCLK toggles
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.spi_master_pkg.all;

entity tb_master_test is
end entity;

architecture rtl of tb_master_test is
  constant CLKPER : time := 10 ns;
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal miso_in : std_logic := '1';

  signal mi : spi_master_in_type := (
    start       => '0',
    mode        => "00",
    sclk_div    => (others => '0'),
    data_width  => (others => '0'),
    tx_data     => (others => '0')
  );
  signal mo : spi_master_out_type;

  signal sig_prev_sclk : std_logic := '0';
  signal sig_toggle_cnt : natural := 0;
  signal sig_done       : std_logic := '0';
begin

  clk <= not clk after CLKPER/2;

  u_master : spi_master
    port map (clk => clk, rst => rst, miso => miso_in, mi => mi, mo => mo);

  driver : process
    variable v_toggle : natural := 0;
    variable v_prev   : std_logic := '0';
    variable cycle_num : integer;
  begin
    wait for 30 ns;
    rst <= '0';
    wait for 10 ns;

    mi.mode        <= "00";
    mi.data_width  <= to_unsigned(8, 6);
    mi.tx_data     <= x"000000AA";
    mi.sclk_div    <= to_unsigned(4, 8);

    wait until rising_edge(clk);
    mi.start <= '1';
    wait until rising_edge(clk);
    mi.start <= '0';

    cycle_num := 0;
    for i in 1 to 100 loop
      wait until rising_edge(clk);
      cycle_num := i;
      exit when mo.busy = '1';
    end loop;
    report "Master started at cycle " & integer'image(cycle_num) severity note;

    for i in 1 to 500 loop
      wait until rising_edge(clk);
      cycle_num := i;
      if (i mod 100) = 0 then
        report "DBG: cycle=" & integer'image(i)
               & " busy=" & std_logic'image(mo.busy)
               & " sclk=" & std_logic'image(mo.sclk)
               & " cs=" & std_logic'image(mo.cs_n)
               & " tx_cnt=" & integer'image(to_integer(mo.tx_count))
               severity note;
      end if;
      if mo.sclk /= sig_prev_sclk then
        v_toggle := v_toggle + 1;
        sig_toggle_cnt <= v_toggle;
        sig_prev_sclk <= mo.sclk;
      end if;
      if mo.rx_valid = '1' then
        report "DONE at cycle " & integer'image(cycle_num)
               & " tx_count=" & integer'image(to_integer(mo.tx_count))
               & " toggles=" & integer'image(v_toggle)
               severity note;
        sig_done <= '1';
        exit;
      end if;
    end loop;

    assert sig_done = '1'
      report "TIMEOUT: no rx_valid or SCLK toggle within 500 cycles"
      severity failure;
    wait;
  end process;

end architecture;
