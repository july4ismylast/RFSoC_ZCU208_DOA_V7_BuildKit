# Where this build stands

One page, so a later session (or you, after a week) does not have to rebuild the
picture from the logs. Facts below are measured; anything unmeasured is marked so.

Generated: 2026-11-06, branch `arena/7c14d5da-rfsoc-zcu208-doa-v7-buildkit`.

---

## 1. Reading `make status`

```
step05_channelizer   FAILED/OLD   see build/logs/step05_channelizer.log
step00…step04        NOT-RUN      -
step06…step15        NOT-RUN      -
```

`FAILED/OLD` in `scripts/stage_status.sh` means exactly one thing: **a log exists and a
stamp does not** — the last attempt at that stage did not exit 0. It carries no other
meaning; it is not a stale-result warning.

So on the Vivado host, twenty stages are unrun and **one has been attempted**: the
channelizer, through the Model Composer flow, which is the attempt this branch is about.

To clear it and start the stage over:

```bash
make clean-stage STEP=step05_channelizer
```

## 2. What has actually been proven, and where

| claim | evidence | where |
|---|---|---|
| the algorithm chain is right | step0–step7 benches: `make steps` 8/8 | `build/logs/`, `docs/steps/` |
| the HDL channelizer is right | `make ip-equivalence`: `bit-exact: 16384 samples, 4 channels, depth 4: MATCH`, gateway error 6.103e-05 = 1.000 LSB | `build/logs/ip_equivalence.log` |
| the IP can be packaged from Verilog | `component.xml` with `doa.v7:model_composer:channelizer:1.0` | `$(IP_REPO)/channelizer_ip/` |
| the software gates | G0, G1a/b/c, G7a, G8a PASS; G2–G6, G7b, G8b, G8c open | `docs/GATES_RUNBOOK.md` |
| the Model Composer model is well formed | 4 in / 4 out, 21 child blocks, 0 unconnected ports, `Ctrl+D` clean | `ip/model_composer/channelizer/README.md` |
| Model Composer can export *an* IP on this install | AMD's untouched `SSRDDC.slx`, steps 1–5 → `generated` | `docs/evidence/2026-11-06-model-composer-negative/` |
| Model Composer cannot export *this* IP | unresolved: `XMC-2002 … Delay1…Delay4`, block fields identical to AMD's | same, plus this branch's `mc_bisect` runs |
| nothing has been synthesized | step10–step12 NOT-RUN | `make status` |

Unmeasured, and not to be asserted: board bring-up, timing closure, resource use, HIL.

## 3. `step05_channelizer` has three ways to pass

`scripts/collect_ip.sh` decides what `step06_collect_ip` requires, and it accepts either
producer for the Model Composer flow.

| route | command | gives you | state |
|---|---|---|---|
| **HDL Coder (default)** | `make step05_channelizer` (`CHANNELIZER_FLOW=matlab_hdl`) | `matlab_channelizer` 7.0 — `dsphdl.Channelizer`, 8 complex s16/beat in, 1024 bins out | the flow the pipeline is built around; needs the `matlab` on `PATH` (R2024a) |
| **Verilog, Model Composer VLNV** | `make ip-from-hdl` | `channelizer_ip` = `doa.v7:model_composer:channelizer:1.0` — four 16.14 lanes, 4-clock delay | verified bit-exact; it is the test datapath, not a spectrum channelizer |
| **Model Composer GUI** | `make mc-example`, `make mc-gui`, then `docs/GUI_MODEL_COMPOSER_IP.md` | AMD's `DDC_DUT` model, exportable as `model_composer_channelizer` | the export route works on AMD's design; our own design has the unexplained Delay refusal |

Prefer the first row for the DOA pipeline. The second row is what to use if you need the
`model_composer` flow stamped. The third is for when you specifically want an IP authored
in Model Composer, and it is the one thing here that is not finished.

## 4. The route to a bitstream, in order

```bash
make step00_preflight          # tools, licences, parts — fails fast
make step01_fetch_references
make step02_hls_covariance
make step03_hls_spectrum
make step04_hls_candidate
make step04_hls_beam
make step05_hls_repack
make step05_channelizer        # see §3
make step05_subband_bridge
make step05_hls_phase_interf
make step06_collect_ip         # validates every VLNV, assembles one IP repo
make step07_vivado_project
make step08_vivado_integrate
make step09_vivado_validate
make step10_synth
make step11_impl
make step12_bitstream
make step13_export_xsa
make step14_hil_vectors
make step15_package
```

or `make pipeline` for the lot, `make status` to watch, `make progress` to write
`docs/progress/PROGRESS.md`.

Each stage is stamped under `build/.stamps/` and logged under `build/logs/`; a stage that
fails leaves its log and no stamp, which is the `FAILED/OLD` above.

## 5. Model Composer: what is settled

- `xmcGenerate(model, …)` — dies inside `vmcGenerate` with
  `Index exceeds the number of array elements. Index must not exceed 0.` 20+ runs, with
  `SubsystemName` filled, `IpLibrary = model_composer`, and a clean model.
- `xmcGenerateButtonPressed(hub)` — this is the **HLS code-generation** check, not the IP
  Catalog export. Control run on AMD's untouched design: hundreds of
  `ERROR-XMC-2002: Unsupported block` naming AMD's own `Vector FIR/FIR Compiler 7.2`,
  `Vector Real Gateway In/Demux1`, `Vector DDFS2/NCO/...`. Every XMC-2002 conclusion drawn
  from this call about our blocks is void.
- The Delay refusal under `IpLibrary = model_composer` is the one open question. The
  "copy AMD's block" theory is disproved: `compareBlocks` showed identical
  `XmcBlockStatus/block_type/block_config/rst/en/reg_retiming`, `latency` 3 vs 4.
- `hdlSSR` is not on the loaded library path (`vmcUtilities, hdlBasic, hdlUtilities`),
  although AMD's boundary uses `hdlSSR/Vector Real Gateway In/Out`. Rebuilds that need
  those blocks must resolve this first.

## 6. Things that cost a day, so they are written down

- The Hub's `SubsystemName` is not a mask parameter in 2023.2 — it appears only after the
  dialog has been opened, and writing to `IPInfoJsonString` does not set it.
- `add_line` wants system-relative names and `autorouting` matches by geometry; wire by
  port handles.
- A `Ground` has infinite sample time; use `Constant` at `Tclk`.
- Copying the Hub between models raises a modal dialog; copy only the design.
- The model's `StopFcn` is `stop_time = toc(start_time)/60`, so without
  `assignin('base','start_time',tic)` it masks the real error.
- A cancelled generation must not be reported as failed — the engine can finish while the
  GUI hangs afterwards.
