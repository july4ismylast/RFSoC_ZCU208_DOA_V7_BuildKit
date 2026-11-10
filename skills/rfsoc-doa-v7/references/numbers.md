# Measured numbers — each row names its proof

Format: `claim | value | path::token,token,…`. `scripts/check_skill.py` reads this table and
fails if a file or a token is missing, so a number cannot drift away from its evidence. Tokens are
literal strings from the source, not restatements. Three forms exist:

| token form | meaning |
|---|---|
| `206179` | the literal string must appear in the file (whitespace-collapsed match) |
| `re:CLB LUTs[^0-9]{1,40}206179` | a regular expression must match, un-collapsed — use it where a bare number is not unique in a big report |
| `gate:NOT RUN=6` | exactly six gate-table rows in that file may contain `NOT RUN` — use it for counts |

Add a row only after the number is in a committed file. A number with no token is a rumour.

## Build result (2026-11-08/09 run)

| claim | value | proof |
|---|---|---|
| production stages that pass | 20/20 | `docs/WHERE_WE_ARE.md`::`20/20 PASS` |
| CLB LUTs | 206 179 / 425 280 = 48.48 % | `docs/evidence/2026-11-09-matlab_hdl/post_route_utilization.rpt`::`re:CLB LUTs[^0-9]{1,40}206179`,`425280`,`48.48` |
| CLB registers | 313 132 = 36.81 % | `docs/evidence/2026-11-09-matlab_hdl/post_route_utilization.rpt`::`re:CLB Registers[^0-9]{1,40}313132`,`36.81` |
| Block RAM tiles (tightest) | 773.5 / 1 080 = 71.62 % | `docs/evidence/2026-11-09-matlab_hdl/post_route_utilization.rpt`::`re:Block RAM Tile[^0-9]{1,40}773\.5`,`1080`,`71.62` |
| DSPs | 1 543 / 4 272 = 36.12 % | `docs/evidence/2026-11-09-matlab_hdl/post_route_utilization.rpt`::`re:DSPs[^0-9]{1,40}1543`,`4272`,`36.12` |
| URAM | 20 of 80 | `docs/evidence/2026-11-09-matlab_hdl/post_route_utilization.rpt`::`re:URAM[^0-9]{1,40}20` |
| post-route WNS | +0.164 ns | `docs/evidence/2026-11-09-matlab_hdl/post_route_timing.rpt`::`re:Worst Slack\s+0\.164ns` |
| release tarball | 24.9 MB + sha256 | `docs/WHERE_WE_ARE.md`::`24.9 MB` |

## Algorithm benches

| claim | value | proof |
|---|---|---|
| unambiguous band edge | 5.996 GHz (25 mm) / 4.997 GHz (30 mm) | `step0_antenna/GUIDE.md`::`5.996`,`4.997` |
| angle accuracy of one baseline | 0.302° at 0 dB, 0.030° at 20 dB | `step0_antenna/GUIDE.md`::`0.302`,`0.030` |
| 8-bit SQNR | 66.08 dB measured vs 66.06 dB theory | `step1_rfadc_mts/GUIDE.md`::`66.08`,`66.06` |
| inter-channel skew budget | 0.73 ps (1 ps costs 0.693°) | `step1_rfadc_mts/GUIDE.md`::`0.73 ps`,`0.693` |
| Q3.13 phase LSB | 7.67e−4 rad = 0.021° | `step2_pl_ip/GUIDE.md`::`7.67e`,`0.021` |
| WPI seed error | 0.320° at 20 dB | `step3_r5_doa/GUIDE.md`::`0.320` |
| Bartlett grid | 36 evaluations, 0.5 → 0.005° | `step3_r5_doa/GUIDE.md`::`36 evaluations` |
| AMC label agreement with model | 100.0 % (120 bursts) | `step4_r5_amc/GUIDE.md`::`100.0` |
| AMC accuracy against truth | 72.5 % (model scores the same) | `step4_r5_amc/GUIDE.md`::`72.5` |
| AMC constant table | 60 constants, sha256 62bc0ee7287bfe1f | `step4_r5_amc/GUIDE.md`::`62bc0ee7287bfe1f` |
| decoy discrimination | 40.0 ns delay, correlation 0.36 | `step5_r5_tracking/GUIDE.md`::`40.0 ns`,`0.36` |
| tracking ladder, rung order | full 2 tracks vs direction-only 1 | `step5_r5_tracking/GUIDE.md`::`direction-only` |
| supervisor binary | 37 kB | `step6_ps_linux/GUIDE.md`::`37 kB` |
| channelizer equivalence | bit-exact, 16 384 samples, error 6.103e-05 | `docs/WHERE_WE_ARE.md`::`16384`,`6.103e-05` |

## Configuration facts

| claim | value | proof |
|---|---|---|
| part | xczu48dr-fsvg1517-2-e | `config/ip_versions.tcl`::`xczu48dr-fsvg1517-2-e` |
| board part | xilinx.com:zcu208:part0:2.0 | `config/ip_versions.tcl`::`xilinx.com:zcu208:part0:2.0` |
| Vivado / Vitis HLS lock | 2023.2 | `config/ip_versions.tcl`::`2023.2` |
| custom IP vendor / library | openai / doa | `config.mk`::`CUSTOM_IP_VENDOR`,`CUSTOM_IP_LIBRARY` |
| channelizer VLNV version | 7.0 | `config/ip_versions.tcl`::`matlab_channelizer`,`IPVER_CHANNELIZER` |
| DOA-side HLS clock constraint | 7.8125 ns | `config.mk`::`PL_CLOCK_PERIOD_NS ?= 7.8125` |
| wideband clock constraint | 4.0 ns | `config.mk`::`WIDEBAND_CLOCK_PERIOD_NS ?= 4.0` |
| DOA fabric clock | 125 MHz | `config.mk`::`DOA_CLOCK_HZ ?= 125000000` |
| wideband fabric clock | 250 MHz | `config.mk`::`WIDEBAND_FABRIC_CLOCK_HZ ?= 250000000` |
| RFDC PL clock | 500 MHz | `config.mk`::`RFDC_PL_CLOCK_HZ ?= 500000000` |
| ADC / complex rate | 4 GSPS / 2 GSPS, decimate 2 | `config.mk`::`ADC_SAMPLE_RATE_HZ ?= 4000000000`,`COMPLEX_SAMPLE_RATE_HZ ?= 2000000000`,`RFDC_DECIMATION ?= 2` |
| RF band / centre / IBW | 2–4 GHz / 3.0 GHz / 1.5 GHz | `config.mk`::`TARGET_RF_LOW_HZ ?= 2000000000`,`RF_CENTER_HZ ?= 3000000000`,`RF_INSTANT_BW_HZ ?= 1500000000` |
| channelizer shape | 1024 bands, 12 taps, 100 dB stopband, no FFT normalisation | `config.mk`::`CHANNELIZER_NUM_BANDS ?= 1024`,`CHANNELIZER_TAPS_PER_BAND ?= 12`,`CHANNELIZER_STOPBAND_DB ?= 100`,`CHANNELIZER_NORMALIZE ?= 0` |
| channelizer coefficients | 12 288 | `docs/BLOCK_GUIDE.md`::`12 288` |
| bin spacing | 1.953125 MHz | `config.mk`::`CHANNELIZER_BIN_SPACING_HZ ?= 1953125` |
| samples per clock | 8 | `config.mk`::`WIDEBAND_SAMPLES_PER_CLOCK ?= 8` |
| array spacing / cone | 30 mm / ±55° | `config.mk`::`ARRAY_AXIS_SPACING_M ?= 0.030`,`ARRAY_CONE_HALF_ANGLE_DEG ?= 55` |
| frame length | 4096 samples | `config.mk`::`PHASE_INTERF_FRAME_SAMPLES ?= 4096` |
| open gates | exactly six (G3, G5, G6, G7b, G8b, G8c) | `docs/GATES_G1_G7.md`::`gate:NOT RUN=6` |

## RTL facts

| claim | value | proof |
|---|---|---|
| bridge input width | 416 bit (8 × 26 × 2) | `ip/custom/doa_subband_bridge_4ch/rtl/doa_subband_bridge_4ch.v`::`416 bits` |
| search frame | 1024 bins = 256 beats | `ip/custom/doa_subband_bridge_4ch/rtl/doa_subband_bridge_4ch.v`::`256 beats/frame` |
| capture / beam defaults | 1024 and 64 beats | `ip/custom/doa_subband_bridge_4ch/rtl/doa_subband_bridge_4ch.v`::`16'd1024`,`16'd64` |
| quantizer default shift | 9 | `ip/custom/doa_subband_bridge_4ch/rtl/doa_subband_bridge_4ch.v`::`4'd9` |
| register file | 16 × 32-bit, drops last | `ip/custom/doa_subband_bridge_4ch/rtl/doa_subband_bridge_4ch.v`::`6'h0F` |
| phase baselines | six, fixed pairs | `ip/custom/phase_interf_4ch/src/phase_interf_core.hpp`::`kFirst`,`kSecond` |
| CORDIC table | 32 entries, 16 iterations | `ip/custom/phase_interf_4ch/src/phase_interf_core.hpp`::`kAtanQ30` |
| free-running kernels | four with ap_ctrl_none | `ip/custom/beam_weight_4ch/src/beam_weight_4ch.cpp`::`ap_ctrl_none` |
| covariance accumulation order | X_b · conj(X_a) | `docs/evidence/2026-11-06-phase-interf/REVIEW.md`::`X_b·conj(X_a)` |

## What is NOT measured (never quote a number for these)

- anything on the board: RF, calibration, MTS lock, captures, temperature, power;
- gate G3 (out-of-context synthesis of the packaged phase IP) — the script exists, it has never run;
- cycles per AMC frame on the R5F (G8c);
- any resource number for a modified design;
- the Model Composer route to the channelizer IP (it dead-ends; `docs/GUI_MODEL_COMPOSER_IP.md`).
