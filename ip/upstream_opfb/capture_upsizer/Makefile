ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
REPO_NAME := capture-upsizer
IP_NAME := capture_upsizer
IP_VLNV := $(OPFB_VLNV_CAPTURE_UPSIZER)
SRC := $(UPSTREAM)/$(REPO_NAME)
COMPONENT_XML := $(SRC)/capture_upsizer_v0.5/component.xml
DST_DIR := $(IP_REPO)/$(IP_NAME)
.PHONY: help fetch list import catalog all clean
help:
	@echo "Import the exact $(IP_VLNV) packaged IP used by the pinned RFSoC_OPFB BD."
	@echo "The GitHub repository name is capture-upsizer, but the IP NAME/VLNV uses capture_upsizer."
fetch:
	@if [ "$(OPFB_FETCH_DONE)" != "1" ]; then $(ROOT)/scripts/fetch_upstream.sh opfb; fi
list: fetch
	find $(SRC) -name component.xml -o -name '*.tcl' -o -name 'Makefile' | sort
import: fetch
	rm -rf "$(IP_REPO)/$(REPO_NAME)" # legacy repo-named copy from the pre-fix adapter; avoid a duplicate VLNV in the IP repo
	COMPONENT_XML="$(COMPONENT_XML)" $(ROOT)/common/scripts/import_packaged_ip.sh "$(SRC)" "$(IP_REPO)" "$(IP_NAME)"
catalog: import
	cd $(ROOT) && $(VIVADO) -mode batch -source common/vivado/create_catalog_project.tcl -tclargs capture_upsizer_catalog "$(DST_DIR)" "$(IP_VLNV)" $(PART) "$(BOARD_PART)"
all: catalog
clean:
	rm -rf "$(DST_DIR)" "$(IP_REPO)/$(REPO_NAME)"
