ROOT := $(abspath ../..)
include $(ROOT)/config.mk
U := $(ROOT)/upstream/SPEAR_plus/hw_design/ZCU216
DESIGN ?= rfsoc_rfdc_v45_rt_4ch_mts
.PHONY: help fetch upstream-bd upstream-bit zcu208-shell
help:
	@echo "SPEAR+ upstream is a ZCU216 multi-channel/MTS reference. Port RFDC/tile assignments separately for ZCU208."
fetch:
	$(ROOT)/scripts/fetch_upstream.sh
upstream-bd: fetch
	$(MAKE) -C $(U) bd DESIGN=$(DESIGN)
upstream-bit: fetch
	$(MAKE) -C $(U) bit DESIGN=$(DESIGN)
zcu208-shell:
	cd $(ROOT) && $(VIVADO) -mode batch -source common/vivado/create_zcu208_shell.tcl -tclargs spear_plus_zcu208_shell $(PART) "$(BOARD_PART)"
