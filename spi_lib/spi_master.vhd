-------------------------------------------------------------------------------
-- Entity   : spi_master
-- Description: Full-duplex SPI master supporting all 4 modes (0-3),
--              configurable SCLK divider (sysclk / (2*(N+1))), and
--              data widths 1-32 bits.  Auto-manages CS, SCLK, and MOSI.
-- Method   : Gaisler two-process structured VHDL (synchronous reset)
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.spi_master_pkg.all;

entity spi_master is
  port (
    clk  : in  std_logic;
    rst  : in  std_logic;
    miso : in  std_logic;
    mi   : in  spi_master_in_type;
    mo   : out spi_master_out_type);
end entity spi_master;

architecture rtl of spi_master is

  -- State enumeration
  type state_type is (
    SPI_IDLE,
    SPI_START,
    SPI_TRANSFER,
    SPI_FINISH
  );

  -- Register state record — ALL flip-flop state lives here
  type reg_type is record
    state           : state_type;

    -- SCLK generation
    sclk_half_cnt   : unsigned(8 downto 0);
    sclk_half_period: unsigned(8 downto 0);
    sclk_level      : std_logic;

    -- Data registers
    tx_shreg        : std_logic_vector(31 downto 0);
    rx_shreg        : std_logic_vector(31 downto 0);
    bit_idx         : unsigned(4 downto 0);
    tx_count        : unsigned(4 downto 0);
    data_width      : unsigned(4 downto 0);

    -- Outputs (driven by registered value)
    mosi_out        : std_logic;
    cs_out          : std_logic;

    -- Status
    busy            : std_logic;
    rx_valid        : std_logic;
    rx_data_out     : std_logic_vector(31 downto 0);

    -- Mode
    cpol            : std_logic;
    cpha            : std_logic;
  end record;

  -- Reset values
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

  -- =====================================================================
  -- Combinational process: all logic, algorithm, and state transitions
  -- =====================================================================
  comb : process(mi, r, miso)
    variable v : reg_type;
  begin
    -- 1. Default: copy current state (prevents inferred latches)
    v := r;

    -- 2. Unconditional input latching
    v.cpol   := mi.mode(1);
    v.cpha   := mi.mode(0);
    v.data_width := mi.data_width;

    -- 3. Default output values (overridden in relevant states)
    v.mosi_out := r.cpol;            -- idle = CPOL level
    v.cs_out   := '1';               -- default deasserted
    v.busy     := '0';
    v.rx_valid := '0';
    v.sclk_level := r.cpol;          -- SCLK idle level

    -- 4. State machine
    case r.state is

      -- ---------------------------------------------------------------
      -- IDLE: waiting for transfer request
      -- ---------------------------------------------------------------
      when SPI_IDLE =>
        if mi.start = '1'
           and mi.data_width >= 1
           and mi.data_width <= 32 then
          v.state := SPI_START;
        end if;

      -- ---------------------------------------------------------------
      -- START: load data, assert CS, configure SCLK
      -- ---------------------------------------------------------------
      when SPI_START =>
        v.busy := '1';

        -- Configure SCLK half-period (system clock / (2*(div+1)))
        v.sclk_half_period := unsigned(mi.sclk_div) + 1;
        v.sclk_half_cnt    := (others => '0');

        -- Load TX data, clear RX, set counters
        v.tx_shreg   := mi.tx_data;
        v.rx_shreg   := (others => '0');
        v.bit_idx    := to_integer(mi.data_width) - 1;
        v.tx_count   := mi.data_width;

        -- Assert CS (active low)
        v.cs_out := '0';

        -- Set MOSI to MSB immediately
        v.mosi_out := mi.tx_data(to_integer(mi.data_width) - 1);

        v.state := SPI_TRANSFER;

      -- ---------------------------------------------------------------
      -- TRANSFER: shift bits, toggle SCLK
      -- ---------------------------------------------------------------
      when SPI_TRANSFER =>
        -- Default MOSI to current bit; updated on SCLK edges below
        v.mosi_out := r.tx_shreg(to_integer(r.bit_idx));

        if r.sclk_half_cnt = r.sclk_half_period - 1 then
          -- SCLK half-period elapsed → clock edge
          v.sclk_half_cnt := (others => '0');

          if r.sclk_level = r.cpol then
            -- Rising from idle to active level
            v.sclk_level := not r.cpol;

            if r.cpha = '0' then
              -- CPHA = 0: sample MISO on active edge
              v.rx_shreg(to_integer(r.bit_idx)) := miso;
            else
              -- CPHA = 1: ensure MOSI is correct on active edge
              v.mosi_out := r.tx_shreg(to_integer(r.bit_idx));
            end if;

          else
            -- Falling from active back to idle level
            v.sclk_level := r.cpol;

            if r.cpha = '0' then
              -- CPHA = 0: shift next MOSI bit on idle edge
              if r.tx_count = 1 then
                -- Last bit — transfer complete
                v.state := SPI_FINISH;
              else
                v.mosi_out := r.tx_shreg(to_integer(r.bit_idx) - 1);
                v.bit_idx  := r.bit_idx - 1;
                v.tx_count := r.tx_count - 1;
              end if;

            else
              -- CPHA = 1: sample MISO on idle edge
              v.rx_shreg(to_integer(r.bit_idx)) := miso;

              if r.tx_count = 1 then
                -- Last bit — transfer complete
                v.state := SPI_FINISH;
              else
                v.bit_idx  := r.bit_idx - 1;
                v.tx_count := r.tx_count - 1;
              end if;
            end if;
          end if;

        else
          -- Still counting toward half-period
          v.sclk_half_cnt := r.sclk_half_cnt + 1;
        end if;

      -- ---------------------------------------------------------------
      -- FINISH: deassert CS, drive received data, return to IDLE
      -- ---------------------------------------------------------------
      when SPI_FINISH =>
        v.cs_out      := '1';             -- deassert CS
        v.rx_valid    := '1';             -- pulse: one cycle
        v.rx_data_out := r.rx_shreg;
        v.busy        := '0';
        v.sclk_level  := r.cpol;          -- SCLK back to idle
        v.state       := SPI_IDLE;        -- advance next cycle

      -- ---------------------------------------------------------------
      -- Others (safety catch)
      -- ---------------------------------------------------------------
      when others =>
        v.state := SPI_IDLE;

    end case;

    -- 5. Drive register inputs
    rin <= v;

    -- 6. Drive outputs from REGISTERED values
    mo.sclk     <= r.sclk_level;
    mo.mosi     <= r.mosi_out;
    mo.cs_n     <= r.cs_out;
    mo.busy     <= r.busy;
    mo.rx_valid <= r.rx_valid;
    mo.rx_data  <= r.rx_data_out;
    mo.tx_count <= r.tx_count;

    -- Synchronous reset — LAST statement, highest priority
    if rst = '1' then
      v := REG_RESET;
    end if;

  end process comb;

  -- =====================================================================
  -- Sequential process: single registered update
  -- =====================================================================
  regs : process(clk)
  begin
    if rising_edge(clk) then
      r <= rin;
    end if;
  end process regs;

end architecture rtl;
