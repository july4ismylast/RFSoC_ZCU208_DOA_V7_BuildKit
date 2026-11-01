ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
IP_OUT := $(CURDIR)/doa_covariance_4ch_v4_prj/solution1/impl/ip
DEST := $(IP_REPO)/doa_covariance_4ch_v4
.PHONY: all hls install clean
all: hls install
hls:
	$(VITIS_HLS) -f build_hls.tcl
install: hls
	@test -f "$(IP_OUT)/component.xml" || { echo "Missing HLS export $(IP_OUT)/component.xml"; exit 2; }
	rm -rf "$(DEST)"
	mkdir -p "$(DEST)"
	cp -a "$(IP_OUT)/." "$(DEST)/"
	@echo "Installed covariance IP at $(DEST)"
clean:
	rm -rf doa_covariance_4ch_v4_prj vitis_hls.log

