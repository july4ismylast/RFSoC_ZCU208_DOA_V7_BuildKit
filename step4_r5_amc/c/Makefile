# The AMC firmware, compiled the two ways that matter.
#
# The C is NOT copied into this folder: firmware/amc_r5/amc.c is the single
# source of truth, and this Makefile is the two-line way to build it here.
#
#   make            double precision, for the host (== the MATLAB model)
#   make single     -DAMC_SINGLE_ACC, because the Cortex-R5F FPU has no double
#   make clean
ROOT := $(abspath ../..)
FIRMWARE := $(ROOT)/firmware/amc_r5
BUILD := $(ROOT)/build/step4
CFLAGS ?= -std=c99 -O2 -Wall -Wextra -I$(FIRMWARE)

.PHONY: all double single clean

all: double single

double: $(BUILD)/test_amc_double
single: $(BUILD)/test_amc_single

$(BUILD)/test_amc_double: $(FIRMWARE)/test_amc.c $(FIRMWARE)/amc.c $(FIRMWARE)/amc.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -o "$@" $(FIRMWARE)/test_amc.c $(FIRMWARE)/amc.c -lm
	@echo "built $@ (double)"

$(BUILD)/test_amc_single: $(FIRMWARE)/test_amc.c $(FIRMWARE)/amc.c $(FIRMWARE)/amc.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -DAMC_SINGLE_ACC -o "$@" $(FIRMWARE)/test_amc.c $(FIRMWARE)/amc.c -lm
	@echo "built $@ (single, the R5 configuration)"

clean:
	rm -rf $(BUILD)
