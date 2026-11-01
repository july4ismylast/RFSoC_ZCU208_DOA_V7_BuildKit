ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
# Prefer newest packaged folder present at the pinned upstream commit.
SRC := $(shell find $(UPSTREAM)/pkg-fft-output -maxdepth 1 -type d -name '*pkg_fft_output*' | sort | tail -1)
DST := $(IP_REPO)/pkg_fft_output
.PHONY: all fetch copy catalog clean
all: copy catalog
fetch:
	$(ROOT)/scripts/fetch_upstream.sh opfb
copy: fetch
	@test -n "$(SRC)" || (echo "No packaged pkg_fft_output IP found"; exit 1)
	rm -rf $(DST); mkdir -p $(DST); cp -a $(SRC)/. $(DST)/
catalog: copy
	cd $(ROOT) && $(VIVADO) -mode batch -source common/vivado/create_catalog_project.tcl -tclargs pkg_fft_output_test $(DST) pkg_fft_output $(PART) "$(BOARD_PART)"
clean:
	rm -rf $(DST) build .Xil
