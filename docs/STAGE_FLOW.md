# The stage flow, as the repository defines it

Every row below is read off this checkout, not from memory: the recipe is the
`$(STAMP_DIR)/<stage>.done` rule in the `Makefile` (line numbers given), wrapped by
`scripts/run_stage.sh`, which writes the log and the stamp.

`make status` reads the same pair: **stamp present → PASS**, **log without stamp →
FAILED/OLD**, **neither → NOT-RUN**.

All stages run through:

```
scripts/run_stage.sh --id <stage> --stamp build/.stamps/<stage>.done \
                     --log build/logs/<stage>.log -- <command>
```

so a stage that fails keeps its log and gets no stamp, and `make pipeline` (a plain
`for` loop over `PRODUCTION_STAGES`, `Makefile:143`) stops at the first one.

---

## The table

| # | stage | Makefile | runs | tool | produces |
|---|---|---|---|---|---|
| 1 | `step00_preflight` | 416 | `scripts/preflight.sh` | shell + all tools | tool/licence/part report |
| 2 | `step01_fetch_references` | 419 | `scripts/fetch_upstream.sh $FETCH_SET` | git/network | `upstream/` reference repos |
| 3 | `step02_hls_covariance` | 422 | `make -C ip/custom/doa_covariance_4ch_v4 all` | `vitis_hls` | covariance IP |
| 4 | `step03_hls_spectrum` | 425 | `make -C ip/custom/spectrum_power4 all` | `vitis_hls` | spectrum-power IP |
| 5 | `step04_hls_candidate` | 428 | `make -C ip/custom/candidate_peak4 all` | `vitis_hls` | candidate-peak IP |
| 6 | `step04_hls_beam` | 431 | `make -C ip/custom/beam_weight_4ch all` | `vitis_hls` | beam-weight IP |
| 7 | `step05_hls_repack` | 434 | `make -C ip/custom/rfdc_repack4 all` | `vitis_hls` | RFDC repack IP |
| 8 | `step05_channelizer` | 437 | `scripts/build_channelizer.sh $CHANNELIZER_FLOW` | `matlab` (R2024a) or Model Composer | `matlab_channelizer` **or** `channelizer_ip` |
| 9 | `step05_subband_bridge` | 440 | `make -C ip/custom/doa_subband_bridge_4ch all` | `vitis_hls` | subband bridge IP |
| 10 | `step05_hls_phase_interf` | 443 | `make -C ip/custom/phase_interf_4ch all` | `vitis_hls` | phase-interferometer IP |
| 11 | `step06_collect_ip` | 446 | `scripts/collect_ip.sh` | python + shell | one IP repo, every VLNV checked |
| 12 | `step07_vivado_project` | 449 | `common/vivado/07_create_project_from_base.tcl` | `vivado` | project on the MTS base |
| 13 | `step08_vivado_integrate` | 452 | `common/vivado/08_integrate_doa_v7.tcl` (+ `create_doa_v7_hier.tcl`, `config/zcu208_bd_map.tcl`) | `vivado` | block design wired |
| 14 | `step09_vivado_validate` | 455 | `common/vivado/09_validate.tcl` | `vivado` | DRC / BD validation |
| 15 | `step10_synth` | 458 | `common/vivado/10_synth.tcl` | `vivado` | synthesis reports |
| 16 | `step11_impl` | 461 | `common/vivado/11_impl.tcl` | `vivado` | place & route, timing |
| 17 | `step12_bitstream` | 464 | `common/vivado/12_bitstream.tcl` | `vivado` | `.bit` |
| 18 | `step13_export_xsa` | 467 | `common/vivado/13_export_xsa.tcl` | `vivado` | `.xsa` |
| 19 | `step14_hil_vectors` | 470 | `scripts/generate_hil.sh` | `matlab` (R2024a) | HIL stimulus/expectations |
| 20 | `step15_package` | 473 | `scripts/package_release.sh` | shell | release archive |

`step01_fetch_references` is **not** in `PRODUCTION_STAGES` (`Makefile:35`), so
`make pipeline` skips it; run it yourself. Everything else is in pipeline order.

## What each stage needs from you

| stages | need | notes |
|---|---|---|
| 1–2 | network, git | step01 clones reference repositories; `FETCH_SET=native\|opfb\|all` |
| 3–7, 9–10 | `vitis_hls` on `PATH` or `VITIS_HLS=` | each is an independent HLS project under `ip/custom/` |
| 8 | `matlab` (R2024a) for `matlab_hdl`; R2022b **through the Model Composer launcher** for `model_composer` | see `docs/TWO_MATLABS.md` |
| 11 | every IP directory that `scripts/collect_ip.sh` lists | it checks VLNVs, not just file presence |
| 12–18 | `vivado` 2023.2, the ZCU208 board part, a licence for the RFSoC devices | 12–18 are the hours-long ones |
| 19 | `matlab` (R2024a) | |
| 20 | — | |

## Verifying the flow yourself, without running it

```bash
make -n pipeline                 # the exact commands, in order
make -n step08_vivado_integrate  # one stage, fully expanded
grep -n '^\$(STAMP_DIR)/step' Makefile   # the recipe for every stage
make list                        # stage ids as the build knows them
```

`make lint` checks that these recipes are syntactically runnable and that the files they
name exist — it is the closest thing to a dry run that does not need the tools.
