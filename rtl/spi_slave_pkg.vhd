-------------------------------------------------------------------------------
-- Package    : spi_slave_pkg
-- Description: Port records and component declaration for spi_slave.
--              Modes 0-3, MSB first, 1-32 bit frames.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package spi_slave_pkg is

  -- mode, data_width and tx_data are captured on the clk edge that sees cs_n
  -- low, and may change while busy = '1'. cs_n, sclk and mosi are sampled
  -- directly by clk: synchronise them to clk before this entity.
  type spi_slave_in_type is record
    mode        : std_logic_vector(1 downto 0);  -- CPOL & CPHA
    data_width  : unsigned(5 downto 0);          -- 1 to 32, else the frame is ignored
    tx_data     : std_logic_vector(31 downto 0); -- right-aligned
    cs_n        : std_logic;
    sclk        : std_logic;
    mosi        : std_logic;                     -- master out, slave in
  end record;

  type spi_slave_out_type is record
    miso        : std_logic;                     -- master in, slave out
    busy        : std_logic;
    rx_valid    : std_logic;                     -- one clk, after the last SCLK edge
    rx_data     : std_logic_vector(31 downto 0); -- right-aligned
    rx_count    : unsigned(5 downto 0);          -- bits left in the frame
  end record;

  component spi_slave
    port (
      clk : in  std_logic;
      rst : in  std_logic;
      mi  : in  spi_slave_in_type;
      mo  : out spi_slave_out_type);
  end component;

end package spi_slave_pkg;
