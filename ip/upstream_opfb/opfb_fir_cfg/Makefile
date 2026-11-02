ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
export PART
HLS_CLK_NS ?= 2.5
export HLS_CLK_NS
IP_NAME := opfb_fir_cfg
IP_VLNV := $(OPFB_VLNV_OPFB_FIR_CFG)
IP_OUT := $(CURDIR)/opfb_fir_cfg_zcu48dr/solution1/impl/ip
.PHONY: all fetch hls catalog clean
all: hls catalog
fetch:
	@if [ "$(OPFB_FETCH_DONE)" != "1" ]; then $(ROOT)/scripts/fetch_upstream.sh opfb; fi
hls: fetch
	$(VITIS_HLS) -f build_hls.tcl
catalog: hls
	rm -rf $(IP_REPO)/$(IP_NAME); mkdir -p $(IP_REPO)/$(IP_NAME)
	cp -a $(IP_OUT)/. $(IP_REPO)/$(IP_NAME)/
	cd $(ROOT) && $(VIVADO) -mode batch -source common/vivado/create_catalog_project.tcl -tclargs opfb_fir_cfg_test $(IP_REPO)/$(IP_NAME) "$(IP_VLNV)" $(PART) "$(BOARD_PART)"
clean:
	rm -rf opfb_fir_cfg_zcu48dr build .Xil
