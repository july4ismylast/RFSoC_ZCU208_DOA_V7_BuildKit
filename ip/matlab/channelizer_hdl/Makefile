ROOT := $(abspath ../../..)
include $(ROOT)/config.mk
TOP ?= Channelizer_DUT
MATLAB_RUNNER ?= $(ROOT)/scripts/run_matlab_clean.sh
HDL_TOP_FILE := hdl_prj/hdlsrc/zu48dr_channelizer_ip/$(TOP).v
PACKAGED_COMPONENT := $(IP_REPO)/matlab_channelizer/component.xml
MATLAB_SOURCES := build_model.m generate_hdl.m ZU48DRChannelizer.m

.PHONY: all model hdl package package-only clean
all: package
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
package-only:
	@test -f "$(HDL_TOP_FILE)" || { echo "ERROR: generated HDL is missing; run make hdl"; exit 1; }
	$(VIVADO) -mode batch -nojournal -nolog -source package_generated_rtl.tcl -tclargs hdl_prj/hdlsrc $(TOP) $(PART)
	@test -f "$(PACKAGED_COMPONENT)" || { echo "ERROR: Vivado did not create packaged IP"; exit 1; }
clean:
	rm -rf hdl_prj build zu48dr_channelizer_ip.slx .Xil
