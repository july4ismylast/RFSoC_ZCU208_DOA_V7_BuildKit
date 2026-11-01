ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
NAME := dac-replay
SRC := $(UPSTREAM)/dac-replay
DST := $(IP_REPO)
.PHONY: help fetch list import catalog all clean
help:
	@echo "Standalone adapter for MazinLab/dac-replay. If upstream already contains packaged Vivado IP, import it; otherwise inspect/build its native source first."
fetch:
	$(ROOT)/scripts/fetch_upstream.sh opfb
list: fetch
	find $(SRC) -name component.xml -o -name '*.tcl' -o -name 'Makefile' | sort
import: fetch
	$(ROOT)/common/scripts/import_packaged_ip.sh $(SRC) $(DST) $(NAME)
catalog: import
	cd $(ROOT) && $(VIVADO) -mode batch -source common/vivado/create_catalog_project.tcl -tclargs dac_replay_catalog $(DST)/$(NAME) $(NAME) $(PART) "$(BOARD_PART)"
all: catalog
clean:
	rm -rf $(DST)/$(NAME)
