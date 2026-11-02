ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
IP_OUT := $(CURDIR)/beam_weight_4ch_hls/solution1/impl/ip
DEST := $(IP_REPO)/beam_weight_4ch
IP_VLNV := $(CUSTOM_IP_VENDOR):$(CUSTOM_IP_LIBRARY):beam_weight_4ch:$(IPVER_BEAM)
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
	rm -rf beam_weight_4ch_hls vitis_hls.log

