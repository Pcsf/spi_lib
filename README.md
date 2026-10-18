# SPI Library

Vendor-independent VHDL-2008 SPI master and slave components using record-based interfaces and the Gaisler two-process structure.

## Features

- SPI modes 0–3 (`mode = CPOL & CPHA`)
- Full-duplex, MSB-first transfers
- Configurable data width from 1 to 32 bits
- Configurable master clock divider
- Active-low chip select
- One-cycle `rx_valid` completion pulse
- Synchronous reset

The master SCLK frequency is:

```text
f_sclk = f_clk / (2 × (sclk_div + 1))
```

## RTL files

- `rtl/spi_master_pkg.vhd`: master interface records and component declaration
- `rtl/spi_master.vhd`: SPI master implementation
- `rtl/spi_slave_pkg.vhd`: slave interface records and component declaration
- `rtl/spi_slave.vhd`: SPI slave implementation
- `rtl/sync_ff.vhd`: flip-flop chain synchroniser used by the slave for `cs_n`, `sclk` and `mosi`

Compile each package before its corresponding entity, and `sync_ff` before `spi_slave`. The required order is listed in `rtl/.compile_order`.

## Slave input synchronisation

The slave passes `cs_n`, `sclk` and `mosi` through `sync_ff` chains before using them. The depth is the `SYNC_STAGES` generic of `spi_slave`:

| `SYNC_STAGES` | Use |
|---|---|
| 2 (default) | Master on another clock or off chip |
| 0 | Master driven by the same `clk`, for example an on-chip `spi_master` |

The synchroniser delays the slave. MISO, and `busy` after `cs_n` falls, change up to `(SYNC_STAGES + 1)` clk periods after the SCLK or `cs_n` edge that causes them. Two master timings must exceed that delay plus the MISO output and board delay and the master's MISO setup time:

- half an SCLK period
- the delay from `cs_n` falling to the first SCLK edge

For example, at `f_clk` = 100 MHz with `SYNC_STAGES = 2` the slave uses 30 ns of each half period. A 10 MHz SCLK (50 ns half period) leaves 20 ns for the I/O delays and setup.

The chains have no reset and power up at the idle level, so no reset logic sits between the stages. Every flop carries `ASYNC_REG` and `SHREG_EXTRACT = no` for Xilinx and `SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS` for Intel. Constrain the path into the first flop as a false path or a max delay in the project's timing constraints.

The master needs no synchroniser: MISO answers the master's own SCLK, so it is timed against `clk` through the I/O constraints.

## Simulation

Initialize the build-framework and UVVM submodules:

```bash
git submodule update --init --recursive
```

The default simulator is ModelSim/Questa:

```bash
make sim
make test   # both test cases; exit status is the verdict, failing on any check or an early stop
```

To use GHDL, set `TOOLCHAIN := ghdl` in `project.mk`, then run:

```bash
make clean
make sim
```

Vivado XSim is not supported: `xelab` 2021.2 segfaults while elaborating UVVM 2026.03.20 (`uvvm_util.global_signals_and_shared_variables_pkg`), even in a testbench that uses nothing but `uvvm_util`. With `TOOLCHAIN := vivado` the UVVM libraries and the project sources compile; elaboration then crashes.

The self-checking regression verifies each DUT independently against UVVM SPI BFMs, checks the bus with a passive protocol monitor, and retains the direct master/slave loopback test.

`make test` runs the regression twice, as declared in `project.mk`: `tb_spi_sync2` with the slave at `SYNC_STAGES = 2` and `tb_spi_sync0` at `SYNC_STAGES = 0`. A control test in each checks that `busy` follows `cs_n` after exactly `SYNC_STAGES + 1` clk edges, which proves the synchroniser depth is the one configured.
