ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
SRC := $(UPSTREAM)/wb2axip
# RFSoC_OPFB does not use wb2axip as packaged Vivado IP.  Its
# vivado/write_prj.tcl adds these three Verilog files directly to sources_1,
# and bd/opfb_streaming.tcl instantiates axis2mm as a module reference.
# There is intentionally no component.xml, VLNV, import, or catalog step here.
RTL_FILES := $(SRC)/rtl/sfifo.v $(SRC)/rtl/axis2mm.v $(SRC)/rtl/skidbuffer.v
.PHONY: help fetch list check all clean
help:
	@echo "Check the three wb2axip RTL files used directly by RFSoC_OPFB write_prj.tcl."
	@echo "This is module-reference RTL, not packaged IP; it is not part of step05 IP collection."
fetch:
	@if [ "$(OPFB_FETCH_DONE)" != "1" ]; then $(ROOT)/scripts/fetch_upstream.sh opfb; fi
list: fetch
	@for file in $(RTL_FILES); do echo "$$file"; done
check: fetch
	@for file in $(RTL_FILES); do \
		test -s "$$file" || { echo "ERROR: required wb2axip RTL is missing: $$file"; exit 1; }; \
		echo "PASS $$file"; \
	done
	@echo "wb2axip is ready for direct RTL/module-reference use; no Vivado IP catalog entry is expected."
all: check
clean:
	@true
