ROOT := $(abspath ../..)
include $(ROOT)/config.mk
U := $(ROOT)/upstream/SPEAR/hw_design/ZCU216
DESIGN ?= rfsoc_rfdc_v39_100M
.PHONY: help fetch upstream-bd upstream-bit zcu208-shell
help:
	@echo "SPEAR upstream is ZCU216/Vivado 2021.1. Build it as a reference; use a verified ZCU208 RFDC/MTS shell for the XCZU48DR port."
fetch:
	$(ROOT)/scripts/fetch_upstream.sh
upstream-bd: fetch
	$(MAKE) -C $(U) bd DESIGN=$(DESIGN)
upstream-bit: fetch
	$(MAKE) -C $(U) bit DESIGN=$(DESIGN)
zcu208-shell:
	cd $(ROOT) && $(VIVADO) -mode batch -source common/vivado/create_zcu208_shell.tcl -tclargs spear_zcu208_shell $(PART) "$(BOARD_PART)"
