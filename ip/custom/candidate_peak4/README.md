# Streaming spectrum candidate gate

The core accepts four unsigned 64-bit bin powers per AXI256 beat. Across one
`TLAST`-delimited spectrum frame it calculates the maximum bin and the global
average. At `TLAST` it emits one AXI192 record with the bin, validity flag,
peak power, and average power. `thresholdQ8_8=512` means peak > 2× average.

This inexpensive gate is intentionally not advertised as full CA-CFAR. The R5
or a later PL CFAR/cluster block must apply persistence, exclusion bands,
multiple-target rules, and false-alarm control before triggering a capture.

