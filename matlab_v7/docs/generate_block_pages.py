from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
BLOCKS = DOCS / "blocks"
BLOCKS.mkdir(parents=True, exist_ok=True)

blocks = [
    dict(slug="01-overall-architecture", title="Overall system architecture",
         image="01-overall-system.jpg", sources=["sim3d_params.m", "run_3d_doa_sim.m", "build_3d_doa_simulink.m"],
         intro="This page connects the signal-generation, receiver, search, estimation, tracking, navigation, and verification paths. The behavioral simulation and the RFSoC implementation use the same geometry, calibration convention, covariance orientation, and frame rate.",
         inputs=[("Mission configuration", "Source, platform, array and accuracy limits"), ("Four RF channels", "Coherent signals from the physical square array")],
         outputs=[("Body-frame DOA", "Azimuth/elevation for guidance"), ("Verification records", "RMSE, HIL and implementation evidence")],
         algorithm=["Generate a direct and reflected RF field at the actual antenna locations.", "Apply coupling, receiver skew, noise, AGC and ADC quantization.", "Search the wideband spectrum and gate one candidate.", "Accumulate calibrated covariance and estimate a refined direction.", "Track the line of sight in the navigation frame and steer only on a valid candidate."],
         code=[("run('sim3d_params.m');", "Loads one authoritative parameter structure."), ("idealIQ=source(position,yaw,pitch,roll);", "Creates the physical antenna voltages before receiver electronics."), ("iq4=receiver(idealIQ);", "Applies the realistic RF and ADC model."), ("snapshots=snapshotSelector(iq4);", "Selects 4096 spatial observations."), ("doaEstimator(snapshots,yaw,pitch,roll)", "Runs calibration, WPI, ML, GN and navigation-frame EKF."), ("platform(azimuth,elevation,valid,sourcePosition)", "Updates vehicle state only when detection is valid.")],
         example="At the default start, the source displacement is [500, 300, 150] m and the true range is 602.0797 m. A valid estimate commands yaw and pitch toward that line of sight; arrival is asserted at 10 m."),
    dict(slug="02-source-propagation", title="RF source and propagation", image="02-source-propagation.jpg",
         sources=["SourceModel3D.m", "source_modulation_profile.m", "body_to_navigation_dcm.m"],
         intro="The source block creates complex baseband RF frames, applies range loss, rotates the world line of sight into the array body frame, and adds configurable reflected paths. Receiver noise and ADC effects are intentionally delegated to the next block.",
         inputs=[("Platform pose", "1x3 position plus yaw, pitch and roll"), ("Waveform profile", "QAM, PSK, LFM, NLFM, CW and other modes")],
         outputs=[("IdealAntennaIQ", "8192x4 complex antenna voltages")],
         algorithm=["Normalize position vectors to prevent implicit expansion.", "Compute the world unit line-of-sight vector.", "Use the full ZYX DCM to obtain body-frame azimuth/elevation.", "Generate and normalize the selected waveform.", "Apply direct-path steering and delayed reflected-path steering."],
         code=[("delta=sourcePosition-platformPosition;", "Forms the physical displacement as a 1x3 vector."), ("worldDirection=delta(:)/range;", "Separates range from direction."), ("bodyDirection=body_to_navigation_dcm(...).'*worldDirection;", "Includes combined yaw, pitch and roll."), ("signal=obj.generateSignal(N)*sqrt(receivedPower_W);", "Scales the normalized waveform by propagation power."), ("tau=obj.AntennaPositions(channel,:)*pathDirection/obj.c;", "Computes geometric delay for each actual antenna location."), ("X4(:,channel)=X4(:,channel)+pathScale*delayed*exp(...);", "Adds a coherent reflected path with its own delay and direction.")],
         example="At 4 GHz the wavelength is 74.948 mm. A 25 mm baseline produces about 120.1 degrees of phase for direction cosine 1, while the 35.355 mm diagonal remains below half a wavelength."),
    dict(slug="03-realistic-receiver", title="Realistic four-channel receiver", image="03-realistic-receiver.jpg",
         sources=["RealisticReceiver4.m", "realism_profile.m", "simulate_realistic_snapshots.m", "estimate_multifrequency_calibration.m", "verify_multifrequency_calibration.m"],
         intro="This block models effects that an ideal steering-vector simulation omits: mutual coupling, gain/phase mismatch, RF time skew, temperature-like drift, common and differential phase noise, thermal noise, AGC, DC offset, clipping and finite ADC resolution.",
         inputs=[("IdealAntennaIQ", "Four coherent complex antenna voltages"), ("Realism profile", "IDEAL, CALIBRATED_LOS or FIELD_STRESS")],
         outputs=[("ADC_IQ", "Clipped and quantized four-channel samples")],
         algorithm=["Mix channels through an actual 4x4 coupling matrix.", "Apply per-channel complex transfer including time-skew phase.", "Add input-referred thermal noise and stochastic phase noise.", "Use one common AGC factor so inter-channel ratios are preserved.", "Clip and round real and imaginary components to the ADC word length."],
         code=[("output=input*obj.CouplingMatrix.';", "Applies voltage-domain coupling before receiver channels."), ("timeSkewPhase_deg=-360*fc*timeSkew;", "Converts picosecond skew into RF phase."), ("output=output.*transfer;", "Applies channel gain, phase and drift."), ("noisePower=k*T*Fs*10^(NF/10);", "Uses the complex sampling bandwidth for thermal noise."), ("output=output*min(requestedGain,maximumGain);", "Applies common, bounded AGC."), ("round(realPart*scale)/scale", "Models deterministic ADC quantization after clipping."), ("polyfit(frequencyOffset,unwrappedPhase,1)", "Estimates picosecond relative time skew from calibration-tone phase slope.")],
         example="A residual 0.02 degree channel-phase error on a 25 mm baseline maps to roughly 0.01 degree of direction error near boresight. FIELD_STRESS intentionally uses larger drift and multipath and is not forced to pass 0.1 degree. On hardware, a five-frequency boresight capture drives estimate_multifrequency_calibration; its packed Q2.14 values program the PL registers and its fit residual tests calibration quality."),
    dict(slug="04-rfdc-mts-interface", title="RFDC, MTS and AXI interface", image="04-rfdc-mts-interface.jpg",
         sources=["rfsoc_buildkit_overlay/README.md", "rfsoc_buildkit_overlay/ip/custom/doa_covariance_4ch_v4/README.md"],
         intro="The hardware interface starts from a verified ZCU208 RFDC shell. Multi-tile synchronization establishes deterministic latency, a fine DDC converts the selected RF band to complex IQ, and the RFDC gearbox supplies four samples per PL clock.",
         inputs=[("Four RF ADC channels", "Matched analog paths"), ("SYSREF and sample clocks", "Common deterministic timing reference")],
         outputs=[("AXI512 stream", "4 lanes x 4 channels x complex int16")],
         algorithm=["Run RFDC tile startup and MTS at every boot.", "Configure identical mixer, NCO, decimation and Nyquist settings.", "Verify tile latency and channel phase with a calibration tone.", "Pack four complex samples for every channel into each 512-bit beat.", "Cross clock domains only through explicit AXI FIFOs.", "Trigger a bounded 4096-sample DOA capture without stalling the continuous RFDC/PFB search stream."],
         code=[("word = lane*4 + channel", "Defines the stable AXI packing order."), ("real -> bits 15:0", "Stores signed ADC I data."), ("imag -> bits 31:16", "Stores signed ADC Q data."), ("4 samples/clock", "Converts a 512 MSPS post-DDC stream to 128 MHz."), ("frameSamples=4096", "Defines one covariance observation interval."), ("MTS before calibration", "Prevents boot-dependent phase offsets from invalidating coefficients."), ("candidate -> capture gate", "Sends only a requested snapshot burst to the frame covariance core.")],
         example="With 2.048 GSPS and RFDC decimation by four, each complex channel is 512 MSPS. Four samples per clock require a 128 MHz PL clock, rather than an impossible 2.048 GHz scalar clock."),
    dict(slug="05-search-detection", title="PFB search, CFAR and candidate selection", image="05-search-detection.jpg",
         sources=["PFBFFTChannelizer4.m", "SpectrumEstimator4.m", "NoiseFloorEstimator1D.m", "CACFAR1D.m", "BinClusterEstimator.m", "CandidateSelector.m"],
         intro="The search branch discovers occupied spectrum, estimates a robust noise floor, applies CA-CFAR, joins adjacent bins, and selects a source matching bandwidth and SNR rules. Detection validity gates navigation but does not manufacture a DOA.",
         inputs=[("ADC_IQ", "Four coherent wideband sample streams")],
         outputs=[("CandidateValid", "Logical navigation gate"), ("Center/Bandwidth", "Selected source spectral properties")],
         algorithm=["Channelize every coherent input with identical coefficients.", "Sum four-channel bin powers and smooth in time.", "Estimate local/global noise using a sliding median.", "Apply training/guard-cell CA-CFAR thresholds.", "Cluster detections and select a bandwidth/SNR-qualified candidate."],
         code=[("NumBands=1024", "Produces 2 MHz bins at 2.048 GSPS."), ("powerSum=sum(abs(subbands).^2,channel);", "Combines evidence without destroying the DOA snapshots."), ("noise=median(localWindow);", "Rejects occupied-bin outliers."), ("alpha=Ntrain*(Pfa^(-1/Ntrain)-1);", "Forms the CA-CFAR scale factor."), ("MergeGapBins=1", "Joins nearly contiguous detections."), ("valid = bandwidth && snr", "Prevents unrelated emitters from steering the platform.")],
         example="A 30 MHz source occupies about 15 bins at 2 MHz spacing. The cluster center is power weighted, while the candidate rule checks the configured 0.5–40 MHz interval and minimum SNR."),
    dict(slug="06-calibration-covariance", title="Calibration and streaming covariance", image="06-calibration-covariance.jpg",
         sources=["rfsoc_buildkit_overlay/ip/custom/doa_covariance_4ch_v4/src/doa_covariance_4ch_v4.cpp", "hil_fixed_covariance_reference.m"],
         intro="This is the main PL DOA backend. It calibrates four complex int16 samples per channel per beat and accumulates the unique entries of a 4x4 Hermitian covariance without storing all 4096 samples.",
         inputs=[("AXI512 IQ", "Four time lanes for four channels"), ("cal0..cal3", "Complex Q2.14 corrections")],
         outputs=[("AXI64 packet", "4 powers, 6 real crosses, 6 imaginary crosses")],
         algorithm=["Unpack sixteen complex words from each AXI beat.", "Apply constant complex calibration with a 14-bit fractional shift.", "Accumulate four powers and six cross products with 64-bit headroom.", "Repeat for 1024 beats, equal to 4096 time samples.", "Emit exactly 16 signed 64-bit values with TLAST on the last word."],
         code=[("packed=input.data.range(32*word+31,32*word);", "Extracts one complex int16 sample."), ("yr=(realProduct>>14);", "Returns the calibrated result to the intended fixed-point scale."), ("power += real*real + imag*imag;", "Accumulates diagonal covariance."), ("crossImag += ys*xf - xs*yf;", "Matches R(second,first)=x_second*conj(x_first)."), ("#pragma HLS PIPELINE II=1", "Requests one four-lane beat every clock."), ("output.last=(index==15);", "Closes one covariance packet deterministically.")],
         example="4096 samples add 12 accumulator bits. A calibrated 20-bit component produces a 40-bit product, so signed 64-bit accumulators provide comfortable headroom."),
    dict(slug="07-weighted-phase", title="Weighted phase-interferometry seed", image="07-weighted-phase.jpg",
         sources=["DOAEstimator4Ch.m", "estimate_doa_from_covariance_v7.m"],
         intro="All six pair phases are used in a weighted two-parameter least-squares solve. The planar nose array observes Y and Z direction cosines; the known forward hemisphere supplies the positive X component.",
         inputs=[("Hermitian covariance", "Calibrated 4x4 complex matrix"), ("Calibrated positions", "Measured element coordinates")],
         outputs=[("Continuous seed", "Off-grid azimuth and elevation")],
         algorithm=["Read phase and coherence for every unique antenna pair.", "Build a six-row Y/Z baseline matrix.", "Convert coherence into bounded inverse-variance-like weights.", "Solve the weighted 2x2 normal equation.", "Enforce the unit sphere and positive boresight component."],
         code=[("crossValue=covariance(second,first);", "Uses the same sign convention as the source and HLS core."), ("phase(pair)=angle(crossValue);", "Extracts geometric phase."), ("weight=coherence/(1-coherence);", "Downweights unreliable cross products."), ("normal=baseline'*(weight.*baseline);", "Forms the weighted geometry matrix."), ("directionYZ=-(normal\\rightSide)/waveNumber;", "Solves for uy and uz."), ("ux=sqrt(1-uy^2-uz^2);", "Applies the known forward-hemisphere constraint.")],
         example="For azimuth 30 degrees and elevation 15 degrees, [ux,uy,uz] is approximately [0.837, 0.483, 0.259]. The square array directly measures uy and uz and reconstructs positive ux."),
    dict(slug="08-ml-gn-refinement", title="Local ML and Gauss-Newton refinement", image="08-ml-gn-refinement.jpg",
         sources=["DOAEstimator4Ch.m", "estimate_doa_from_covariance_v7.m"],
         intro="The refinement is bounded and hardware predictable. A fixed 36-point rank-one likelihood search secures the local basin, then a fixed power iteration and two limited Gauss-Newton steps remove the remaining grid residue without a general eigendecomposition.",
         inputs=[("WPI seed", "Initial azimuth/elevation"), ("Covariance", "Calibrated spatial statistics")],
         outputs=[("Raw refined DOA", "Continuous measurement before tracking")],
         algorithm=["Evaluate a 3x3 neighborhood at four decreasing step sizes.", "Keep the highest Bartlett/rank-one ML score after each stage.", "Approximate the dominant signal vector with four power iterations.", "Build I-vvH as a rank-one noise projector.", "Run exactly two Gauss-Newton updates, each limited to 0.05 degree."],
         code=[("MLStepSchedule=[.5 .1 .02 .005]", "Provides coarse capture and fine resolution."), ("score=real(a'*R*a)/4;", "Scores a single-source steering candidate."), ("signalVector=R*signalVector;", "One deterministic power-iteration step."), ("noiseProjector=eye(4)-v*v';", "Avoids a full 4x4 eigensolver."), ("gradient=2*real(D'*(Pn*a));", "Computes the local MUSIC derivative."), ("step=min(step,0.05 deg)", "Prevents noisy covariance from causing a large jump.")],
         example="The fixed ML stages evaluate 36 candidates per frame. Two GN iterations add fixed work and can refine between the final 0.005 degree candidate positions."),
    dict(slug="09-attitude-ekf", title="Full-attitude navigation-frame EKF", image="09-attitude-ekf.jpg",
         sources=["body_to_navigation_dcm.m", "DOAEstimator4Ch.m", "verify_full_attitude_geometry.m", "verify_rotating_frame_ekf.m"],
         intro="The array measures direction in the rotating body frame. V7 converts that unit vector with a full yaw-pitch-roll DCM, tracks the world line of sight, projects the state back onto the unit sphere, and converts it back for guidance.",
         inputs=[("Raw body DOA", "Refined measurement"), ("Platform attitude", "Yaw, pitch and roll")],
         outputs=[("Tracked body DOA", "Smoothed bearing for control")],
         algorithm=["Convert azimuth/elevation to a body unit vector.", "Rotate it into navigation coordinates with the ZYX DCM.", "Predict a six-state unit-vector/rate model.", "Update with a 3-D vector measurement using a Joseph covariance form.", "Normalize LOS and remove radial rate, then rotate back to body coordinates."],
         code=[("rotation=body_to_navigation_dcm(yaw,pitch,roll);", "Constructs one orthonormal attitude transform."), ("measurement=rotation*bodyMeasurement;", "Prevents platform motion from appearing as target motion."), ("transition=[I dt*I;0 I];", "Uses a constant LOS-rate process model."), ("gain=P*H'/S;", "Computes the small fixed-size Kalman gain."), ("updated(1:3)=normalize(updated(1:3));", "Enforces the physical unit sphere."), ("bodyEstimate=rotation.'*navigationEstimate;", "Returns the tracked direction to the array frame.")],
         example="A fixed world source observed while yaw changes 38 degrees, pitch changes 16 degrees and roll oscillates 12 degrees should remain stationary inside the navigation-frame EKF."),
    dict(slug="10-platform-guidance", title="Platform guidance and arrival", image="10-platform-guidance.jpg",
         sources=["PlatformDynamics3D.m", "TruthErrorMonitor3D.m", "plot_homing_results.m"],
         intro="The controller uses detection-gated pure pursuit with wrapped azimuth filtering, bounded turn/climb rates and explicit 3-D kinematics. Truth monitoring uses the same full attitude convention but never feeds the estimator.",
         inputs=[("Tracked body DOA", "Azimuth/elevation"), ("DetectionValid", "Candidate gate"), ("Source position", "Used only for simulation arrival/truth")],
         outputs=[("Platform state", "Position, yaw, pitch, roll"), ("Range/Arrived", "Termination signals")],
         algorithm=["Normalize source and platform positions to 1x3.", "Stop immediately when true range is inside the arrival radius.", "Update bearing filters only for valid detections.", "Limit yaw and pitch rates before integrating attitude.", "Integrate the forward velocity vector and repeat the arrival test."],
         code=[("sourcePosition=reshape(sourcePosition,1,3);", "Prevents the previous 3x1/1x3 Simulink expansion bug."), ("arrived=range<=ArrivalRadius;", "Defines an unambiguous stop condition."), ("azInnovation=wrap180(measuredAz-filteredAz);", "Avoids discontinuity at +/-180 degrees."), ("yawRate=max(-limit,min(limit,command/Dt));", "Enforces platform dynamics."), ("velocity=[V*cos(p)*cos(y), ...];", "Constructs the 3-D forward velocity."), ("Position=Position+velocity*Dt;", "Advances one discrete simulation step.")],
         example="At 25 m/s and 0.1 s update time the vehicle advances 2.5 m per step. From the default 602 m range, a nearly direct intercept takes about 24 seconds."),
    dict(slug="11-hil-verification", title="Hardware-in-the-loop verification", image="11-hil-flow.jpg",
         sources=["generate_zcu48dr_hil_vectors.m", "hil_fixed_covariance_reference.m", "run_zcu48dr_hil.m", "HIL_ZU48DR_GUIDE.md"],
         intro="The HIL flow is deliberately separate from the behavioral simulation. MATLAB produces packed AXI input and a bit-accurate golden covariance; the board processes the same frame; MATLAB then requires an exact 16-word match before evaluating the captured DOA.",
         inputs=[("AXI512 stimulus", "1024 beats for 4096 samples"), ("Board capture CSV", "16 signed int64 outputs")],
         outputs=[("HIL report", "Exact integer match, relative error and angular error")],
         algorithm=["Generate a deterministic calibrated-LOS snapshot frame.", "Quantize ADC samples and Q2.14 calibration coefficients.", "Pack four samples per channel into each 512-bit AXI beat.", "Replay through the ZU48DR covariance IP and capture 16 output words.", "Compare exact integers, reconstruct covariance and calculate final DOA."],
         code=[("run_zcu48dr_hil('prepare')", "Creates stimulus, manifest and golden files."), ("word=lane*4+channel", "Matches the HLS unpacking convention."), ("golden=hil_fixed_covariance_reference(...)", "Models every calibration shift and accumulation."), ("run_zcu48dr_hil('compare','capture.csv')", "Loads actual board output."), ("exact=all(captured==golden);", "Makes arithmetic mismatches impossible to hide."), ("Pass=exact && angularError<=0.1", "Checks both digital equivalence and system meaning.")],
         example="Loopback mode verifies only the host parser. A real HIL pass requires a capture produced after programming the ZCU208 and replaying the supplied 1024 AXI beats."),
    dict(slug="12-pl-ps-partition", title="ZU48DR PL/PS implementation partition", image="12-pl-ps-partition.jpg",
         sources=["ACCURACY_AND_HDL_GUIDE.md", "rfsoc_buildkit_overlay/README.md", "rfsoc_buildkit_overlay/ip/custom/doa_covariance_4ch_v4"],
         intro="Continuous high-rate operations remain in programmable logic, while one small covariance packet per estimate moves to the real-time processor. This avoids a large general eigensolver in PL and makes timing and resource use auditable.",
         inputs=[("PL RF stream", "Four coherent channels"), ("Calibration registers", "Coefficients and measured manifold")],
         outputs=[("R5F DOA update", "10 Hz bearing and confidence"), ("A53 telemetry", "Logs, calibration and control")],
         algorithm=["Use RFDC hard blocks and PL for rate conversion and spectral search.", "Gate a selected 4096-sample burst into the II=1 fixed-point covariance core while the continuous search path remains independent.", "Transfer only 16 int64 values per DOA frame.", "Run WPI, fixed ML, bounded GN and EKF on R5F initially.", "Use A53 for supervision, storage and network functions, not hard real-time loops."],
         code=[("PL: 512-bit AXI at 128 MHz", "Carries the complete decimated four-channel stream."), ("PL: covariance packet", "Reduces 4096 samples to 128 bytes."), ("R5F: fixed loop counts", "Provides deterministic compute time."), ("A53: calibration manager", "Updates coefficients after MTS and temperature events."), ("Vivado timing report", "Is required before accepting the PL design."), ("HIL exact comparison", "Is required before accepting numerical equivalence.")],
         example="At ten DOA updates per second, covariance traffic to the processor is only about 1.28 kB/s. The high-rate burden remains in PL where parallel fixed-point arithmetic is appropriate."),
]


def page(block, index):
    previous_link = blocks[index - 1]["slug"] + ".md" if index > 0 else None
    next_link = blocks[index + 1]["slug"] + ".md" if index + 1 < len(blocks) else None
    nav = ["[Master guide](../../REALISTIC_DOA_ENGINEERING_GUIDE.md)"]
    if previous_link:
        nav.append(f"[Previous block]({previous_link})")
    if next_link:
        nav.append(f"[Next block]({next_link})")
    lines = [f"# {index + 1}. {block['title']}", "", " | ".join(nav), "",
             f"![{block['title']}](../diagrams/{block['image']})", "", block["intro"], "",
             "## On this page", "", "- [Inputs and outputs](#inputs-and-outputs)",
             "- [Algorithm](#algorithm)", "- [Code walkthrough](#code-walkthrough)",
             "- [Worked example](#worked-example)", "- [Implementation checks](#implementation-checks)", "",
             "## Source files", ""]
    lines += [f"- `{source}`" for source in block["sources"]]
    lines += ["", "## Inputs and outputs", "", "| Direction | Name | Meaning |", "| --- | --- | --- |"]
    lines += [f"| Input | {name} | {meaning} |" for name, meaning in block["inputs"]]
    lines += [f"| Output | {name} | {meaning} |" for name, meaning in block["outputs"]]
    lines += ["", "## Algorithm", ""]
    lines += [f"{i}. {step}" for i, step in enumerate(block["algorithm"], 1)]
    lines += ["", "## Code walkthrough", "", "The following follows the implementation statement by statement. Short fragments are used so every operation can be mapped back to the source file.", "",
              "| Code statement | What that line does |", "| --- | --- |"]
    lines += [f"| `{code}` | {meaning} |" for code, meaning in block["code"]]
    lines += ["", "## Worked example", "", block["example"], "", "## Implementation checks", "",
              "- Confirm dimensions and sign conventions against the preceding block.",
              "- Run the associated MATLAB regression before generating HDL or deploying software.",
              "- Treat resource, timing and accuracy as unverified until the generated reports or campaign outputs are saved.",
              "- Preserve the calibrated array coordinates and covariance orientation across MATLAB, HLS and processor code.", ""]
    return "\n".join(lines)


for index, block in enumerate(blocks):
    (BLOCKS / f"{block['slug']}.md").write_text(page(block, index), encoding="utf-8")

toc = []
for index, block in enumerate(blocks, 1):
    toc.append(f"| {index} | [{block['title']}](docs/blocks/{block['slug']}.md) | `{', '.join(block['sources'][:2])}` |")

master = f"""# Realistic 0.1-degree 2x2 DOA and ZU48DR engineering guide

This is the entry point for the V7 simulation, implementation partition and HIL verification. Every block below links to a dedicated page containing its JPEG block diagram, inputs/outputs, algorithm, statement-by-statement code explanation, numerical example and implementation checks.

![Complete V7 signal flow](docs/diagrams/01-overall-system.jpg)

## Clickable block index

| # | Block page | Principal source |
| ---: | --- | --- |
{chr(10).join(toc)}

## Header index

- [Accuracy definition](#accuracy-definition)
- [Realism profiles](#realism-profiles)
- [Recommended commands](#recommended-commands)
- [Hardware acceptance gates](#hardware-acceptance-gates)
- [Documentation map](#documentation-map)

## Accuracy definition

The qualified claim remains a 3-D great-circle RMSE no larger than 0.1 degree over 1000 independent estimates at per-channel SNR of at least 15 dB, 4096 coherent snapshots, azimuth -45 to +45 degrees, elevation -35 to +35 degrees, one dominant selected source and a calibrated forward-facing 25 mm planar square array.

V7 adds a separate realistic campaign. It does not redefine FIELD_STRESS failures as passes. Multipath, unstable differential phase, poor MTS, or incorrect manifold calibration can make 0.1 degree physically impossible even when the estimator code is correct.

## Realism profiles

| Profile | Purpose | Expected use |
| --- | --- | --- |
| `IDEAL` | Mathematical sign and geometry checks | Unit tests only |
| `CALIBRATED_LOS` | Small position error, calibrated coupling, residual drift, phase noise, ADC and weak multipath | Qualified accuracy and homing |
| `FIELD_STRESS` | Stronger multipath, coupling residual and thermal drift | Robustness characterization; pass is not forced |

Select the profile in `sim3d_params.m`:

```matlab
P.Realism.Profile = 'CALIBRATED_LOS';
```

## Recommended commands

```matlab
verify_r2024a_setup
run_accuracy_campaign('acceptance')
run_realistic_accuracy_campaign('acceptance')
run_3d_doa_sim
START_HERE

% Separate hardware-in-the-loop flow
run_zcu48dr_hil('prepare')
run_zcu48dr_hil('compare','capture.csv')
```

## Hardware acceptance gates

1. RFDC MTS reports deterministic tile alignment at every boot.
2. Calibration tone residual differential phase and gain meet the stated budget.
3. Vitis HLS C simulation matches `hil_fixed_covariance_reference.m` exactly.
4. HLS synthesis meets the requested II=1 and 128 MHz target.
5. Vivado implementation meets timing in the complete ZCU208 RFDC shell.
6. Board capture matches all 16 covariance integers exactly.
7. Captured covariance produces no more than 0.1 degree error for the supplied HIL frame.
8. A real far-field campaign replaces ideal coordinates with a measured array manifold.

## Documentation map

- [Complete file, function and source-code guide](COMPLETE_FILE_AND_CODE_GUIDE.md)
- [Separate ZU48DR HIL guide](HIL_ZU48DR_GUIDE.md)
- [Accuracy and HDL assumptions](ACCURACY_AND_HDL_GUIDE.md)
- [Generated Simulink model](SIMULINK_MODEL_GUIDE.md)
- [Source waveform parameters](SOURCE_WAVEFORM_PARAMETER_GUIDE.md)
- [V7 change log](CHANGELOG_V7.md)
- [Validation report and evidence boundary](PROJECT_VALIDATION_REPORT.md)
"""
(ROOT / "REALISTIC_DOA_ENGINEERING_GUIDE.md").write_text(master, encoding="utf-8")
print(f"Generated {len(blocks)} block pages and master guide")
