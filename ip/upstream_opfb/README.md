# MazinLab OPFB adapters (Plan-B only)

These adapters prepare the custom IP definitions used by the pinned
RFSoC_OPFB design for inspection under the project's Vivado **2023.2** lock.
They do **not** integrate the OPFB into the MTS/DOA production block design;
that interface/rate adaptation remains stage V06 work.

The selection below is taken from the `CHECK IPs` list and
`create_bd_cell -vlnv` calls in the pinned RFSoC_OPFB
`bd/opfb_streaming.tcl` (`RFSoC_OPFB` at
`8ab3d5b6136490ebdf3b24953889decdfc3f40ae`; every repository commit is pinned
in `config/upstream_repositories.tsv`).  The VLNV variables themselves live in
`config.mk`, the packaged `component.xml` paths are explicit in each adapter,
and `scripts/collect_ip.sh` verifies the same list at step06.  No adapter may
guess an IP from a GitHub repository name, a substring, or the first
`component.xml` found.

| Adapter | Result in `build/ip_repo/` | Pinned VLNV |
|---|---|---|
| `adc_to_opfb` (HLS rebuild for ZU48DR) | `adc_to_opfb` | `mazinlab:mkidgen3:adc_to_opfb:1.32` |
| `opfb_fir_cfg` (HLS rebuild for ZU48DR) | `opfb_fir_cfg` | `mazinlab:mkidgen3:opfb_fir_cfg:1.31` |
| `fir_to_fft` (HLS rebuild for ZU48DR) | `fir_to_fft` | `mazinlab:mkidgen3:fir_to_fft:1.31` |
| `ssrfft_packaged` | `ssrfft_16x4096_axis` | `MazinLab:mkidgen3:ssrfft_16x4096_axis:1.0` |
| `pkg_fft_output_packaged` | `pkg_fft_output` | `mazinlab:mkidgen3:pkg_fft_output:1.31` |
| `capture_upsizer` | `capture_upsizer` | `mazinlab:mkidgen3:capture_upsizer:0.5` |
| `iq_capture` | `filter_iq` | `mazinlab:mkidgen3:filter_iq:0.3` |
| `iq_capture` | `filter_phase` | `mazinlab:mkidgen3:filter_phase:0.5` |
| `iq_capture` | `pair_iq` | `mazinlab:mkidgen3:pair_iq:0.4` |
| `opfb_bin_to_res` | `bin_to_res` | `mazinlab:mkidgen3:bin_to_res:1.33` |

Repository names are not IP names.  In particular:

- GitHub `capture-upsizer` packages IP **`capture_upsizer`**.
- GitHub `opfb-bin-to-res` packages IP **`bin_to_res`**.
- GitHub `iq-capture` packages **three** IPs (`filter_iq`, `filter_phase`,
  and `pair_iq`); there is no IP named `iq-capture`.

Two fetched repositories are intentionally **not** in the default step05 set:

- `dac_replay`: not instantiated by `bd/opfb_streaming.tcl`.  Its adapter is
  standalone inspection only and explicitly selects
  `mazinlab:mkidgen3:dac_table_axim:1.33` from several packaged candidates.
- `wb2axip`: RFSoC_OPFB adds `rtl/sfifo.v`, `rtl/axis2mm.v`, and
  `rtl/skidbuffer.v` directly in `vivado/write_prj.tcl` and instantiates
  `axis2mm` as a module reference.  It has no `component.xml` or VLNV to
  collect, so its adapter only checks those RTL files.

Run the complete Plan-B IP preparation with:

```bash
make rebuild STEP=step05_channelizer CHANNELIZER_FLOW=opfb
make rebuild STEP=step06_collect_ip CHANNELIZER_FLOW=opfb
```

**User-PC flow selection (recorded 2026-11-03):** OPFB is the flow used
for step05/step06 IP collection. The repository-wide
`CHANNELIZER_FLOW` default in `config.mk` remains `matlab_hdl` until
stage V06 selects a production implementation, so always pass
`CHANNELIZER_FLOW=opfb` explicitly for these two steps on the user PC;
a bare/default `step06_collect_ip` would instead look for
`matlab_channelizer`.

The parent Makefile fetches the pinned OPFB repositories once, then passes
`OPFB_FETCH_DONE=1` to the child adapters.  The many `BD 41-1306` messages in
the throwaway catalog projects come from the inspection helper exposing both
an interface and its individual pins; they are not production BD connections.
