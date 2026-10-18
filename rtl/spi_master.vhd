-------------------------------------------------------------------------------
-- Entity     : spi_master
-- Description: Full-duplex SPI master, modes 0-3, MSB first, 1-32 bit frames.
--              Drives cs_n for the whole frame.
-- Method     : Gaisler two-process, synchronous reset
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.spi_master_pkg.all;

entity spi_master is
  port (
    clk : in  std_logic;
    rst : in  std_logic;
    mi  : in  spi_master_in_type;
    mo  : out spi_master_out_type);
end entity spi_master;

architecture rtl of spi_master is

  type state_type is (
    SPI_IDLE,
    SPI_START,
    SPI_TRANSFER,
    SPI_FINISH
  );

  type reg_type is record
    state           : state_type;

    sclk_half_cnt   : unsigned(8 downto 0);
    sclk_half_period: unsigned(8 downto 0);
    sclk_level      : std_logic;

    tx_shreg        : std_logic_vector(31 downto 0);
    rx_shreg        : std_logic_vector(31 downto 0);
    bit_idx         : unsigned(5 downto 0);
    tx_count        : unsigned(5 downto 0);
    data_width      : unsigned(5 downto 0);

    mosi_out        : std_logic;
    cs_out          : std_logic;

    busy            : std_logic;
    rx_valid        : std_logic;
    rx_data_out     : std_logic_vector(31 downto 0);

    cpol            : std_logic;
    cpha            : std_logic;
  end record;

  constant REG_RESET : reg_type := (
    state           => SPI_IDLE,
    sclk_half_cnt   => (others => '0'),
    sclk_half_period=> (others => '0'),
    sclk_level      => '0',
    tx_shreg        => (others => '0'),
    rx_shreg        => (others => '0'),
    bit_idx         => (others => '0'),
    tx_count        => (others => '0'),
    data_width      => (others => '0'),
    mosi_out        => '0',
    cs_out          => '1',
    busy            => '0',
    rx_valid        => '0',
    rx_data_out     => (others => '0'),
    cpol            => '0',
    cpha            => '0'
  );

  signal r, rin : reg_type;

begin

  comb : process(all)
    variable v       : reg_type;
    variable width_i : integer;
  begin
    v := r;

    v.rx_valid := '0';

    case r.state is

      when SPI_IDLE =>
        v.mosi_out  := '0';
        v.cs_out    := '1';
        v.busy      := '0';
        v.sclk_level := mi.mode(1);

        if mi.start = '1'
           and mi.data_width >= to_unsigned(1, mi.data_width'length)
           and mi.data_width <= to_unsigned(32, mi.data_width'length) then
          v.cpol             := mi.mode(1);
          v.cpha             := mi.mode(0);
          v.data_width       := mi.data_width;
          v.sclk_half_period := resize(mi.sclk_div, 9) + to_unsigned(1, 9);
          v.tx_shreg         := mi.tx_data;
          v.state            := SPI_START;
        end if;

      when SPI_START =>
        v.busy := '1';

        v.sclk_half_cnt := (others => '0');
        v.sclk_level    := r.cpol;
        v.rx_shreg      := (others => '0');
        v.tx_count      := r.data_width;
        width_i         := to_integer(r.data_width);
        v.bit_idx       := to_unsigned(width_i - 1, 6);

        -- The first bit is on MOSI before the first SCLK edge in every mode.
        v.cs_out   := '0';
        v.mosi_out := r.tx_shreg(width_i - 1);

        v.state := SPI_TRANSFER;

      when SPI_TRANSFER =>
        v.cs_out := '0';
        v.busy   := '1';
        width_i  := to_integer(r.bit_idx);

        v.mosi_out := r.tx_shreg(width_i);

        if r.sclk_half_cnt = r.sclk_half_period - to_unsigned(1, 9) then
          v.sclk_half_cnt := (others => '0');

          if r.sclk_level = r.cpol then
            -- Leading edge: SCLK leaves its idle level.
            v.sclk_level := not r.cpol;

            if r.cpha = '0' then
              v.rx_shreg(width_i) := mi.miso;
            end if;

          else
            -- Trailing edge: SCLK returns to its idle level.
            v.sclk_level := r.cpol;

            if r.cpha = '0' then
              if r.tx_count = to_unsigned(1, 6) then
                v.tx_count := (others => '0');
                v.state    := SPI_FINISH;
              else
                width_i := width_i - 1;
                v.mosi_out := r.tx_shreg(width_i);
                v.bit_idx  := to_unsigned(width_i, 6);
                v.tx_count := r.tx_count - to_unsigned(1, 6);
              end if;

            else
              v.rx_shreg(width_i) := mi.miso;

              -- MOSI follows bit_idx one clk after this edge.
              if r.tx_count = to_unsigned(1, 6) then
                v.tx_count := (others => '0');
                v.state    := SPI_FINISH;
              else
                width_i := width_i - 1;
                v.bit_idx  := to_unsigned(width_i, 6);
                v.tx_count := r.tx_count - to_unsigned(1, 6);
              end if;
            end if;
          end if;

        else
          v.sclk_half_cnt := r.sclk_half_cnt + to_unsigned(1, 9);
        end if;

      when SPI_FINISH =>
        v.cs_out      := '1';
        v.rx_valid    := '1';
        v.rx_data_out := r.rx_shreg;
        v.busy        := '0';
        v.sclk_level  := r.cpol;
        v.state       := SPI_IDLE;

      when others =>
        v.state := SPI_IDLE;

    end case;

    if rst = '1' then
      v := REG_RESET;
    end if;

    rin <= v;

    mo.sclk     <= r.sclk_level;
    mo.mosi     <= r.mosi_out;
    mo.cs_n     <= r.cs_out;
    mo.busy     <= r.busy;
    mo.rx_valid <= r.rx_valid;
    mo.rx_data  <= r.rx_data_out;
    mo.tx_count <= r.tx_count;

  end process comb;

  regs : process(clk)
  begin
    if rising_edge(clk) then
      r <= rin;
    end if;
  end process regs;

end architecture rtl;
