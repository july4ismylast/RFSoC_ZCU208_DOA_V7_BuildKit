ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
IP_NAME := ssrfft_16x4096_axis
IP_VLNV := $(OPFB_VLNV_SSRFFT)
SRC := $(UPSTREAM)/ssrfft_16x4096/MazinLab_mkidgen3_ssrfft_16x4096_axis_v1_0
DST := $(IP_REPO)/$(IP_NAME)
.PHONY: all fetch copy catalog clean
all: copy catalog
fetch:
	@if [ "$(OPFB_FETCH_DONE)" != "1" ]; then $(ROOT)/scripts/fetch_upstream.sh opfb; fi
copy: fetch
	@test -f "$(SRC)/component.xml" || { echo "ERROR: pinned SSRFFT component is missing: $(SRC)/component.xml"; exit 1; }
	rm -rf $(DST); mkdir -p $(DST); cp -a $(SRC)/. $(DST)/
catalog: copy
	cd $(ROOT) && $(VIVADO) -mode batch -source common/vivado/create_catalog_project.tcl -tclargs ssrfft_test $(DST) "$(IP_VLNV)" $(PART) "$(BOARD_PART)"
clean:
	rm -rf $(DST) build .Xil
