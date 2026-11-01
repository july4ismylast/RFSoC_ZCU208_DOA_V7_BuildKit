# Validation report

## Passed in this environment

- `make` defaults to the complete help menu.
- `make list` and `make status` enumerate every stage.
- `make -n` for every numbered stage is non-mutating.
- a deliberately unavailable-tool preflight failed and created no success stamp.
- all shell scripts pass `bash -n`.
- all authored Tcl files are syntactically complete according to Tcl parsing.
- all local Markdown/image links resolve.
- the overall SVG renders to the embedded 1800×1000 JPEG.
- the complete V7 MATLAB reference and all four HLS self-checking testbenches
  are present.

Run the same static checks with:

```bash
make lint
```

## Not run here

Vivado, Vitis HLS, MATLAB R2024a, RFSoC board files, and a ZCU208 were not
installed in this execution environment. Consequently no HLS synthesis report,
HDL Coder/Model Composer IP, Vivado utilization/timing report, bitstream, XSA,
or physical HIL result was fabricated. The numbered stages and acceptance
instructions are provided for execution on the licensed build host and board.

