ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
IP_NAME := pkg_fft_output
IP_VLNV := $(OPFB_VLNV_PKG_FFT_OUTPUT)
# Exact folder for the VLNV instantiated by the pinned RFSoC_OPFB BD.  Do not
# replace this with a lexical "newest folder" search: the upstream repo also
# contains 0.2 and 0.3 packaged versions.
SRC := $(UPSTREAM)/pkg-fft-output/mazinlab_mkidgen3_pkg_fft_output_1.31
DST := $(IP_REPO)/$(IP_NAME)
.PHONY: all fetch copy catalog clean
all: copy catalog
fetch:
	@if [ "$(OPFB_FETCH_DONE)" != "1" ]; then $(ROOT)/scripts/fetch_upstream.sh opfb; fi
copy: fetch
	@test -f "$(SRC)/component.xml" || { echo "ERROR: pinned pkg_fft_output component is missing: $(SRC)/component.xml"; exit 1; }
	rm -rf $(DST); mkdir -p $(DST); cp -a $(SRC)/. $(DST)/
catalog: copy
	cd $(ROOT) && $(VIVADO) -mode batch -source common/vivado/create_catalog_project.tcl -tclargs pkg_fft_output_test $(DST) "$(IP_VLNV)" $(PART) "$(BOARD_PART)"
clean:
	rm -rf $(DST) build .Xil
