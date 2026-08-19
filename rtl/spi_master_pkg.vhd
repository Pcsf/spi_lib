-------------------------------------------------------------------------------
-- Package : spi_master_pkg
-- Description: Port record types and component declaration for SPI master
-- Author   : Generated using Gaisler two-process methodology
-- Notes    : Vendor-agnostic SPI master supporting all 4 SPI modes (0-3),
--            configurable clock speed (1/2 to sysclk/512), and data widths
--            from 1 to 32 bits.  Standard microcontroller-like register
--            interface.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package spi_master_pkg is

  ---------------------------------------------------------------------------
  -- Input port record  (driven by host firmware / control logic)
  ---------------------------------------------------------------------------
  type spi_master_in_type is record
    start       : std_logic;                       -- launch transfer
    mode        : std_logic_vector(1 downto 0);    -- {CPOL, CPHA} 0-3
    sclk_div    : unsigned(7 downto 0);            -- half-period divider
    data_width  : unsigned(5 downto 0);            -- 1 .. 32 bits
    tx_data     : std_logic_vector(31 downto 0);   -- data to transmit
  end record;

  ---------------------------------------------------------------------------
  -- Output port record (consumed by host firmware / control logic)
  ---------------------------------------------------------------------------
  type spi_master_out_type is record
    mosi        : std_logic;                       -- master-out, slave-in
    sclk        : std_logic;                       -- serial clock
    cs_n        : std_logic;                       -- chip-select (active-low)
    busy        : std_logic;                       -- transfer in progress
    rx_valid    : std_logic;                       -- rx_data valid pulse
    rx_data     : std_logic_vector(31 downto 0);   -- received data
    tx_count    : unsigned(5 downto 0);            -- bits remaining
  end record;

  ---------------------------------------------------------------------------
  -- Component declaration
  ---------------------------------------------------------------------------
  component spi_master
    port (
      clk  : in  std_logic;
      rst  : in  std_logic;
      miso : in  std_logic;                     -- slave-in, master-out
      mi   : in  spi_master_in_type;
      mo   : out spi_master_out_type);
  end component;

end package spi_master_pkg;
