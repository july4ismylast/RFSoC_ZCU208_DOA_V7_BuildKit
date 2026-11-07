ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
.PHONY: all export verify clean

# Model Composer 2023.2 carries MATLAB R2022b, and the command-line MATLAB
# (R2024a here) cannot run it: xlGenerateButton only exists once the Model
# Composer / System Generator paths are on the MATLAB path.
#
# Two facts come from a real run on the ZCU208 host (2026-11-07, see
# docs/evidence/2026-11-07-host-probe/model_composer_launcher_eval_bug.txt):
#
#   1. the launcher evals its arguments into `exec matlab <args> -r <startup>`,
#      so a MATLAB statement passed after -batch loses its quotes and the eval
#      dies on the first parenthesis:
#        syntax error near unexpected token `('
#   2. it always appends its own -r, and MATLAB does not accept -batch with -r.
#
# So the build does not go through the launcher at all.  scripts/
# build_model_composer_ip.sh runs R2022b directly in -batch and sets the same
# paths the launcher's own banner lists (Model Composer simulink/bsp libs,
# Vivado scripts/sysgen/matlab, sysgen.jar).  The launcher keeps the one job it
# is good for: the GUI, through `make mc-gui`.
all: export verify

export:
	@test -n "$(strip $(MODEL_COMPOSER_MODEL))" || { \
	    echo "MODEL_COMPOSER_MODEL=/absolute/path/to/model.slx is required"; \
	    echo "the model needs one Xilinx System Generator token set to IP Catalog"; \
	    echo "to create or edit that model: make mc-gui"; \
	    exit 2; }
	@$(ROOT)/scripts/build_model_composer_ip.sh "$(MODEL_COMPOSER_MODEL)"

# A build is only a build if it produced IP.  The exporter prints its own
# success line, but a token that was not set to IP Catalog, or a compile that
# stopped early, leaves nothing behind -- so check the artifact too.
verify:
	@dest="$(IP_REPO)/model_composer_channelizer/component.xml"; \
	if [ ! -s "$$dest" ]; then \
	    echo "ERROR: the export did not produce $$dest"; \
	    echo "Check the token's compile target is IP Catalog, and that the"; \
	    echo "model was saved after the last edit."; \
	    exit 3; fi; \
	if [ "$$dest" -ot "$(MODEL_COMPOSER_MODEL)" ]; then \
	    echo "WARNING: component.xml is older than the model -- stale IP"; fi; \
	echo "verified IP: $$dest"; \
	ls -l "$$dest" | awk '{print "  size " $$5 " bytes, " $$6 " " $$7 " " $$8}'; \
	version="$$(grep -o '<spirit:version>[^<]*' "$$dest" | head -n 1 | cut -d'>' -f2)"; \
	[ -n "$$version" ] && echo "  version $$version"; \
	echo "  consumed by step06_collect_ip and step08_vivado_integrate"

clean:
	rm -rf build .Xil
