# Project adapters
- `rfsoc_mts_zcu208`: direct ZCU208/MTS upstream build.
- `rfsoc_sam_zcu208`: direct ZCU208 spectrum analyzer upstream build.
- `rfsoc_pynq_base_zcu208`: direct ZCU208 base overlay upstream build.
- `spear_bf_reference`: ZCU216 beamforming reference + a ZCU208 port shell; not a direct board substitution.
- `spear_plus_reference`: ZCU216 streaming/MTS reference + ZCU208 port shell.
- `leo_rfsoc4x2_reference`: RFSoC4x2 PFB/DDS/CIC architecture reference + ZCU208 port shell.
- `rfsoc_opfb_reference`: upstream RFSoC4x2 OPFB top-level; individual OPFB custom IPs are separately retargeted to XCZU48DR.
