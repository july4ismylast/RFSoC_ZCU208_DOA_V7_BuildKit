ROOT := $(abspath ../..)
include $(ROOT)/config.mk
U := $(ROOT)/upstream/rfsoc_sam/boards/ZCU208/rfsoc_sam
.PHONY: help fetch bd bit all clean
help:
	@echo "Reference only under the 2023.2 lock: pinned commit is the 2024.1 design update. Production base is RFSoC-MTS; borrow SAM patterns, do not build here in 2023.2."
fetch:
	$(ROOT)/scripts/fetch_upstream.sh rfsoc_sam
bd: fetch
	$(MAKE) -C $(U) block_design
bit: fetch
	$(MAKE) -C $(U) bitstream
all: fetch
	$(MAKE) -C $(U) all
clean:
	-$(MAKE) -C $(U) clean
