ROOT := $(abspath ../../..)
include $(ROOT)/config.mk

.PHONY: all ip verify clean

all: ip

verify:
	python3 verify_golden_model.py

ip: verify
	$(VIVADO) -mode batch -nojournal -nolog -source package_ip.tcl

clean:
	rm -rf "$(IP_REPO)/doa_subband_bridge_4ch" "$(BUILD)/subband_bridge_work"
