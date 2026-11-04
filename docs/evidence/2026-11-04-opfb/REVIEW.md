# OPFB evaluation validity warning

The initial synthesis and routed reports in this folder are **not valid
full-width OPFB fit/timing evidence**. The user inspected the generated wrapper
and confirmed scalar istream/qstream/output TDATA and scalar AXI control buses.
The original evaluation script externalized both interfaces and all their member
pins, overriding interface connections before width propagation.

The corrected script externalizes interfaces and only the standalone clock/reset
pins. A pre-synthesis stream-width guard now rejects collapsed streams and records
interface widths. Fresh synthesis is required; do not reuse the old checkpoint for
production feasibility claims. Existing reports are retained for audit history.

The 48 REQP-1729 DSP pre-adder warnings also remain a numerical-review item.

## Corrected-width synthesis (commit 99eef1a evidence)

The width report confirms 16-byte I/Q inputs and a 64-byte output.
Synthesis uses 78,603 LUTs, 57,241 FFs, 54.5 BRAM tiles and 272 DSPs.
Its normal top-level flow also inserts 892 bonded IOBs, exceeding the 347
available package I/Os. These AXI ports must be internal integration boundaries,
not package pins. The route target now re-synthesizes the existing evaluation
project with `synth_design -mode out_of_context`, checks that no package I/O
buffers or black boxes remain, then performs the standalone physical screen.
The first scalar-port routed reports remain invalid; no corrected-width route
result has yet been reviewed.
