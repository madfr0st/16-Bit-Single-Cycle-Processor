# =============================================================================
# sim.mk  --  Icarus Verilog quick-sim harness (no Vivado required)
# =============================================================================
# Usage:
#     make -f scripts/sim.mk CORE=scp16
#     make -f scripts/sim.mk CORE=x86lite32
#     make -f scripts/sim.mk CORE=armlite32
#     make -f scripts/sim.mk CORE=scp16 wave    # open the VCD in GTKWave
#     make -f scripts/sim.mk CORE=scp16 clean
#
# Requires:
#   * Icarus Verilog (iverilog, vvp)            https://steveicarus.github.io
#   * GTKWave        (gtkwave)                  https://gtkwave.sourceforge.net
# =============================================================================

CORE ?= scp16

RTL_DIR := cores/$(CORE)/rtl
SIM_DIR := cores/$(CORE)/sim
BUILD   := build_sim/$(CORE)

RTL     := $(wildcard $(RTL_DIR)/*.v)
TB      := $(SIM_DIR)/cpu_tb.v
OUT     := $(BUILD)/cpu_tb.vvp
VCD     := dump.vcd

# Allow the sim to find `defines.v` via -I for the 32-bit cores
INC     := -I $(RTL_DIR)

.PHONY: all run wave clean

all: run

$(OUT): $(RTL) $(TB)
	@mkdir -p $(BUILD)
	iverilog -g2012 $(INC) -o $@ $(TB) $(RTL)

run: $(OUT)
	vvp $(OUT)

wave: $(VCD)
	gtkwave $(VCD) &

clean:
	rm -rf $(BUILD) $(VCD)
