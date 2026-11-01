ROOT := $(abspath ../..)
include $(ROOT)/config.mk
U := $(ROOT)/upstream/RFSoC-PYNQ/boards/ZCU208/base
.PHONY: help fetch all clean
help:
	@echo "Native ZCU208 PYNQ base overlay. Upstream documents Vivado 2024.1."
fetch:
	$(ROOT)/scripts/fetch_upstream.sh
all: fetch
	$(MAKE) -C $(U)
clean:
	-$(MAKE) -C $(U) clean
