ROOT := $(abspath ../..)
include $(ROOT)/config.mk
U := $(ROOT)/upstream/rfsoc_sam/boards/ZCU208/rfsoc_sam
.PHONY: help fetch bd bit all clean
help:
	@echo "Native ZCU208 spectrum-analyzer reference. Current upstream documents Vivado 2024.1."
fetch:
	$(ROOT)/scripts/fetch_upstream.sh
bd: fetch
	$(MAKE) -C $(U) block_design
bit: fetch
	$(MAKE) -C $(U) bitstream
all: fetch
	$(MAKE) -C $(U) all
clean:
	-$(MAKE) -C $(U) clean
