# ZCU208 / XCZU48DR target. Keep all path overrides absolute.
PART ?= xczu48dr-fsvg1517-2-e
BOARD_PART ?= xilinx.com:zcu208:part0:2.0
PROJECT_NAME ?= doa_v7_zcu208

VIVADO ?= vivado
VITIS_HLS ?= vitis_hls
MATLAB ?= matlab
# Two MATLABs are normal on a machine that also has Model Composer.  The
# command-line one (MATLAB, default 'matlab') runs the codegen, the HIL vectors
# and the preflight; Model Composer 2023.2 needs the release it shipped with
# (R2022b) and its own launcher.  Set both absolutely in config.local.mk or on
# the command line; only `step05_channelizer CHANNELIZER_FLOW=model_composer`
# reads them.
#
#   make step05_channelizer CHANNELIZER_FLOW=model_composer \
#        MODEL_COMPOSER=/path/Model_Composer/2023.2/bin/model_composer \
#        MODEL_COMPOSER_MODEL=/abs/path/channelizer.slx
# This workstation (the ZCU208 host), as measured by `make tools` on 2026-11-07:
# MATLAB R2024a is the `matlab` on PATH; R2022b is installed next to Model
# Composer and has no symlink, so it is named by its absolute path.  Model
# Composer 2023.2 only runs with R2022b.  Override either in config.local.mk
# (plain `=` there) or on the command line.
MATLAB_2022B   ?= /media/joshua/Linux/Programs/R2022b/bin/matlab
MODEL_COMPOSER ?= /media/joshua/Linux/Programs/X20232/Model_Composer/2023.2/bin/model_composer
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
# 1 turns the missing MTS base project (stage V03) from a preflight failure into a
# warning, so steps 02-06 can be built before that base exists.
PREFLIGHT_ALLOW_MISSING_BASE ?= 0

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
IPVER_RFDC_REPACK4 ?= 1.0
IPVER_CHANNELIZER ?= 7.0
IPVER_SUBBAND_BRIDGE ?= 1.0
IPVER_PHASE_INTERF ?= 1.0

# --- OPFB Plan-B IP lock -------------------------------------------------------
# Exact custom-IP VLNVs used by the pinned RFSoC_OPFB bd/opfb_streaming.tcl
# (RFSoC_OPFB 8ab3d5b6136490ebdf3b24953889decdfc3f40ae).  The three HLS blocks
# are rebuilt for the ZU48DR part, but keep these upstream identities so the
# catalog checks and any later OPFB BD adaptation never have to guess a repo
# name or "latest" packaged folder.  These are evaluation/Plan-B identities;
# they are not production DOA IPs in config/ip_versions.tcl.
OPFB_VLNV_ADC_TO_OPFB ?= mazinlab:mkidgen3:adc_to_opfb:1.32
OPFB_VLNV_OPFB_FIR_CFG ?= mazinlab:mkidgen3:opfb_fir_cfg:1.31
OPFB_VLNV_FIR_TO_FFT ?= mazinlab:mkidgen3:fir_to_fft:1.31
OPFB_VLNV_SSRFFT ?= MazinLab:mkidgen3:ssrfft_16x4096_axis:1.0
OPFB_VLNV_PKG_FFT_OUTPUT ?= mazinlab:mkidgen3:pkg_fft_output:1.31
OPFB_VLNV_CAPTURE_UPSIZER ?= mazinlab:mkidgen3:capture_upsizer:0.5
OPFB_VLNV_FILTER_IQ ?= mazinlab:mkidgen3:filter_iq:0.3
OPFB_VLNV_FILTER_PHASE ?= mazinlab:mkidgen3:filter_phase:0.5
OPFB_VLNV_PAIR_IQ ?= mazinlab:mkidgen3:pair_iq:0.4
OPFB_VLNV_BIN_TO_RES ?= mazinlab:mkidgen3:bin_to_res:1.33

# --- DOA / RF conditions (user-confirmed) -------------------------------------
# Target RF band 2-4 GHz, fed by 4 ADC channels (2x2 array), with a 1.5 GHz
# realtime instantaneous bandwidth (user, 2026-11-02).  Stage V04 locks the
# plan (V04_RFDC_DOA_CONTRACT.md): MTS 4.000 GSPS clock kept, band sampled in
# Nyquist Zone 2 around RF_CENTER_HZ, RFDC hardened DDC decimates 2x to a
# 2.0 GS/s complex stream per channel (SSR-8 at 250 MHz), channelised into
# CHANNELIZER_NUM_BANDS bins.  Keep these variables, PL_CLOCK and the MATLAB
# reference Fs in sync -- never change one independently of the contract.
TARGET_RF_LOW_HZ ?= 2000000000
TARGET_RF_HIGH_HZ ?= 4000000000
ADC_CHANNEL_COUNT ?= 4
RF_CENTER_HZ ?= 3000000000
RF_INSTANT_BW_HZ ?= 1500000000
ADC_SAMPLE_RATE_HZ ?= 4000000000
RFDC_DECIMATION ?= 2
# CONFIG.PL_Clock_Freq (MHz) = RFDC_PL_CLOCK_HZ / 1e6.  The copied MTS BD
# carries the live default 100.0; scratch v1.3 proved that explicitly
# setting 500.000 (common multiple of ADC 250 / DAC 500 AXIS) plus a late
# MTS restore is required for ADC MTS to persist at decimation 2.
RFDC_PL_CLOCK_HZ ?= 500000000
COMPLEX_SAMPLE_RATE_HZ ?= 2000000000
WIDEBAND_FABRIC_CLOCK_HZ ?= 250000000
WIDEBAND_CLOCK_PERIOD_NS ?= 4.0
WIDEBAND_SAMPLES_PER_CLOCK ?= 8
CHANNELIZER_NUM_BANDS ?= 1024
CHANNELIZER_TAPS_PER_BAND ?= 12
CHANNELIZER_STOPBAND_DB ?= 100
# MATLAB dsphdl candidate only: Gate-0 probe v2 proved that Normalize=false
# (0) preserves the tone far above the fixed-point LSB; Normalize=true (1)
# underflowed at 1024 bands in attempt 1.  OPFB does not use this variable.
CHANNELIZER_NORMALIZE ?= 0
# MATLAB dsphdl candidate only: the transposed structure passed V06
# Gates 0T/1T/2T/3T and is selected as the Plan-A production architecture.
# This selects the filter structure only; the AXI4-Stream wrapper and
# production packaging/integration remain incomplete and guarded.
CHANNELIZER_FILTER_STRUCTURE ?= transposed
CHANNELIZER_BIN_SPACING_HZ ?= 1953125
DOA_CLOCK_HZ ?= 125000000
# V07 phase-interferometry contract (V07_PHASE_INTERFEROMETRY.md).  The DOA
# angles are estimated from per-bin cross-spectra, not from a frame covariance
# alone.  Array geometry is set by the wrap-free rule for a SQUARE 2x2 in a cone
# of half-angle ARRAY_CONE_HALF_ANGLE_DEG at the top of the band:
#     d * sqrt(2) * sin(theta) <= lambda_min / 2
#     => d <= c / (2*sqrt(2)*f_high*sin(theta)) = 32.3 mm at 4.0 GHz, 55 deg.
# 30 mm is the widest round spacing inside that rule (62 deg of cone at 4 GHz);
# the review's 50 mm needs 32 deg and is rejected, and 25 mm is kept as the
# fallback for a +/-90 deg field.  Measured in
# docs/evidence/2026-11-06-phase-interf/wideband_df_check.txt (V07 section 11).
ARRAY_AXIS_SPACING_M ?= 0.030
ARRAY_CONE_HALF_ANGLE_DEG ?= 55
PHASE_INTERF_FRAME_SAMPLES ?= 4096

# matlab_hdl, model_composer, opfb, or external. MATLAB HDL transposed is
# the selected Plan-A core, but step05 packaging remains guarded until its
# AXI4-Stream wrapper is complete. OPFB is retained as explicit Plan B.
CHANNELIZER_FLOW ?= matlab_hdl
MODEL_COMPOSER_MODEL ?=
EXTERNAL_CHANNELIZER_IP ?=

FETCH_SET ?= native
FETCH_RETRIES ?= 3
FETCH_TIMEOUT_SECONDS ?= 60

# Mandatory for steps 07 onward: a known-good ZCU208 RFDC/MTS base project.
# For the locked production base (BASE_KIND=mts) no manual setting is needed:
# stage V03 produces exactly this file -- scripts/prepare_mts_2023p2_patch.sh
# copies the pinned RFSoC-MTS tree to build/mts_base_src_2023p2/ (recorded
# adaptations: PS VLNV 3.4 -> 3.5, impl strategy Performance_ExtraTimingOpt),
# and running boards/ZCU208/build_mts/mts.tcl there
# creates project "mts" (mts/mts.xpr, BD name "mts").  Override BASE_XPR /
# BASE_BD only when deliberately using a different verified ZCU208 base.
ifeq ($(BASE_KIND),mts)
BASE_XPR ?= $(BUILD)/mts_base_src_2023p2/boards/ZCU208/build_mts/mts/mts.xpr
BASE_BD ?= mts
else
BASE_XPR ?=
BASE_BD ?=
endif
ZCU208_BD_MAP ?= $(CURDIR)/config/zcu208_bd_map.tcl
INTEGRATION_MODE ?= mapped
WORK_XPR ?= $(BUILD)/vivado/$(PROJECT_NAME)/$(PROJECT_NAME).xpr

PL_CLOCK_PERIOD_NS ?= 7.8125
FRAME_SAMPLES ?= 4096
ADC_STREAM_BITS ?= 512

V7_MATLAB_ROOT ?= $(CURDIR)/matlab_v7
HIL_OUTPUT_DIR ?= $(BUILD)/hil_vectors

# Per-machine overrides: tool paths, licences, the base project.  Not tracked
# (see .gitignore), so every machine keeps its own.  Example:
#   MATLAB_2022B   ?= /opt/MATLAB/R2022b/bin/matlab
#   MODEL_COMPOSER ?= /opt/Model_Composer/2023.2/bin/model_composer
#   BASE_XPR       ?= /data/vivado/mts/mts.xpr
-include $(CURDIR)/config.local.mk

export PART BOARD_PART PROJECT_NAME VIVADO VITIS_HLS MATLAB JOBS
export BUILD UPSTREAM IP_REPO RELEASE_DIR EXPECTED_VIVADO_VERSION EXPECTED_MATLAB_RELEASE
export SKIP_IP_CATALOG_CHECK PREFLIGHT_ALLOW_MISSING_BASE BASE_KIND CUSTOM_IP_VENDOR CUSTOM_IP_LIBRARY
export IPVER_COVARIANCE IPVER_SPECTRUM IPVER_CANDIDATE IPVER_BEAM IPVER_CHANNELIZER
export IPVER_RFDC_REPACK4 IPVER_SUBBAND_BRIDGE IPVER_PHASE_INTERF
export OPFB_VLNV_ADC_TO_OPFB OPFB_VLNV_OPFB_FIR_CFG OPFB_VLNV_FIR_TO_FFT
export OPFB_VLNV_SSRFFT OPFB_VLNV_PKG_FFT_OUTPUT OPFB_VLNV_CAPTURE_UPSIZER
export OPFB_VLNV_FILTER_IQ OPFB_VLNV_FILTER_PHASE OPFB_VLNV_PAIR_IQ
export OPFB_VLNV_BIN_TO_RES
export TARGET_RF_LOW_HZ TARGET_RF_HIGH_HZ ADC_CHANNEL_COUNT
export RF_CENTER_HZ RF_INSTANT_BW_HZ ADC_SAMPLE_RATE_HZ RFDC_DECIMATION
export RFDC_PL_CLOCK_HZ COMPLEX_SAMPLE_RATE_HZ WIDEBAND_FABRIC_CLOCK_HZ WIDEBAND_CLOCK_PERIOD_NS
export WIDEBAND_SAMPLES_PER_CLOCK CHANNELIZER_NUM_BANDS
export CHANNELIZER_TAPS_PER_BAND CHANNELIZER_STOPBAND_DB CHANNELIZER_NORMALIZE
export CHANNELIZER_FILTER_STRUCTURE CHANNELIZER_BIN_SPACING_HZ DOA_CLOCK_HZ
export ARRAY_AXIS_SPACING_M ARRAY_CONE_HALF_ANGLE_DEG PHASE_INTERF_FRAME_SAMPLES
export CHANNELIZER_FLOW MODEL_COMPOSER_MODEL EXTERNAL_CHANNELIZER_IP
export MODEL_COMPOSER MATLAB_2022B
export FETCH_SET FETCH_RETRIES FETCH_TIMEOUT_SECONDS
export BASE_XPR BASE_BD ZCU208_BD_MAP INTEGRATION_MODE WORK_XPR PL_CLOCK_PERIOD_NS FRAME_SAMPLES ADC_STREAM_BITS
export V7_MATLAB_ROOT HIL_OUTPUT_DIR
