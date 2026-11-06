# File-by-file and code guide

This index describes authored files and the retained reference adapters. Build
products under `build/` are intentionally excluded.

## Top level

| File | Purpose |
|---|---|
| `Makefile` | User interface for independent, logged, restartable numbered stages. |
| `config.mk` | All board, tool, path, channelizer, frame, and project overrides. |
| `README.md` | Outcome, safe start, architecture decisions, and document links. |
| `BUILD_STAGES.md` | Every target, checkpoint, and failure-recovery command. |
| `ZCU208_IMPLEMENTATION_GUIDE.md` | Overall block diagram, algorithms, packing, examples, and acceptance. |
| `RESEARCH_REFERENCES.md` | Vendor/GitHub primary sources and adoption decisions. |
| `SOURCE_MATRIX.md` | Original comparison of native and architectural references. |

## Build scripts

### `scripts/run_stage.sh`

The parser consumes `--id`, `--stamp`, `--log`, then the command following
`--`. It creates only the stamp/log parent folders, deletes an old stamp before
execution, timestamps the start, and records a shell-escaped command. It
temporarily disables `set -e` around a `tee` pipeline so it can read the real
command status from `PIPESTATUS[0]`. Failure writes a log but no stamp. Success
writes a four-field stamp (`stage`, start, finish, result).

### Other scripts

| File | Ordered behavior |
|---|---|
| `preflight.sh` | Finds tools → checks part/base → reads Vivado version → checks expected version → prints summary → fails on hard errors. |
| `fetch_upstream.sh` | Reads TSV → filters set/name → retries bounded clone/fetch → detached checkout → recursive submodules → prints exact commit. |
| `build_channelizer.sh` | Validates one of four choices → dispatches only that flow. |
| `collect_ip.sh` | Builds required directory list → verifies each `component.xml` → writes TSV manifest. |
| `generate_hil.sh` | Validates V7 path → exports two paths → invokes one MATLAB wrapper. |
| `stage_status.sh` | Reads each stamp/log without modifying the build. |
| `clean_stage.sh` | Whitelists each accepted stage and deletes only its known outputs. |
| `clean_build.sh` | Rejects `/` and home paths before deleting configured build products. |
| `package_release.sh` | Selects existing artifacts → creates tar.gz → writes SHA-256. |

## Configuration

| File | Purpose |
|---|---|
| `config/upstream_repositories.tsv` | Repository name, group, URL, and branch/commit in one auditable manifest. |
| `config/zcu208_bd_map.tcl` | The only base-project-specific RFDC/AXI/clock/DMA wiring layer. |

## Vitis HLS custom IP

Every custom directory has the same pattern: C++ header/source, independent
testbench, `build_hls.tcl`, local Makefile, and block README.

| Directory | Input → output | Function |
|---|---|---|
| `ip/custom/doa_covariance_4ch_v4` | AXI512 samples → 16 AXI64 words | Q2.14 correction plus four powers and six complex cross-products. |
| `ip/custom/spectrum_power4` | AXI512 samples → AXI256 powers | Four-channel incoherent power for four lanes. |
| `ip/custom/candidate_peak4` | AXI256 powers → AXI192 record | Frame peak, average, bin, and programmable validity gate. |
| `GATES_RUNBOOK.md` | Operator sheet for gates G2–G6: exact commands, artefacts to read, pass criteria, and the log-publishing flow (`make push-gate-logs`). |
| `scripts/compare_wpi_vs_music.py` | V07 §10: interferometry vs wideband 2D MUSIC/ISSM, the manifold-rank result for the 4-element 2×2, and calibration/geometry sensitivity. |
| `scripts/compare_wideband_estimators.py` | V07 §11: the wrap-free spacing rule for a square 2×2 over 2–4 GHz (`d·√2·sin θ ≤ λ/2`), five estimators on the same per-bin cross-spectra, measured diagonal aliasing, position-error sensitivity, and the unwrap-fit frame losses. `make wideband-df`. |
| `ip/custom/phase_interf_4ch` | AXI512 beats → AXI64 accumulators + AXI128 phases | V07 per-bin cross-spectrum (six baselines), integer CORDIC `atan2`, frame tag. `make host-check` runs the production core on g++ without Xilinx headers, `make host-kernel-check` compiles the kernel and its Vitis testbench against `tb/host_shim/`, and `gate3_ooc.tcl` is the (unrun) OOC timing gate at 4.0 ns. |
| `ip/custom/beam_weight_4ch` | AXI512 samples → AXI256 beam | Optional four-lane complex weighted sum. |

For each block, `build_hls.tcl` follows the same lines: read target part/period
from the environment, reset one HLS project, add source and testbench, select
top, reset one solution, set part/clock, configure IP Catalog metadata, run C
simulation, synthesize, export, and exit. The local Makefile then verifies
`component.xml` before copying the whole package into `build/ip_repo`.

Detailed line-by-line algorithm explanations are in sections 5, 6, 8, and 12
of `ZCU208_IMPLEMENTATION_GUIDE.md`; the self-checking testbench next to each
source supplies an executable numerical example.

## MATLAB HDL and Model Composer

| File | Function |
|---|---|
| `ip/matlab/channelizer_hdl/ZU48DRChannelizer.m` | MATLAB System object around `dsphdl.Channelizer`. |
| `ip/matlab/channelizer_hdl/build_model.m` | Creates complex fixed-point four-element vector I/O and a MATLAB System block. |
| `ip/matlab/channelizer_hdl/generate_hdl.m` | Selects Verilog, Vivado, XCZU48DR, and invokes HDL Coder. |
| `ip/matlab/channelizer_hdl/package_generated_rtl.tcl` | Finds generated RTL, sets top, packages IP, and writes it into the common repository. |
| `ip/model_composer/channelizer/export_model_composer_ip.m` | Updates a supplied model, finds its System Generator token, exports, and copies the newest complete IP. |
| `ip/model_composer/channelizer/Makefile` | Requires an explicit model path before MATLAB is launched. |

## Vivado Tcl

| File | Function |
|---|---|
| `common/vivado/common.tcl` | Required-environment, project-open, BD-select, output-directory, and successful-run helpers. |
| `07_create_project_from_base.tcl` | Copies the verified base project and installs IP paths. |
| `create_doa_v7_hier.tcl` | Creates separate search/capture/beam streams and instantiates four custom IPs. |
| `08_integrate_doa_v7.tcl` | Opens project → selects BD → creates hierarchy → invokes board map → addresses → validates → saves. |
| `09_validate.tcl` | Validates and exports IP/message/BD reports. |
| `10_synth.tcl` | Regenerates BD targets, runs `synth_1`, and writes utilization/timing. |
| `11_impl.tcl` | Runs route, reports results, and enforces nonnegative WNS. |
| `12_bitstream.tcl` | Opens the routed design and writes `.bit` plus available `.hwh`. |
| `13_export_xsa.tcl` | Exports a fixed hardware platform including bitstream. |

`create_doa_v7_hier.tcl` intentionally has three independent sample inputs.
Within the hierarchy, search connects spectrum power to candidate peak; capture
connects directly to covariance; beam has its own monitor stream. AXI-Lite
control interfaces remain visible for the board map to attach through a PS
SmartConnect.

## HIL and MATLAB V7 reference

| Path | Function |
|---|---|
| `hil/matlab/generate_zcu208_hil_vectors.m` | Board-named wrapper that calls the embedded V7 generator and adds device/stream metadata. |
| `hil/matlab/generate_zcu48dr_hil_vectors.m` | Produces packed AXI512 beats, calibration registers, and golden covariance. |
| `hil/matlab/hil_fixed_covariance_reference.m` | Bit-accurate integer covariance oracle. |
| `hil/matlab/run_zcu48dr_hil.m` | Prepare/loopback/compare harness with exact covariance and ≤0.1° angle checks. |
| `matlab_v7/` | Complete latest V7 simulation, estimator, realism model, tests, HIL, guides, and its original RFSoC overlay. |

The V7 file `estimate_doa_from_covariance_v7.m` is the processor-side golden
algorithm: decoupling and Hermitian repair, optional forward/backward averaging,
six-baseline WPI, four 3×3 ML neighborhoods, four power iterations, and bounded
GN refinement. `DOAEstimator4Ch.m` additionally contains the navigation-frame
unit-vector EKF used in the moving simulation.

## Reference adapters

- `projects/rfsoc_mts_zcu208`, `rfsoc_pynq_base_zcu208`, and
  `rfsoc_sam_zcu208` point to native ZCU208 references.
- `projects/rfsoc_opfb_reference`, `leo_rfsoc4x2_reference`, and `spear*` are
  architecture references only.
- `ip/upstream_opfb/*` are independent adapters for pinned OPFB sub-IP. They
  must be rebuilt and interface-checked; their presence is not proof of ZCU208
  compatibility.

## Diagram assets

| File | Use |
|---|---|
| `docs/diagrams/zcu208-overall.jpg` | Top-level project partition embedded in the guides. |
| `docs/diagrams/zcu208-overall.svg` | Editable source for the exact diagram. |
| `docs/diagrams/v7-calibration-covariance.jpg` | V7 calibration/covariance detail. |
| `docs/diagrams/v7-hil-flow.jpg` | V7 HIL sequence. |
| `docs/build-stages.mmd` | Mermaid source printed by `make graph`. |

