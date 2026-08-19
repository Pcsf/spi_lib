# ==============================================================================
# project.mk — SPI Library project configuration
# ==============================================================================

PROJECT_NAME := spi_lib
BUILD_DIR    := build
TOOLCHAIN    := ghdl
SRC_ROOT     := .

GHDL_STD   := 08
GHDL_TOP   := tb_spi
GHDL_FLAGS :=
GHDL_SIM_FLAGS :=

# QuestaSim / ModelSim settings. Select with: make TOOLCHAIN=modelsim
VLIB      := vlib
VMAP      := vmap
VCOM      := vcom
VLOG      := vlog
VSIM      := vsim
VSIM_WORK := work
VSIM_TOP  := tb_spi
VSIM_FLAGS :=

VHDL_SRCS_DIR := \
    rtl \
    tb
