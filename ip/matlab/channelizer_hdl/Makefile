ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
TOP ?= Channelizer_DUT
MATLAB_RUNNER ?= $(ROOT)/scripts/run_matlab_clean.sh
HDL_TOP_FILE := hdl_prj/hdlsrc/zu48dr_channelizer_ip/$(TOP).v
PACKAGED_COMPONENT := $(IP_REPO)/matlab_channelizer/component.xml
IP_VLNV := $(CUSTOM_IP_VENDOR):$(CUSTOM_IP_LIBRARY):matlab_channelizer:$(IPVER_CHANNELIZER)
MATLAB_SOURCES := build_model.m generate_hdl.m ZU48DRChannelizer.m
V06_PROBE_REPORT := $(ROOT)/build/output/v06_channelizer_probe.rpt
V06_GATE1_REPORT := $(ROOT)/build/output/v06_gate1_hdl_generation.rpt
ALLOW_CHANNELIZER_PACKAGE ?= 0

.PHONY: all model hdl package package-only require-package-allowed probe gate1 clean
all: package
# Stage V06 Gate 0 (passed on the user PC, 2026-11-03): the installed
# dsphdl.Channelizer accepts the production-size SSR-8/1024-band
# fixed-point configuration with Normalize=false.  The probe remains
# available as a regression check and does not generate HDL.
probe: v06_probe_ssr8_1024.m
	$(MATLAB_RUNNER) "$(MATLAB)" -batch "v06_probe_ssr8_1024"
	@test -f "$(V06_PROBE_REPORT)" || { echo "ERROR: V06 probe report missing: $(V06_PROBE_REPORT)"; exit 1; }
	@grep -q "V06 CHANNELIZER PROBE RESULT=PASS" "$(V06_PROBE_REPORT)" || { echo "ERROR: V06 probe did not PASS (see $(V06_PROBE_REPORT))"; exit 1; }

# Stage V06 Gate 1: parameterize the legacy harness to config.mk's
# 1024-band/SSR-8 values, generate one channel of Verilog, and catalog
# the generated top/ports/reports.  This deliberately does not invoke
# Vivado packaging or create a production IP component.
gate1: $(MATLAB_SOURCES) v06_gate1_generate_hdl.m v06_probe_ssr8_1024.m
	$(MATLAB_RUNNER) "$(MATLAB)" -batch "v06_gate1_generate_hdl"
	@test -f "$(V06_GATE1_REPORT)" || { echo "ERROR: V06 Gate-1 report missing: $(V06_GATE1_REPORT)"; exit 1; }
	@grep -q "V06 GATE1 HDL GENERATION RESULT=PASS" "$(V06_GATE1_REPORT)" || { echo "ERROR: V06 Gate-1 did not PASS (see $(V06_GATE1_REPORT))"; exit 1; }

model:
	$(MATLAB_RUNNER) "$(MATLAB)" -batch "build_model"
hdl: $(HDL_TOP_FILE)
$(HDL_TOP_FILE): $(MATLAB_SOURCES)
	$(MATLAB_RUNNER) "$(MATLAB)" -batch "generate_hdl"
	@test -f "$@" || { echo "ERROR: expected generated HDL top is missing: $@"; exit 1; }
require-package-allowed:
	@test "$(ALLOW_CHANNELIZER_PACKAGE)" = "1" || { echo "ERROR: MATLAB channelizer packaging is blocked during V06. Run the Gate-1 generation target only; packaging requires the frozen AXI4-Stream wrapper contract and ALLOW_CHANNELIZER_PACKAGE=1."; exit 2; }
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
