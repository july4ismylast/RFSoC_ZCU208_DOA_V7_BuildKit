# Stage V05 — `rfdc_repack4` gearbox specification

**Input contract:** V04 (`V04_RFDC_DOA_CONTRACT.md`) — 4 physical ADCs,
4.000 GSPS, RFDC fine-mixer Real→I/Q, decimation 2×, 2.0 GS/s complex per
channel as SSR‑8 @ 250 MHz. **Output contract:** the V06 channelizer input.
VLNV: `openai:doa:rfdc_repack4:1.0` (variables `IPVER_RFDC_REPACK4` in
`config.mk` + `config/ip_versions.tcl`).

## 1. Why this block exists, and why it is custom HLS

In R2C mode each physical ADC produces **two** AXI4-Streams (even = I,
odd = Q, PG269 4 GSPS R2C figure; proven in the pinned SAM/PYNQ ZCU208 BDs
where `m00→s_axis_re`, `m01→s_axis_im`). The DOA chain's internal
convention — MATLAB reference, covariance/spectrum/candidate HLS — is
packed 32-bit complex words `{Q[31:16], I[15:0]}`. Something must perform
the sample-wise I/Q interleave, identically for all four channels, without
ever dropping or reordering a beat.

Upstream options compared (Rule: compare all, then adapt the best):

| Candidate | Behaviour | Verdict |
|---|---|---|
| AMD `axis_combiner:1.1` (LEO pattern) | Concatenates whole beats → `{Q-vector, I-vector}` 256-bit, does **not** interleave samples | ❌ pushes an awkward un-interleave into every consumer |
| Direct separate RE/IM into the channelizer (SAM/PYNQ pattern) | Zero extra logic, but the channelizer must natively accept split I/Q | ⚠️ viable only if the V06 winner's interface is split-I/Q; our proven HLS chain is packed-complex |
| RF Analyzer "I & Q Merge" (UG1287) | Same function, closed example-design block | ❌ not a reusable pinned IP |
| **Custom HLS `rfdc_repack4` (this stage)** | Sample-wise interleave, project packing, bit-exact TB, II=1 @4.0 ns | ✅ chosen — one small, auditable contract block; a V06 shim can split I/Q again if the winning channelizer needs it |

## 2. Interface

Clock: single 250 MHz domain (`clkRFdiv2` in the MTS tree; HLS constraint
`WIDEBAND_CLOCK_PERIOD_NS=4.0`). Reset: the domain's `proc_sys_reset`
peripheral reset in V07 (HLS `ap_ctrl_none`, no AXI-Lite, no state to
configure — deliberate: a coherence path must not depend on PS writes).

| Port | Width | Source/destination |
|---|---:|---|
| `s_axis_ch0_i/q` | 128 | RFDC `m00_axis` (I) / `m01_axis` (Q) |
| `s_axis_ch1_i/q` | 128 | RFDC `m02_axis` / `m03_axis` |
| `s_axis_ch2_i/q` | 128 | RFDC `m10_axis` / `m11_axis` |
| `s_axis_ch3_i/q` | 128 | RFDC `m12_axis` / `m13_axis` |
| `m_axis_ch0..3` | 256 | V06 channelizer instance 0..3 |

No TKEEP/TSTRB/TLAST anywhere (the RFDC does not produce them; framing is
created by the channelizer/capture path, not here).

Packing, per channel, per beat (`s` = 0..7, 0 = earliest sample):
input lane `s` = bits `[16s+15:16s]` of the I (resp. Q) beat;
output word `s` = bits `[32s+31:32s]` = `{Q_s, I_s}`.
The sample-order-within-beat assumption (LSB lane = earliest) follows the
PG269 AXI4-Stream timing figures and is re-proven by the V12 ramp/tone
HIL test; if hardware showed the opposite order, the fix is a lane
reversal inside this one block plus a version bump — nowhere else.

## 3. Alignment semantics (the part that protects DOA coherence)

* The gearbox joins beats **by ordinal**: output beat *n* of channel *c*
  is built from input beat *n* of `ch_c_i` and `ch_c_q`. It never drops,
  duplicates or reorders beats, and applies the same latency to all
  channels (registered interfaces, `register_mode=both`).
* Absolute sample alignment *between* channels/tiles is **not** created
  here — it is established upstream by MTS/SYSREF and the RFDC FIFO
  startup sequence (software's job). The integration rules that follow:
  all eight inputs must see the same reset release; V07 may insert
  same-clock `axis_data_fifo` skid buffers per stream if place-and-route
  or startup skew demands it, but their depths must be identical and they
  must be empty when MTS alignment is (re)established.
* Back-pressure: the search path is continuous 2.0 GS/s; downstream
  (channelizer) must be always-ready at SSR‑8. If a downstream stall ever
  asserts, AXI4-Stream ready propagates to the RFDC, whose internal FIFO
  is shallow — overflow is a system error to be made visible in V07 debug
  (RFDC FIFO flags/ILA), never silently absorbed here.

## 4. What V05 deliberately does not include

* **No bin-select/capture gate yet.** Selecting the candidate bin and
  packing 4 snapshots into the covariance 512-bit beat depends on the V06
  channelizer's bin order/valid cadence; it is specified in V06 against
  the winning implementation (contract target already fixed in V04 §4).
* No clock crossing (250→125 MHz happens on the selected-bin stream,
  after channelization, where the rate is ~2 MHz — not on 8×128-bit
  raw streams).
* No calibration/phase correction (stays in the covariance IP's existing
  per-channel complex calibration inputs).

## 5. Acceptance gates

- [ ] `make step05_hls_repack` on Vitis HLS 2023.2: C-sim PASS
      (`PASS: rfdc_repack4 SSR-8 I/Q packing, 5 beats x 4 channels x 8 lanes`).
- [ ] Csynth report: II=1, clock estimate meets 4.0 ns on
      `xczu48dr-fsvg1517-2-e`, utilisation recorded here after the run.
- [ ] Exported `component.xml` VLNV exactly
      `openai:doa:rfdc_repack4:1.0` (enforced by the IP Makefile and
      step06 `collect_ip`).
- [ ] (V12) Hardware ramp/tone capture proves lane order I/Q assignment
      and cross-channel beat alignment end-to-end.
