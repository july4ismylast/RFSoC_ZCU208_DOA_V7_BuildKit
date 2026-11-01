ROOT := $(abspath ../..)
include $(ROOT)/config.mk
BLOCKS := adc_to_opfb opfb_fir_cfg fir_to_fft ssrfft_packaged \
	pkg_fft_output_packaged capture_upsizer dac_replay iq_capture \
	opfb_bin_to_res wb2axip
.PHONY: all fetch list $(BLOCKS) clean
all: fetch $(BLOCKS)
fetch:
	$(ROOT)/scripts/fetch_upstream.sh opfb
list:
	@for block in $(BLOCKS); do echo "$$block"; done
$(BLOCKS): fetch
	$(MAKE) --no-print-directory -C $@ all
clean:
	@for block in $(BLOCKS); do $(MAKE) --no-print-directory -C $$block clean; done

