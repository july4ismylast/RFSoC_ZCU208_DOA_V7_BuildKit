ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
export PART
HLS_CLK_NS ?= 2.5
export HLS_CLK_NS
IP_OUT := $(CURDIR)/opfb_fir_cfg_zcu48dr/solution1/impl/ip
.PHONY: all fetch hls catalog clean
all: hls catalog
fetch:
	$(ROOT)/scripts/fetch_upstream.sh opfb
hls: fetch
	$(VITIS_HLS) -f build_hls.tcl
catalog: hls
	mkdir -p $(IP_REPO)/opfb_fir_cfg
	cp -a $(IP_OUT)/. $(IP_REPO)/opfb_fir_cfg/
	cd $(ROOT) && $(VIVADO) -mode batch -source common/vivado/create_catalog_project.tcl -tclargs opfb_fir_cfg_test $(IP_REPO)/opfb_fir_cfg opfb_fir_cfg $(PART) "$(BOARD_PART)"
clean:
	rm -rf opfb_fir_cfg_zcu48dr build .Xil
