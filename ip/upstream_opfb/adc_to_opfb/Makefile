ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
export PART
HLS_CLK_NS ?= 2.5
export HLS_CLK_NS
IP_OUT := $(CURDIR)/adc_to_opfb_zcu48dr/solution1/impl/ip
.PHONY: all fetch hls catalog clean
all: hls catalog
fetch:
	$(ROOT)/scripts/fetch_upstream.sh opfb
hls: fetch
	$(VITIS_HLS) -f build_hls.tcl
catalog: hls
	mkdir -p $(IP_REPO)/adc_to_opfb
	cp -a $(IP_OUT)/. $(IP_REPO)/adc_to_opfb/
	cd $(ROOT) && $(VIVADO) -mode batch -source common/vivado/create_catalog_project.tcl -tclargs adc_to_opfb_test $(IP_REPO)/adc_to_opfb adc_to_opfb $(PART) "$(BOARD_PART)"
clean:
	rm -rf adc_to_opfb_zcu48dr build .Xil
