ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
IP_OUT := $(CURDIR)/rfdc_repack4_hls/solution1/impl/ip
DEST := $(IP_REPO)/rfdc_repack4
IP_VLNV := $(CUSTOM_IP_VENDOR):$(CUSTOM_IP_LIBRARY):rfdc_repack4:$(IPVER_RFDC_REPACK4)
.PHONY: all hls install clean
all: hls install
hls:
	$(VITIS_HLS) -f build_hls.tcl
install: hls
	@test -f "$(IP_OUT)/component.xml" || { echo "Missing HLS export $(IP_OUT)/component.xml"; exit 2; }
	@$(ROOT)/common/scripts/check_component_vlnv.sh "$(IP_OUT)/component.xml" "$(IP_VLNV)"
	rm -rf "$(DEST)"
	mkdir -p "$(DEST)"
	cp -a "$(IP_OUT)/." "$(DEST)/"
clean:
	rm -rf rfdc_repack4_hls vitis_hls.log
