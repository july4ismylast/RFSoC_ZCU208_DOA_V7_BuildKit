ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
MATLAB_RUNNER ?= $(ROOT)/scripts/run_matlab_clean.sh
.PHONY: all export clean
# Model Composer 2023.2 only runs with the MATLAB release it shipped with
# (R2022b) and only through its own launcher, which puts the MC / System
# Generator paths on the MATLAB path.  So MODEL_COMPOSER wins, MATLAB_2022B is
# the fallback, and the command-line MATLAB (usually R2024a) is never used here:
# silently using it is how this stage fails with "xlGenerateButton unavailable".
ifeq ($(strip $(MODEL_COMPOSER)),)
MC_LAUNCH := $(MATLAB_RUNNER) "$(MATLAB_2022B)"
MC_WHY    := MATLAB_2022B
else
MC_LAUNCH := "$(MODEL_COMPOSER)"
MC_WHY    := the Model Composer launcher
endif

all: export

export:
	@test -n "$(MODEL_COMPOSER_MODEL)" || { \
	    echo "MODEL_COMPOSER_MODEL=/absolute/path/to/model.slx is required"; \
	    echo "the model needs one Xilinx System Generator token set to IP Catalog"; \
	    exit 2; }
	@if [ -z "$(strip $(MODEL_COMPOSER))" ] && [ -z "$(strip $(MATLAB_2022B))" ]; then \
	    echo "Model Composer needs MATLAB 2022b, not the command-line MATLAB:"; \
	    echo "  make step05_channelizer CHANNELIZER_FLOW=model_composer \\\\"; \
	    echo "       MODEL_COMPOSER=/path/Model_Composer/2023.2/bin/model_composer \\\\"; \
	    echo "       MODEL_COMPOSER_MODEL=/abs/path/channelizer.slx"; \
	    exit 2; fi
	@echo "Model Composer export via $(MC_WHY)"
	$(MC_LAUNCH) -batch "addpath(pwd); export_model_composer_ip('$(MODEL_COMPOSER_MODEL)')"
clean:
	rm -rf build .Xil
