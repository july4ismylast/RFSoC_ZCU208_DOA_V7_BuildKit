ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
REPO_NAME := dac-replay
IP_NAME := dac_table_axim
# Standalone inspection only: dac-replay is not instantiated by the pinned
# RFSoC_OPFB streaming BD and is not part of the default step05 OPFB set.
# The upstream repository contains several older dac_table_8x packages; this
# adapter deliberately selects only the current AXI-memory-mapped package
# below instead of taking the first component.xml found.
IP_VLNV := mazinlab:mkidgen3:dac_table_axim:1.33
SRC := $(UPSTREAM)/$(REPO_NAME)
COMPONENT_XML := $(SRC)/mazinlab_mkidgen3_dac_table_axim_1_33/component.xml
DST_DIR := $(IP_REPO)/$(IP_NAME)
.PHONY: help fetch list import catalog all clean
help:
	@echo "Standalone inspection adapter for $(IP_VLNV)."
	@echo "Not used by RFSoC_OPFB bd/opfb_streaming.tcl and not built by step05."
fetch:
	@if [ "$(OPFB_FETCH_DONE)" != "1" ]; then $(ROOT)/scripts/fetch_upstream.sh opfb; fi
list: fetch
	find $(SRC) -name component.xml -o -name '*.tcl' -o -name 'Makefile' | sort
import: fetch
	rm -rf "$(IP_REPO)/$(REPO_NAME)" # legacy repo-named copy from the pre-fix adapter
	COMPONENT_XML="$(COMPONENT_XML)" $(ROOT)/common/scripts/import_packaged_ip.sh "$(SRC)" "$(IP_REPO)" "$(IP_NAME)"
catalog: import
	cd $(ROOT) && $(VIVADO) -mode batch -source common/vivado/create_catalog_project.tcl -tclargs dac_replay_catalog "$(DST_DIR)" "$(IP_VLNV)" $(PART) "$(BOARD_PART)"
all: catalog
clean:
	rm -rf "$(DST_DIR)" "$(IP_REPO)/$(REPO_NAME)"
