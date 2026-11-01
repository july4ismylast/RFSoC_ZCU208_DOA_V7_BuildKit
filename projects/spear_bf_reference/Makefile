ROOT := $(abspath ../..)
include $(ROOT)/config.mk
U := $(ROOT)/upstream/SPEAR_BF/hw_design/ZCU216
DESIGN ?= rfsoc_rfdc_v39_100M
.PHONY: help fetch upstream-bd upstream-bit zcu208-shell
help:
	@echo "SPEAR-BF upstream is ZCU216/Vivado 2021.1 reference; do not treat it as a ZCU208 project."
	@echo "Use: make upstream-bd DESIGN=... | make upstream-bit DESIGN=... | make zcu208-shell"
fetch:
	$(ROOT)/scripts/fetch_upstream.sh
upstream-bd: fetch
	$(MAKE) -C $(U) bd DESIGN=$(DESIGN)
upstream-bit: fetch
	$(MAKE) -C $(U) bit DESIGN=$(DESIGN)
zcu208-shell:
	cd $(ROOT) && $(VIVADO) -mode batch -source common/vivado/create_zcu208_shell.tcl -tclargs spear_bf_zcu208_shell $(PART) "$(BOARD_PART)"
