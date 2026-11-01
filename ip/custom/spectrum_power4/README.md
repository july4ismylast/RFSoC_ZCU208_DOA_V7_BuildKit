# Four-lane spectrum power IP

One 512-bit input beat contains four time/frequency lanes, each holding four
complex signed-int16 antenna channels. The core emits one 256-bit beat with
four unsigned 64-bit incoherent powers. It sustains one beat per clock and
copies `TLAST`. This is the detector statistic, not the DOA covariance.

Packing is identical to the V7 covariance core: `word = lane*4 + channel`,
real in bits 15:0 and imaginary in bits 31:16.

