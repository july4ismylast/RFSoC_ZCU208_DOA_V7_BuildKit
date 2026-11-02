ROOT := $(abspath ../..)
include $(ROOT)/config.mk

# Default step05 set: only the adapters that produce the ten MazinLab IP
# definitions actually instantiated by the pinned RFSoC_OPFB
# bd/opfb_streaming.tcl.  iq_capture produces three of those definitions.
BD_IP_BLOCKS := adc_to_opfb opfb_fir_cfg fir_to_fft ssrfft_packaged \
	pkg_fft_output_packaged capture_upsizer iq_capture opfb_bin_to_res

# Not part of the RFSoC_OPFB streaming BD (and therefore not part of step05):
#  - dac_replay is a standalone packaged-IP inspection adapter;
#  - wb2axip is used upstream as plain module-reference RTL, not packaged IP.
OPTIONAL_BLOCKS := dac_replay wb2axip

.PHONY: all fetch list list-optional $(BD_IP_BLOCKS) $(OPTIONAL_BLOCKS) clean
all: fetch $(BD_IP_BLOCKS)

# Fetch the pinned OPFB repository set once here.  Child adapters keep their
# own fetch target for standalone use, but OPFB_FETCH_DONE=1 prevents the
# whole set from being re-fetched eleven times in one step05 run.
fetch:
	$(ROOT)/scripts/fetch_upstream.sh opfb

list:
	@for block in $(BD_IP_BLOCKS); do echo "$$block"; done

list-optional:
	@for block in $(OPTIONAL_BLOCKS); do echo "$$block"; done

$(BD_IP_BLOCKS) $(OPTIONAL_BLOCKS): fetch
	$(MAKE) --no-print-directory -C $@ all OPFB_FETCH_DONE=1

clean:
	@for block in $(BD_IP_BLOCKS) $(OPTIONAL_BLOCKS); do \
		$(MAKE) --no-print-directory -C $$block clean; \
	done
