SHELL := /bin/bash
.DEFAULT_GOAL := help

include config.mk

STAMP_DIR := $(BUILD)/.stamps
LOG_DIR   := $(BUILD)/logs

STAGES := \
	step00_preflight \
	step01_fetch_references \
	step02_hls_covariance \
	step03_hls_spectrum \
	step04_hls_candidate \
	step04_hls_beam \
	step05_hls_repack \
	step05_channelizer \
	step05_subband_bridge \
	step06_collect_ip \
	step07_vivado_project \
	step08_vivado_integrate \
	step09_vivado_validate \
	step10_synth \
	step11_impl \
	step12_bitstream \
	step13_export_xsa \
	step14_hil_vectors \
	step15_package

PRODUCTION_STAGES := step00_preflight step02_hls_covariance step03_hls_spectrum \
	step04_hls_candidate step04_hls_beam step05_hls_repack step05_channelizer \
	step05_subband_bridge step06_collect_ip step07_vivado_project \
	step08_vivado_integrate step09_vivado_validate step10_synth step11_impl \
	step12_bitstream step13_export_xsa step14_hil_vectors step15_package

ifeq ($(FORCE),1)
FORCE_DEP := FORCE
endif

.PHONY: help list lint pipeline all stage rebuild status graph clean-stage clean-build FORCE $(STAGES)

help:
	@echo "ZCU208 DOA V7 restartable build"
	@echo
	@echo "Run one stage:       make step02_hls_covariance"
	@echo "Resume full build:   make pipeline"
	@echo "Force one stage:     make rebuild STEP=step02_hls_covariance"
	@echo "Remove one result:   make clean-stage STEP=step02_hls_covariance"
	@echo "Inspect progress:    make status"
	@echo "Static validation:   make lint"
	@echo "Dry-run a stage:     make -n step10_synth"
	@echo "Run/capture V06 gate: make debug-channelizer-gate GATE=gate4-axis-wrapper-rtl-sim"
	@echo
	@echo "Stages (each can be invoked independently):"
	@echo "  step00_preflight         Check tools, part, versions, and configuration"
	@echo "  step01_fetch_references  Fetch selected upstream references; FETCH_SET=native|opfb|all"
	@echo "  step02_hls_covariance    C-sim, synth, and export V7 4-channel covariance IP"
	@echo "  step03_hls_spectrum      C-sim, synth, and export 4-lane spectrum-power IP"
	@echo "  step04_hls_candidate     C-sim, synth, and export streaming peak/noise candidate IP"
	@echo "  step04_hls_beam          C-sim, synth, and export optional vector beam monitor IP"
	@echo "  step05_hls_repack        C-sim, synth, and export V05 RFDC SSR-8 I/Q gearbox IP (250 MHz)"
	@echo "  step05_channelizer       Build selected channelizer flow"
	@echo "                             CHANNELIZER_FLOW=matlab_hdl|model_composer|opfb|external"
	@echo "  step05_subband_bridge    Verify, synth-check, and package 4-channel subband stream bridge IP"
	@echo "  step06_collect_ip        Validate component.xml files and assemble one IP repository"
	@echo "  step07_vivado_project    Copy a verified ZCU208 base .xpr into an isolated project"
	@echo "  step08_vivado_integrate  Add DOA V7 using config/zcu208_bd_map.tcl"
	@echo "  step09_vivado_validate   Validate block design and write clock/interface reports"
	@echo "  step10_synth             Generate targets and run synthesis only"
	@echo "  step11_impl              Run opt/place/route only from synthesis"
	@echo "  step12_bitstream         Write .bit/.hwh only from routed design"
	@echo "  step13_export_xsa        Export hardware handoff including bitstream"
	@echo "  step14_hil_vectors       Generate V7 fixed-point HIL vectors in MATLAB"
	@echo "  step15_package           Package outputs, reports, manifests, and logs"
	@echo
	@echo "Important configuration:"
	@echo "  BASE_XPR  (BASE_KIND=mts default: stage-V03 output build/mts_base_src_2023p2/boards/ZCU208/build_mts/mts/mts.xpr)"
	@echo "  BASE_BD   (BASE_KIND=mts default: mts)   ZCU208_BD_MAP=config/zcu208_bd_map.tcl"
	@echo "  EXPECTED_VIVADO_VERSION=<version used by the base project>"
	@echo "  V7_MATLAB_ROOT=/absolute/path/to/DOA_2x2_Realistic_HIL_R2024a_ZU48DR_V7"
	@echo
	@echo "Use 'make list' for stage names and BUILD_STAGES.md for debugging."

list:
	@for stage_name in $(STAGES); do echo "$$stage_name"; done

lint:
	@./scripts/static_validate.sh

all: pipeline

pipeline:
	@set -e; for stage_name in $(PRODUCTION_STAGES); do \
		echo; echo "===== $$stage_name ====="; \
		$(MAKE) --no-print-directory $$stage_name; \
	done

stage:
	@test -n "$(STEP)" || { echo "ERROR: use make stage STEP=stepNN_name"; exit 2; }
	@case " $(STAGES) " in *" $(STEP) "*) ;; *) echo "ERROR: unknown STEP=$(STEP)"; exit 2;; esac
	@$(MAKE) --no-print-directory "$(STEP)"

rebuild:
	@test -n "$(STEP)" || { echo "ERROR: use make rebuild STEP=stepNN_name"; exit 2; }
	@$(MAKE) --no-print-directory FORCE=1 "$(STEP)"

status:
	@./scripts/stage_status.sh "$(BUILD)" $(STAGES)

graph:
	@cat docs/build-stages.mmd

clean-stage:
	@test -n "$(STEP)" || { echo "ERROR: use make clean-stage STEP=stepNN_name"; exit 2; }
	@./scripts/clean_stage.sh "$(STEP)" "$(BUILD)" "$(IP_REPO)" "$(PROJECT_NAME)"

clean-build:
	@./scripts/clean_build.sh "$(BUILD)" "$(IP_REPO)"

step00_preflight: $(STAMP_DIR)/step00_preflight.done
step01_fetch_references: $(STAMP_DIR)/step01_fetch_references.done
step02_hls_covariance: $(STAMP_DIR)/step02_hls_covariance.done
step03_hls_spectrum: $(STAMP_DIR)/step03_hls_spectrum.done
step04_hls_candidate: $(STAMP_DIR)/step04_hls_candidate.done
step04_hls_beam: $(STAMP_DIR)/step04_hls_beam.done
step05_hls_repack: $(STAMP_DIR)/step05_hls_repack.done
step05_channelizer: $(STAMP_DIR)/step05_channelizer.done
step05_subband_bridge: $(STAMP_DIR)/step05_subband_bridge.done
step06_collect_ip: $(STAMP_DIR)/step06_collect_ip.done
step07_vivado_project: $(STAMP_DIR)/step07_vivado_project.done
step08_vivado_integrate: $(STAMP_DIR)/step08_vivado_integrate.done
step09_vivado_validate: $(STAMP_DIR)/step09_vivado_validate.done
step10_synth: $(STAMP_DIR)/step10_synth.done
step11_impl: $(STAMP_DIR)/step11_impl.done
step12_bitstream: $(STAMP_DIR)/step12_bitstream.done
step13_export_xsa: $(STAMP_DIR)/step13_export_xsa.done
step14_hil_vectors: $(STAMP_DIR)/step14_hil_vectors.done
step15_package: $(STAMP_DIR)/step15_package.done

$(STAMP_DIR)/step00_preflight.done: Makefile config.mk config/ip_versions.tcl common/vivado/common.tcl common/vivado/00_check_ip_catalog.tcl scripts/preflight.sh scripts/run_stage.sh $(FORCE_DEP)
	@./scripts/run_stage.sh --id step00_preflight --stamp "$@" --log "$(LOG_DIR)/step00_preflight.log" -- ./scripts/preflight.sh

$(STAMP_DIR)/step01_fetch_references.done: scripts/fetch_upstream.sh scripts/run_stage.sh config/upstream_repositories.tsv $(FORCE_DEP)
	@./scripts/run_stage.sh --id step01_fetch_references --stamp "$@" --log "$(LOG_DIR)/step01_fetch_references.log" -- ./scripts/fetch_upstream.sh "$(FETCH_SET)"

$(STAMP_DIR)/step02_hls_covariance.done: $(shell find ip/custom/doa_covariance_4ch_v4 -type f 2>/dev/null) config.mk common/scripts/check_component_vlnv.sh scripts/run_stage.sh $(FORCE_DEP)
	@./scripts/run_stage.sh --id step02_hls_covariance --stamp "$@" --log "$(LOG_DIR)/step02_hls_covariance.log" -- make --no-print-directory -C ip/custom/doa_covariance_4ch_v4 all

$(STAMP_DIR)/step03_hls_spectrum.done: $(shell find ip/custom/spectrum_power4 -type f 2>/dev/null) config.mk common/scripts/check_component_vlnv.sh scripts/run_stage.sh $(FORCE_DEP)
	@./scripts/run_stage.sh --id step03_hls_spectrum --stamp "$@" --log "$(LOG_DIR)/step03_hls_spectrum.log" -- make --no-print-directory -C ip/custom/spectrum_power4 all

$(STAMP_DIR)/step04_hls_candidate.done: $(shell find ip/custom/candidate_peak4 -type f 2>/dev/null) config.mk common/scripts/check_component_vlnv.sh scripts/run_stage.sh $(FORCE_DEP)
	@./scripts/run_stage.sh --id step04_hls_candidate --stamp "$@" --log "$(LOG_DIR)/step04_hls_candidate.log" -- make --no-print-directory -C ip/custom/candidate_peak4 all

$(STAMP_DIR)/step04_hls_beam.done: $(shell find ip/custom/beam_weight_4ch -type f 2>/dev/null) config.mk common/scripts/check_component_vlnv.sh scripts/run_stage.sh $(FORCE_DEP)
	@./scripts/run_stage.sh --id step04_hls_beam --stamp "$@" --log "$(LOG_DIR)/step04_hls_beam.log" -- make --no-print-directory -C ip/custom/beam_weight_4ch all

$(STAMP_DIR)/step05_hls_repack.done: $(shell find ip/custom/rfdc_repack4 -type f 2>/dev/null) config.mk common/scripts/check_component_vlnv.sh scripts/run_stage.sh $(FORCE_DEP)
	@./scripts/run_stage.sh --id step05_hls_repack --stamp "$@" --log "$(LOG_DIR)/step05_hls_repack.log" -- make --no-print-directory -C ip/custom/rfdc_repack4 all

$(STAMP_DIR)/step05_channelizer.done: $(shell find ip/matlab/channelizer_hdl ip/model_composer/channelizer ip/upstream_opfb -type f 2>/dev/null) scripts/build_channelizer.sh scripts/fetch_upstream.sh common/scripts/import_packaged_ip.sh common/scripts/check_component_vlnv.sh common/vivado/create_catalog_project.tcl scripts/run_matlab_clean.sh config.mk config/upstream_repositories.tsv scripts/run_stage.sh $(FORCE_DEP)
	@./scripts/run_stage.sh --id step05_channelizer --stamp "$@" --log "$(LOG_DIR)/step05_channelizer.log" -- ./scripts/build_channelizer.sh "$(CHANNELIZER_FLOW)"

$(STAMP_DIR)/step05_subband_bridge.done: $(shell find ip/custom/doa_subband_bridge_4ch -type f 2>/dev/null) common/scripts/check_component_vlnv.sh config.mk config/ip_versions.tcl common/vivado/common.tcl scripts/run_stage.sh $(FORCE_DEP)
	@./scripts/run_stage.sh --id step05_subband_bridge --stamp "$@" --log "$(LOG_DIR)/step05_subband_bridge.log" -- make --no-print-directory -C ip/custom/doa_subband_bridge_4ch all

$(STAMP_DIR)/step06_collect_ip.done: scripts/collect_ip.sh config.mk config/ip_versions.tcl scripts/run_stage.sh $(FORCE_DEP)
	@./scripts/run_stage.sh --id step06_collect_ip --stamp "$@" --log "$(LOG_DIR)/step06_collect_ip.log" -- ./scripts/collect_ip.sh

$(STAMP_DIR)/step07_vivado_project.done: common/vivado/07_create_project_from_base.tcl config.mk config/ip_versions.tcl common/vivado/common.tcl scripts/run_stage.sh $(FORCE_DEP)
	@./scripts/run_stage.sh --id step07_vivado_project --stamp "$@" --log "$(LOG_DIR)/step07_vivado_project.log" -- $(VIVADO) -mode batch -nojournal -nolog -source common/vivado/07_create_project_from_base.tcl

$(STAMP_DIR)/step08_vivado_integrate.done: common/vivado/08_integrate_doa_v7.tcl common/vivado/create_doa_v7_hier.tcl config/zcu208_bd_map.tcl config.mk config/ip_versions.tcl common/vivado/common.tcl scripts/run_stage.sh $(FORCE_DEP)
	@./scripts/run_stage.sh --id step08_vivado_integrate --stamp "$@" --log "$(LOG_DIR)/step08_vivado_integrate.log" -- $(VIVADO) -mode batch -nojournal -nolog -source common/vivado/08_integrate_doa_v7.tcl

$(STAMP_DIR)/step09_vivado_validate.done: common/vivado/09_validate.tcl config.mk config/ip_versions.tcl common/vivado/common.tcl scripts/run_stage.sh $(FORCE_DEP)
	@./scripts/run_stage.sh --id step09_vivado_validate --stamp "$@" --log "$(LOG_DIR)/step09_vivado_validate.log" -- $(VIVADO) -mode batch -nojournal -nolog -source common/vivado/09_validate.tcl

$(STAMP_DIR)/step10_synth.done: common/vivado/10_synth.tcl config.mk config/ip_versions.tcl common/vivado/common.tcl scripts/run_stage.sh $(FORCE_DEP)
	@./scripts/run_stage.sh --id step10_synth --stamp "$@" --log "$(LOG_DIR)/step10_synth.log" -- $(VIVADO) -mode batch -nojournal -nolog -source common/vivado/10_synth.tcl

$(STAMP_DIR)/step11_impl.done: common/vivado/11_impl.tcl config.mk config/ip_versions.tcl common/vivado/common.tcl scripts/run_stage.sh $(FORCE_DEP)
	@./scripts/run_stage.sh --id step11_impl --stamp "$@" --log "$(LOG_DIR)/step11_impl.log" -- $(VIVADO) -mode batch -nojournal -nolog -source common/vivado/11_impl.tcl

$(STAMP_DIR)/step12_bitstream.done: common/vivado/12_bitstream.tcl config.mk config/ip_versions.tcl common/vivado/common.tcl scripts/run_stage.sh $(FORCE_DEP)
	@./scripts/run_stage.sh --id step12_bitstream --stamp "$@" --log "$(LOG_DIR)/step12_bitstream.log" -- $(VIVADO) -mode batch -nojournal -nolog -source common/vivado/12_bitstream.tcl

$(STAMP_DIR)/step13_export_xsa.done: common/vivado/13_export_xsa.tcl config.mk config/ip_versions.tcl common/vivado/common.tcl scripts/run_stage.sh $(FORCE_DEP)
	@./scripts/run_stage.sh --id step13_export_xsa --stamp "$@" --log "$(LOG_DIR)/step13_export_xsa.log" -- $(VIVADO) -mode batch -nojournal -nolog -source common/vivado/13_export_xsa.tcl

$(STAMP_DIR)/step14_hil_vectors.done: hil/matlab/generate_zcu208_hil_vectors.m scripts/generate_hil.sh scripts/run_matlab_clean.sh config.mk scripts/run_stage.sh $(FORCE_DEP)
	@./scripts/run_stage.sh --id step14_hil_vectors --stamp "$@" --log "$(LOG_DIR)/step14_hil_vectors.log" -- ./scripts/generate_hil.sh

$(STAMP_DIR)/step15_package.done: scripts/package_release.sh config.mk scripts/run_stage.sh $(FORCE_DEP)
	@./scripts/run_stage.sh --id step15_package --stamp "$@" --log "$(LOG_DIR)/step15_package.log" -- ./scripts/package_release.sh

# Deliberate user action only: never part of pipeline/all.
.PHONY: publish-evidence
publish-evidence:
	@CHANNELIZER_FLOW="$(CHANNELIZER_FLOW)" BUILD="$(BUILD)" IP_REPO="$(IP_REPO)" bash scripts/publish_build_evidence.sh

.PHONY: publish-debug-logs
publish-debug-logs:
	@CHANNELIZER_FLOW="$(CHANNELIZER_FLOW)" BUILD="$(BUILD)" bash scripts/publish_debug_logs.sh

# Run one stage, then snapshot its logs even if the stage fails. The snapshot
# is committed locally; use GitHub Desktop's Push origin on machines without
# command-line GitHub authentication.
.PHONY: debug-stage debug-stages
debug-stage:
	@test -n "$(STEP)" || { echo "ERROR: use make debug-stage STEP=stepNN_name"; exit 2; }
	@bash scripts/run_stage_and_publish_debug.sh "$(STEP)"

debug-stages:
	@test -n "$(STEPS)" || { echo "ERROR: use make debug-stages STEPS=\"step05_channelizer ...\""; exit 2; }
	@bash scripts/run_stages_and_publish_debug.sh $(STEPS)

# Run one V06 MATLAB-HDL feasibility gate and snapshot its console transcript
# plus its report, even when the gate fails.
.PHONY: debug-channelizer-gate
debug-channelizer-gate:
	@test -n "$(GATE)" || { echo "ERROR: use make debug-channelizer-gate GATE=gate4-axis-wrapper-rtl-sim"; exit 2; }
	@BUILD="$(BUILD)" bash scripts/run_channelizer_gate_and_publish_debug.sh "$(GATE)"

.PHONY: repair-mts-module-refs
repair-mts-module-refs:
	@$(VIVADO) -mode batch -nojournal -nolog -source common/vivado/07_repair_mts_module_refs.tcl

# Standalone native OPFB resource screen, never modifies the MTS project.
.PHONY: opfb-resource-check
opfb-resource-check:
	@mkdir -p "$(LOG_DIR)"
	@set -o pipefail; $(VIVADO) -mode batch -nojournal -nolog -source common/vivado/v06_opfb_ooc.tcl 2>&1 | tee "$(LOG_DIR)/v06_opfb_ooc.log"

.PHONY: opfb-route-check
opfb-route-check:
	@mkdir -p "$(LOG_DIR)"
	@set -o pipefail; $(VIVADO) -mode batch -nojournal -nolog -source common/vivado/v06_opfb_route.tcl 2>&1 | tee "$(LOG_DIR)/v06_opfb_route.log"
