library ieee;
use ieee.std_logic_1164.all;

package spi_bus_monitor_pkg is
  subtype spi_monitor_errors_type is std_logic_vector(8 downto 0);
  constant SPI_MON_NO_ERRORS : spi_monitor_errors_type := (others => '0');

  constant SPI_MON_MOSI_DATA      : natural := 0;
  constant SPI_MON_MISO_DATA      : natural := 1;
  constant SPI_MON_IDLE_POLARITY  : natural := 2;
  constant SPI_MON_EDGE_SEQUENCE  : natural := 3;
  constant SPI_MON_EDGE_COUNT     : natural := 4;
  constant SPI_MON_PREMATURE_CS   : natural := 5;
  constant SPI_MON_DATA_TIMING    : natural := 6;
  constant SPI_MON_CLOCK_PERIOD   : natural := 7;
  constant SPI_MON_TIMEOUT        : natural := 8;
end package spi_bus_monitor_pkg;
