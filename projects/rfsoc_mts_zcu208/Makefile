ROOT := $(abspath ../..)
include $(ROOT)/config.mk
U := $(ROOT)/upstream/RFSoC-MTS/boards/ZCU208/build_mts
.PHONY: help fetch project all clean
help:
	@echo "PRODUCTION BASE (BASE_KIND=mts). Upstream MTS was generated in Vivado 2022.1.2 (ps:3.4); this project is locked to 2023.2 (ps:3.5), so DO NOT build it in 2023.2 until stage V03 upgrades its IPs in a controlled way."
	@echo "Use the top-level flow (step01 fetch -> V03 base upgrade -> step07). Upstream make all is reference only."
fetch:
	$(ROOT)/scripts/fetch_upstream.sh RFSoC-MTS
project: fetch
	cd $(U) && $(VIVADO) -mode batch -source mts.tcl
all: fetch
	$(MAKE) -C $(U) all
clean:
	-$(MAKE) -C $(U) clean
