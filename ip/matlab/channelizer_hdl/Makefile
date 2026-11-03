ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
TOP ?= Channelizer_DUT
MATLAB_RUNNER ?= $(ROOT)/scripts/run_matlab_clean.sh
HDL_TOP_FILE := hdl_prj/hdlsrc/zu48dr_channelizer_ip/$(TOP).v
HDL_TOP_FILE_TRANSPOSED := hdl_prj/hdlsrc_transposed/zu48dr_channelizer_ip/$(TOP).v
PACKAGED_COMPONENT := $(IP_REPO)/matlab_channelizer/component.xml
IP_VLNV := $(CUSTOM_IP_VENDOR):$(CUSTOM_IP_LIBRARY):matlab_channelizer:$(IPVER_CHANNELIZER)
MATLAB_SOURCES := build_model.m generate_hdl.m ZU48DRChannelizer.m
V06_PROBE_REPORT := $(ROOT)/build/output/v06_channelizer_probe.rpt
V06_PROBE_TRANSPOSED_REPORT := $(ROOT)/build/output/v06_channelizer_probe_transposed.rpt
V06_GATE1_REPORT := $(ROOT)/build/output/v06_gate1_hdl_generation.rpt
V06_GATE1_TRANSPOSED_REPORT := $(ROOT)/build/output/v06_gate1_hdl_generation_transposed.rpt
V06_GATE2_REPORT := $(ROOT)/build/output/v06_gate2_ooc_synthesis.rpt
V06_GATE2R_BRAM_REPORT := $(ROOT)/build/output/v06_gate2r_bram_ooc_synthesis.rpt
V06_GATE2T_TRANSPOSED_REPORT := $(ROOT)/build/output/v06_gate2t_transposed_ooc_synthesis.rpt
V06_GATE3_TRANSPOSED_REPORT := $(ROOT)/build/output/v06_gate3_transposed_numerics.rpt
ALLOW_CHANNELIZER_PACKAGE ?= 0

.PHONY: all model hdl package package-only require-package-allowed probe probe-transposed gate1 gate1-transposed gate2 gate2r-bram gate2t-transposed gate3-transposed clean
all: package
# Stage V06 Gate 0 (passed on the user PC, 2026-11-03): the installed
# dsphdl.Channelizer accepts the production-size SSR-8/1024-band
# fixed-point configuration with Normalize=false.  The probe remains
# available as a regression check and does not generate HDL.
probe: v06_probe_ssr8_1024.m
	V06_FILTER_STRUCTURE=systolic $(MATLAB_RUNNER) "$(MATLAB)" -batch "v06_probe_ssr8_1024"
	@test -f "$(V06_PROBE_REPORT)" || { echo "ERROR: V06 probe report missing: $(V06_PROBE_REPORT)"; exit 1; }
	@grep -q "V06 CHANNELIZER PROBE RESULT=PASS" "$(V06_PROBE_REPORT)" || { echo "ERROR: V06 probe did not PASS (see $(V06_PROBE_REPORT))"; exit 1; }

# Stage V06 Gate 2T, step 1: rerun the same production-size Gate-0
# fixed-point probe with only FilterStructure changed to Direct form
# transposed.  The separate *_transposed report preserves the proved
# systolic Gate-0 evidence.
probe-transposed: v06_probe_ssr8_1024.m
	V06_FILTER_STRUCTURE=transposed $(MATLAB_RUNNER) "$(MATLAB)" -batch "v06_probe_ssr8_1024"
	@test -f "$(V06_PROBE_TRANSPOSED_REPORT)" || { echo "ERROR: V06 transposed probe report missing: $(V06_PROBE_TRANSPOSED_REPORT)"; exit 1; }
	@grep -q "^FILTER_STRUCTURE=Direct form transposed$$" "$(V06_PROBE_TRANSPOSED_REPORT)" || { echo "ERROR: transposed probe did not select Direct form transposed (see $(V06_PROBE_TRANSPOSED_REPORT))"; exit 1; }
	@grep -q "V06 CHANNELIZER PROBE RESULT=PASS" "$(V06_PROBE_TRANSPOSED_REPORT)" || { echo "ERROR: V06 transposed probe did not PASS (see $(V06_PROBE_TRANSPOSED_REPORT))"; exit 1; }

# Stage V06 Gate 1 (passed on the user PC, 2026-11-03): parameterize the
# legacy harness to config.mk's 1024-band/SSR-8 values, generate one
# channel of Verilog, and catalog the generated top/ports/reports.  This
# deliberately does not invoke Vivado packaging or create a production
# IP component.
gate1: $(MATLAB_SOURCES) v06_gate1_generate_hdl.m v06_probe_ssr8_1024.m
	V06_FILTER_STRUCTURE=systolic $(MATLAB_RUNNER) "$(MATLAB)" -batch "v06_gate1_generate_hdl"
	@test -f "$(V06_GATE1_REPORT)" || { echo "ERROR: V06 Gate-1 report missing: $(V06_GATE1_REPORT)"; exit 1; }
	@grep -q "V06 GATE1 HDL GENERATION RESULT=PASS" "$(V06_GATE1_REPORT)" || { echo "ERROR: V06 Gate-1 did not PASS (see $(V06_GATE1_REPORT))"; exit 1; }

# Stage V06 Gate 2T, step 2: generate the transposed one-channel RTL
# under hdl_prj/hdlsrc_transposed.  Gate 1 itself requires the matching
# transposed Gate-0 PASS report, exact peak bin, signed 26/24 output,
# and the transposed latency recorded by that probe.  No packaging.
gate1-transposed: $(MATLAB_SOURCES) v06_gate1_generate_hdl.m v06_probe_ssr8_1024.m
	@test -f "$(V06_PROBE_TRANSPOSED_REPORT)" || { echo "ERROR: transposed Gate-0 report missing; run make -C ip/matlab/channelizer_hdl probe-transposed first"; exit 1; }
	@grep -q "V06 CHANNELIZER PROBE RESULT=PASS" "$(V06_PROBE_TRANSPOSED_REPORT)" || { echo "ERROR: transposed Gate-0 has not PASSed; see $(V06_PROBE_TRANSPOSED_REPORT)"; exit 1; }
	V06_FILTER_STRUCTURE=transposed $(MATLAB_RUNNER) "$(MATLAB)" -batch "v06_gate1_generate_hdl"
	@test -f "$(V06_GATE1_TRANSPOSED_REPORT)" || { echo "ERROR: V06 transposed Gate-1 report missing: $(V06_GATE1_TRANSPOSED_REPORT)"; exit 1; }
	@grep -q "^FILTER_STRUCTURE=Direct form transposed$$" "$(V06_GATE1_TRANSPOSED_REPORT)" || { echo "ERROR: transposed Gate-1 did not select Direct form transposed (see $(V06_GATE1_TRANSPOSED_REPORT))"; exit 1; }
	@test -f "$(HDL_TOP_FILE_TRANSPOSED)" || { echo "ERROR: transposed generated HDL top missing: $(HDL_TOP_FILE_TRANSPOSED)"; exit 1; }
	@grep -q "V06 GATE1 HDL GENERATION RESULT=PASS" "$(V06_GATE1_TRANSPOSED_REPORT)" || { echo "ERROR: V06 transposed Gate-1 did not PASS (see $(V06_GATE1_TRANSPOSED_REPORT))"; exit 1; }

# Stage V06 Gate 2 (passed systolic baseline): synthesize exactly the Gate-1 RTL for
# one channel, out-of-context, on the pinned part at the config.mk
# 4.0 ns wideband period.  The Tcl writes utilization/timing reports and
# a checkpoint; it does not implement, package, or modify a block design.
gate2: v06_gate2_ooc_synth.tcl v06_gate2_ooc.xdc
	@test -f "$(V06_GATE1_REPORT)" || { echo "ERROR: Gate-1 report missing; run make -C ip/matlab/channelizer_hdl gate1 first"; exit 1; }
	@grep -q "V06 GATE1 HDL GENERATION RESULT=PASS" "$(V06_GATE1_REPORT)" || { echo "ERROR: Gate-1 has not PASSed; see $(V06_GATE1_REPORT)"; exit 1; }
	@test -f "$(HDL_TOP_FILE)" || { echo "ERROR: generated HDL top missing: $(HDL_TOP_FILE); run make -C ip/matlab/channelizer_hdl gate1 first"; exit 1; }
	$(VIVADO) -mode batch -nojournal -nolog -source v06_gate2_ooc_synth.tcl
	@test -f "$(V06_GATE2_REPORT)" || { echo "ERROR: V06 Gate-2 report missing: $(V06_GATE2_REPORT)"; exit 1; }
	@grep -q "V06 GATE2 OOC SYNTHESIS RESULT=PASS" "$(V06_GATE2_REPORT)" || { echo "ERROR: V06 Gate-2 did not PASS (see $(V06_GATE2_REPORT))"; exit 1; }

# Stage V06 Gate 2R (completed 2026-11-03; zero resource change): re-synthesize the
# exact Gate-1 systolic RTL with only synth_design changed to
# -directive AreaMapLargeShiftRegToBRAM.  The Gate-2 hierarchical
# report showed 55,952 of 63,439 FilterBank LUTs were SRLs and the
# channelizer used no BRAM.  Isolated v06_gate2r_bram_* outputs keep
# the Gate-2 default-directive evidence intact; no MATLAB rerun,
# implementation, packaging, or block-design change is performed.
gate2r-bram: v06_gate2_ooc_synth.tcl v06_gate2_ooc.xdc
	@test -f "$(V06_GATE1_REPORT)" || { echo "ERROR: Gate-1 report missing; run make -C ip/matlab/channelizer_hdl gate1 first"; exit 1; }
	@grep -q "V06 GATE1 HDL GENERATION RESULT=PASS" "$(V06_GATE1_REPORT)" || { echo "ERROR: Gate-1 has not PASSed; see $(V06_GATE1_REPORT)"; exit 1; }
	@test -f "$(HDL_TOP_FILE)" || { echo "ERROR: generated HDL top missing: $(HDL_TOP_FILE); run make -C ip/matlab/channelizer_hdl gate1 first"; exit 1; }
	V06_GATE2_VARIANT=bram $(VIVADO) -mode batch -nojournal -nolog -source v06_gate2_ooc_synth.tcl
	@test -f "$(V06_GATE2R_BRAM_REPORT)" || { echo "ERROR: V06 Gate-2R BRAM report missing: $(V06_GATE2R_BRAM_REPORT)"; exit 1; }
	@grep -q "V06 GATE2R BRAM OOC SYNTHESIS RESULT=PASS" "$(V06_GATE2R_BRAM_REPORT)" || { echo "ERROR: V06 Gate-2R BRAM did not PASS (see $(V06_GATE2R_BRAM_REPORT))"; exit 1; }

# Stage V06 Gate 2T, step 3 (completed 2026-11-03; material PASS): synthesize
# only the isolated Direct-form-transposed Gate-1 RTL, with the default
# Vivado directive and the same part/XDC as the systolic Gate 2.  The
# summary includes deltas versus the 88,534-LUT / 57,670-SRL systolic
# baseline.  No implementation, packaging, or BD change is performed.
gate2t-transposed: v06_gate2_ooc_synth.tcl v06_gate2_ooc.xdc
	@test -f "$(V06_GATE1_TRANSPOSED_REPORT)" || { echo "ERROR: transposed Gate-1 report missing; run make -C ip/matlab/channelizer_hdl gate1-transposed first"; exit 1; }
	@grep -q "V06 GATE1 HDL GENERATION RESULT=PASS" "$(V06_GATE1_TRANSPOSED_REPORT)" || { echo "ERROR: transposed Gate-1 has not PASSed; see $(V06_GATE1_TRANSPOSED_REPORT)"; exit 1; }
	@test -f "$(HDL_TOP_FILE_TRANSPOSED)" || { echo "ERROR: transposed generated HDL top missing: $(HDL_TOP_FILE_TRANSPOSED); run make -C ip/matlab/channelizer_hdl gate1-transposed first"; exit 1; }
	V06_GATE2_VARIANT=transposed $(VIVADO) -mode batch -nojournal -nolog -source v06_gate2_ooc_synth.tcl
	@test -f "$(V06_GATE2T_TRANSPOSED_REPORT)" || { echo "ERROR: V06 Gate-2T transposed report missing: $(V06_GATE2T_TRANSPOSED_REPORT)"; exit 1; }
	@grep -q "V06 GATE2T TRANSPOSED OOC SYNTHESIS RESULT=PASS" "$(V06_GATE2T_TRANSPOSED_REPORT)" || { echo "ERROR: V06 Gate-2T transposed did not PASS (see $(V06_GATE2T_TRANSPOSED_REPORT))"; exit 1; }

# Stage V06 Gate 3: compare the exact transposed ZU48DRChannelizer
# wrapper against a floating-point dsp.Channelizer using the same
# quantized 16-tone input.  Forty snapshots are collected, startup
# snapshots are discarded, and the report freezes serialized bin
# order, snapshot/column alignment, per-bin phase correction, global
# and per-tone gain/phase, and the signed 26/24 output contract.
# MATLAB only: no HDL generation, packaging, Vivado run, or BD change.
gate3-transposed: v06_gate3_transposed_compare.m ZU48DRChannelizer.m
	@test -f "$(V06_GATE1_TRANSPOSED_REPORT)" || { echo "ERROR: transposed Gate-1 report missing; run make -C ip/matlab/channelizer_hdl gate1-transposed first"; exit 1; }
	@grep -q "V06 GATE1 HDL GENERATION RESULT=PASS" "$(V06_GATE1_TRANSPOSED_REPORT)" || { echo "ERROR: transposed Gate-1 has not PASSed; see $(V06_GATE1_TRANSPOSED_REPORT)"; exit 1; }
	@test -f "$(V06_GATE2T_TRANSPOSED_REPORT)" || { echo "ERROR: Gate-2T report missing; run make -C ip/matlab/channelizer_hdl gate2t-transposed first"; exit 1; }
	@grep -q "V06 GATE2T TRANSPOSED OOC SYNTHESIS RESULT=PASS" "$(V06_GATE2T_TRANSPOSED_REPORT)" || { echo "ERROR: Gate-2T has not PASSed; see $(V06_GATE2T_TRANSPOSED_REPORT)"; exit 1; }
	@grep -q "^RESOURCE_IMPROVEMENT_MATERIAL=1$$" "$(V06_GATE2T_TRANSPOSED_REPORT)" || { echo "ERROR: Gate-2T was not a material resource improvement; see $(V06_GATE2T_TRANSPOSED_REPORT)"; exit 1; }
	@test -f "$(HDL_TOP_FILE_TRANSPOSED)" || { echo "ERROR: transposed generated HDL top missing: $(HDL_TOP_FILE_TRANSPOSED)"; exit 1; }
	V06_FILTER_STRUCTURE=transposed $(MATLAB_RUNNER) "$(MATLAB)" -batch "v06_gate3_transposed_compare"
	@test -f "$(V06_GATE3_TRANSPOSED_REPORT)" || { echo "ERROR: V06 Gate-3 report missing: $(V06_GATE3_TRANSPOSED_REPORT)"; exit 1; }
	@grep -q "^FILTER_STRUCTURE=Direct form transposed$$" "$(V06_GATE3_TRANSPOSED_REPORT)" || { echo "ERROR: Gate-3 did not select Direct form transposed (see $(V06_GATE3_TRANSPOSED_REPORT))"; exit 1; }
	@grep -q "V06 GATE3 TRANSPOSED NUMERICS RESULT=PASS" "$(V06_GATE3_TRANSPOSED_REPORT)" || { echo "ERROR: V06 Gate-3 did not PASS (see $(V06_GATE3_TRANSPOSED_REPORT))"; exit 1; }

model:
	$(MATLAB_RUNNER) "$(MATLAB)" -batch "build_model"
hdl: $(HDL_TOP_FILE)
$(HDL_TOP_FILE): $(MATLAB_SOURCES)
	$(MATLAB_RUNNER) "$(MATLAB)" -batch "generate_hdl"
	@test -f "$@" || { echo "ERROR: expected generated HDL top is missing: $@"; exit 1; }
require-package-allowed:
	@test "$(ALLOW_CHANNELIZER_PACKAGE)" = "1" || { echo "ERROR: MATLAB channelizer packaging is blocked during V06. Run the Gate-1/Gate-2 feasibility targets only; packaging requires the frozen AXI4-Stream wrapper contract and ALLOW_CHANNELIZER_PACKAGE=1."; exit 2; }
package: require-package-allowed $(PACKAGED_COMPONENT)
$(PACKAGED_COMPONENT): $(HDL_TOP_FILE) package_generated_rtl.tcl
	$(VIVADO) -mode batch -nojournal -nolog -source package_generated_rtl.tcl -tclargs hdl_prj/hdlsrc $(TOP) $(PART)
	@test -f "$@" || { echo "ERROR: Vivado did not create packaged IP: $@"; exit 1; }
	@$(ROOT)/common/scripts/check_component_vlnv.sh "$@" "$(IP_VLNV)"
package-only: require-package-allowed
	@test -f "$(HDL_TOP_FILE)" || { echo "ERROR: generated HDL is missing; run make gate1 or make hdl"; exit 1; }
	$(VIVADO) -mode batch -nojournal -nolog -source package_generated_rtl.tcl -tclargs hdl_prj/hdlsrc $(TOP) $(PART)
	@test -f "$(PACKAGED_COMPONENT)" || { echo "ERROR: Vivado did not create packaged IP"; exit 1; }
	@$(ROOT)/common/scripts/check_component_vlnv.sh "$(PACKAGED_COMPONENT)" "$(IP_VLNV)"
clean:
	rm -rf hdl_prj build zu48dr_channelizer_ip.slx .Xil
