ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
SRC := $(UPSTREAM)/ssrfft_16x4096/MazinLab_mkidgen3_ssrfft_16x4096_axis_v1_0
DST := $(IP_REPO)/ssrfft_16x4096_axis
.PHONY: all fetch copy catalog clean
all: copy catalog
fetch:
	$(ROOT)/scripts/fetch_upstream.sh opfb
copy: fetch
	rm -rf $(DST); mkdir -p $(DST); cp -a $(SRC)/. $(DST)/
catalog: copy
	cd $(ROOT) && $(VIVADO) -mode batch -source common/vivado/create_catalog_project.tcl -tclargs ssrfft_test $(DST) ssrfft $(PART) "$(BOARD_PART)"
clean:
	rm -rf $(DST) build .Xil
