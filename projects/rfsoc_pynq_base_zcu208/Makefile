ROOT := $(abspath ../..)
include $(ROOT)/config.mk
U := $(ROOT)/upstream/RFSoC-PYNQ/boards/ZCU208/base
.PHONY: help fetch all clean
help:
	@echo "Reference only under the 2023.2 lock: pinned commit is the last 2024.1 design (current upstream master is 2025.2). Production base is RFSoC-MTS."
fetch:
	$(ROOT)/scripts/fetch_upstream.sh RFSoC-PYNQ
all: fetch
	$(MAKE) -C $(U)
clean:
	-$(MAKE) -C $(U) clean
