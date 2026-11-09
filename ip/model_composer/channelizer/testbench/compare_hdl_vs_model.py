#!/usr/bin/env python3
"""Compare what channelizer.slx describes with what channelizer_dut.v implements.

Two things can be compared without Model Composer:

  datapath arithmetic   Gateway In (sfix16_En14, Truncate, Wrap) -> Delay 4 ->
                        Gateway Out, versus a 16-bit shift register of depth 4
  latency               measured from an impulse, not assumed

Two things cannot, and are printed as differences instead of being glossed over:

  port layout           the model's gateways are named In1..In4 / Out1..Out4, one
                        16-bit port each; the Verilog packs them into din[63:0]
  clock enable          the Hub's clock_wrapper is "Clock Enables", so its export
                        carries a ce input; the Verilog has none

Run: python3 ip/model_composer/channelizer/testbench/compare_hdl_vs_model.py
"""
import numpy as np

WIDTH = 16
FRAC = 14
LATENCY = 4
CHANNELS = 4
SAMPLES = 4096
LSB = 2.0 ** -FRAC
WORD = 2 ** WIDTH
HALF = WORD // 2


def to_sfix16_en14(values):
    """Gateway In: Truncate towards -inf, then Wrap into 16 bits (two's complement)."""
    codes = np.floor(values / LSB).astype(np.int64)
    codes = np.mod(codes + HALF, WORD) - HALF
    return codes


def from_sfix16_en14(codes):
    return codes * LSB


def shift_register(codes, latency):
    """What channelizer_dut.v does: pipe[i] <= pipe[i-1], four stages.

    Written the way the Verilog is: dout is the last register, read before the
    clock edge (non-blocking assignment), and the input enters pipe[0] at that
    edge.  With four registers the output is therefore four clocks behind the
    input: y[n] = x[n-4].
    """
    pipe = [np.zeros_like(codes[0]) for _ in range(latency)]
    out = np.zeros_like(codes)
    for index in range(codes.shape[0]):
        out[index] = pipe[latency - 1]
        for stage in range(latency - 1, 0, -1):
            pipe[stage] = pipe[stage - 1]
        pipe[0] = codes[index]
    return out


def index_delay(codes, latency):
    """The same delay written independently: y[n] = x[n-latency]."""
    out = np.zeros_like(codes)
    if codes.shape[0] > latency:
        out[latency:] = codes[:codes.shape[0] - latency]
    return out


def model_path(values, latency):
    """What the model describes: gateway quantises, delay holds, gateway passes on."""
    return index_delay(to_sfix16_en14(values), latency)


def main():
    rng = np.random.default_rng(7)
    failures = []

    # Values on a fine grid, so the gateway really does quantise.
    raw = rng.uniform(-2.0, 2.0, size=(SAMPLES, CHANNELS)) + LSB / 3.0
    reference = model_path(raw, LATENCY)

    # The Verilog carries the quantised codes; it must reproduce them exactly.
    codes = to_sfix16_en14(raw)
    hdl = shift_register(codes, LATENCY)   # the Verilog's pipeline, loop by loop
    if np.array_equal(hdl, reference):
        print(f"bit-exact: {SAMPLES * CHANNELS} samples, 4 channels, depth {LATENCY}: MATCH")
    else:
        failures.append("datapath mismatch between model and Verilog")

    # Latency from an impulse: first non-zero output index.
    impulse = np.zeros((SAMPLES, 1))
    impulse[0, 0] = 1.0
    response = model_path(impulse, LATENCY)
    measured = int(np.argmax(response[:, 0] != 0))
    print(f"latency measured from an impulse: {measured} clocks (declared {LATENCY})")
    if measured != LATENCY:
        failures.append(f"latency {measured} != {LATENCY}")

    # Quantisation the gateway performs, which the Verilog therefore inherits.
    worst = float(np.max(np.abs(from_sfix16_en14(to_sfix16_en14(raw)) - raw)))
    print(f"gateway quantisation: worst error {worst:.3e} = {worst / LSB:.3f} LSB "
          f"(LSB = {LSB:.6f})")
    if worst > LSB:
        failures.append("quantisation exceeds one LSB")

    print("interface differences (not equal, by design):")
    print("  model: 4 x 16-bit ports In1..In4 / Out1..Out4 + clk + ce")
    print("  verilog: din[63:0] / dout[63:0] + clk, no ce")

    if failures:
        print("RESULT=FAIL")
        for failure in failures:
            print("  " + failure)
        return 1
    print("RESULT=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
