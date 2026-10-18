-------------------------------------------------------------------------------
-- Package    : spi_master_pkg
-- Description: Port records and component declaration for spi_master.
--              Modes 0-3, MSB first, 1-32 bit frames,
--              f_sclk = f_clk / (2 * (sclk_div + 1)).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package spi_master_pkg is

  -- mode, sclk_div, data_width and tx_data are captured on the clk edge that
  -- accepts start, and may change while busy = '1'.
  type spi_master_in_type is record
    start       : std_logic;                       -- accepted only while idle
    mode        : std_logic_vector(1 downto 0);    -- CPOL & CPHA
    sclk_div    : unsigned(7 downto 0);
    data_width  : unsigned(5 downto 0);            -- 1 to 32, else start is ignored
    tx_data     : std_logic_vector(31 downto 0);   -- right-aligned
    miso        : std_logic;                       -- master in, slave out
  end record;

  type spi_master_out_type is record
    mosi        : std_logic;                       -- master out, slave in
    sclk        : std_logic;
    cs_n        : std_logic;
    busy        : std_logic;
    rx_valid    : std_logic;                       -- one clk, as cs_n rises
    rx_data     : std_logic_vector(31 downto 0);   -- right-aligned
    tx_count    : unsigned(5 downto 0);            -- bits left in the frame
  end record;

  component spi_master
    port (
      clk : in  std_logic;
      rst : in  std_logic;
      mi  : in  spi_master_in_type;
      mo  : out spi_master_out_type);
  end component;

end package spi_master_pkg;
