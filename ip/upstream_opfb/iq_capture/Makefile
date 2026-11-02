ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
REPO_NAME := iq-capture
SRC := $(UPSTREAM)/$(REPO_NAME)

# This one upstream repository supplies three separate IP definitions, all of
# which are instantiated by the pinned RFSoC_OPFB streaming BD.  They must be
# imported and catalog-checked individually; there is no IP named iq-capture.
FILTER_IQ_COMPONENT_XML := $(SRC)/mazinlab_mkidgen3_filter_iq_0_3/component.xml
FILTER_PHASE_COMPONENT_XML := $(SRC)/mazinlab_mkidgen3_filter_phase_0_5/component.xml
PAIR_IQ_COMPONENT_XML := $(SRC)/mazinlab_mkidgen3_pair_iq_0_4/component.xml

.PHONY: help fetch list import catalog all clean
help:
	@echo "Import and catalog-check the three pinned iq-capture IPs:"
	@echo "  $(OPFB_VLNV_FILTER_IQ)"
	@echo "  $(OPFB_VLNV_FILTER_PHASE)"
	@echo "  $(OPFB_VLNV_PAIR_IQ)"
fetch:
	@if [ "$(OPFB_FETCH_DONE)" != "1" ]; then $(ROOT)/scripts/fetch_upstream.sh opfb; fi
list: fetch
	find $(SRC) -name component.xml -o -name '*.tcl' -o -name 'Makefile' | sort
import: fetch
	rm -rf "$(IP_REPO)/$(REPO_NAME)" # legacy repo-named copy from the pre-fix adapter; avoid duplicate VLNVs in the IP repo
	COMPONENT_XML="$(FILTER_IQ_COMPONENT_XML)" $(ROOT)/common/scripts/import_packaged_ip.sh "$(SRC)" "$(IP_REPO)" filter_iq
	COMPONENT_XML="$(FILTER_PHASE_COMPONENT_XML)" $(ROOT)/common/scripts/import_packaged_ip.sh "$(SRC)" "$(IP_REPO)" filter_phase
	COMPONENT_XML="$(PAIR_IQ_COMPONENT_XML)" $(ROOT)/common/scripts/import_packaged_ip.sh "$(SRC)" "$(IP_REPO)" pair_iq
catalog: import
	cd $(ROOT) && $(VIVADO) -mode batch -source common/vivado/create_catalog_project.tcl -tclargs filter_iq_catalog "$(IP_REPO)/filter_iq" "$(OPFB_VLNV_FILTER_IQ)" $(PART) "$(BOARD_PART)"
	cd $(ROOT) && $(VIVADO) -mode batch -source common/vivado/create_catalog_project.tcl -tclargs filter_phase_catalog "$(IP_REPO)/filter_phase" "$(OPFB_VLNV_FILTER_PHASE)" $(PART) "$(BOARD_PART)"
	cd $(ROOT) && $(VIVADO) -mode batch -source common/vivado/create_catalog_project.tcl -tclargs pair_iq_catalog "$(IP_REPO)/pair_iq" "$(OPFB_VLNV_PAIR_IQ)" $(PART) "$(BOARD_PART)"
all: catalog
clean:
	rm -rf "$(IP_REPO)/filter_iq" "$(IP_REPO)/filter_phase" "$(IP_REPO)/pair_iq" "$(IP_REPO)/$(REPO_NAME)"
