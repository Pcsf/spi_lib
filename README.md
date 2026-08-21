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

Compile each package before its corresponding entity. The required order is listed in `rtl/.compile_order`.

## Simulation

Initialize the build-framework and UVVM submodules:

```bash
git submodule update --init --recursive
```

The default simulator is ModelSim/Questa:

```bash
make sim
```

To use GHDL, set `TOOLCHAIN := ghdl` in `project.mk`, then run:

```bash
make clean
make sim
```

The self-checking regression verifies each DUT independently against UVVM SPI BFMs, checks the bus with a passive protocol monitor, and retains the direct master/slave loopback test.
