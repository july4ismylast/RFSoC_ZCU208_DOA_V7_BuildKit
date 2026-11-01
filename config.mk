# ZCU208 / XCZU48DR target. Keep all path overrides absolute.
PART ?= xczu48dr-fsvg1517-2-e
BOARD_PART ?= xilinx.com:zcu208:part0:2.0
PROJECT_NAME ?= doa_v7_zcu208

VIVADO ?= vivado
VITIS_HLS ?= vitis_hls
MATLAB ?= matlab
JOBS ?= 8

BUILD ?= $(CURDIR)/build
UPSTREAM ?= $(CURDIR)/upstream
IP_REPO ?= $(BUILD)/ip_repo
RELEASE_DIR ?= $(BUILD)/release

# --- V00 version lock (2026-11-01, user-confirmed) -----------------------------
# Vivado/Vitis 2023.2 only.  Every IP VLNV lives in config/ip_versions.tcl and
# is certified only for this release; step00 proves the table against the
# installed catalog.  Empty is no longer allowed (preflight fails).
EXPECTED_VIVADO_VERSION ?= 2023.2
EXPECTED_MATLAB_RELEASE ?= R2024a
# Set to 1 only for a tool-presence smoke test on a machine without Vivado;
# a production step00 must run the catalog proof.
SKIP_IP_CATALOG_CHECK ?= 0

# Base design: Xilinx RFSoC-MTS (boards/ZCU208, standard MTS), pinned in
# config/upstream_repositories.tsv.  It was generated with Vivado 2022.1.2
# (zynq_ultra_ps_e:3.4); using it under the 2023.2 lock (ps:3.5) requires the
# controlled IP-upgrade stage V03 before any DOA integration.
BASE_KIND ?= mts

# Custom-IP identity.  HLS build_hls.tcl files read these from the environment;
# config/ip_versions.tcl builds the matching VLNVs for the block design, and
# scripts/collect_ip.sh verifies them against each component.xml at step06.
# Bump the matching IPVER_* whenever an IP's interface or control scheme changes.
CUSTOM_IP_VENDOR ?= openai
CUSTOM_IP_LIBRARY ?= doa
IPVER_COVARIANCE ?= 7.1
IPVER_SPECTRUM ?= 2.0
IPVER_CANDIDATE ?= 1.0
IPVER_BEAM ?= 2.1
IPVER_CHANNELIZER ?= 7.0

# --- DOA / RF conditions (user-confirmed) -------------------------------------
# Target RF band 2-4 GHz, fed by 4 ADC channels (2x2 array).  The RFDC
# sample-rate / decimation / Nyquist-zone plan that realises this band on the
# MTS base is decided and proven in stage V04; do not change PL_CLOCK or the
# MATLAB Fs independently of that decision (see VIVADO_AUDIT_AND_STAGE_PLAN).
TARGET_RF_LOW_HZ ?= 2000000000
TARGET_RF_HIGH_HZ ?= 4000000000
ADC_CHANNEL_COUNT ?= 4

# matlab_hdl, model_composer, opfb, or external.
CHANNELIZER_FLOW ?= matlab_hdl
MODEL_COMPOSER_MODEL ?=
EXTERNAL_CHANNELIZER_IP ?=

FETCH_SET ?= native
FETCH_RETRIES ?= 3
FETCH_TIMEOUT_SECONDS ?= 60

# Mandatory for steps 07 onward. Use a known-good ZCU208 RFDC/MTS project.
BASE_XPR ?=
BASE_BD ?=
ZCU208_BD_MAP ?= $(CURDIR)/config/zcu208_bd_map.tcl
INTEGRATION_MODE ?= mapped
WORK_XPR ?= $(BUILD)/vivado/$(PROJECT_NAME)/$(PROJECT_NAME).xpr

PL_CLOCK_PERIOD_NS ?= 7.8125
FRAME_SAMPLES ?= 4096
ADC_STREAM_BITS ?= 512

V7_MATLAB_ROOT ?= $(CURDIR)/matlab_v7
HIL_OUTPUT_DIR ?= $(BUILD)/hil_vectors

export PART BOARD_PART PROJECT_NAME VIVADO VITIS_HLS MATLAB JOBS
export BUILD UPSTREAM IP_REPO RELEASE_DIR EXPECTED_VIVADO_VERSION EXPECTED_MATLAB_RELEASE
export SKIP_IP_CATALOG_CHECK BASE_KIND CUSTOM_IP_VENDOR CUSTOM_IP_LIBRARY
export IPVER_COVARIANCE IPVER_SPECTRUM IPVER_CANDIDATE IPVER_BEAM IPVER_CHANNELIZER
export TARGET_RF_LOW_HZ TARGET_RF_HIGH_HZ ADC_CHANNEL_COUNT
export CHANNELIZER_FLOW MODEL_COMPOSER_MODEL EXTERNAL_CHANNELIZER_IP
export FETCH_SET FETCH_RETRIES FETCH_TIMEOUT_SECONDS
export BASE_XPR BASE_BD ZCU208_BD_MAP INTEGRATION_MODE WORK_XPR PL_CLOCK_PERIOD_NS FRAME_SAMPLES ADC_STREAM_BITS
export V7_MATLAB_ROOT HIL_OUTPUT_DIR
