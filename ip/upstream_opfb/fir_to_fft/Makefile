ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
export PART
HLS_CLK_NS ?= 2.5
export HLS_CLK_NS
IP_OUT := $(CURDIR)/fir_to_fft_zcu48dr/solution1/impl/ip
.PHONY: all fetch hls catalog clean
all: hls catalog
fetch:
	$(ROOT)/scripts/fetch_upstream.sh opfb
hls: fetch
	$(VITIS_HLS) -f build_hls.tcl
catalog: hls
	mkdir -p $(IP_REPO)/fir_to_fft
	cp -a $(IP_OUT)/. $(IP_REPO)/fir_to_fft/
	cd $(ROOT) && $(VIVADO) -mode batch -source common/vivado/create_catalog_project.tcl -tclargs fir_to_fft_test $(IP_REPO)/fir_to_fft fir_to_fft $(PART) "$(BOARD_PART)"
clean:
	rm -rf fir_to_fft_zcu48dr build .Xil
