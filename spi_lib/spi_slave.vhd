-------------------------------------------------------------------------------
-- Entity   : spi_slave
-- Description: Full-duplex SPI slave responding to master-driven SCLK and
--              chip-select.  Supports all 4 SPI modes and data widths 1-32
--              bits.
-- Method   : Gaisler two-process structured VHDL (synchronous reset)
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.spi_slave_pkg.all;

entity spi_slave is
  port (
    clk : in  std_logic;
    rst : in  std_logic;
    mi  : in  spi_slave_in_type;
    mo  : out spi_slave_out_type);
end entity spi_slave;

architecture rtl of spi_slave is

  -- State enumeration
  type state_type is (
    SLAVE_IDLE,
    SLAVE_ACTIVE,
    SLAVE_DONE
  );

  -- Register state record — ALL flip-flop state lives here
  type reg_type is record
    state          : state_type;

    -- Data registers
    tx_shreg       : std_logic_vector(31 downto 0);
    rx_shreg       : std_logic_vector(31 downto 0);
    bit_idx        : unsigned(4 downto 0);
    tx_count       : unsigned(4 downto 0);
    data_width     : unsigned(4 downto 0);

    -- Outputs
    miso_out       : std_logic;
    busy           : std_logic;
    rx_valid       : std_logic;
    rx_data_out    : std_logic_vector(31 downto 0);
    rx_count_out   : unsigned(4 downto 0);

    -- Mode
    cpol           : std_logic;
    cpha           : std_logic;

    -- SCLK delay for edge detection
    sclk_d1        : std_logic;
  end record;

  -- Reset values
  constant REG_RESET : reg_type := (
    state          => SLAVE_IDLE,
    tx_shreg       => (others => '0'),
    rx_shreg       => (others => '0'),
    bit_idx        => (others => '0'),
    tx_count       => (others => '0'),
    data_width     => (others => '0'),
    miso_out       => '0',
    busy           => '0',
    rx_valid       => '0',
    rx_data_out    => (others => '0'),
    rx_count_out   => (others => '0'),
    cpol           => '0',
    cpha           => '0',
    sclk_d1        => '0'
  );

  signal r, rin : reg_type;

begin

  -- =====================================================================
  -- Combinational process: all logic, algorithm, and state transitions
  -- =====================================================================
  comb : process(mi, r)
    variable v : reg_type;
  begin
    -- 1. Default: copy current state (prevents inferred latches)
    v := r;

    -- 2. Unconditional input latching
    v.cpol   := mi.mode(1);
    v.cpha   := mi.mode(0);
    v.data_width := mi.data_width;

    -- 3. Default output values (overridden in relevant states)
    v.miso_out   := '0';
    v.busy       := '0';
    v.rx_valid   := '0';
    v.sclk_d1    := mi.sclk;      -- captured for next cycle's edge detection

    -- 4. State machine
    case r.state is

      -- ---------------------------------------------------------------
      -- IDLE: waiting for CS low
      -- ---------------------------------------------------------------
      when SLAVE_IDLE =>
        v.miso_out := '0';
        v.rx_count_out := (others => '0');

        if mi.cs_n = '0'
           and mi.data_width >= 1
           and mi.data_width <= 32 then
          v.busy  := '1';
          v.tx_shreg  := mi.tx_data;
          v.rx_shreg  := (others => '0');
          v.bit_idx   := to_integer(mi.data_width) - 1;
          v.tx_count  := mi.data_width;
          v.miso_out  := mi.tx_data(to_integer(mi.data_width) - 1);
          v.state     := SLAVE_ACTIVE;
        end if;

      -- ---------------------------------------------------------------
      -- ACTIVE: responding to master SCLK edges
      -- ---------------------------------------------------------------
      when SLAVE_ACTIVE =>

        -- Rising-edge detection (low→high)
        if r.sclk_d1 = '0' and mi.sclk = '1' then

          if r.cpha = '0' then
            -- CPHA = 0: sample MOSI on rising edge
            v.rx_shreg(to_integer(r.bit_idx)) := mi.mosi;
          else
            -- CPHA = 1: shift MISO on rising edge
            v.miso_out := r.tx_shreg(to_integer(r.bit_idx));
          end if;

        -- Falling-edge detection (high→low)
        elsif r.sclk_d1 = '1' and mi.sclk = '0' then

          if r.cpha = '0' then
            -- CPHA = 0: shift MISO on falling edge
            if r.tx_count = 1 then
              -- Last bit — capture final MOSI, then finish
              v.rx_shreg(to_integer(r.bit_idx)) := mi.mosi;
              v.state := SLAVE_DONE;
            else
              v.miso_out := r.tx_shreg(to_integer(r.bit_idx) - 1);
              v.bit_idx  := r.bit_idx - 1;
              v.tx_count := r.tx_count - 1;
            end if;

          else
            -- CPHA = 1: sample MOSI on falling edge
            v.rx_shreg(to_integer(r.bit_idx)) := mi.mosi;

            if r.tx_count = 1 then
              -- Last bit — transfer complete
              v.state := SLAVE_DONE;
            else
              v.bit_idx  := r.bit_idx - 1;
              v.tx_count := r.tx_count - 1;
            end if;
          end if;

        end if;

        -- Update delayed SCLK for next edge detection
        v.sclk_d1 := mi.sclk;

        -- Safety: master released CS prematurely
        if mi.cs_n = '1' then
          v.state   := SLAVE_IDLE;
          v.busy    := '0';
        end if;

      -- ---------------------------------------------------------------
      -- DONE: transfer complete, wait for CS release
      -- ---------------------------------------------------------------
      when SLAVE_DONE =>
        v.rx_valid   := '1';
        v.rx_data_out := r.rx_shreg;
        v.rx_count_out := (others => '0');
        v.busy       := '0';

        if mi.cs_n = '1' then
          -- CS released — go back to IDLE
          v.rx_valid   := '0';
          v.rx_count_out := (others => '0');
          v.state      := SLAVE_IDLE;
        end if;

      -- ---------------------------------------------------------------
      -- Others (safety catch)
      -- ---------------------------------------------------------------
      when others =>
        v.state := SLAVE_IDLE;

    end case;

    -- 5. Drive register inputs
    rin <= v;

    -- 6. Drive outputs from REGISTERED values
    mo.miso     <= r.miso_out;
    mo.busy     <= r.busy;
    mo.rx_valid <= r.rx_valid;
    mo.rx_data  <= r.rx_data_out;
    mo.rx_count <= r.rx_count_out;

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
