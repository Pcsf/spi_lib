-------------------------------------------------------------------------------
-- Entity     : sync_ff
-- Description: Flip-flop chain synchroniser for one asynchronous input.
--              q follows d after STAGES clk edges. STAGES = 0 connects d
--              straight to q, for an input already synchronous to clk.
--              The chain has no reset and powers up at INIT: a synchronous
--              reset would put a LUT in front of every stage and take its
--              delay out of the settling time.
-- Constraints: false path or max delay on the path into the first stage.
-- Method     : Gaisler two-process, no reset
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity sync_ff is
  generic (
    STAGES : natural   := 2;
    INIT   : std_logic := '0');
  port (
    clk : in  std_logic;
    d   : in  std_logic;
    q   : out std_logic);
end entity sync_ff;

architecture rtl of sync_ff is
begin

  g_bypass : if STAGES = 0 generate
    q <= d;
  end generate g_bypass;

  g_sync : if STAGES > 0 generate
    subtype reg_type is std_logic_vector(STAGES - 1 downto 0);

    constant REG_INIT : reg_type := (others => INIT);

    signal r, rin : reg_type := REG_INIT;

    -- Xilinx: keep the chain as adjacent flops, never an SRL.
    -- Intel: report the chain as a synchroniser.
    attribute async_reg : string;
    attribute async_reg of r : signal is "true";
    attribute shreg_extract : string;
    attribute shreg_extract of r : signal is "no";
    attribute altera_attribute : string;
    attribute altera_attribute of r : signal is
      "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS";
  begin

    comb : process(all)
      variable v : reg_type;
    begin
      v := r;
      v := v(STAGES - 2 downto 0) & d;

      rin <= v;
      q   <= r(STAGES - 1);
    end process comb;

    regs : process(clk)
    begin
      if rising_edge(clk) then
        r <= rin;
      end if;
    end process regs;

  end generate g_sync;

end architecture rtl;
