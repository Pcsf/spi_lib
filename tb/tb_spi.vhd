-------------------------------------------------------------------------------
-- Testbench: tb_spi
-- Description: Self-checking full-duplex testbench for spi_master + spi_slave.
--              Covers all four SPI modes and widths 1, 8, 16, and 32.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.spi_master_pkg.all;
use work.spi_slave_pkg.all;

entity tb_spi is
end entity tb_spi;

architecture sim of tb_spi is

  constant CLK_PERIOD : time := 10 ns;

  type width_array_type is array (natural range <>) of positive;
  constant TEST_WIDTHS : width_array_type := (1, 8, 16, 32);

  function low_mask(width : positive) return unsigned is
    variable result : unsigned(31 downto 0) := (others => '0');
  begin
    for bit_num in 0 to width - 1 loop
      result(bit_num) := '1';
    end loop;
    return result;
  end function;

  signal clk     : std_logic := '0';
  signal rst     : std_logic := '1';
  signal sim_end : boolean := false;

  signal s_mosi : std_logic;
  signal s_miso : std_logic;
  signal s_sclk : std_logic;
  signal s_cs_n : std_logic;

  signal mi : spi_master_in_type := (
    start      => '0',
    mode       => "00",
    sclk_div   => to_unsigned(4, 8),
    data_width => to_unsigned(8, 6),
    tx_data    => (others => '0')
  );
  signal mo : spi_master_out_type;

  signal si : spi_slave_in_type := (
    mode       => "00",
    data_width => to_unsigned(8, 6),
    tx_data    => (others => '0'),
    cs_n       => '1',
    sclk       => '0',
    mosi       => '0'
  );
  signal so : spi_slave_out_type;

begin

  clk <= not clk after CLK_PERIOD / 2 when not sim_end else '0';

  u_master : spi_master
    port map (
      clk  => clk,
      rst  => rst,
      miso => s_miso,
      mi   => mi,
      mo   => mo
    );

  u_slave : spi_slave
    port map (
      clk => clk,
      rst => rst,
      mi  => si,
      mo  => so
    );

  s_mosi <= mo.mosi;
  s_miso <= so.miso;
  s_sclk <= mo.sclk;
  s_cs_n <= mo.cs_n;

  si.cs_n <= s_cs_n;
  si.sclk <= s_sclk;
  si.mosi <= s_mosi;

  test_driver : process
    variable errors            : natural := 0;
    variable tests_run         : natural := 0;
    variable mode_value        : std_logic_vector(1 downto 0);
    variable width_value       : positive;
    variable mask_value        : unsigned(31 downto 0);
    variable master_tx         : unsigned(31 downto 0);
    variable slave_tx          : unsigned(31 downto 0);
    variable master_rx         : unsigned(31 downto 0);
    variable slave_rx          : unsigned(31 downto 0);
    variable master_done       : boolean;
    variable slave_done        : boolean;
    variable started           : boolean;
    variable previous_sclk     : std_logic;
    variable sclk_transitions  : natural;
  begin
    -- Hold synchronous reset for at least four rising edges.
    for cycle in 1 to 5 loop
      wait until rising_edge(clk);
    end loop;
    rst <= '0';
    wait until rising_edge(clk);

    for mode_num in 0 to 3 loop
      mode_value := std_logic_vector(to_unsigned(mode_num, 2));

      for width_index in TEST_WIDTHS'range loop
        width_value := TEST_WIDTHS(width_index);
        mask_value  := low_mask(width_value);

        -- Different values in each direction prove full-duplex operation.
        master_tx := unsigned'(x"A5C39E71") xor
                     to_unsigned(mode_num * 16#01010101#, 32);
        slave_tx  := unsigned'(x"5A3C618E") xor
                     to_unsigned(mode_num * 16#00110011#, 32);

        mi.mode       <= mode_value;
        mi.sclk_div   <= to_unsigned(width_index + 1, mi.sclk_div'length);
        mi.data_width <= to_unsigned(width_value, mi.data_width'length);
        mi.tx_data    <= std_logic_vector(master_tx);
        si.mode       <= mode_value;
        si.data_width <= to_unsigned(width_value, si.data_width'length);
        si.tx_data    <= std_logic_vector(slave_tx);

        -- Allow the idle SCLK polarity to settle before asserting CS.
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        mi.start <= '1';
        wait until rising_edge(clk);
        mi.start <= '0';

        started := false;
        for cycle in 1 to 20 loop
          wait until rising_edge(clk);
          if mo.busy = '1' then
            started := true;
            exit;
          end if;
        end loop;

        if not started then
          report "Master busy did not assert: mode=" & integer'image(mode_num) &
                 " width=" & integer'image(width_value)
            severity error;
          errors := errors + 1;
        else
          -- Configuration belongs to the accepted start request. Changing the
          -- host-side values during a transfer must not alter the transaction.
          mi.mode       <= not mode_value;
          mi.sclk_div   <= (others => '0');
          mi.data_width <= (others => '0');
          mi.tx_data    <= (others => '0');
          si.mode       <= not mode_value;
          si.data_width <= (others => '0');
          si.tx_data    <= (others => '0');
        end if;

        master_done      := false;
        slave_done       := false;
        previous_sclk    := mo.sclk;
        sclk_transitions := 0;

        for cycle in 1 to 2000 loop
          wait until rising_edge(clk);

          if mo.sclk /= previous_sclk then
            sclk_transitions := sclk_transitions + 1;
            previous_sclk := mo.sclk;
          end if;

          if so.rx_valid = '1' then
            slave_rx   := unsigned(so.rx_data);
            slave_done := true;
          end if;

          if mo.rx_valid = '1' then
            master_rx   := unsigned(mo.rx_data);
            master_done := true;
          end if;

          exit when master_done and slave_done;
        end loop;

        if not master_done then
          report "Master completion timeout: mode=" & integer'image(mode_num) &
                 " width=" & integer'image(width_value)
            severity error;
          errors := errors + 1;
        elsif (master_rx and mask_value) /= (slave_tx and mask_value) then
          report "Master RX mismatch: mode=" & integer'image(mode_num) &
                 " width=" & integer'image(width_value) &
                 " got=0x" & to_hstring(std_logic_vector(master_rx and mask_value)) &
                 " expected=0x" & to_hstring(std_logic_vector(slave_tx and mask_value))
            severity error;
          errors := errors + 1;
        end if;

        if not slave_done then
          report "Slave completion timeout: mode=" & integer'image(mode_num) &
                 " width=" & integer'image(width_value)
            severity error;
          errors := errors + 1;
        elsif (slave_rx and mask_value) /= (master_tx and mask_value) then
          report "Slave RX mismatch: mode=" & integer'image(mode_num) &
                 " width=" & integer'image(width_value) &
                 " got=0x" & to_hstring(std_logic_vector(slave_rx and mask_value)) &
                 " expected=0x" & to_hstring(std_logic_vector(master_tx and mask_value))
            severity error;
          errors := errors + 1;
        end if;

        if sclk_transitions /= 2 * width_value then
          report "Wrong SCLK edge count: mode=" & integer'image(mode_num) &
                 " width=" & integer'image(width_value) &
                 " got=" & integer'image(sclk_transitions) &
                 " expected=" & integer'image(2 * width_value)
            severity error;
          errors := errors + 1;
        end if;

        if mo.cs_n /= '1' or mo.busy /= '0' or mo.tx_count /= 0 then
          report "Master did not return to idle after transfer"
            severity error;
          errors := errors + 1;
        end if;

        if so.busy /= '0' or so.rx_count /= 0 then
          report "Slave did not return to idle after transfer"
            severity error;
          errors := errors + 1;
        end if;

        tests_run := tests_run + 1;
        wait until rising_edge(clk);
        wait until rising_edge(clk);
      end loop;
    end loop;

    report "SPI test summary: " & integer'image(tests_run) &
           " transfers, " & integer'image(errors) & " errors"
      severity note;

    assert errors = 0
      report "SPI TESTS FAILED"
      severity failure;

    report "ALL SPI TESTS PASSED" severity note;
    sim_end <= true;
    wait;
  end process;

end architecture sim;
