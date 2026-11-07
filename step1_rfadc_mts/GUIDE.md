# step1 — RF-ADC, MTS clock, and the capture record

**Gates:** G5 (DAC→ADC loopback) is simulated here, not measured — it needs the
board. **Runs on:** python3 + numpy, or MATLAB. No Vitis, no Vivado.

This step turns the step0 scenes into the exact bytes the PL writes and the PS
reads, and it quantifies the three things that can go wrong between the antenna
and those bytes: **quantisation**, **per-channel time skew** (the MTS clock) and
the **loopback delay**.

## Record layout (the contract everything downstream relies on)

```
  0  char[8]  "ZC208C01"
  8  uint32   fs_hz         2 000 000 000
 12  uint32   fc_hz         4 000 000 000
 16  uint16   channels      4
 18  uint16   bits          12
 20  uint32   samples       4096
 24  float32  scale         LSB = 1/scale,  x = raw / scale
 28  uint32   flags         bit0 signed Q15, bit1 MTS skew compensated
 32  int16[]  payload       index = ((n * channels) + ch) * 2 + (0 = I, 1 = Q)
```

One burst = **32 B header + 64 kB payload**. That is the `doa_capture` DMA
record; `ip/custom/doa_covariance_4ch_v4` and the PS both use it.

## The three error sources, with numbers

**Quantisation.** For a signal whose peak is at full scale,

```
SQNR = 6.02*b + 1.76 - 20*log10(peak/rms)      (b = 12 here)
```

**MTS skew.** A per-channel sampling error `dt` shows up mostly through the
*carrier*, not the baseband:

```
phase error  = 2*pi*fc*dt          (1 ps at 4 GHz = 0.0251 rad)
angle error  = phase error * lambda/(2*pi*d)
```

so 1 ps on a 25 mm baseline at 4 GHz is **0.69°** — larger than the 0.5° budget.
The budget is **0.73 ps**, which is why the MTS clock in the diagram is a block of
its own and why `flags` bit1 exists.

**Loopback delay.** One sample at 2 GS/s is 0.5 ns = 15 cm of cable. So G5
measures *bulk group delay* to within a sample, not cable length: it proves the
DAC and ADC share a clock and a trigger, which is what it is for.

## Files

| file | what it is |
|---|---|
| `py/capture_format.py` | header pack/unpack, the 12-bit quantiser, `apply_skew`, `loopback_delay`; `python3 step1_rfadc_mts/py/capture_format.py` prints the numbers |
| `matlab/step1_capture_header.m` | the same 32 bytes in MATLAB, for checking the C driver |
| `testbench/run_testbench.py` | five checks (below) |

## How to run it

```bash
python3 step1_rfadc_mts/testbench/run_testbench.py     # -> RESULT=PASS (5/5)
python3 step1_rfadc_mts/py/capture_format.py
matlab -batch "cd step1_rfadc_mts/matlab; h=step1_capture_header; disp(h.bytes)"   # NOT run here
```

## The test bench

| check | result on 2026-11-07 |
|---|---|
| T1.1 write → read is bit exact | 65 568 B, 4 ch × 4096, max error **2.0e−11** |
| T1.2 SQNR vs crest-corrected theory | **66.08 dB vs 66.06 dB** (textbook 74.0, crest 7.9 dB) |
| T1.3 1 ps of skew | measured **0.693°**, formula 0.687°; budget **0.73 ps** |
| T1.4 loopback delay | injected 37 samples → found 37 (18.5 ns, 15 cm resolution) |
| T1.5 the file means the same as the array | az **−6.022°** from file and from data, truth −6.00°, drift 1e−4° |

`RESULT=PASS (5/5)`.

## On the board (G5)

```bash
# 1. load the bitstream with the loopback image (step7)
# 2. capture two bursts: DAC NCO on, then off
make step05_hls_phase_interf          # the capture path must exist first (G2)
# 3. read the record at the DMA node and run the same estimator
python3 step1_rfadc_mts/py/capture_format.py --from /dev/xdma0_c2h_0
```

The last command is **not written yet**: it needs a board. Everything in the
paragraph above that says "read" is the part of G5 that only hardware can do.

## What is not proven here

* The 12-bit quantiser is a uniform rounding model; the real RFSoC ADC is
  12-bit with its own INL/DNL and a digital step. The simulated SQNR is an
  upper bound.
* `apply_skew` is an ideal fractional delay; the MTS clock's real skew comes
  from the LMK's phase-adjust resolution and from the PL routing.
* Nothing about the DAC→ADC path is measured: G5 stays open until a capture
  exists.
