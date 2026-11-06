ROOT := $(abspath ../../..)
include $(ROOT)/config.mk

IP_OUT := $(CURDIR)/phase_interf_4ch_prj/solution1/impl/ip
DEST := $(IP_REPO)/phase_interf_4ch
IP_VLNV := $(CUSTOM_IP_VENDOR):$(CUSTOM_IP_LIBRARY):phase_interf_4ch:$(IPVER_PHASE_INTERF)

CXX ?= g++
HOST_BIN := $(ROOT)/build/host/phase_interf_host_tb
HOST_KERNEL_BIN := $(ROOT)/build/host/phase_interf_kernel_tb

.PHONY: all hls install host-check host-kernel-check gate3-ooc clean

# `all` is the production path (needs Vitis HLS 2023.2).
all: hls install

hls:
	$(VITIS_HLS) -f build_hls.tcl

install: hls
	@test -f "$(IP_OUT)/component.xml" || { echo "Missing HLS export $(IP_OUT)/component.xml"; exit 2; }
	@$(ROOT)/common/scripts/check_component_vlnv.sh "$(IP_OUT)/component.xml" "$(IP_VLNV)"
	rm -rf "$(DEST)"
	mkdir -p "$(DEST)"
	cp -a "$(IP_OUT)/." "$(DEST)/"
	@echo "Installed phase-interferometry IP at $(DEST)"

# Tool-independent check of the production core (g++, no Xilinx headers).
# This is V07 gate G1 and runs on any machine.
host-check:
	@mkdir -p $(dir $(HOST_BIN))
	$(CXX) -std=c++14 -O2 -Wall -Wextra -Isrc -o "$(HOST_BIN)" golden/phase_interf_host_tb.cpp
	"$(HOST_BIN)"

# Compiles the PRODUCTION kernel and the PRODUCTION Vitis C-simulation testbench
# against the minimal host shim in tb/host_shim (no Vitis needed).  This proves
# the code compiles, the AXI beat packing and the 16-word/phase record layouts
# are what the PS expects, and the accumulators match the host core.  It is not
# csim_design: no scheduling, II, latency or HLS overflow semantics.
host-kernel-check:
	@mkdir -p $(dir $(HOST_KERNEL_BIN))
	$(CXX) -std=c++14 -O2 -Wall -Wextra -Wno-unknown-pragmas -Wno-unused-label \
	    -I tb/host_shim -I src tb/phase_interf_4ch_tb.cpp src/phase_interf_4ch.cpp \
	    -o "$(HOST_KERNEL_BIN)"
	"$(HOST_KERNEL_BIN)"

# V07 gate G3: OOC synthesis + timing of the packaged IP at 4.0 ns.  Needs a
# licensed Vivado 2023.2 and a packaged IP (step05 + step06).  NOT RUN in the
# authoring environment; see gate3_ooc.tcl and V07 section 8.
gate3-ooc:
	$(VIVADO) -mode batch -nojournal -nolog -source gate3_ooc.tcl

clean:
	rm -rf phase_interf_4ch_prj vitis_hls.log "$(HOST_BIN)" "$(HOST_KERNEL_BIN)"
