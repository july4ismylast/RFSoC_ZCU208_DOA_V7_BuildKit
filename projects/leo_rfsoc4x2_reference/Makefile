ROOT := $(abspath ../..)
include $(ROOT)/config.mk
U := $(ROOT)/upstream/rfsoc4x2_public
.PHONY: help fetch inspect zcu208-shell
help:
	@echo "leoeltipo/rfsoc4x2_public is a RFSoC4x2 PFB/DDS/CIC/cascaded-PFB reference."
	@echo "Its board/RFDC shell is not interchangeable with ZCU208. Reuse algorithm/IP structure, not board wiring."
fetch:
	$(ROOT)/scripts/fetch_upstream.sh rfsoc4x2_public
inspect: fetch
	find $(U) -maxdepth 3 \( -name '*.tcl' -o -name 'Makefile' -o -name '*.slx' \) -print | sort
zcu208-shell:
	cd $(ROOT) && $(VIVADO) -mode batch -source common/vivado/create_zcu208_shell.tcl -tclargs leo_style_zcu208_shell $(PART) "$(BOARD_PART)"
