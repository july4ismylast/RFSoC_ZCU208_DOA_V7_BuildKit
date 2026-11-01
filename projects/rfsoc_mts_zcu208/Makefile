ROOT := $(abspath ../..)
include $(ROOT)/config.mk
U := $(ROOT)/upstream/RFSoC-MTS/boards/ZCU208/build_mts
.PHONY: help fetch project all clean
help:
	@echo "Native ZCU208 reference. Upstream expects Vivado 2022.1. make all builds their MTS overlay."
fetch:
	$(ROOT)/scripts/fetch_upstream.sh
project: fetch
	cd $(U) && $(VIVADO) -mode batch -source mts.tcl
all: fetch
	$(MAKE) -C $(U) all
clean:
	-$(MAKE) -C $(U) clean
