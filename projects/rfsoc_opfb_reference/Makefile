ROOT := $(abspath ../..)
include $(ROOT)/config.mk
U := $(ROOT)/upstream/RFSoC_OPFB
.PHONY: help fetch upstream-project upstream-bit zcu208-ips
help:
	@echo "RFSoC_OPFB reference: 4096ch 2/1 oversampled PFB. Upstream top-level is RFSoC4x2; individual HLS IPs are retargeted separately in ../../ip/upstream_opfb."
fetch:
	$(ROOT)/scripts/fetch_upstream.sh
upstream-project: fetch
	$(MAKE) -C $(U) vivado_prj
upstream-bit: fetch
	$(MAKE) -C $(U) bitstream
zcu208-ips:
	$(MAKE) -C $(ROOT) opfb-ips
