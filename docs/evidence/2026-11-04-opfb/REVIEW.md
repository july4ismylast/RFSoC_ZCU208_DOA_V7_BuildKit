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

## Completion diagnosis for the archived route evidence

The archived `v06_opfb_route.log` does **not** support the claim that Vivado
stopped partway through this OPFB physical screen. It records `synth_design` in
out-of-context mode, the 16/16/64-byte interface-width checks, and successful
completion markers for `route_design`, timing/report generation, `report_drc`,
checkpoint writing, and Vivado exit. The DRC report says `Design State : Fully
Routed`; it contains one RTSTAT-10 warning (539 nets with no routable loads),
not a truncated or empty DRC result. Its small size is explained by the small
number of violations, not evidence of interruption. The log tail also reports
zero errors and successful license release; it gives no indication of an OOM,
license failure, or CI timeout.

Scope matters: `make opfb-route-check` is a **standalone out-of-context
physical feasibility screen**, and its Tcl deliberately does not create a
bitstream. So it completed successfully as that screen, but this is not proof
that the complete ZCU208 production implementation, bitstream, or board-level
timing/signoff completed. Do not run the full production `clean`/`build` merely
because no `.bit` accompanies this evidence; the `.bit` is not an output of this
target.

The evidence publisher now refuses an OPFB publication unless the route/DRC
completion markers, fully-routed DRC state, zero route-error count, and expected
interface widths are present. This protects against publishing partial OPFB
screen results, without incorrectly requiring a bitstream or imposing a
minimum DRC report size.

## Corrected-width synthesis (commit 99eef1a evidence)

The width report confirms 16-byte I/Q inputs and a 64-byte output.
Synthesis uses 78,603 LUTs, 57,241 FFs, 54.5 BRAM tiles and 272 DSPs.
Its normal top-level flow also inserts 892 bonded IOBs, exceeding the 347
available package I/Os. These AXI ports must be internal integration boundaries,
not package pins. The route target now re-synthesizes the existing evaluation
project with `synth_design -mode out_of_context`, checks that no package I/O
buffers or black boxes remain, then performs the standalone physical screen.
The archived `v06_opfb_route.log` records a later corrected-width
out-of-context synthesis and completed route; its width report confirms the
16/16/64-byte interfaces. Review its utilization, unconstrained timing, DRC,
and route-status reports as an OOC feasibility result only. The earlier
scalar-port reports must not be used to draw OPFB capacity conclusions.
