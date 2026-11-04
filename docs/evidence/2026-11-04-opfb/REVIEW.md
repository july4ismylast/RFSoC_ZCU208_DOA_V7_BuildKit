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
