ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
IP_OUT := $(CURDIR)/spectrum_power4_hls/solution1/impl/ip
DEST := $(IP_REPO)/spectrum_power4
IP_VLNV := $(CUSTOM_IP_VENDOR):$(CUSTOM_IP_LIBRARY):spectrum_power4:$(IPVER_SPECTRUM)
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
	rm -rf spectrum_power4_hls vitis_hls.log

