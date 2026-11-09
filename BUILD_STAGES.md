# Restartable build stages

```mermaid
flowchart TD
  A["00 Preflight"] --> B["02–05 Build selected IP"]
  B --> C["06 Collect IP"]
  C --> D["07 Copy verified ZCU208 base"]
  D --> E["08 Integrate + 09 validate"]
  E --> F["10 Synthesis"]
  F --> G["11 Route + timing gate"]
  G --> H["12 Bitstream + 13 XSA"]
  H --> I["14 HIL vectors + 15 package"]
```

`make` defaults to `make help`. Every numbered target owns one result stamp in
`build/.stamps` and one complete console log in `build/logs`. A stamp is written
only after the command exits successfully. The individual targets deliberately
do not depend on all earlier targets: running `make step10_synth` runs synthesis
only and reports a clear error if its project prerequisite is absent.

Cleaning steps 08–13 preserves the copied Vivado project and removes only that
stage's checkpoint/reports/output. The integration Tcl replaces its generated
`/doa_v7` hierarchy on rerun. Only cleaning step07 deliberately removes the
isolated project copy.

## Command patterns

| Need | Command |
|---|---|
| Show stages | `make help` or `make list` |
| Inspect checkpoints | `make status` |
| Run one stage | `make step03_hls_spectrum` |
| Preview without writes | `make -n step03_hls_spectrum` |
| Force rerun | `make rebuild STEP=step03_hls_spectrum` |
| Remove one stage product | `make clean-stage STEP=step03_hls_spectrum` |
| Resume the production sequence | `make pipeline` |
| Remove generated build products | `make clean-build` |

## Stage reference

### `step00_preflight`

Checks `make`, Git, Python 3, Vitis HLS, Vivado, MATLAB, the XCZU48DR part
and pinned ZCU208 board part, base-project path, and selected channelizer.
The Vivado/Vitis version lock is hard: `EXPECTED_VIVADO_VERSION` defaults to
**2023.2** in `config.mk`, both tools must match it, and the stage finishes
by running `common/vivado/00_check_ip_catalog.tcl`, which proves every AMD
catalog VLNV in `config/ip_versions.tcl` against the installed Vivado and
writes `build/output/ip_catalog_lock.txt` (`SKIP_IP_CATALOG_CHECK=1` is for
tool-presence smoke tests only).

### `step01_fetch_references`

Fetches only the selected set from `config/upstream_repositories.tsv`. Every
ref there is a **pinned full commit SHA** (branch names float and would
invalidate the VLNV audit). Clones are resumable, retries are bounded, and
each checked-out commit is printed. The production base is fetched with
`FETCH_SET=RFSoC-MTS`; see `V03_MTS_BASE_2023P2.md`.

```bash
make step01_fetch_references FETCH_SET=native
make rebuild STEP=step01_fetch_references FETCH_SET=opfb
make step01_fetch_references FETCH_SET=RFSoC-MTS
```

### `step02_hls_covariance`

Runs the exact-match C test, HLS synthesis, and IP Catalog export for the V7
covariance core. The result is `build/ip_repo/doa_covariance_4ch_v4`.

### `step03_hls_spectrum`

Builds the updated AXI512-to-AXI256 four-lane power statistic. Its test verifies
every lane and `TLAST`.

### `step04_hls_candidate`

Builds the free-running four-lane frame peak/average detector. It emits one
candidate record per `TLAST`-delimited spectrum frame and exposes a Q8.8
peak-to-average threshold. Full CFAR/persistence remains a later detector gate.

### `step04_hls_beam`

Builds an optional four-lane complex-weight diagnostic. This block is not in
the DOA estimator and may be omitted from a resource-constrained deployment
after integration Tcl is adjusted.

### `step05_hls_repack`

Builds the stage-V05 RFDC gearbox (`V05_RFDC_REPACK4_SPEC.md`): pairs the
eight 128-bit RFDC I/Q streams into four 256-bit SSR-8 complex streams at
250 MHz. The C test is bit-exact over beats × channels × lanes; csynth uses
`WIDEBAND_CLOCK_PERIOD_NS` (4.0 ns), not the low-rate DOA clock.

### `step05_channelizer`

Select exactly one implementation:

| Flow | Selection | Use |
|---|---|---|
| MATLAB HDL Coder | `CHANNELIZER_FLOW=matlab_hdl` | Default R2024a fixed-point vector harness |
| Model Composer/System Generator | `CHANNELIZER_FLOW=model_composer MODEL_COMPOSER_MODEL=...` | Existing tested model with IP Catalog token |
| MazinLab OPFB | `CHANNELIZER_FLOW=opfb` | Plan-B only: fetches the pinned set once and builds/imports exactly the ten MazinLab IP definitions used by RFSoC_OPFB `bd/opfb_streaming.tcl` (see `ip/upstream_opfb/README.md`); DOA rate/interface adaptation is still stage V06 |
| External IP | `CHANNELIZER_FLOW=external EXTERNAL_CHANNELIZER_IP=...` | Previously packaged compatible channelizer |

**Stage V06 status:** Transposed Gates 0T, 1T, 2T, 3, 4, 4B, and 4C
(`v06_gate4_axis_wrapper_rtl_sim.rpt`, exact 416-bit payload match across
all 128 output beats) have passed. `step05_channelizer` packages
`channelizer_axis_wrapper.sv` + the 228 transposed RTL files as
`openai:doa:matlab_channelizer:7.0` into `build/ip_repo/matlab_channelizer`,
verifies `component.xml`, and smoke-tests BD instantiation + VHDL target
generation. When `hdl_prj/hdlsrc_transposed/zu48dr_channelizer_ip/Channelizer_DUT.v`
is already present on disk, `step05_channelizer` packages it directly without
forcing a redundant MATLAB regeneration (`make -C ip/matlab/channelizer_hdl hdl-regen`
forces regeneration when desired).

### `step05_subband_bridge`

Runs the Python golden reference check, XSim self-checking RTL testbench,
250 MHz (`4.000 ns`) out-of-context synthesis timing gate, Vivado IP Packager
export (`openai:doa:doa_subband_bridge_4ch:1.0`), and an in-memory VHDL BD
smoke test exercising `doa_subband_bridge_4ch`, `axis_clock_converter:1.1`,
`axis_dwidth_converter:1.1`, `axi_fifo_mm_s:4.3`, `xpm_cdc_gen:1.0`,
`clk_wiz:6.0`, `proc_sys_reset:5.0`, and `assign_bd_address`.

### `hls-all` (every custom HLS model at once)

`make hls-all` runs `make -C ip/custom/<ip> all` for all seven blocks
(`doa_covariance_4ch_v4`, `spectrum_power4`, `candidate_peak4`,
`beam_weight_4ch`, `rfdc_repack4`, `doa_subband_bridge_4ch`,
`phase_interf_4ch`) — exactly what `step02…step05` run, without the Vivado
stages. `make hls-clean` resets them.

### `step05_hls_phase_interf`

Builds the V07 per-bin phase-interferometry block
(`openai:doa:phase_interf_4ch:1.0`, see
[V07_PHASE_INTERFEROMETRY.md](V07_PHASE_INTERFEROMETRY.md)): C simulation,
synthesis at the pinned clock, and catalogue export into `build/ip_repo`.
The tool-independent half of the verification does not need Vitis:

```bash
make -C ip/custom/phase_interf_4ch host-check        # g++, bit-exact core test
make -C ip/custom/phase_interf_4ch host-kernel-check # kernel + C-sim TB via host shim
make -C ip/custom/phase_interf_4ch gate3-ooc         # Vivado 2023.2, OOC timing at 4.0 ns
make rebuild STEP=step05_hls_phase_interf      # needs Vitis HLS 2023.2
make -C ip/custom/phase_interf_4ch collect-reports  # csynth reports -> build/output/v07_gate2_*
make push-gate-logs                            # commit+push the gate evidence (see GATES_RUNBOOK.md)
```

Accumulator layout is deliberately identical to `doa_covariance_4ch_v4`, so the
PS writes one calibration table and one frame length to both blocks.

### `step06_collect_ip`

Validates every required `component.xml` and writes `ip_manifest.tsv`. Under
`CHANNELIZER_FLOW=matlab_hdl` it requires all eight custom IPs:
`doa_covariance_4ch_v4:7.1`, `spectrum_power4:2.0`, `candidate_peak4:1.0`,
`beam_weight_4ch:2.1`, `rfdc_repack4:1.0`, `matlab_channelizer:7.0`,
`doa_subband_bridge_4ch:1.0`, and `phase_interf_4ch:1.0`.

### `step07_vivado_project`

Opens `BASE_XPR`, verifies the part and board part, creates an isolated copy
under `build/vivado`, and appends the common IP repository. The source base
project is not modified. For the locked base (`BASE_KIND=mts`, default),
`BASE_XPR`/`BASE_BD` default to the stage-V03 output
(`build/mts_base_src_2023p2/boards/ZCU208/build_mts/mts/mts.xpr`, BD `mts`);
if that file does not exist yet, run stage V03 first — see
`V03_MTS_BASE_2023P2.md` (fetch `RFSoC-MTS`, run
`scripts/prepare_mts_2023p2_patch.sh`, then build the unmodified MTS project).

### `step08_vivado_integrate`

Creates `/doa_v7` and invokes `config/zcu208_bd_map.tcl` (`INTEGRATION_MODE=mapped`
by default): exports `vin1_23`, applies V04 staged 4-ch Zone-2 R2C 2× DDC + MTS
restore on `/usp_rf_data_converter_1`, moves ADC AXIS clocks/resets and
`user_sysref_adc` to 250 MHz (`clkRFdiv2`), derives a 125 MHz `/doa_v7` clock
and synchronous reset, connects `rfdc_repack4` -> 4× `matlab_channelizer` ->
`doa_subband_bridge_4ch` -> async CDCs -> `/doa_v7` -> PS AXI-Stream RX FIFOs
(`doa_cov_fifo` & `doa_beam_fifo`), attaches all 6 DOA AXI4-Lite slaves to
`/control_interconnect`, assigns addresses, validates the BD, and writes
`build/output/v07_bd_integration.rpt` + `build/output/doa_address_map.txt`.

### `step09_vivado_validate`

Runs `validate_bd_design`, writes an IP-status report, exports the integrated BD
Tcl, and captures critical warnings/errors. This is the fastest stage for
debugging interface widths and missing clocks.

### `step10_synth`

Regenerates BD output products, resets only `synth_1`, runs synthesis, and
writes post-synthesis utilization and timing reports.

### `step11_impl`

Resets only `impl_1`, runs through route, writes route/utilization/timing
reports, and fails the stage if the worst setup slack is negative.

### `step12_bitstream` and `step13_export_xsa`

These consume the routed design. They do not rerun HLS, MATLAB, synthesis, or
route. Outputs are written under `build/output`.

### `step14_hil_vectors`

Uses the V7 MATLAB model to generate AXI512 stimulus, calibration registers,
and the exact 16-word covariance result. Set `V7_MATLAB_ROOT` to the latest V7
directory.

### `step15_package`

Archives output products, reports, manifests, logs, and HIL vectors and writes
a SHA-256 checksum. It does not hide missing earlier artifacts.

## Failure recovery examples

If spectrum HLS fails, edit only `ip/custom/spectrum_power4`, then run:

```bash
make rebuild STEP=step03_hls_spectrum
```

If block-design validation fails, edit only `config/zcu208_bd_map.tcl`, then:

```bash
make rebuild STEP=step08_vivado_integrate
make rebuild STEP=step09_vivado_validate
```

If timing fails, inspect `build/output/post_route_timing.rpt`, modify the PL
architecture or constraints, and rerun `step10_synth` only when RTL changed;
otherwise rerun `step11_impl`.
