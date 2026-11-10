# Architecture

Everything here is taken from `config.mk`, `config/zcu208_bd_map.tcl`, `config/ip_versions.tcl`, the
IP headers under `ip/custom/*/src/`, and `docs/BLOCK_GUIDE.md` Part 2. When the user's checkout
disagrees, the checkout wins.

## 1. The four layers

```
   RF 2-4 GHz, 4 channels
            │
   ┌────────▼─────────┐  usp_rf_data_converter:2.6
   │ RF Data Converter│  4 GSPS, decimate 2, NCO -3.000 GHz, 8-bit, 8 samples/clk
   └────────┬─────────┘  500 MHz PL clock  → 8 x 128-bit lanes at 250 MHz
            │
   ┌────────▼───────────────────────────────────────────────┐  wideband fabric, 250 MHz
   │ rfdc_repack4  →  4 x 256-bit per-channel lanes         │
   │ matlab_channelizer x4 (one per ADC channel)            │  1024 bands, 12 taps
   │ doa_subband_bridge_4ch                                 │  4 x 416-bit in → 5 stream outs
   └────────┬───────────────────────────────────────────────┘
            │ axis_clock_converter 250 → 125 MHz
   ┌────────▼───────────────────────────────────────────────┐  DOA fabric, 125 MHz
   │ spectrum_power4 · candidate_peak4 · covariance · beam   │  + phase_interf_4ch (V07)
   │ FIFOs the PS reads (axi_fifo_mm_s)                     │
   └────────┬───────────────────────────────────────────────┘
            │ AXI4-Lite control + stream FIFOs
   ┌────────▼───────────────────────────────────────────────┐
   │ R5F: DOA estimate, AMC, tracking ladder                 │
   │ A53/Linux: supervisor, policy, logging, host link       │
   └─────────────────────────────────────────────────────────┘
```

## 2. The two clock domains — the most common mistake

| domain | frequency | period | what lives there | where it is set |
|---|---|---|---|---|
| wideband / ADC fabric | 250 MHz | 4.000 ns | RFDC interface, `rfdc_repack4`, the four channelizers, `doa_subband_bridge_4ch` | `WIDEBAND_FABRIC_CLOCK_HZ` = 250000000, `WIDEBAND_CLOCK_PERIOD_NS` = 4.0 |
| DOA fabric | 125 MHz | 8.000 ns | spectrum, candidate, covariance, beam, phase interferometer, the stream FIFOs | `DOA_CLOCK_HZ` = 125000000 |
| RFDC PL clock | 500 MHz | 2.000 ns | inside the RFDC only (`PL_Clock_Freq` 500.000) | RFDC configuration, stage 08 |

The HLS constraint for the four DOA-side kernels is **7.8125 ns** (`PL_CLOCK_PERIOD_NS`), i.e. 128 MHz
against a 125 MHz clock — a small margin, not a different clock. `rfdc_repack4` and
`phase_interf_4ch` are constrained at **4.0 ns**. Saying "the DOA clock is 128 MHz" is the classic
error: the clock is 125 MHz; 7.8125 ns is the constraint written into `build_hls.tcl`.

The 250 → 125 MHz crossing is not hand-rolled: the block design instantiates `axis_clock_converter`
for search, capture and beam, and a second one for the candidate feedback stream, each with its own
FIFO depth in `config/zcu208_bd_map.tcl`.

## 3. Data widths, block by block

These are the `ap_axiu<>` widths from the IP headers. They are the contract; a width change is a
block-design change.

| block | in | out | header |
|---|---|---|---|
| `rfdc_repack4` | 4 × 128-bit (RFDC lanes) | 4 × 256-bit (one per channel) | `ip/custom/rfdc_repack4/src/rfdc_repack4.hpp` — `ap_uint<128>`, `ap_uint<256>` |
| `matlab_channelizer` | 256-bit, 8 samples | 416-bit = 8 samples × 26 bit × 2 (I/Q) | HDL Coder output, `sfix16_En15` → `sfix26_En24` |
| `doa_subband_bridge_4ch` | 4 × 416-bit streams + 192-bit candidate feedback | 512-bit search, 512-bit capture, 512-bit beam, 4 × 128-bit monitor | `ip/custom/doa_subband_bridge_4ch/rtl/doa_subband_bridge_4ch.v` |
| `spectrum_power4` | 512-bit | 256-bit | `spectrum_power4.hpp` — `ap_axiu<512,0,0,0>` / `<256,…>` |
| `candidate_peak4` | 256-bit | 192-bit | `candidate_peak4.hpp` |
| `doa_covariance_4ch_v4` | 512-bit | 64-bit | `doa_covariance_4ch_v4.hpp` |
| `beam_weight_4ch` | 512-bit | 256-bit | `beam_weight_4ch.hpp` |
| `phase_interf_4ch` (V07) | 512-bit | 128-bit (6 × Q3.13 phase + tag) and 64-bit accumulator words | `phase_interf_4ch.hpp` |

Samples are packed `{Q[31:16], I[15:0]}` per 32-bit word; the channelizer output is 26-bit
`sfix26_En24` per sample, eight samples per beat.

## 4. The 23 blocks a user may ask about

`rfdc`, `rfdc_repack4`, `matlab_channelizer`, `subband_bridge`, `cdc_forward`, `cdc_candidate`,
`spectrum_power`, `candidate_peak`, `covariance`, `beam_monitor`, `phase_interf`, `clocking`,
`fifo_cov`, `fifo_beam`, `control_ic`, `rpu`, `rpu_doa`, `rpu_amc`, `rpu_tracking`, `apu`, `host`,
`mts_base`, `ip_flow`.

One internal picture per block, with ports, stages and notes, is in `docs/diagrams/blocks/` and
explained in `docs/BLOCK_GUIDE.md` Part 5. If the user asks "what is inside X", that is the file to
quote.

## 5. The control side

- One `axi_interconnect` with **13 master interfaces**; `M07…M12` are the DOA-side slaves
  (`config/zcu208_bd_map.tcl`, section 8):
  `S_AXI_COV_CTRL`, `S_AXI_CANDIDATE_CTRL`, `S_AXI_BEAM_CTRL`, `/doa_cov_fifo/S_AXI`,
  `/doa_beam_fifo/S_AXI` — all on the 125 MHz domain — and `/doa_subband_bridge_0/s_axi_ctrl` on the
  250 MHz domain.
- The bridge's register file is 32-bit, byte-addressed, `0x00`…`0x3C`:
  `0x00 CTRL` … `0x3C DROP_COUNTS`. Source of truth: `package_ip.tcl` comments and the bridge RTL.
- `proc_sys_reset` per domain supplies the active-low resets (`rst_doa_125m_n`, `rst_rf_250m_n`).
- Deliberately **not** attached: the spectrum/candidate stream paths (no DMA), and anything on the
  A53 that would need Linux drivers. The PS reads the covariance and beam FIFOs; the rest is
  captured through the `hier_adc*_cap` / `deepCapture` hierarchies.

## 6. Who runs what

| processor | code | role | built by |
|---|---|---|---|
| R5F (`psu_cortexr5_0`) | `step3_r5_doa/c/doa_core.c`, `firmware/amc_r5/amc.c` | DOA estimation, AMC, tracking ladder | Vitis application project (not yet created — see `references/build-and-gates.md` G8b) |
| A53 (`psu_cortexa53_0`, Linux) | `step6_ps_linux/c/supervisor.cpp` | supervisor, policy, logging, host link | `make -C step6_ps_linux/c` (host) and `make -C step6_ps_linux/c cross` (aarch64, static) |
| host PC | `step0_antenna/py`, … `step7_board_bringup` | the eight benches, the studies, the release | `make steps` |

The split exists because the R5F has deterministic timing and no OS, while the supervisor needs
files and sockets. Do not describe the A53 as running the estimator: it does not.

## 7. What "the base project" means

The bitstream is built by copying a **verified ZCU208 RFSoC-MTS base project** (`BASE_KIND=mts`,
`BASE_XPR=build/mts_base_src_2023p2/boards/ZCU208/build_mts/mts/mts.xpr`) and adding a `/doa_v7`
hierarchy to its existing `/mts` block design in stage 08. The base supplies the RFDC, the clocking,
the DDR and the PS; this project adds the signal chain. Replacing the base invalidates every
downstream number, which is why `step00` and `BASE_XPR` are checked before anything else runs.
