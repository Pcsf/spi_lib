library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library bitvis_vip_spi;
use bitvis_vip_spi.spi_bfm_pkg.all;

use work.spi_master_pkg.all;
use work.spi_slave_pkg.all;
use work.spi_bus_monitor_pkg.all;

entity tb_spi is
end entity tb_spi;

architecture sim of tb_spi is
  constant CLK_PERIOD : time := 10 ns;

  type phase_type is (
    PHASE_MONITOR_QUALIFICATION,
    PHASE_MASTER_INDEPENDENT,
    PHASE_SLAVE_INDEPENDENT,
    PHASE_LOOPBACK
  );

  type natural_array_type is array (natural range <>) of natural;
  constant TEST_WIDTHS     : natural_array_type := (1, 2, 7, 8, 9, 16, 31, 32);
  constant LOOPBACK_WIDTHS : natural_array_type := (1, 8, 16, 32);
  constant TEST_DIVIDERS   : natural_array_type := (0, 1, 4, 255);
  constant TEST_BIT_TIMES  : natural_array_type := (80, 100, 140, 200);

  type pattern_array_type is array (natural range <>) of std_logic_vector(31 downto 0);
  constant TEST_PATTERNS : pattern_array_type := (
    x"00000000",
    x"FFFFFFFF",
    x"AAAAAAAA",
    x"55555555",
    x"00000001",
    x"FFFFFFFE",
    x"A5C39E71",
    x"5A3C618E"
  );

  function low_mask(width : positive) return std_logic_vector is
    variable result : std_logic_vector(31 downto 0) := (others => '0');
  begin
    result(width - 1 downto 0) := (others => '1');
    return result;
  end function;

  function masked(data : std_logic_vector(31 downto 0); width : positive)
    return std_logic_vector is
  begin
    return data and low_mask(width);
  end function;

  signal clk     : std_logic := '0';
  signal rst     : std_logic := '1';
  signal sim_end : boolean := false;
  signal phase   : phase_type := PHASE_MONITOR_QUALIFICATION;

  signal mi : spi_master_in_type := (
    start      => '0',
    mode       => "00",
    sclk_div   => (others => '0'),
    data_width => to_unsigned(8, 6),
    tx_data    => (others => '0')
  );
  signal mo          : spi_master_out_type;
  signal master_miso : std_logic;

  signal si : spi_slave_in_type := (
    mode       => "00",
    data_width => to_unsigned(8, 6),
    tx_data    => (others => '0'),
    cs_n       => '1',
    sclk       => '0',
    mosi       => '0'
  );
  signal so : spi_slave_out_type;

  signal bfm_sclk : std_logic := '0';
  signal bfm_ss_n : std_logic := '1';
  signal bfm_mosi : std_logic := 'Z';

  signal uvvm_master_bus_sclk : std_logic := 'Z';
  signal uvvm_master_bus_ss_n : std_logic := 'Z';
  signal uvvm_master_bus_mosi : std_logic := 'Z';
  signal uvvm_slave_miso      : std_logic := 'Z';
  signal one_bit_slave_miso   : std_logic := '0';
  signal use_one_bit_slave    : std_logic := '0';
  signal uvvm_slave_request   : std_logic := '0';
  signal uvvm_slave_done     : std_logic := '0';
  signal uvvm_slave_mode     : std_logic_vector(1 downto 0) := "00";
  signal uvvm_slave_width    : unsigned(5 downto 0) := to_unsigned(8, 6);
  signal uvvm_slave_bit_time : time := 100 ns;
  signal uvvm_slave_tx       : std_logic_vector(31 downto 0) := (others => '0');
  signal uvvm_slave_rx       : std_logic_vector(31 downto 0) := (others => '0');

  signal synth_cs_n : std_logic := '1';
  signal synth_sclk : std_logic := '0';
  signal synth_mosi : std_logic := '0';
  signal synth_miso : std_logic := '0';

  signal monitor_arm                  : std_logic := '0';
  signal monitor_mode                 : std_logic_vector(1 downto 0) := "00";
  signal monitor_width                : unsigned(5 downto 0) := to_unsigned(8, 6);
  signal monitor_expected_mosi        : std_logic_vector(31 downto 0) := (others => '0');
  signal monitor_expected_miso        : std_logic_vector(31 downto 0) := (others => '0');
  signal monitor_check_clock_period   : std_logic := '0';
  signal monitor_expected_half_period : time := 10 ns;
  signal monitor_cs_n                 : std_logic;
  signal monitor_sclk                 : std_logic;
  signal monitor_mosi                 : std_logic;
  signal monitor_miso                 : std_logic;
  signal monitor_done                 : std_logic;
  signal monitor_errors               : spi_monitor_errors_type;
  signal monitor_observed_mosi        : std_logic_vector(31 downto 0);
  signal monitor_observed_miso        : std_logic_vector(31 downto 0);
  signal monitor_edge_count           : natural;

  signal master_rx_events      : natural := 0;
  signal slave_rx_events       : natural := 0;
  signal master_rx_capture     : std_logic_vector(31 downto 0) := (others => '0');
  signal slave_rx_capture      : std_logic_vector(31 downto 0) := (others => '0');
  signal master_rx_valid_d1    : std_logic := '0';
  signal slave_rx_valid_d1     : std_logic := '0';
  signal master_rx_pulse_error : std_logic := '0';
  signal slave_rx_pulse_error  : std_logic := '0';

begin
  clk <= not clk after CLK_PERIOD / 2 when not sim_end else '0';

  u_master : spi_master
    port map (
      clk  => clk,
      rst  => rst,
      miso => master_miso,
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

  uvvm_master_bus_sclk <= mo.sclk;
  uvvm_master_bus_ss_n <= mo.cs_n;
  uvvm_master_bus_mosi <= mo.mosi;

  master_miso <= so.miso when phase = PHASE_LOOPBACK else
                 one_bit_slave_miso when phase = PHASE_MASTER_INDEPENDENT and use_one_bit_slave = '1' else
                 uvvm_slave_miso when phase = PHASE_MASTER_INDEPENDENT else
                 '0';

  si.cs_n <= mo.cs_n when phase = PHASE_LOOPBACK else
             bfm_ss_n when phase = PHASE_SLAVE_INDEPENDENT else
             '1';
  si.sclk <= mo.sclk when phase = PHASE_LOOPBACK else
             bfm_sclk when phase = PHASE_SLAVE_INDEPENDENT else
             si.mode(1);
  si.mosi <= mo.mosi when phase = PHASE_LOOPBACK else
             bfm_mosi when phase = PHASE_SLAVE_INDEPENDENT else
             '0';

  monitor_cs_n <= synth_cs_n when phase = PHASE_MONITOR_QUALIFICATION else
                  bfm_ss_n when phase = PHASE_SLAVE_INDEPENDENT else
                  mo.cs_n;
  monitor_sclk <= synth_sclk when phase = PHASE_MONITOR_QUALIFICATION else
                  bfm_sclk when phase = PHASE_SLAVE_INDEPENDENT else
                  uvvm_master_bus_sclk when phase = PHASE_MASTER_INDEPENDENT else
                  mo.sclk;
  monitor_mosi <= synth_mosi when phase = PHASE_MONITOR_QUALIFICATION else
                  bfm_mosi when phase = PHASE_SLAVE_INDEPENDENT else
                  uvvm_master_bus_mosi when phase = PHASE_MASTER_INDEPENDENT else
                  mo.mosi;
  monitor_miso <= synth_miso when phase = PHASE_MONITOR_QUALIFICATION else
                  so.miso when phase = PHASE_SLAVE_INDEPENDENT or phase = PHASE_LOOPBACK else
                  one_bit_slave_miso when use_one_bit_slave = '1' else
                  uvvm_slave_miso;

  u_monitor : entity work.spi_bus_monitor
    port map (
      arm                  => monitor_arm,
      mode                 => monitor_mode,
      data_width           => monitor_width,
      expected_mosi        => monitor_expected_mosi,
      expected_miso        => monitor_expected_miso,
      check_clock_period   => monitor_check_clock_period,
      expected_half_period => monitor_expected_half_period,
      cs_n                 => monitor_cs_n,
      sclk                 => monitor_sclk,
      mosi                 => monitor_mosi,
      miso                 => monitor_miso,
      done                 => monitor_done,
      errors               => monitor_errors,
      observed_mosi        => monitor_observed_mosi,
      observed_miso        => monitor_observed_miso,
      edge_count           => monitor_edge_count
    );

  capture_results : process(clk)
  begin
    if rising_edge(clk) then
      if mo.rx_valid = '1' then
        master_rx_capture <= mo.rx_data;
        master_rx_events  <= master_rx_events + 1;
        if master_rx_valid_d1 = '1' then
          master_rx_pulse_error <= '1';
        end if;
      end if;
      if so.rx_valid = '1' then
        slave_rx_capture <= so.rx_data;
        slave_rx_events  <= slave_rx_events + 1;
        if slave_rx_valid_d1 = '1' then
          slave_rx_pulse_error <= '1';
        end if;
      end if;
      master_rx_valid_d1 <= mo.rx_valid;
      slave_rx_valid_d1  <= so.rx_valid;
    end if;
  end process capture_results;

  uvvm_slave_responder : process
    variable v_config : t_spi_bfm_config;
    variable v_rx     : std_logic_vector(31 downto 0);
    variable v_width  : natural;
  begin
    loop
      wait on uvvm_slave_request;

      v_width                   := to_integer(uvvm_slave_width);
      v_rx                      := (others => '0');
      v_config                  := C_SPI_BFM_CONFIG_DEFAULT;
      v_config.CPOL             := uvvm_slave_mode(1);
      v_config.CPHA             := uvvm_slave_mode(0);
      v_config.spi_bit_time     := uvvm_slave_bit_time;
      v_config.ss_n_to_sclk     := uvvm_slave_bit_time / 2;
      v_config.sclk_to_ss_n     := CLK_PERIOD;
      v_config.inter_word_delay := 0 ns;

      spi_slave_transmit_and_receive(
        tx_data  => uvvm_slave_tx(v_width - 1 downto 0),
        rx_data  => v_rx(v_width - 1 downto 0),
        msg      => "master DUT transaction",
        sclk     => uvvm_master_bus_sclk,
        ss_n     => uvvm_master_bus_ss_n,
        mosi     => uvvm_master_bus_mosi,
        miso     => uvvm_slave_miso,
        config   => v_config
      );

      uvvm_slave_rx   <= v_rx;
      uvvm_slave_done <= uvvm_slave_request;
    end loop;
  end process uvvm_slave_responder;

  test_driver : process
    variable errors               : natural := 0;
    variable monitor_tests        : natural := 0;
    variable master_tests         : natural := 0;
    variable master_control_tests : natural := 0;
    variable slave_tests          : natural := 0;
    variable slave_control_tests  : natural := 0;
    variable loopback_tests       : natural := 0;
    variable transaction_index    : natural := 0;
    variable mode_value           : std_logic_vector(1 downto 0);
    variable width_value          : positive;
    variable divider_value        : natural;
    variable master_tx            : std_logic_vector(31 downto 0);
    variable slave_tx             : std_logic_vector(31 downto 0);
    variable bfm_rx               : std_logic_vector(31 downto 0);
    variable v_config             : t_spi_bfm_config;
    variable monitor_token        : std_logic := '0';
    variable slave_bfm_token      : std_logic := '0';
    variable master_events_before : natural;
    variable slave_events_before  : natural;
    variable completed            : boolean;

    procedure check(
      constant condition : in boolean;
      constant message   : in string
    ) is
    begin
      if not condition then
        report message severity error;
        errors := errors + 1;
      end if;
    end procedure;

    procedure arm_monitor(
      constant mode_value       : in std_logic_vector(1 downto 0);
      constant width_value      : in positive;
      constant expected_mosi    : in std_logic_vector(31 downto 0);
      constant expected_miso    : in std_logic_vector(31 downto 0);
      constant check_period     : in boolean;
      constant half_period      : in time
    ) is
    begin
      monitor_mode                 <= mode_value;
      monitor_width                <= to_unsigned(width_value, monitor_width'length);
      monitor_expected_mosi        <= expected_mosi;
      monitor_expected_miso        <= expected_miso;
      monitor_check_clock_period   <= '1' when check_period else '0';
      monitor_expected_half_period <= half_period;
      monitor_token                := not monitor_token;
      monitor_arm                  <= monitor_token;
      wait for 0 ns;
    end procedure;

    procedure wait_for_monitor(constant test_name : in string) is
    begin
      if monitor_done /= monitor_token then
        wait until monitor_done = monitor_token for 2 ms;
      end if;
      check(monitor_done = monitor_token, test_name & ": monitor timeout");
    end procedure;

    -- UVVM SPI BFM 5.1.4 indexes below zero on one-bit transfers.
    procedure drive_one_bit_master(
      constant mode_value : in std_logic_vector(1 downto 0);
      constant tx_bit     : in std_logic;
      variable rx_bit     : out std_logic
    ) is
    begin
      bfm_sclk <= mode_value(1);
      bfm_ss_n <= '1';
      bfm_mosi <= 'Z';
      wait for 20 ns;

      bfm_ss_n <= '0';
      if mode_value(0) = '0' then
        bfm_mosi <= tx_bit;
      end if;
      wait for 35 ns;

      if mode_value(0) = '1' then
        bfm_mosi <= tx_bit;
      end if;
      bfm_sclk <= not mode_value(1);
      wait for 40 ns;

      if mode_value(0) = '0' then
        rx_bit := to_x01(so.miso);
      end if;
      bfm_sclk <= mode_value(1);
      wait for 0 ns;
      if mode_value(0) = '1' then
        rx_bit := to_x01(so.miso);
      end if;

      wait for 25 ns;
      bfm_ss_n <= '1';
      bfm_mosi <= 'Z';
      wait for 0 ns;
    end procedure;

    procedure drive_manual_frame(
      constant mode_value   : in std_logic_vector(1 downto 0);
      constant width_value  : in positive;
      constant tx_data      : in std_logic_vector(31 downto 0);
      constant mutate_config: in boolean;
      variable rx_data      : out std_logic_vector(31 downto 0)
    ) is
    begin
      rx_data  := (others => '0');
      bfm_sclk <= mode_value(1);
      bfm_ss_n <= '1';
      bfm_mosi <= 'Z';
      wait for 20 ns;

      bfm_ss_n <= '0';
      if mode_value(0) = '0' then
        bfm_mosi <= tx_data(width_value - 1);
      end if;

      wait for 20 ns;
      if mutate_config then
        si.mode       <= not mode_value;
        si.data_width <= (others => '0');
        si.tx_data    <= (others => '0');
      end if;
      wait for 15 ns;

      for bit_index in width_value - 1 downto 0 loop
        if mode_value(0) = '1' then
          bfm_mosi <= tx_data(bit_index);
        end if;

        bfm_sclk <= not mode_value(1);
        wait for 0 ns;
        if mode_value(0) = '0' then
          rx_data(bit_index) := to_x01(so.miso);
        end if;
        wait for 40 ns;

        bfm_sclk <= mode_value(1);
        wait for 0 ns;
        if mode_value(0) = '1' then
          rx_data(bit_index) := to_x01(so.miso);
        end if;

        if bit_index > 0 then
          if mode_value(0) = '0' then
            bfm_mosi <= tx_data(bit_index - 1);
          end if;
          wait for 40 ns;
        end if;
      end loop;

      wait for 25 ns;
      bfm_ss_n <= '1';
      bfm_mosi <= 'Z';
      wait for 0 ns;
    end procedure;

    procedure drive_synthetic_mode0(
      constant frame_width : in positive;
      constant bits_sent   : in positive;
      constant mosi_data   : in std_logic_vector(31 downto 0);
      constant miso_data   : in std_logic_vector(31 downto 0)
    ) is
      variable source_index : natural;
    begin
      synth_cs_n <= '1';
      synth_sclk <= '0';
      synth_mosi <= mosi_data(frame_width - 1);
      synth_miso <= miso_data(frame_width - 1);
      wait for 10 ns;
      synth_cs_n <= '0';
      wait for 10 ns;

      for sent in 0 to bits_sent - 1 loop
        synth_sclk <= '1';
        wait for 10 ns;
        synth_sclk <= '0';
        if sent < bits_sent - 1 then
          source_index := frame_width - 1 - ((sent + 1) mod frame_width);
          synth_mosi <= mosi_data(source_index);
          synth_miso <= miso_data(source_index);
        end if;
        wait for 10 ns;
      end loop;

      synth_cs_n <= '1';
      wait for 10 ns;
    end procedure;

  begin
    for cycle in 1 to 5 loop
      wait until rising_edge(clk);
    end loop;
    rst <= '0';
    wait until rising_edge(clk);

    -------------------------------------------------------------------------
    -- Passive monitor qualification
    -------------------------------------------------------------------------
    phase <= PHASE_MONITOR_QUALIFICATION;
    wait for 0 ns;

    arm_monitor("00", 4, x"0000000A", x"00000005", true, 10 ns);
    drive_synthetic_mode0(4, 4, x"0000000A", x"00000005");
    wait_for_monitor("monitor valid frame");
    check(monitor_errors = SPI_MON_NO_ERRORS,
          "Monitor rejected a valid frame: 0x" & to_hstring(monitor_errors));
    monitor_tests := monitor_tests + 1;

    arm_monitor("00", 4, x"0000000B", x"00000005", true, 10 ns);
    drive_synthetic_mode0(4, 4, x"0000000A", x"00000005");
    wait_for_monitor("monitor MOSI corruption");
    check(monitor_errors(SPI_MON_MOSI_DATA) = '1',
          "Monitor failed to detect MOSI corruption");
    monitor_tests := monitor_tests + 1;

    arm_monitor("00", 4, x"0000000A", x"00000005", true, 10 ns);
    drive_synthetic_mode0(4, 1, x"0000000A", x"00000005");
    wait_for_monitor("monitor premature CS");
    check(monitor_errors(SPI_MON_PREMATURE_CS) = '1',
          "Monitor failed to detect premature CS release");
    monitor_tests := monitor_tests + 1;

    arm_monitor("00", 1, x"00000001", x"00000000", true, 10 ns);
    drive_synthetic_mode0(1, 2, x"00000001", x"00000000");
    wait_for_monitor("monitor extra edge");
    check(monitor_errors(SPI_MON_EDGE_COUNT) = '1',
          "Monitor failed to detect an extra SCLK edge");
    monitor_tests := monitor_tests + 1;

    report "Monitor qualification: " & integer'image(monitor_tests) & "/4 PASS"
      severity note;

    -------------------------------------------------------------------------
    -- SPI master against UVVM slave BFM
    -------------------------------------------------------------------------
    phase <= PHASE_MASTER_INDEPENDENT;
    wait until rising_edge(clk);

    for mode_number in 0 to 3 loop
      mode_value := std_logic_vector(to_unsigned(mode_number, 2));

      for width_index in TEST_WIDTHS'range loop
        width_value       := TEST_WIDTHS(width_index);
        divider_value     := TEST_DIVIDERS((mode_number + width_index) mod TEST_DIVIDERS'length);
        master_tx         := TEST_PATTERNS(transaction_index mod TEST_PATTERNS'length);
        slave_tx          := TEST_PATTERNS((transaction_index + 3) mod TEST_PATTERNS'length);
        transaction_index := transaction_index + 1;

        mi.mode       <= mode_value;
        mi.sclk_div   <= to_unsigned(divider_value, mi.sclk_div'length);
        mi.data_width <= to_unsigned(width_value, mi.data_width'length);
        mi.tx_data    <= master_tx;

        uvvm_slave_mode     <= mode_value;
        uvvm_slave_width    <= to_unsigned(width_value, uvvm_slave_width'length);
        uvvm_slave_bit_time <= 2 * (divider_value + 1) * CLK_PERIOD;
        uvvm_slave_tx       <= slave_tx;

        if width_value = 1 then
          use_one_bit_slave  <= '1';
          one_bit_slave_miso <= slave_tx(0);
        else
          use_one_bit_slave   <= '0';
          slave_bfm_token     := not slave_bfm_token;
          uvvm_slave_request  <= slave_bfm_token;
        end if;
        arm_monitor(mode_value, width_value, master_tx, slave_tx, true,
                    (divider_value + 1) * CLK_PERIOD);

        wait until rising_edge(clk);
        mi.start <= '1';
        wait until rising_edge(clk);
        mi.start <= '0';

        completed := false;
        for cycle in 1 to 200000 loop
          wait until rising_edge(clk);
          if mo.rx_valid = '1' then
            completed := true;
            exit;
          end if;
        end loop;
        check(completed,
              "Master completion timeout: mode=" & integer'image(mode_number) &
              " width=" & integer'image(width_value));

        if width_value > 1 then
          if uvvm_slave_done /= slave_bfm_token then
            wait until uvvm_slave_done = slave_bfm_token for 2 ms;
          end if;
          check(uvvm_slave_done = slave_bfm_token,
                "UVVM slave timeout: mode=" & integer'image(mode_number) &
                " width=" & integer'image(width_value));
        end if;

        wait_for_monitor("master independent transaction");
        wait for 0 ns;

        check(masked(mo.rx_data, width_value) = masked(slave_tx, width_value),
              "Master RX mismatch: mode=" & integer'image(mode_number) &
              " width=" & integer'image(width_value));
        check((mo.rx_data and not low_mask(width_value)) = x"00000000",
              "Master RX upper bits are not zero: width=" & integer'image(width_value));
        check(master_rx_pulse_error = '0', "Master rx_valid exceeded one cycle");
        if width_value > 1 then
          check(masked(uvvm_slave_rx, width_value) = masked(master_tx, width_value),
                "UVVM slave RX mismatch: mode=" & integer'image(mode_number) &
                " width=" & integer'image(width_value));
        else
          check(monitor_observed_mosi(0) = master_tx(0),
                "One-bit master MOSI mismatch: mode=" & integer'image(mode_number));
        end if;
        check(monitor_errors = SPI_MON_NO_ERRORS,
              "Master wire-protocol error: mode=" & integer'image(mode_number) &
              " width=" & integer'image(width_value) &
              " flags=0x" & to_hstring(monitor_errors));

        master_tests := master_tests + 1;
        wait until rising_edge(clk);
      end loop;
    end loop;

    report "Master independent: " & integer'image(master_tests) & "/32 PASS"
      severity note;

    master_events_before := master_rx_events;
    mi.data_width <= to_unsigned(0, mi.data_width'length);
    mi.start <= '1';
    wait until rising_edge(clk);
    mi.start <= '0';
    for cycle in 1 to 8 loop
      wait until rising_edge(clk);
    end loop;
    check(mo.busy = '0' and mo.cs_n = '1' and master_rx_events = master_events_before,
          "Master accepted zero data width");
    master_control_tests := master_control_tests + 1;

    mi.data_width <= to_unsigned(33, mi.data_width'length);
    mi.start <= '1';
    wait until rising_edge(clk);
    mi.start <= '0';
    for cycle in 1 to 8 loop
      wait until rising_edge(clk);
    end loop;
    check(mo.busy = '0' and mo.cs_n = '1' and master_rx_events = master_events_before,
          "Master accepted data width 33");
    master_control_tests := master_control_tests + 1;

    mode_value := "11";
    master_tx  := x"000000A5";
    slave_tx   := x"0000005A";
    mi.mode       <= mode_value;
    mi.sclk_div   <= to_unsigned(4, mi.sclk_div'length);
    mi.data_width <= to_unsigned(8, mi.data_width'length);
    mi.tx_data    <= master_tx;
    use_one_bit_slave     <= '0';
    uvvm_slave_mode       <= mode_value;
    uvvm_slave_width      <= to_unsigned(8, uvvm_slave_width'length);
    uvvm_slave_bit_time   <= 10 * CLK_PERIOD;
    uvvm_slave_tx         <= slave_tx;
    slave_bfm_token       := not slave_bfm_token;
    uvvm_slave_request    <= slave_bfm_token;
    arm_monitor(mode_value, 8, master_tx, slave_tx, true, 5 * CLK_PERIOD);

    wait until rising_edge(clk);
    mi.start <= '1';
    wait until rising_edge(clk);
    mi.start <= '0';
    if mo.busy /= '1' then
      wait until mo.busy = '1' for 20 * CLK_PERIOD;
    end if;
    check(mo.busy = '1', "Master did not start configuration-capture test");

    mi.mode       <= "00";
    mi.sclk_div   <= (others => '0');
    mi.data_width <= (others => '0');
    mi.tx_data    <= (others => '0');
    mi.start      <= '1';
    wait until rising_edge(clk);
    mi.start <= '0';

    completed := false;
    for cycle in 1 to 2000 loop
      wait until rising_edge(clk);
      if mo.rx_valid = '1' then
        completed := true;
        exit;
      end if;
    end loop;
    check(completed, "Master configuration-capture transaction timed out");
    if uvvm_slave_done /= slave_bfm_token then
      wait until uvvm_slave_done = slave_bfm_token for 100 us;
    end if;
    wait_for_monitor("master configuration capture");
    check(masked(mo.rx_data, 8) = masked(slave_tx, 8),
          "Master configuration changed while busy");
    check(masked(uvvm_slave_rx, 8) = masked(master_tx, 8),
          "Second start corrupted the active master transfer");
    check(monitor_errors = SPI_MON_NO_ERRORS,
          "Master configuration-capture protocol error");
    master_control_tests := master_control_tests + 1;

    use_one_bit_slave  <= '1';
    one_bit_slave_miso <= '0';
    mi.mode       <= "00";
    mi.sclk_div   <= to_unsigned(4, mi.sclk_div'length);
    mi.data_width <= to_unsigned(32, mi.data_width'length);
    mi.tx_data    <= x"FFFFFFFF";
    wait until rising_edge(clk);
    mi.start <= '1';
    wait until rising_edge(clk);
    mi.start <= '0';
    wait until mo.busy = '1' for 20 * CLK_PERIOD;
    check(mo.busy = '1', "Master did not start reset-abort test");
    for cycle in 1 to 4 loop
      wait until rising_edge(clk);
    end loop;
    master_events_before := master_rx_events;
    rst <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    check(mo.busy = '0' and mo.cs_n = '1' and mo.sclk = '0' and mo.rx_valid = '0',
          "Master did not return to reset state during a transfer");
    check(master_rx_events = master_events_before,
          "Master produced rx_valid while reset aborted a transfer");
    rst <= '0';
    wait until rising_edge(clk);
    master_control_tests := master_control_tests + 1;

    report "Master controls: " & integer'image(master_control_tests) & "/4 PASS"
      severity note;

    -------------------------------------------------------------------------
    -- SPI slave against UVVM master BFM
    -------------------------------------------------------------------------
    phase <= PHASE_SLAVE_INDEPENDENT;
    wait until rising_edge(clk);

    for mode_number in 0 to 3 loop
      mode_value := std_logic_vector(to_unsigned(mode_number, 2));

      for width_index in TEST_WIDTHS'range loop
        width_value       := TEST_WIDTHS(width_index);
        master_tx         := TEST_PATTERNS(transaction_index mod TEST_PATTERNS'length);
        slave_tx          := TEST_PATTERNS((transaction_index + 5) mod TEST_PATTERNS'length);
        transaction_index := transaction_index + 1;

        si.mode       <= mode_value;
        si.data_width <= to_unsigned(width_value, si.data_width'length);
        si.tx_data    <= slave_tx;

        v_config                  := C_SPI_BFM_CONFIG_DEFAULT;
        v_config.CPOL            := mode_value(1);
        v_config.CPHA            := mode_value(0);
        if width_value = 1 then
          v_config.spi_bit_time := 80 ns;
        else
          v_config.spi_bit_time := TEST_BIT_TIMES((mode_number + width_index) mod TEST_BIT_TIMES'length) * 1 ns;
        end if;
        v_config.ss_n_to_sclk    := 35 ns;
        v_config.sclk_to_ss_n     := 25 ns;
        v_config.inter_word_delay := 0 ns;

        wait until rising_edge(clk);
        wait until rising_edge(clk);
        slave_events_before := slave_rx_events;
        arm_monitor(mode_value, width_value, master_tx, slave_tx, true,
                    v_config.spi_bit_time / 2);

        bfm_rx := (others => '0');
        if width_value = 1 then
          drive_one_bit_master(mode_value, master_tx(0), bfm_rx(0));
        else
          spi_master_transmit_and_receive(
            tx_data => master_tx(width_value - 1 downto 0),
            rx_data => bfm_rx(width_value - 1 downto 0),
            msg     => "slave DUT transaction",
            sclk    => bfm_sclk,
            ss_n    => bfm_ss_n,
            mosi    => bfm_mosi,
            miso    => so.miso,
            config  => v_config
          );
        end if;

        wait_for_monitor("slave independent transaction");
        wait until rising_edge(clk);

        check(slave_rx_events = slave_events_before + 1,
              "Slave rx_valid count mismatch: mode=" & integer'image(mode_number) &
              " width=" & integer'image(width_value));
        check(masked(slave_rx_capture, width_value) = masked(master_tx, width_value),
              "Slave RX mismatch: mode=" & integer'image(mode_number) &
              " width=" & integer'image(width_value));
        check((slave_rx_capture and not low_mask(width_value)) = x"00000000",
              "Slave RX upper bits are not zero: width=" & integer'image(width_value));
        check(slave_rx_pulse_error = '0', "Slave rx_valid exceeded one cycle");
        check(masked(bfm_rx, width_value) = masked(slave_tx, width_value),
              "UVVM master RX mismatch: mode=" & integer'image(mode_number) &
              " width=" & integer'image(width_value));
        check(monitor_errors = SPI_MON_NO_ERRORS,
              "Slave wire-protocol error: mode=" & integer'image(mode_number) &
              " width=" & integer'image(width_value) &
              " flags=0x" & to_hstring(monitor_errors));

        slave_tests := slave_tests + 1;
      end loop;
    end loop;

    report "Slave independent: " & integer'image(slave_tests) & "/32 PASS"
      severity note;

    slave_events_before := slave_rx_events;
    si.mode       <= "00";
    si.data_width <= to_unsigned(0, si.data_width'length);
    si.tx_data    <= (others => '0');
    bfm_sclk <= '0';
    bfm_mosi <= '0';
    bfm_ss_n <= '0';
    for cycle in 1 to 4 loop
      wait until rising_edge(clk);
    end loop;
    check(so.busy = '0' and slave_rx_events = slave_events_before,
          "Slave accepted zero data width");
    bfm_ss_n <= '1';
    wait until rising_edge(clk);
    slave_control_tests := slave_control_tests + 1;

    si.data_width <= to_unsigned(33, si.data_width'length);
    bfm_ss_n <= '0';
    for cycle in 1 to 4 loop
      wait until rising_edge(clk);
    end loop;
    check(so.busy = '0' and slave_rx_events = slave_events_before,
          "Slave accepted data width 33");
    bfm_ss_n <= '1';
    wait until rising_edge(clk);
    slave_control_tests := slave_control_tests + 1;

    mode_value := "11";
    master_tx  := x"0000003C";
    slave_tx   := x"000000C3";
    si.mode       <= mode_value;
    si.data_width <= to_unsigned(8, si.data_width'length);
    si.tx_data    <= slave_tx;
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    slave_events_before := slave_rx_events;
    arm_monitor(mode_value, 8, master_tx, slave_tx, true, 40 ns);
    drive_manual_frame(mode_value, 8, master_tx, true, bfm_rx);
    wait_for_monitor("slave configuration capture");
    wait until rising_edge(clk);
    check(slave_rx_events = slave_events_before + 1,
          "Slave configuration-capture rx_valid mismatch");
    check(masked(slave_rx_capture, 8) = masked(master_tx, 8),
          "Slave configuration changed while selected");
    check(masked(bfm_rx, 8) = masked(slave_tx, 8),
          "Slave transmit data changed while selected");
    check(monitor_errors = SPI_MON_NO_ERRORS,
          "Slave configuration-capture protocol error");
    slave_control_tests := slave_control_tests + 1;

    si.mode       <= "00";
    si.data_width <= to_unsigned(8, si.data_width'length);
    si.tx_data    <= x"000000A5";
    bfm_sclk <= '0';
    bfm_mosi <= '1';
    bfm_ss_n <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    slave_events_before := slave_rx_events;
    bfm_sclk <= '1';
    wait for 40 ns;
    bfm_sclk <= '0';
    wait for 20 ns;
    bfm_ss_n <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    check(so.busy = '0' and slave_rx_events = slave_events_before,
          "Slave completed after premature CS release");
    slave_control_tests := slave_control_tests + 1;

    bfm_sclk <= '0';
    bfm_ss_n <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    check(so.busy = '1', "Slave did not start reset-abort test");
    slave_events_before := slave_rx_events;
    rst <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    check(so.busy = '0' and so.rx_valid = '0' and so.rx_count = 0,
          "Slave did not return to reset state during a transfer");
    check(slave_rx_events = slave_events_before,
          "Slave produced rx_valid while reset aborted a transfer");
    bfm_ss_n <= '1';
    rst <= '0';
    wait until rising_edge(clk);
    slave_control_tests := slave_control_tests + 1;

    report "Slave controls: " & integer'image(slave_control_tests) & "/5 PASS"
      severity note;

    -------------------------------------------------------------------------
    -- Original master/slave loopback matrix under the independent monitor
    -------------------------------------------------------------------------
    phase <= PHASE_LOOPBACK;
    wait until rising_edge(clk);

    for mode_number in 0 to 3 loop
      mode_value := std_logic_vector(to_unsigned(mode_number, 2));

      for width_index in LOOPBACK_WIDTHS'range loop
        width_value := LOOPBACK_WIDTHS(width_index);
        master_tx   := x"A5C39E71" xor std_logic_vector(to_unsigned(mode_number, 32));
        slave_tx    := x"5A3C618E" xor std_logic_vector(to_unsigned(width_value, 32));

        mi.mode       <= mode_value;
        mi.sclk_div   <= to_unsigned(width_index + 1, mi.sclk_div'length);
        mi.data_width <= to_unsigned(width_value, mi.data_width'length);
        mi.tx_data    <= master_tx;
        si.mode       <= mode_value;
        si.data_width <= to_unsigned(width_value, si.data_width'length);
        si.tx_data    <= slave_tx;

        wait until rising_edge(clk);
        wait until rising_edge(clk);
        master_events_before := master_rx_events;
        slave_events_before  := slave_rx_events;
        arm_monitor(mode_value, width_value, master_tx, slave_tx, true,
                    (width_index + 2) * CLK_PERIOD);

        mi.start <= '1';
        wait until rising_edge(clk);
        mi.start <= '0';

        completed := false;
        for cycle in 1 to 5000 loop
          wait until rising_edge(clk);
          if master_rx_events = master_events_before + 1 and
             slave_rx_events = slave_events_before + 1 then
            completed := true;
            exit;
          end if;
        end loop;

        check(completed,
              "Loopback timeout: mode=" & integer'image(mode_number) &
              " width=" & integer'image(width_value));
        wait_for_monitor("loopback transaction");
        wait for 0 ns;

        check(masked(master_rx_capture, width_value) = masked(slave_tx, width_value),
              "Loopback master RX mismatch: mode=" & integer'image(mode_number) &
              " width=" & integer'image(width_value));
        check(master_rx_pulse_error = '0' and slave_rx_pulse_error = '0',
              "Loopback rx_valid exceeded one cycle");
        check(masked(slave_rx_capture, width_value) = masked(master_tx, width_value),
              "Loopback slave RX mismatch: mode=" & integer'image(mode_number) &
              " width=" & integer'image(width_value));
        check(monitor_errors = SPI_MON_NO_ERRORS,
              "Loopback wire-protocol error: mode=" & integer'image(mode_number) &
              " width=" & integer'image(width_value) &
              " flags=0x" & to_hstring(monitor_errors));

        loopback_tests := loopback_tests + 1;
      end loop;
    end loop;

    report "Master/slave loopback: " & integer'image(loopback_tests) & "/16 PASS"
      severity note;

    report "SPI regression summary: monitor=" & integer'image(monitor_tests) &
           " master=" & integer'image(master_tests) &
           " master_control=" & integer'image(master_control_tests) &
           " slave=" & integer'image(slave_tests) &
           " slave_control=" & integer'image(slave_control_tests) &
           " loopback=" & integer'image(loopback_tests) &
           " errors=" & integer'image(errors)
      severity note;

    assert errors = 0
      report "SPI REGRESSION FAILED"
      severity failure;

    report "SPI REGRESSION PASSED" severity note;
    sim_end <= true;
    wait;
  end process test_driver;

end architecture sim;
