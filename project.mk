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

VHDL_SRCS_DIR := \
    rtl \
    tb
