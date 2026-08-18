-------------------------------------------------------------------------------
-- Package : spi_slave_pkg
-- Description: Port record types and component declaration for SPI slave
-- Author   : Generated using Gaisler two-process methodology
-- Notes    : Vendor-agnostic SPI slave supporting all 4 SPI modes (0-3),
--            configurable data widths 1-32 bits.  Responds to master-driven
--            clock and chip-select.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package spi_slave_pkg is

  ---------------------------------------------------------------------------
  -- Input port record  (driven by master's SPI bus signals)
  ---------------------------------------------------------------------------
  type spi_slave_in_type is record
    mode        : std_logic_vector(1 downto 0);  -- {CPOL, CPHA}
    data_width  : unsigned(4 downto 0);          -- 1 .. 32 bits
    tx_data     : std_logic_vector(31 downto 0); -- data to transmit
    cs_n        : std_logic;                     -- chip-select (active-low)
    sclk        : std_logic;                     -- serial clock from master
    mosi        : std_logic;                     -- master-out, slave-in
  end record;

  ---------------------------------------------------------------------------
  -- Output port record
  ---------------------------------------------------------------------------
  type spi_slave_out_type is record
    miso        : std_logic;                     -- slave-out, master-in
    busy        : std_logic;                     -- transfer in progress
    rx_valid    : std_logic;                     -- rx_data valid pulse
    rx_data     : std_logic_vector(31 downto 0); -- received data
    rx_count    : unsigned(4 downto 0);          -- bits remaining
  end record;

  ---------------------------------------------------------------------------
  -- Component declaration
  ---------------------------------------------------------------------------
  component spi_slave
    port (
      clk : in  std_logic;
      rst : in  std_logic;
      mi  : in  spi_slave_in_type;
      mo  : out spi_slave_out_type);
  end component;

end package spi_slave_pkg;
