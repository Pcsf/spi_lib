# ==============================================================================
# project.mk — SPI Library project configuration
# ==============================================================================

PROJECT_NAME := spi_lib
BUILD_DIR    := build
TOOLCHAIN    := modelsim
SRC_ROOT     := .
SCAN_EXCLUDE := uvvm

GHDL_STD   := 08
GHDL_TOP   := tb_spi
GHDL_FLAGS := -frelaxed-rules -fsynopsys -Wno-hide -Wno-shared
GHDL_SIM_FLAGS :=

# QuestaSim / ModelSim settings. Select with: make TOOLCHAIN=modelsim
VLIB      := vlib
VMAP      := vmap
VCOM      := vcom
VLOG      := vlog
VSIM      := vsim
VSIM_WORK := work
VSIM_TOP  := tb_spi
VSIM_FLAGS := -t fs

UVVM_ROOT := uvvm
VHDL_LIBS := uvvm_util bitvis_vip_spi
VHDL_LIB_uvvm_util_SRCS := $(addprefix $(UVVM_ROOT)/uvvm_util/src/,\
    types_pkg.vhd \
    adaptations_pkg.vhd \
    string_methods_pkg.vhd \
    protected_types_pkg.vhd \
    global_signals_and_shared_variables_pkg.vhd \
    hierarchy_linked_list_pkg.vhd \
    alert_hierarchy_pkg.vhd \
    license_pkg.vhd \
    methods_pkg.vhd \
    bfm_common_pkg.vhd \
    generic_queue_pkg.vhd \
    data_queue_pkg.vhd \
    data_fifo_pkg.vhd \
    data_stack_pkg.vhd \
    dummy_rand_extension_pkg.vhd \
    rand_pkg.vhd \
    dummy_func_cov_extension_pkg.vhd \
    association_list_pkg.vhd \
    func_cov_pkg.vhd \
    uvvm_util_context.vhd)
VHDL_LIB_uvvm_util_GHDL_FLAGS := -frelaxed-rules -fsynopsys -Wno-hide -Wno-shared
VHDL_LIB_uvvm_util_VCOM_FLAGS := -explicit -vopt -stats=none -suppress 1236,1246,1346,1902

VHDL_LIB_bitvis_vip_spi_SRCS := \
    $(UVVM_ROOT)/bitvis_vip_spi/src/spi_bfm_pkg.vhd
VHDL_LIB_bitvis_vip_spi_DEPS := uvvm_util
VHDL_LIB_bitvis_vip_spi_GHDL_FLAGS := -frelaxed-rules -fsynopsys -Wno-hide -Wno-shared
VHDL_LIB_bitvis_vip_spi_VCOM_FLAGS := -explicit -vopt -stats=none -suppress 1236,1246,1346,1902

VHDL_SRCS_DIR := \
    rtl \
    tb
