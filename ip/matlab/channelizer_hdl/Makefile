ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
TOP ?= Channelizer_DUT
MATLAB_RUNNER ?= $(ROOT)/scripts/run_matlab_clean.sh
HDL_TOP_FILE := hdl_prj/hdlsrc/zu48dr_channelizer_ip/$(TOP).v
PACKAGED_COMPONENT := $(IP_REPO)/matlab_channelizer/component.xml
IP_VLNV := $(CUSTOM_IP_VENDOR):$(CUSTOM_IP_LIBRARY):matlab_channelizer:$(IPVER_CHANNELIZER)
MATLAB_SOURCES := build_model.m generate_hdl.m ZU48DRChannelizer.m
V06_PROBE_REPORT := $(ROOT)/build/output/v06_channelizer_probe.rpt

.PHONY: all model hdl package package-only probe clean
all: package
# Stage V06 gate 0 only: prove the installed dsphdl.Channelizer accepts the
# production-size SSR-8/1024-band fixed-point configuration in MATLAB.
# This intentionally does not generate HDL; the legacy model below is still
# the 64-band/four-lane harness and is not the V06 production channelizer.
probe: v06_probe_ssr8_1024.m
	$(MATLAB_RUNNER) "$(MATLAB)" -batch "v06_probe_ssr8_1024"
	@test -f "$(V06_PROBE_REPORT)" || { echo "ERROR: V06 probe report missing: $(V06_PROBE_REPORT)"; exit 1; }
	@grep -q "V06 CHANNELIZER PROBE RESULT=PASS" "$(V06_PROBE_REPORT)" || { echo "ERROR: V06 probe did not PASS (see $(V06_PROBE_REPORT))"; exit 1; }
model:
	$(MATLAB_RUNNER) "$(MATLAB)" -batch "build_model"
hdl: $(HDL_TOP_FILE)
$(HDL_TOP_FILE): $(MATLAB_SOURCES)
	$(MATLAB_RUNNER) "$(MATLAB)" -batch "generate_hdl"
	@test -f "$@" || { echo "ERROR: expected generated HDL top is missing: $@"; exit 1; }
package: $(PACKAGED_COMPONENT)
$(PACKAGED_COMPONENT): $(HDL_TOP_FILE) package_generated_rtl.tcl
	$(VIVADO) -mode batch -nojournal -nolog -source package_generated_rtl.tcl -tclargs hdl_prj/hdlsrc $(TOP) $(PART)
	@test -f "$@" || { echo "ERROR: Vivado did not create packaged IP: $@"; exit 1; }
	@$(ROOT)/common/scripts/check_component_vlnv.sh "$@" "$(IP_VLNV)"
package-only:
	@test -f "$(HDL_TOP_FILE)" || { echo "ERROR: generated HDL is missing; run make hdl"; exit 1; }
	$(VIVADO) -mode batch -nojournal -nolog -source package_generated_rtl.tcl -tclargs hdl_prj/hdlsrc $(TOP) $(PART)
	@test -f "$(PACKAGED_COMPONENT)" || { echo "ERROR: Vivado did not create packaged IP"; exit 1; }
	@$(ROOT)/common/scripts/check_component_vlnv.sh "$(PACKAGED_COMPONENT)" "$(IP_VLNV)"
clean:
	rm -rf hdl_prj build zu48dr_channelizer_ip.slx .Xil
