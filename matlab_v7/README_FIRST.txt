REALISTIC 0.1-DEGREE 2x2 DOA V7 - MATLAB R2024a / ZU48DR HIL
================================================

QUICK START
-----------
Close and reopen MATLAB once after replacing V6 files so no old System object
class remains cached.

1. Extract this ZIP.
2. Open MATLAB R2024a in the extracted directory.
3. Read COMPLETE_FILE_AND_CODE_GUIDE.md for every file/function/source listing.
   Use REALISTIC_DOA_ENGINEERING_GUIDE.md for the shorter illustrated workflow.
4. Run the deterministic and statistical acceptance checks:

   verify_hybrid_doa_2x2
   run_accuracy_campaign('acceptance')
   run_realistic_accuracy_campaign('acceptance')

5. Run the full generated Simulink demonstration:

   START_HERE

START_HERE performs all three required actions:

   verify_r2024a_setup
   build_3d_doa_simulink
   sim('DOA_3D_Homing')

For the standalone MATLAB version, run:

   run_3d_doa_sim

SOURCE MODULATION
-----------------
Select only P.Source.ModulationType in sim3d_params.m. The matching parameters
are fetched by the switch/case in source_modulation_profile.m. Edit the LFM,
NLFM, PM, FM, or other case there, or use the optional override block in
sim3d_params.m for one experiment.

WHAT MUST HAPPEN
----------------
- The moving target/receiver starts at [0 0 50] m.
- The RF source remains at [500 300 200] m.
- The target steers toward the detected source.
- Range decreases from approximately 602 m.
- Simulation stops when range is at or below 10 m.

RESULTS SHOWN
-------------
1. 3D target/receiver trajectory and RF-source position.
2. Range to source and arrival radius.
3. Detection-valid state and peak SNR.
4. Estimated versus true azimuth.
5. Azimuth estimation error.
6. Estimated versus true elevation.
7. Elevation error and total 3D angular error.
8. Detected RF center frequency and estimated bandwidth.
9. Target/receiver yaw, pitch, and roll.
10. Final RF/PFB spectrum and configured source band edges.

The Simulink model also opens four live scopes and contains numeric displays
for detection, arrival, range, SNR, DOA truth/estimate/errors, RF center, and
bandwidth.

DETAILED DOCUMENTATION
----------------------
- COMPLETE_FILE_AND_CODE_GUIDE.md (all 63 code files and complete source)
- REALISTIC_DOA_ENGINEERING_GUIDE.md (clickable illustrated block index)
- HIL_ZU48DR_GUIDE.md (separate board flow)
- SIMULINK_MODEL_GUIDE.md
- RUN_3D_DOA_SIM_GUIDE.md
- SOURCE_WAVEFORM_PARAMETER_GUIDE.md
- ALGORITHM_CALCULATION_EXAMPLES.md
- FILE_BY_FILE_REFERENCE.md

IMPORTANT HARDWARE NOTE
-----------------------
The default is a square 2x2 array on the nose Y-Z plane, with +X boresight.
It measures azimuth/elevation in the known forward hemisphere. Like every
planar array, it has an unresolved front/back mirror without that constraint.
Read ACCURACY_AND_HDL_GUIDE.md before interpreting the 0.1-degree RMSE claim.

SEPARATE HIL QUICK START
------------------------
1. run_zcu48dr_hil('prepare')
2. Build doa_covariance_4ch_v4 with Vitis HLS.
3. Replay hil_vectors/adc_4ch_4spc_axis512.hex on the board.
4. Save the 16 signed int64 outputs to capture.csv.
5. run_zcu48dr_hil('compare','capture.csv')

The loopback command verifies only the host parser. It is not a hardware pass.
