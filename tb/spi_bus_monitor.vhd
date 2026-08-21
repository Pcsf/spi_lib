library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.spi_bus_monitor_pkg.all;

entity spi_bus_monitor is
  generic (
    G_TIMEOUT : time := 2 ms
  );
  port (
    arm                  : in  std_logic;
    mode                 : in  std_logic_vector(1 downto 0);
    data_width           : in  unsigned(5 downto 0);
    expected_mosi        : in  std_logic_vector(31 downto 0);
    expected_miso        : in  std_logic_vector(31 downto 0);
    check_clock_period   : in  std_logic;
    expected_half_period : in  time;
    cs_n                 : in  std_logic;
    sclk                 : in  std_logic;
    mosi                 : in  std_logic;
    miso                 : in  std_logic;
    done                 : out std_logic;
    errors               : out spi_monitor_errors_type;
    observed_mosi        : out std_logic_vector(31 downto 0);
    observed_miso        : out std_logic_vector(31 downto 0);
    edge_count           : out natural
  );
end entity spi_bus_monitor;

architecture sim of spi_bus_monitor is
begin
  monitor : process
    variable v_errors        : spi_monitor_errors_type := (others => '0');
    variable v_observed_mosi : std_logic_vector(31 downto 0);
    variable v_observed_miso : std_logic_vector(31 downto 0);
    variable v_width         : natural;
    variable v_samples       : natural;
    variable v_edges         : natural;
    variable v_expected_sclk : std_logic;
    variable v_previous_edge : time;
    variable v_timed_out     : boolean;
    variable v_frame_ended   : boolean;
    variable v_sample_edge   : boolean;
    variable v_bit_index     : natural;
  begin
    done          <= '0';
    errors        <= (others => '0');
    observed_mosi <= (others => '0');
    observed_miso <= (others => '0');
    edge_count    <= 0;

    loop
      wait on arm;

      v_errors        := (others => '0');
      v_observed_mosi := (others => '0');
      v_observed_miso := (others => '0');
      v_width         := to_integer(data_width);
      v_samples       := 0;
      v_edges         := 0;
      v_previous_edge := 0 ns;
      v_timed_out     := false;
      v_frame_ended   := false;

      if v_width < 1 or v_width > 32 then
        v_errors(SPI_MON_EDGE_COUNT) := '1';
      else
        if cs_n /= '0' then
          wait until cs_n = '0' for G_TIMEOUT;
        end if;

        if cs_n /= '0' then
          v_errors(SPI_MON_TIMEOUT) := '1';
          v_timed_out := true;
        else
          wait for 0 ns;
          if to_x01(sclk) /= mode(1) then
            v_errors(SPI_MON_IDLE_POLARITY) := '1';
          end if;
        end if;

        if not v_timed_out then
          for edge_number in 0 to 2 * v_width - 1 loop
            wait on sclk, cs_n for G_TIMEOUT;

            if cs_n = '1' then
              v_errors(SPI_MON_PREMATURE_CS) := '1';
              v_frame_ended := true;
              exit;
            elsif not sclk'event then
              v_errors(SPI_MON_TIMEOUT) := '1';
              v_timed_out := true;
              exit;
            end if;

            wait for 0 ns;
            v_edges := v_edges + 1;

            if edge_number mod 2 = 0 then
              v_expected_sclk := not mode(1);
            else
              v_expected_sclk := mode(1);
            end if;

            if to_x01(sclk) /= v_expected_sclk then
              v_errors(SPI_MON_EDGE_SEQUENCE) := '1';
            end if;

            if check_clock_period = '1' and edge_number > 0 then
              if now - v_previous_edge /= expected_half_period then
                v_errors(SPI_MON_CLOCK_PERIOD) := '1';
              end if;
            end if;
            v_previous_edge := now;

            v_sample_edge := (mode(0) = '0' and edge_number mod 2 = 0) or
                             (mode(0) = '1' and edge_number mod 2 = 1);

            if v_sample_edge then
              v_bit_index := v_width - v_samples - 1;

              if mosi'last_event = 0 ns or miso'last_event = 0 ns then
                v_errors(SPI_MON_DATA_TIMING) := '1';
              end if;

              v_observed_mosi(v_bit_index) := to_x01(mosi);
              v_observed_miso(v_bit_index) := to_x01(miso);

              if to_x01(mosi) /= expected_mosi(v_bit_index) then
                v_errors(SPI_MON_MOSI_DATA) := '1';
              end if;
              if to_x01(miso) /= expected_miso(v_bit_index) then
                v_errors(SPI_MON_MISO_DATA) := '1';
              end if;

              v_samples := v_samples + 1;
            end if;
          end loop;
        end if;

        if not v_timed_out and not v_frame_ended then
          loop
            wait on sclk, cs_n for G_TIMEOUT;
            if cs_n = '1' then
              exit;
            elsif sclk'event then
              v_errors(SPI_MON_EDGE_COUNT) := '1';
              v_edges := v_edges + 1;
            else
              v_errors(SPI_MON_TIMEOUT) := '1';
              exit;
            end if;
          end loop;

          wait for 0 ns;
          if to_x01(sclk) /= mode(1) then
            v_errors(SPI_MON_IDLE_POLARITY) := '1';
          end if;
        end if;
      end if;

      if v_edges /= 2 * v_width and
         v_errors(SPI_MON_PREMATURE_CS) = '0' and
         v_errors(SPI_MON_TIMEOUT) = '0' then
        v_errors(SPI_MON_EDGE_COUNT) := '1';
      end if;

      errors        <= v_errors;
      observed_mosi <= v_observed_mosi;
      observed_miso <= v_observed_miso;
      edge_count    <= v_edges;
      done          <= arm;
    end loop;
  end process monitor;
end architecture sim;
