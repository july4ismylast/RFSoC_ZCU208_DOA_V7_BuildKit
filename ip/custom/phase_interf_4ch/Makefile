ROOT := $(abspath ../../..)
include $(ROOT)/config.mk

IP_OUT := $(CURDIR)/phase_interf_4ch_prj/solution1/impl/ip
DEST := $(IP_REPO)/phase_interf_4ch
IP_VLNV := $(CUSTOM_IP_VENDOR):$(CUSTOM_IP_LIBRARY):phase_interf_4ch:$(IPVER_PHASE_INTERF)

CXX ?= g++
HOST_BIN := $(ROOT)/build/host/phase_interf_host_tb

.PHONY: all hls install host-check clean

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

clean:
	rm -rf phase_interf_4ch_prj vitis_hls.log "$(HOST_BIN)"
