# rfdc_repack4 — stage V05 RFDC gearbox

Pairs the eight RFDC AXI4-Stream outputs of the V04 wideband contract
(`m00/m01`, `m02/m03`, `m10/m11`, `m12/m13`; even = I, odd = Q) into four
256-bit SSR-8 complex streams at 250 MHz. Complex word packing is the
project-wide `{Q[31:16], I[15:0]}`; word/lane `s` is the `s`-th oldest
sample in the beat. Full interface, ordering, alignment and upstream
comparison: `V05_RFDC_REPACK4_SPEC.md` at the repo root.

Build (from repo root): `make step05_hls_repack`
(C-sim bit-exact packing test → csynth at 4.0 ns → IP Catalog export with
the pinned `IPVER_RFDC_REPACK4` VLNV → installed to `build/ip_repo`).
