# Reference matrix

| Reference | Board in upstream | Main idea reused | Direct ZCU208 build? | Build-kit action |
|---|---|---|---|---|
| RFSoC-MTS | ZCU208 + RFSoC4x2 | ADC/DAC multi-tile alignment | Yes | Call upstream ZCU208 Make/Tcl |
| rfsoc_sam | ZCU208, ZCU111, 4x2, 2x2 | FFT/spectrum analyzer | Yes | Call upstream ZCU208 Make |
| RFSoC-PYNQ | ZCU208 + others | ZCU208 base overlay | Yes | Call upstream base Make |
| RFSoC_OPFB | RFSoC4x2 current | 4096ch 2/1 OPFB | No top-level | Rebuild individual HLS IPs for XCZU48DR; reuse packaged SysGen FFT |
| leoeltipo/rfsoc4x2_public | RFSoC4x2 | PFB/DDS/CIC/cascaded-PFB | No | Architecture reference + clean ZCU208 shell |
| SPEAR-BF | ZCU216 | multichannel phase/amplitude beamforming | No | Build upstream as reference; use ZCU208 shell + custom IP |
| SPEAR+ | ZCU216 | 4ch streaming + MTS | No | Build upstream as reference; port data path to verified ZCU208 MTS shell |

## RFSoC_OPFB submodule coverage
The upstream `.gitmodules` also references `capture-upsizer`, `dac-replay`, `iq-capture`, `opfb-bin-to-res`, and `wb2axip`. Separate adapters are included for each. They import an existing packaged Vivado IP when `component.xml` is present; if an upstream repo is source-only, `make list` shows its native Tcl/Make/HLS files so it can be built using that repo's own flow before catalog import.
