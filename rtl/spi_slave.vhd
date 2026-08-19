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
    bit_idx        : unsigned(5 downto 0);
    tx_count       : unsigned(5 downto 0);
    data_width     : unsigned(5 downto 0);

    -- Outputs
    miso_out       : std_logic;
    busy           : std_logic;
    rx_valid       : std_logic;
    rx_data_out    : std_logic_vector(31 downto 0);
    rx_count_out   : unsigned(5 downto 0);

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
  comb : process(all)
    variable v         : reg_type;
    variable idx_i     : integer;
    variable width_i   : integer;
    variable leading_edge  : boolean;
    variable trailing_edge : boolean;
  begin
    -- 1. Default: copy current state (prevents inferred latches)
    v := r;

    -- rx_valid is a one-cycle completion pulse.
    v.rx_valid := '0';

    leading_edge  := (r.sclk_d1 = r.cpol) and (mi.sclk /= r.cpol);
    trailing_edge := (r.sclk_d1 /= r.cpol) and (mi.sclk = r.cpol);

    case r.state is

      -- ---------------------------------------------------------------
      -- IDLE: waiting for CS low
      -- ---------------------------------------------------------------
      when SLAVE_IDLE =>
        v.miso_out     := '0';
        v.busy         := '0';
        v.rx_count_out := (others => '0');
        v.sclk_d1      := mi.sclk;

        if mi.cs_n = '0'
           and mi.data_width >= to_unsigned(1, mi.data_width'length)
           and mi.data_width <= to_unsigned(32, mi.data_width'length) then
          v.busy       := '1';
          v.cpol       := mi.mode(1);
          v.cpha       := mi.mode(0);
          v.data_width := mi.data_width;
          v.tx_shreg   := mi.tx_data;
          v.rx_shreg   := (others => '0');
          width_i      := to_integer(mi.data_width);
          v.bit_idx      := to_unsigned(width_i - 1, 6);
          v.tx_count     := mi.data_width;
          v.rx_count_out := mi.data_width;
          v.miso_out     := mi.tx_data(width_i - 1);
          v.state      := SLAVE_ACTIVE;
        end if;

      -- ---------------------------------------------------------------
      -- ACTIVE: responding to master SCLK edges
      -- ---------------------------------------------------------------
      when SLAVE_ACTIVE =>
        v.busy   := '1';
        idx_i    := to_integer(r.bit_idx);
        v.sclk_d1 := mi.sclk;

        if leading_edge then
          if r.cpha = '0' then
            -- CPHA = 0: sample MOSI on the leading edge.
            v.rx_shreg(idx_i) := mi.mosi;
          else
            -- CPHA = 1: launch MISO on the leading edge.
            v.miso_out := r.tx_shreg(idx_i);
          end if;

        elsif trailing_edge then
          if r.cpha = '0' then
            -- CPHA = 0: launch the next MISO bit on the trailing edge.
            if r.tx_count = to_unsigned(1, 6) then
              v.rx_data_out  := v.rx_shreg;
              v.rx_valid     := '1';
              v.busy         := '0';
              v.tx_count     := (others => '0');
              v.rx_count_out := (others => '0');
              v.state        := SLAVE_DONE;
            else
              idx_i := idx_i - 1;
              v.miso_out     := r.tx_shreg(idx_i);
              v.bit_idx      := to_unsigned(idx_i, 6);
              v.tx_count     := r.tx_count - 1;
              v.rx_count_out := r.tx_count - 1;
            end if;
          else
            -- CPHA = 1: sample MOSI on the trailing edge.
            v.rx_shreg(idx_i) := mi.mosi;

            if r.tx_count = to_unsigned(1, 6) then
              v.rx_data_out  := v.rx_shreg;
              v.rx_valid     := '1';
              v.busy         := '0';
              v.tx_count     := (others => '0');
              v.rx_count_out := (others => '0');
              v.state        := SLAVE_DONE;
            else
              idx_i := idx_i - 1;
              v.bit_idx      := to_unsigned(idx_i, 6);
              v.tx_count     := r.tx_count - 1;
              v.rx_count_out := r.tx_count - 1;
            end if;
          end if;
        end if;

        -- Safety: master released CS prematurely.
        if mi.cs_n = '1' then
          v.state := SLAVE_IDLE;
          v.busy  := '0';
        end if;

      -- ---------------------------------------------------------------
      -- DONE: transfer complete, wait for CS release
      -- ---------------------------------------------------------------
      when SLAVE_DONE =>
        v.rx_count_out := (others => '0');
        v.busy         := '0';

        if mi.cs_n = '1' then
          -- CS released — go back to IDLE.
          v.state := SLAVE_IDLE;
        end if;

      -- ---------------------------------------------------------------
      -- Others (safety catch)
      -- ---------------------------------------------------------------
      when others =>
        v.state := SLAVE_IDLE;

    end case;

    -- Synchronous reset — last algorithm assignment, highest priority.
    if rst = '1' then
      v := REG_RESET;
    end if;

    -- 4. Drive register inputs
    rin <= v;

    -- 5. Drive outputs from REGISTERED values
    mo.miso     <= r.miso_out;
    mo.busy     <= r.busy;
    mo.rx_valid <= r.rx_valid;
    mo.rx_data  <= r.rx_data_out;
    mo.rx_count <= r.rx_count_out;

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
