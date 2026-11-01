# V00 + V01 + V02 — what changed (branch `vivado-2023.2-v00-v01`)

Date: 2026-11-01 · Lock: Vivado/Vitis **2023.2** · Base: **RFSoC-MTS ZCU208**
(`BASE_KIND=mts`) · RF **2–4 GHz** · **4 ADC**. Applied on top of the audit in
`VIVADO_AUDIT_AND_STAGE_PLAN.md` (kept in the workspace, not this repo).

## V00 — version lock: check first, put in a variable, then use it

| File | Change |
|---|---|
| `config/ip_versions.tcl` **(new)** | Single source of truth: lock metadata, every AMD catalog VLNV for 2023.2 (PS `zynq_ultra_ps_e:3.5`, RFDC `usp_rf_data_converter:2.6`, `axis_data_fifo:2.0`, …), every custom-IP VLNV, `doa_require_vivado_lock` (borrowed BD-Tcl guard pattern), `doa_pinned_ip` / `doa_create_pinned_ip` (exact VLNV, fail-with-available-list). |
| `config.mk` | `EXPECTED_VIVADO_VERSION=2023.2` (no longer empty/warn), `BOARD_PART=xilinx.com:zcu208:part0:2.0`, `BASE_KIND=mts`, `CUSTOM_IP_VENDOR/LIBRARY`, `IPVER_*`, `TARGET_RF_LOW/HIGH_HZ`, `ADC_CHANNEL_COUNT=4`, `SKIP_IP_CATALOG_CHECK` — all exported. |
| `common/vivado/00_check_ip_catalog.tcl` **(new)** | In-memory Vivado proof: every pinned catalog VLNV must exist exactly once in the installed 2023.2; writes `build/output/ip_catalog_lock.txt`. |
| `common/vivado/common.tcl` | Sources the lock file; `open_work_project` enforces Vivado version + PART + BOARD_PART; new `doa_append_ip_repo_paths` (append, dedup — never overwrite a base project's repos). |
| `common/vivado/07/08*.tcl` | Use the append helper (07 was deleting base IP repos); 07 asserts the lock before opening anything. Stages 09–13 inherit the lock check via `open_work_project`. |
| `common/vivado/create_doa_v7_hier.tcl` | Deleted `find_unique_ipdef` (last sorted NAME match, version ignored) and both `axis_data_fifo:*` wildcards. All 6 IPs now via `doa_create_pinned_ip`. |
| `common/vivado/create_zcu208_shell.tcl` | Wildcards removed (pinned PS/reset), file marked **DEPRECATED** (production starts from MTS, V03). |
| `common/vivado/create_catalog_project.tcl` | "First substring match" removed; full VLNV or unique NAME must resolve to exactly 1 IP, else fail listing matches. |
| `scripts/preflight.sh` | Hard lock: Vivado **and** Vitis HLS must equal 2023.2, board/base/RF checks, Python 3 check, then runs the catalog proof. |

## V01 — IP version plumbing (HLS → package → BD can no longer drift)

| File | Change |
|---|---|
| `ip/custom/*/build_hls.tcl` (×4) | `config_export -vendor/-library/-version` now read `CUSTOM_IP_*` / `IPVER_*` from `config.mk` (env defaults match the lock). |
| `ip/custom/beam_weight_4ch/src/beam_weight_4ch.cpp` | `s_axilite port=return` → `ap_ctrl_none port=return`: single-beat top now streams freely like spectrum/candidate. **IP 2.0 → 2.1.** |
| `ip/custom/doa_covariance_4ch_v4/src/*.cpp` | AXIS ports gain `register_mode=both` (timing on the 512-bit fan-out). No register-map change. **IP 7.0 → 7.1.** |
| `ip/matlab/channelizer_hdl/package_generated_rtl.tcl` | Vendor/library/version from the same variables. (Bus-interface definition is still V06 — now flagged in-file.) |
| `scripts/collect_ip.sh` | Parses vendor/library/name/version from every `component.xml` and **fails step06 on any mismatch** vs the pinned VLNV; manifest records expected vs packaged VLNV. |
| `matlab_v7/rfsoc_buildkit_overlay/…` | Deliberately untouched (historical 7.0 copy). The pinned 7.1 top-level core can never be confused with it. |

## V02 — upstream pinning & adapter honesty

- `config/upstream_repositories.tsv`: **all refs are full commit SHAs**
  (MTS `f8e93e7…`, PYNQ pinned to its last 2024.1-design commit `29960d0…`,
  SAM to its 2024.1 commit `873c70c…`, OPFB sub-repos pinned too, SPEAR/LEO
  pinned). Branch names float — PYNQ master is already 2025.2.
- `projects/*/Makefile`: `fetch` now passes its own project name (before, the
  SPEAR/LEO adapters silently fetched the *native* set); MTS/PYNQ/SAM help
  texts state their true Vivado and that only MTS is the production base
  under the 2023.2 lock; dead root target `opfb-ips` replaced with an
  explicit Plan-B message.

## V03 preparation (no BD changes yet)

- `scripts/prepare_mts_2023p2_patch.sh` **(new)**: verifies the pinned MTS
  checkout SHA, copies it to `build/mts_base_src_2023p2/`, applies exactly
  one substitution (`zynq_ultra_ps_e` 3.4 → 3.5, the only catalog delta),
  prints the diff. Pristine upstream is never modified.
- `V03_MTS_BASE_2023P2.md` **(new)**: run order, expected first-run failure
  modes, and the 4 acceptance gates — including "build the *unmodified* MTS
  base first" and the proposed 4-ADC map
  (`m00/m02/m10/m12` → DOA ch0–3).

## Verified here (no Vivado on this machine)

- `make lint` — **PASS** (shell syntax, Make dry-runs, Tcl completeness).
- `config/ip_versions.tcl` sources cleanly in `tclsh`; VLNV variables resolve.
- `scripts/collect_ip.sh` against synthetic `component.xml` files: passes
  with the pinned versions (7.1/2.0/1.0/2.1/7.0) and **correctly fails**
  (exit 4) when one file is downgraded 2.1 → 2.0.
- Real end-to-end V02+V03 dry run: fetched RFSoC-MTS at the pinned SHA via
  `scripts/fetch_upstream.sh`, ran the patch helper — diff shows **only**
  the 2 PS-VLNV lines (check list + `create_bd_cell`).
- No `xilinx.com:ip:…:*` wildcard or `find_unique_ipdef` remains in
  production Tcl (only in explanatory comments).

## Not yet done (by design — next stages)

V03 execution on your 2023.2 PC (needs your Vivado log) → V04 RFDC 4-slice +
2–4 GHz sample-rate/Nyquist plan → V05 new `rfdc_repack4` gearbox IP →
V06 channelizer bus interfaces + instantiation → V07 `zcu208_bd_map.tcl`
(clocks/resets/SmartConnect/result path/fixed `ADDR_*`) → V08 XDC →
V09–V12 synth/impl/bit/HIL. The DOA hierarchy's single-clock assumption,
missing wrapper regeneration in step10, and step12/13 handoff polish are
intentionally left for V07–V11 where they can be validated on real tools.
