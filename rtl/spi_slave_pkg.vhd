-------------------------------------------------------------------------------
-- Package    : spi_slave_pkg
-- Description: Port records and component declaration for spi_slave.
--              Modes 0-3, MSB first, 1-32 bit frames.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package spi_slave_pkg is

  -- mode, data_width and tx_data are captured when the slave sees cs_n low,
  -- and may change while busy = '1'.
  --
  -- cs_n, sclk and mosi pass through SYNC_STAGES flops (default 2; 0 only when
  -- the master runs on clk). MISO, and busy after cs_n falls, then change up
  -- to (SYNC_STAGES + 1) clk periods after the edge that causes them. Half an
  -- SCLK period, and the master's cs_n-to-first-SCLK delay, must exceed that
  -- plus the MISO output and board delay and the master's MISO setup time.
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
    generic (
      SYNC_STAGES : natural := 2);
    port (
      clk : in  std_logic;
      rst : in  std_logic;
      mi  : in  spi_slave_in_type;
      mo  : out spi_slave_out_type);
  end component;

end package spi_slave_pkg;
