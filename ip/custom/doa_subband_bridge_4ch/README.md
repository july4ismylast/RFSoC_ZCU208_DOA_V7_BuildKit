# `doa_subband_bridge_4ch` (`openai:doa:doa_subband_bridge_4ch:1.0`)

Single-clock (`250 MHz` `clkRFdiv2`) deterministic stream bridge between the four single-channel transposed SSR-8 channelizers (`openai:doa:matlab_channelizer:7.0`) and the three `512`-bit four-lane × four-channel AXI4-Stream inputs of `/doa_v7`:

1. **Always-ready 4-channel SSR-8 ingestion (`s_axis_ch0..3`, `416` bits each):**
   - Each beat carries 8 contiguous subbands `{Q_sfix26_En24, I_sfix26_En24}` per channel (`128` beats = `1024` subbands per `0.512 µs` snapshot).
   - `s_axis_ch0..3_tready` stays continuously asserted while out of reset so `rfdc_repack4` and the four channelizers run lockstep without stall.
   - Stage-1 pipeline quantizes `sfix26_En24 -> sfix16_En15` with half-up rounding and symmetric `[-32768, +32767]` saturation (`SCALE_SHIFT = 9` default for unity gain `1.0`).

2. **Search Spectrum Serializer (`m_axis_search`, `512` bits -> `S_AXIS_SEARCH`):**
   - Captures one coherent `128`-beat (`1024`-bin × 4-channel) snapshot in dual `128 × 512` Block RAMs and emits `256` beats in natural bin order `0..1023` (`4` bins × `4` channels per beat, `TLAST` on beat `255`).

3. **Selected-Bin 4-Snapshot Packer (`m_axis_capture` -> `S_AXIS_DOA_CAPTURE`, `m_axis_beam` -> `S_AXIS_BEAM_MONITOR`):**
   - Extracts `active_bin[9:0]` across all four antenna channels once per `128`-beat snapshot and packs four consecutive snapshots into each `512`-bit beat (`word = snapshot_lane*4 + channel`).
   - Locks `active_bin` across each `CAPTURE_BEATS` integration frame (default `1024` beats = `4096` snapshots).
   - Supports hardware closed-loop tracking from `/doa_v7/M_AXIS_CANDIDATE` (`s_axis_candidate`, `192` bits) or manual bin selection via `s_axi_ctrl`.

4. **Legacy MTS Capture Tie-Off / Monitor (`m_axis_mon_ch0..3`, `128` bits each):**
   - Drives valid/quiescent `128`-bit AXI4-Streams to keep `/hier_adc0..2_cap` and `/deepCapture` clean inside `mts.bd`.

## AXI4-Lite Register Map (`s_axi_ctrl`)

| Offset | Name | Access | Default | Description |
|---|---|---|---|---|
| `0x00` | `CTRL` | R/W | `0x0000_000F` | `[0]` `auto_bin_en`, `[1]` `capture_en`, `[2]` `search_en`, `[3]` `beam_en`, `[4]` `mon_en` |
| `0x04` | `MANUAL_BIN` | R/W | `18` | Manual frequency bin `0..1023` (`active_bin` when `auto_bin_en=0` or prior to first candidate) |
| `0x08` | `SCALE_SHIFT` | R/W | `9` | Right shift `0..15` (`9` = unity gain `sfix26_En24 -> sfix16_En15`; smaller shifts apply `2^(9-shift)` digital gain) |
| `0x0C` | `CAPTURE_BEATS` | R/W | `1024` | `512`-bit beats per `m_axis_capture` `TLAST` packet (`1024` = `4096` snapshots) |
| `0x10` | `BEAM_PACKET_BEATS` | R/W | `64` | `512`-bit beats per `m_axis_beam` `TLAST` packet (`64` = `256` beam snapshots = `512` 32-bit words) |
| `0x14` | `STATUS` | RO | — | `[9:0]` `active_bin`, `[16]` `last_cand_valid`, `[17]` `has_auto_bin`, `[26:24]` `srch_state` |
| `0x18` | `LAST_CANDIDATE` | RO | `0` | `[15:0]` `last_cand_bin`, `[16]` `last_cand_valid` |
| `0x1C` | `CAND_PEAK_LO` | RO | `0` | Lower 32 bits of last `candidate_peak4` `peak_power` |
| `0x20` | `CAND_PEAK_HI` | RO | `0` | Upper 32 bits of last `candidate_peak4` `peak_power` |
| `0x24` | `CAND_AVG_LO` | RO | `0` | Lower 32 bits of last `candidate_peak4` `avg_power` |
| `0x28` | `CAND_AVG_HI` | RO | `0` | Upper 32 bits of last `candidate_peak4` `avg_power` |
| `0x2C` | `SNAPSHOT_COUNT` | RO | `0` | Total `128`-beat 4-channel snapshots ingested |
| `0x30` | `SEARCH_FRAME_COUNT` | RO | `0` | Completed `256`-beat `m_axis_search` frames |
| `0x34` | `CAPTURE_FRAME_COUNT` | RO | `0` | Completed `CAPTURE_BEATS` `m_axis_capture` frames |
| `0x38` | `CANDIDATE_COUNT` | RO | `0` | Accepted `s_axis_candidate` packets |
| `0x3C` | `DROP_COUNTS` | RO | `0` | `[31:16]` `capture_drop_count`, `[15:0]` `beam_drop_count` |
