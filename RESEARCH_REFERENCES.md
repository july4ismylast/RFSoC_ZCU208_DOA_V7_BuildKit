# Primary-source research and decisions

The design follows current vendor guidance and treats third-party GitHub
projects as architectural references, not drop-in ZCU208 IP.

| Primary source | What was adopted |
|---|---|
| [AMD RF Data Converter PG269 — MTS](https://docs.amd.com/r/en-US/pg269-rf-data-converter/Multi-Tile-Synchronization) | Tile clocks/data paths are independent; use MTS/SYSREF and a verified board configuration for coherent channels. |
| [AMD PG269 — deterministic MTS API](https://docs.amd.com/r/en-US/pg269-rf-data-converter/Deterministic-Multi-Tile-Synchronization-API-Use) | Hardware bring-up must verify alignment and deterministic latency rather than assume one successful capture is sufficient. |
| [Xilinx RFSoC-MTS](https://github.com/Xilinx/RFSoC-MTS) | Native ZCU208 clock/MTS reference and loopback acceptance pattern. |
| [MathWorks RFSoC reference designs](https://www.mathworks.com/help/hdlcoder/xilinxzynq7000/ug/reference-designs-for-rfsoc-devices.html) | ZCU208-supported RFDC settings, samples-per-clock choices, and HDL Workflow Advisor integration. |
| [MathWorks polyphase channelizer capture](https://www.mathworks.com/help/hdlcoder/ug/hdl-polyphase-channelizer.html) | HDL-optimized channelizer, triggered FPGA capture, and host comparison pattern. |
| [MathWorks RFSoC MTS example](https://www.mathworks.com/help/hdlcoder/ug/hdl-multi-tile-synchronization.html) | Cross-tile sample alignment is a separate hardware acceptance test. |
| [MathWorks wideband radar detection/capture](https://www.mathworks.com/help/soc/ug/detect-and-capture-wideband-radar-signal-using-xilinx-rfsoc-device.html) | Continuous PL detection plus triggered capture and processor analysis partition. |
| [AMD Vitis HLS AXI4-Stream guidance](https://docs.amd.com/r/en-US/ug1399-vitis-hls/AXI4-Stream-Interfaces) | Explicit `hls::stream`, registered AXI ports, `TLAST`, pipelined II=1 cores, C test before export. |
| [Xilinx HLS examples](https://github.com/Xilinx/Vitis-HLS-Introductory-Examples) | Source + self-checking testbench + Tcl build + IP export layout. |
| [AMD Model Composer IP Catalog export](https://docs.amd.com/r/en-US/ug1483-model-composer-sys-gen-user-guide/Generating-Packaged-IP-for-Vivado) | Model Composer is a selectable IP-generation route, not mixed blindly with HDL Coder output. |
| [Xilinx RFSoC-PYNQ](https://github.com/Xilinx/RFSoC-PYNQ) | Native ZCU208 project/build layout and board software reference. |
| [StrathSDR RFSoC spectrum analyser](https://github.com/strath-sdr/rfsoc_sam) | Separate `block_design` and `bitstream` targets; ZCU208 spectrum architecture reference. |
| [MazinLab RFSoC OPFB](https://github.com/MazinLab/RFSoC_OPFB) | High-throughput OPFB pattern and independently packaged HLS/System Generator IP, with mandatory board/interface/tool review before reuse. |
| [functions-lab SPEAR](https://github.com/functions-lab/SPEAR) | Separate block-design and bitstream Make targets, PYNQ handoff, and explicit board/sample-rate configurations; ZCU216 content is reference-only. |
| [functions-lab SPEAR-BF](https://github.com/functions-lab/SPEAR_BF) | PL complex weight control, MTS plus software calibration, and deterministic streaming concepts; not copied as ZCU208 IP. |
| [functions-lab SPEAR+](https://github.com/functions-lab/SPEAR_plus) | Hardware-assisted streaming/DMA decoupling and per-design `make bd`/`make bit` pattern; adapted here as independent capture and build stages. |

## Rejected shortcuts

- Changing a ZCU111, ZCU216, or RFSoC4x2 part number to XCZU48DR.
- Using one AXI broadcaster where covariance backpressure can stop search.
- Importing prebuilt IP created by a different Vivado release.
- Calling the scalar MATLAB channelizer a 2 GHz production implementation.
- Claiming the V7 simulation RMSE is already measured ZCU208 field accuracy.
