ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
export PART
IP_OUT := $(CURDIR)/doa_covariance_4ch_hls/solution1/impl/ip
.PHONY: all hls catalog clean
all: hls catalog
hls:
	$(VITIS_HLS) -f build_hls.tcl
catalog: hls
	rm -rf $(ROOT)/ip_repo/doa_covariance_4ch
	mkdir -p $(ROOT)/ip_repo/doa_covariance_4ch
	cp -a $(IP_OUT)/. $(ROOT)/ip_repo/doa_covariance_4ch/
	cd $(ROOT) && $(VIVADO) -mode batch -source common/vivado/create_catalog_project.tcl -tclargs doa_covariance_4ch_test $(ROOT)/ip_repo/doa_covariance_4ch doa_covariance_4ch $(PART) "$(BOARD_PART)"
clean:
	rm -rf doa_covariance_4ch_hls build .Xil
