ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
MATLAB_RUNNER ?= $(ROOT)/scripts/run_matlab_clean.sh
.PHONY: all export clean
all: export
export:
	@test -n "$(MODEL_COMPOSER_MODEL)" || { echo "MODEL_COMPOSER_MODEL=/absolute/path/to/model.slx is required"; exit 2; }
	$(MATLAB_RUNNER) "$(MATLAB)" -batch "addpath(pwd); export_model_composer_ip('$(MODEL_COMPOSER_MODEL)')"
clean:
	rm -rf build .Xil
