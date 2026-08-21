---
task: "Integrate UVVM SPI BFMs and independent protocol checking"
slug: 20260821-084154_uvvm-spi-verification
project: spi_lib
phase: complete
progress: 19/19
started: 2026-08-21T08:41:54Z
updated: 2026-08-21T09:16:00Z
principal_stated_goal: "OK. I like the proposal. Go ahead with the implementation"
principal_stated_goal_source: prompt
principal_stated_goal_signal: 4
principal_stated_goal_locked: 2026-08-21T08:41:54Z
context_sufficient: true
interview_invoked: false
current_state: "The master and slave validate each other in one loopback test, and the build framework supports only the work VHDL library."
ideal_state: "Pinned UVVM SPI BFMs independently exercise each DUT while a qualified passive monitor checks the wire protocol under GHDL and Questa."
capabilities_invoked:
  - ISA
  - FPGA-VHDL-Design
  - VHDL-Testbench-Patterns
  - Altera-Dev-Env
---

# UVVM-backed SPI verification

## Problem

The current `tb_spi` connects `spi_master` directly to `spi_slave`. It proves end-to-end data exchange, but matching protocol mistakes can pass because neither endpoint is an independent reference. The `mk/` framework also compiles every VHDL unit into `work`, while UVVM requires named libraries.

## Vision

A single regression command gives fast, diagnostic confidence at three seams: the master against UVVM's slave BFM, the slave against UVVM's master BFM, and both DUTs together under an independent wire observer. A failure names the DUT, mode, width, direction, and violated protocol property rather than requiring waveform interpretation.

## Out of Scope

- No RTL behavior or public package interface changes.
- No UVVM VVC framework, transaction queue, scoreboard, or unrelated VIP compilation.
- No claim that simulation establishes metastability safety for the slave's asynchronous SPI inputs.
- No synthesis-time BIST implementation.

## Principles

- A DUT must not define correctness for another DUT under test.
- Third-party verification code is pinned and consumed unchanged.
- Protocol legality and endpoint data results are separate evidence.
- Build-framework extensions are generic enough to serve other named VHDL libraries.

## Constraints

- UVVM is pinned to release `2026.03.20`; moving `master` is not accepted.
- Only `uvvm_util` and `bitvis_vip_spi/src/spi_bfm_pkg.vhd` are compiled.
- VHDL remains VHDL-2008.
- Toolchain selection remains in `project.mk`; command-line `TOOLCHAIN=` overrides are not used.
- The final default toolchain remains ModelSim/Questa.
- Existing `make sim` behavior remains the primary regression entry point.

## Goal

Implement the UVVM-backed verification architecture and the generic named-library support it requires, preserving the existing RTL and closing every functional claim with self-checking simulation evidence.

## Test Strategy

| isc | type | check | threshold | tool | anchors_to |
|-----|------|-------|-----------|------|------------|
| ISC-1 | bash | generic named-library fixture under GHDL | compile and run exit 0 | framework fixture through `make` with `TOOLCHAIN` selected in fixture `project.mk` | derived: named-library-support |
| ISC-2 | bash | generic named-library fixture under Questa | compile and run exit 0 | framework fixture through Altera container | derived: named-library-support |
| ISC-3 | bash | pinned UVVM dependency identity | exact release commit | `git submodule status uvvm` | derived: reproducibility |
| ISC-4 | bash | BFM-only UVVM compile set | no VVC/scoreboard sources | `make info` plus compile transcript | derived: bounded-dependency |
| ISC-5 | bash | independent master regression | all cases pass | GHDL/Questa `tb_spi` summary | literal |
| ISC-5.1 | bash | master rejects invalid widths | widths 0 and 33 cause no transaction | `Master controls` summary | derived: input-validation |
| ISC-5.2 | bash | master captures accepted configuration | host changes and second start do not alter active frame | `Master controls` summary | derived: transaction-atomicity |
| ISC-5.3 | bash | master reset abort | idle outputs and no completion pulse | `Master controls` summary | derived: reset-safety |
| ISC-5.4 | bash | master receive status contract | one-cycle valid and zero unused bits | independent master matrix | derived: interface-contract |
| ISC-6 | bash | independent slave regression | all cases pass | GHDL/Questa `tb_spi` summary | literal |
| ISC-6.1 | bash | slave rejects invalid widths | widths 0 and 33 cause no transaction | `Slave controls` summary | derived: input-validation |
| ISC-6.2 | bash | slave captures selected configuration | host changes do not alter active frame | `Slave controls` summary | derived: transaction-atomicity |
| ISC-6.3 | bash | slave abort behavior | premature CS and reset cause no completion pulse | `Slave controls` summary | derived: abort-safety |
| ISC-6.4 | bash | slave receive status contract | one-cycle valid and zero unused bits | independent slave matrix | derived: interface-contract |
| ISC-7 | bash | passive monitor valid-frame behavior | all valid cases accepted | monitor qualification summary | derived: protocol-legality |
| ISC-8 | bash | passive monitor discriminates malformed frames | every injected class rejected | monitor qualification summary | derived: protocol-legality |
| ISC-9 | bash | legacy loopback regression | 16/16 transfers pass | GHDL/Questa `tb_spi` summary | derived: regression |
| ISC-10 | bash | complete regressions terminate cleanly | zero unexpected errors/warnings | `make sim` under both simulators | literal |
| ISC-11 | bash | Anti: approved scope remains bounded | zero RTL diffs and no VVC source references | `git diff -- rtl` and `rg` | derived: scope |

## Features

### F1 · Named VHDL libraries
Why: external verification libraries become first-class build inputs instead of simulator-specific side scripts.

- [x] ISC-1: The `mk/` GHDL flow compiles ordered source lists into named libraries and resolves their dependencies from `work`.
- [x] ISC-2: The `mk/` ModelSim/Questa flow creates, maps, and compiles the same named libraries before `work`.

### F2 · Pinned UVVM BFM dependency
Why: the testbench uses a maintained independent implementation without importing the weight of the complete methodology.

- [x] ISC-3: UVVM is a git submodule pinned to release `2026.03.20` commit `4f1e13bf96dca5571597ca7416b9340e9de94efd`.
- [x] ISC-4: The build compiles UVVM Utility and the SPI BFM package, but no VVC framework, scoreboard, or unrelated VIP source.

### F3 · Independent endpoint verification
Why: each SPI endpoint must pass against a reference that does not share its RTL assumptions.

- [x] ISC-5: `spi_master` passes all four modes, widths 2–32, representative dividers, and data patterns against the UVVM slave BFM; width 1 passes against an independent one-bit responder and the passive monitor.
- [x] ISC-5.1: `spi_master` ignores start requests with data widths 0 and 33 without bus activity or completion.
- [x] ISC-5.2: `spi_master` holds the accepted mode, divider, width, and data while busy and ignores a second start.
- [x] ISC-5.3: Synchronous reset during a master transfer restores idle outputs without `rx_valid`.
- [x] ISC-5.4: Master `rx_valid` is one cycle and every unused upper receive bit is zero.
- [x] ISC-6: `spi_slave` passes all four modes, widths 2–32, representative timings, and data patterns against the UVVM master BFM; width 1 passes against an independent one-bit driver and the passive monitor.
- [x] ISC-6.1: `spi_slave` ignores chip selection with data widths 0 and 33 without accepting a transaction.
- [x] ISC-6.2: `spi_slave` holds the selected mode, width, and transmit data for the complete frame.
- [x] ISC-6.3: Premature CS release and synchronous reset abort a slave frame without `rx_valid`.
- [x] ISC-6.4: Slave `rx_valid` is one cycle and every unused upper receive bit is zero.

### F4 · Independent wire-protocol observer
Why: valid data exchange is insufficient when both endpoints can agree on the same illegal edge behavior.

- [x] ISC-7: A passive monitor accepts every valid UVVM/DUT frame and checks CPOL, CPHA sampling edge, MSB-first data, CS framing, and edge count.
- [x] ISC-8: Controlled malformed frames prove the monitor rejects data corruption and protocol framing faults with distinct diagnostics.

### F5 · Regression continuity
Why: stronger verification must preserve the existing full-duplex integration evidence and stay one-command reproducible.

- [x] ISC-9: The original four-mode by four-width loopback matrix still passes 16 of 16 transactions.
- [x] ISC-10: GHDL and Questa run the complete self-checking regression to a final PASS without manual waveform inspection.
- [x] ISC-11: Anti: implementation changes neither RTL files nor their public package interfaces, and does not compile the UVVM VVC stack.

## Decisions

- 2026-08-21 08:41: Use UVVM direct BFMs rather than VVCs because the testbench needs blocking master/slave reference operations, not queued transaction components.
- 2026-08-21 08:41: Retain a custom passive monitor because UVVM's SPI VIP explicitly states that it is not a protocol checker.
- 2026-08-21 08:41: Extend `mk/` with generic named-library variables instead of a UVVM-specific compile target.
- 2026-08-21 09:05: UVVM SPI BFM 5.1.4 indexes below zero on one-bit master transactions. Keep vendor sources unchanged; use minimal independent one-bit master/slave adapters under the same passive protocol monitor.

## Learning

- 2026-08-21 | conjectured: UVVM SPI BFM 5.1.4 accepts every width supported by the DUTs, including one bit
  refuted by: GHDL stopped at `spi_bfm_pkg.vhd:757` with index `-1` for a one-bit transfer
  learned: unconstrained BFM data arguments do not imply every length is implemented safely; vendor VIP boundary widths need an explicit smoke probe
  criterion now: ISC-5 and ISC-6 explicitly use UVVM for widths 2–32 and qualified independent one-bit adapters for width 1

## Verification

- ISC-1: `mk/test/vhdl_libraries` GHDL fixture — `NAMED VHDL LIBRARIES TEST PASSED`.
- ISC-2: `mk/test/vhdl_libraries` Questa fixture — `NAMED VHDL LIBRARIES TEST PASSED`, 0 errors, 0 warnings.
- ISC-3: `git submodule status uvvm` + exact tag probe — commit `4f1e13bf`, tag `2026.03.20`.
- ISC-4: `make info` + VVC grep — 20 `uvvm_util` sources, one SPI BFM source, zero VVC/scoreboard sources.
- ISC-5: `tb_spi` — `Master independent: 32/32 PASS` under GHDL and Questa.
- ISC-5.1: `tb_spi` — invalid master widths 0 and 33 rejected.
- ISC-5.2: `tb_spi` — active master configuration and transfer survive host mutation and a second start.
- ISC-5.3: `tb_spi` — synchronous master reset abort returns registered outputs to idle without completion.
- ISC-5.4: `tb_spi` master matrix — one-cycle `rx_valid`, zero unused receive bits.
- ISC-6: `tb_spi` — `Slave independent: 32/32 PASS` under GHDL and Questa.
- ISC-6.1: `tb_spi` — invalid slave widths 0 and 33 rejected.
- ISC-6.2: `tb_spi` — selected slave configuration survives host mutation for the frame.
- ISC-6.3: `tb_spi` — premature CS and synchronous reset abort without completion.
- ISC-6.4: `tb_spi` slave matrix — one-cycle `rx_valid`, zero unused receive bits.
- ISC-7: `tb_spi` valid frames — protocol monitor reports zero flags across independent and loopback matrices.
- ISC-8: `tb_spi` — `Monitor qualification: 4/4 PASS` including corruption, premature-CS, and extra-edge discrimination.
- ISC-9: `tb_spi` — `Master/slave loopback: 16/16 PASS` under GHDL and Questa.
- ISC-10: final `make sim` — GHDL PASS; Questa PASS with 0 errors and 0 warnings.
- ISC-11: RTL diff + VVC grep — no `rtl/` changes and no VVC framework source reference.
