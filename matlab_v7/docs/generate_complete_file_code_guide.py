from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "COMPLETE_FILE_AND_CODE_GUIDE.md"

BLOCKS = [
    ("Project entry, configuration and dashboards", "01-overall-system.jpg", [
        "sim3d_params.m", "START_HERE.m", "run_3d_doa_sim.m",
        "run_3d_doa_sim_compat.m", "run_simulink_homing.m",
        "build_3d_doa_simulink.m", "plot_simulink_results.m",
        "plot_homing_results.m", "doa_3d_gui.m", "doa_3d_gui_update.m"]),
    ("RF source, waveform and propagation", "02-source-propagation.jpg", [
        "SourceModel3D.m", "source_modulation_profile.m",
        "source_modulation_summary.m"]),
    ("Realistic receiver and calibration", "03-realistic-receiver.jpg", [
        "RealisticReceiver4.m", "realism_profile.m",
        "simulate_realistic_snapshots.m", "estimate_multifrequency_calibration.m"]),
    ("PFB search, CFAR and candidate selection", "05-search-detection.jpg", [
        "PFBFFTChannelizer4.m", "SpectrumEstimator4.m",
        "NoiseFloorEstimator1D.m", "CACFAR1D.m", "BinClusterEstimator.m",
        "CandidateSelector.m", "SignalMetricsMonitor.m", "SnapshotDecimator4.m",
        "SyntheticFourChannelSource.m", "doa_search_params.m",
        "run_search_chain_matlab.m", "build_doa_search_model.m"]),
    ("DOA seed and off-grid refinement", "08-ml-gn-refinement.jpg", [
        "DOAEstimator4Ch.m", "estimate_doa_from_covariance_v7.m",
        "body_to_navigation_dcm.m"]),
    ("Tracking, guidance and truth", "10-platform-guidance.jpg", [
        "PlatformDynamics3D.m", "TruthErrorMonitor3D.m"]),
    ("MATLAB verification and accuracy campaigns", "09-attitude-ekf.jpg", [
        "verify_r2024a_setup.m", "verify_doa_direction.m",
        "verify_hybrid_doa_2x2.m", "verify_rotating_frame_ekf.m",
        "verify_full_attitude_geometry.m", "verify_simulink_vector_shapes.m",
        "verify_source_waveforms.m", "verify_multifrequency_calibration.m",
        "run_accuracy_campaign.m", "run_realistic_accuracy_campaign.m",
        "run_fixed_point_input_parity.m"]),
    ("Separate ZCU48DR HIL flow", "11-hil-flow.jpg", [
        "generate_zcu48dr_hil_vectors.m", "hil_fixed_covariance_reference.m",
        "run_zcu48dr_hil.m"]),
    ("MATLAB HDL front-end reference", "04-rfdc-mts-interface.jpg", [
        "ZU48DRChannelizer4.m", "design_pfb_coefficients.m",
        "build_rfsoc_hdl_frontend_model.m", "generate_rfsoc_hdl_frontend.m"]),
    ("Four-sample-per-clock production HLS core", "06-calibration-covariance.jpg", [
        "rfsoc_buildkit_overlay/ip/custom/doa_covariance_4ch_v4/src/doa_covariance_4ch_v4.hpp",
        "rfsoc_buildkit_overlay/ip/custom/doa_covariance_4ch_v4/src/doa_covariance_4ch_v4.cpp",
        "rfsoc_buildkit_overlay/ip/custom/doa_covariance_4ch_v4/tb/doa_covariance_4ch_v4_tb.cpp",
        "rfsoc_buildkit_overlay/ip/custom/doa_covariance_4ch_v4/build_hls.tcl",
        "rfsoc_buildkit_overlay/ip/custom/doa_covariance_4ch_v4/Makefile"]),
    ("Legacy scalar HLS compatibility reference", "06-calibration-covariance.jpg", [
        "rfsoc_buildkit_overlay/ip/custom/doa_covariance_4ch/src/doa_covariance_4ch.cpp",
        "rfsoc_buildkit_overlay/ip/custom/doa_covariance_4ch/build_hls.tcl",
        "rfsoc_buildkit_overlay/ip/custom/doa_covariance_4ch/Makefile"]),
    ("Documentation generators", "12-pl-ps-partition.jpg", [
        "docs/generate_block_diagrams.py", "docs/generate_block_pages.py",
        "docs/generate_complete_file_code_guide.py"]),
]

PURPOSES = {
    "sim3d_params.m": "Creates the authoritative P structure for source, array, receiver, estimator, navigation, accuracy and simulation settings.",
    "START_HERE.m": "Runs verification, builds the executable Simulink model and launches the closed-loop simulation.",
    "run_3d_doa_sim.m": "Executes the complete MATLAB-only RF search, DOA, EKF and homing loop.",
    "run_3d_doa_sim_compat.m": "Small launcher used after restarting MATLAB when an older System object was cached.",
    "run_simulink_homing.m": "Builds, simulates and plots the generated Simulink model in one command.",
    "build_3d_doa_simulink.m": "Programmatically creates every Simulink block, property, connection, display and log.",
    "plot_simulink_results.m": "Reads SimulationOutput logs safely and creates the final accuracy and RF dashboards.",
    "plot_homing_results.m": "Creates the common nine-panel trajectory, range, DOA, signal and attitude dashboard.",
    "doa_3d_gui.m": "Creates the optional live MATLAB GUI used by the scripted homing simulation.",
    "doa_3d_gui_update.m": "Updates live GUI plots without rebuilding the window.",
    "SourceModel3D.m": "Generates waveform, path loss, full-attitude array steering and reflected propagation paths.",
    "source_modulation_profile.m": "Returns the complete parameter set for the selected waveform family.",
    "source_modulation_summary.m": "Formats the active waveform parameters for console and dashboard text.",
    "RealisticReceiver4.m": "Models coupling, receiver mismatch, skew, drift, noise, AGC, DC, clipping and ADC quantization.",
    "realism_profile.m": "Defines IDEAL, CALIBRATED_LOS and FIELD_STRESS physical/calibration assumptions.",
    "simulate_realistic_snapshots.m": "Creates controlled-SNR Monte-Carlo snapshots using the same physical impairment model.",
    "estimate_multifrequency_calibration.m": "Estimates relative gain, center phase and time skew and packs PL Q2.14 corrections.",
    "PFBFFTChannelizer4.m": "Behavioral four-channel polyphase FFT channelizer.",
    "SpectrumEstimator4.m": "Calculates smoothed per-bin and summed power plus the RF frequency axis.",
    "NoiseFloorEstimator1D.m": "Estimates robust local/global spectral noise using a sliding median.",
    "CACFAR1D.m": "Applies one-dimensional cell-averaging CFAR thresholds.",
    "BinClusterEstimator.m": "Merges detected bins and estimates cluster center, width and peak power.",
    "CandidateSelector.m": "Selects a source cluster using bandwidth and SNR rules.",
    "SignalMetricsMonitor.m": "Formats peak power, SNR, RF center and bandwidth for displays/logging.",
    "SnapshotDecimator4.m": "Selects the fixed 4096 coherent spatial snapshots used by DOA.",
    "SyntheticFourChannelSource.m": "Deterministic four-channel source for isolated search-chain testing.",
    "doa_search_params.m": "Compact parameter script for the standalone search-chain example.",
    "run_search_chain_matlab.m": "Runs the search/detection blocks without navigation.",
    "build_doa_search_model.m": "Builds a focused Simulink search-chain model.",
    "DOAEstimator4Ch.m": "Implements calibration, covariance, six-baseline WPI, bounded ML/GN and navigation-frame EKF.",
    "estimate_doa_from_covariance_v7.m": "Processor-side reference that estimates DOA directly from a captured PL covariance packet.",
    "body_to_navigation_dcm.m": "Returns the project ZYX yaw/pitch/roll body-to-navigation direction-cosine matrix.",
    "PlatformDynamics3D.m": "Implements detection-gated guidance, rate limits, 3-D kinematics, roll and arrival.",
    "TruthErrorMonitor3D.m": "Computes true body-frame direction and azimuth/elevation/great-circle errors.",
    "verify_r2024a_setup.m": "Runs the complete constructor, geometry, calibration, waveform and toolbox smoke suite.",
    "verify_doa_direction.m": "Checks estimator sign at positive and negative directions.",
    "verify_hybrid_doa_2x2.m": "Checks exact deterministic 2x2 geometry and calibration at representative angles.",
    "verify_rotating_frame_ekf.m": "Checks that platform rotation is not interpreted as source motion.",
    "verify_full_attitude_geometry.m": "Checks DCM orthogonality and yaw/pitch/roll truth consistency.",
    "verify_simulink_vector_shapes.m": "Prevents the earlier 3x1/1x3 implicit-expansion and circling bug.",
    "verify_source_waveforms.m": "Exercises all documented waveform modes and verifies finite four-channel IQ.",
    "verify_multifrequency_calibration.m": "Regression for gain, phase and picosecond time-skew estimation.",
    "run_accuracy_campaign.m": "Runs the controlled 1000-trial 0.1-degree baseline campaign.",
    "run_realistic_accuracy_campaign.m": "Runs the calibrated-LOS array/RF/ADC Monte-Carlo campaign.",
    "run_fixed_point_input_parity.m": "Measures DOA degradation caused by ADC input quantization.",
    "generate_zcu48dr_hil_vectors.m": "Writes packed AXI512 stimulus, calibration registers, manifest and golden covariance.",
    "hil_fixed_covariance_reference.m": "Bit-accurate MATLAB model of HLS calibration shifts and covariance accumulators.",
    "run_zcu48dr_hil.m": "Provides separate prepare, host-loopback and real board-capture comparison modes.",
    "ZU48DRChannelizer4.m": "Synthesizable four-channel DSP HDL channelizer wrapper.",
    "design_pfb_coefficients.m": "Creates one shared fixed-point prototype filter for coherent HDL paths.",
    "build_rfsoc_hdl_frontend_model.m": "Builds the MATLAB HDL reference front-end model for ZCU208.",
    "generate_rfsoc_hdl_frontend.m": "Launches HDL Coder for the reference channelizer subsystem.",
    "rfsoc_buildkit_overlay/ip/custom/doa_covariance_4ch_v4/src/doa_covariance_4ch_v4.hpp": "Declares AXI types and the production HLS top-level interface.",
    "rfsoc_buildkit_overlay/ip/custom/doa_covariance_4ch_v4/src/doa_covariance_4ch_v4.cpp": "Four-sample-per-clock calibration and covariance HLS implementation.",
    "rfsoc_buildkit_overlay/ip/custom/doa_covariance_4ch_v4/tb/doa_covariance_4ch_v4_tb.cpp": "Self-checking 4096-sample C testbench for all 16 outputs and TLAST.",
    "rfsoc_buildkit_overlay/ip/custom/doa_covariance_4ch_v4/build_hls.tcl": "Runs C simulation, synthesis and IP export for XCZU48DR at 128 MHz.",
    "rfsoc_buildkit_overlay/ip/custom/doa_covariance_4ch_v4/Makefile": "One-command Vitis HLS build entry point.",
    "rfsoc_buildkit_overlay/ip/custom/doa_covariance_4ch/src/doa_covariance_4ch.cpp": "Legacy one-sample/128-bit covariance reference; not the production-rate core.",
    "rfsoc_buildkit_overlay/ip/custom/doa_covariance_4ch/build_hls.tcl": "Legacy scalar-core HLS build script.",
    "rfsoc_buildkit_overlay/ip/custom/doa_covariance_4ch/Makefile": "Legacy scalar-core make wrapper.",
    "docs/generate_block_diagrams.py": "Recreates the twelve 1600x440 JPEG block diagrams.",
    "docs/generate_block_pages.py": "Recreates the master guide and twelve individual block pages.",
    "docs/generate_complete_file_code_guide.py": "Recreates this complete file/function/source-code guide.",
}

EDIT_NOTES = {
    "sim3d_params.m": "Edit this file first for mission and receiver settings. Keep the baseline <= lambda/2 assertion valid.",
    "realism_profile.m": "Change impairment budgets here; do not hide FIELD_STRESS failures by loosening the acceptance threshold.",
    "DOAEstimator4Ch.m": "Keep loop counts bounded for the processor/HDL implementation and preserve covariance sign convention.",
    "build_3d_doa_simulink.m": "Regenerate the SLX after changing System object ports or nontunable properties.",
    "rfsoc_buildkit_overlay/ip/custom/doa_covariance_4ch_v4/src/doa_covariance_4ch_v4.cpp": "Do not change packing or conjugation without updating MATLAB HIL reference and capture software together.",
    "run_zcu48dr_hil.m": "Loopback is host-only; only compare mode with a board-produced CSV is HIL evidence.",
}

LANGUAGE = {".m": "matlab", ".cpp": "cpp", ".hpp": "cpp", ".tcl": "tcl", ".py": "python"}


def anchor(path):
    return "file-" + re.sub(r"[^a-z0-9]+", "-", path.lower()).strip("-")


def first_comment(lines, suffix):
    marks = ("%",) if suffix == ".m" else (("//", "/*") if suffix in (".cpp", ".hpp") else ("#",))
    for line in lines[:40]:
        stripped = line.strip()
        if any(stripped.startswith(mark) for mark in marks):
            value = stripped.lstrip("%/#* ").strip()
            if value:
                return value
    return "See the purpose and function map below."


def definitions(lines, suffix):
    found = []
    if suffix in (".cpp", ".hpp"):
        index = 0
        while index < len(lines):
            start = index
            combined = lines[index].strip()
            if "(" not in combined or combined.startswith(("#", "if ", "for ", "while ", "switch ", "return ")):
                index += 1
                continue
            balance = combined.count("(") - combined.count(")")
            while balance > 0 and index + 1 < len(lines) and index - start < 10:
                index += 1
                part = lines[index].strip()
                combined += " " + part
                balance += part.count("(") - part.count(")")
            match = re.match(r'^(?:extern\s+"C"\s+)?(?:static\s+)?[\w:<>,&* ]+\s+([A-Za-z_]\w*)\s*\(', combined)
            if match and match.group(1) not in {"if", "for", "while", "switch", "catch"}:
                found.append((start + 1, "C/C++ function", combined.rstrip(" {;")))
            index += 1
        return found
    for number, line in enumerate(lines, 1):
        stripped = line.strip()
        if suffix == ".m":
            if stripped.startswith("classdef "):
                found.append((number, "class", stripped))
            elif stripped.startswith("function "):
                found.append((number, "function/method", stripped))
        elif suffix == ".py" and stripped.startswith(("def ", "class ")):
            found.append((number, "Python definition", stripped))
        elif suffix == ".tcl" and stripped.startswith("proc "):
            found.append((number, "Tcl procedure", stripped))
        elif Path("x/" + stripped).name.endswith(":") and "=" not in stripped:
            found.append((number, "Make target", stripped))
    return found


def definition_role(kind, definition, relative):
    if kind == "class":
        return "Declares the System object/class that owns this block's configuration, state and execution methods."
    if kind == "Make target":
        return "Defines a command-line build target for synthesis/export or cleanup."
    match = re.search(r"function\s+(?:\[[^]]+\]\s*=\s*|[\w,]+\s*=\s*)?([A-Za-z]\w*)", definition)
    if not match and kind == "C/C++ function":
        candidates = re.findall(r"([A-Za-z_]\w*)\s*\(", definition)
        name = candidates[-1] if candidates else "function"
    elif not match and kind == "Python definition":
        py_match = re.search(r"(?:def|class)\s+([A-Za-z_]\w*)", definition)
        name = py_match.group(1) if py_match else "definition"
    else:
        name = match.group(1) if match else "function"
    roles = {
        "setupImpl": "Runs once when the System object locks; validates configuration and creates persistent processing resources.",
        "stepImpl": "Runs once per input frame and implements the block's main signal-processing algorithm.",
        "resetImpl": "Restores persistent algorithm/tracker/filter state to its initial condition.",
        "releaseImpl": "Releases locked child System objects and hardware/software resources.",
        "getOutputSizeImpl": "Declares fixed Simulink output dimensions for model compilation.",
        "getOutputDataTypeImpl": "Declares output numeric types for Simulink propagation.",
        "isOutputComplexImpl": "Declares whether each output is real or complex.",
        "isOutputFixedSizeImpl": "Declares that output dimensions remain fixed while running.",
        "getInputNamesImpl": "Assigns readable names to generated MATLAB System block input ports.",
        "getOutputNamesImpl": "Assigns readable names to generated MATLAB System block output ports.",
        "getIconImpl": "Builds the label shown on the generated Simulink block.",
        "weightedPhaseSeed": "Solves the six-baseline coherence-weighted phase equations for a continuous initial direction.",
        "localMLRefinement": "Evaluates the fixed 36-candidate local likelihood schedule around the WPI seed.",
        "gaussNewtonPolish": "Applies the fixed power iteration and bounded Gauss-Newton off-grid correction.",
        "unitVectorEKF": "Transforms the measurement to navigation coordinates, updates the six-state EKF and returns body DOA.",
        "steeringVector": "Calculates the calibrated four-element complex steering vector for a candidate direction.",
        "musicDOA": "Runs the optional legacy full-grid MUSIC estimator.",
        "mvdrDOA": "Runs the optional legacy full-grid MVDR estimator.",
        "applyCalibration": "Applies inverse gain/phase correction and the calibrated coupling-decoupling matrix.",
        "initializeState": "Initializes platform position, attitude and navigation-filter state.",
        "wrap180": "Wraps an angle into the half-open -180 to +180 degree interval.",
        "body_to_navigation_dcm": "Creates the full ZYX body-to-navigation rotation matrix.",
        "readLoggedSeries": "Finds a named Simulink log and normalizes its time/data dimensions.",
        "covarianceFromValues": "Reconstructs the Hermitian 4x4 covariance from the 16-word HIL packet.",
        "steeringVector": "Calculates a four-channel steering vector from azimuth/elevation and calibrated positions.",
        "low16": "Extracts and sign-interprets the low 16-bit half-word.",
        "high16": "Extracts and sign-interprets the high 16-bit half-word.",
        "calibrate": "Applies one packed complex Q2.14 channel correction using fixed-point arithmetic.",
        "doa_covariance_4ch_v4": "Production HLS top: accepts AXI512 frames, calibrates four lanes/channels and emits covariance.",
        "main": "Runs the self-checking C testbench and returns nonzero if any covariance/TLAST comparison fails.",
        "render": "Draws and saves one standardized JPEG block diagram.",
        "page": "Builds one block-level Markdown page from its structured metadata.",
        "anchor": "Converts a source path/title into a stable Markdown anchor identifier.",
        "definitions": "Extracts classes, functions, methods and build targets with their source line numbers.",
        "key_lines": "Selects representative interface, algorithm and configuration lines for explanation.",
    }
    if name in roles:
        return roles[name]
    if relative.endswith(".m") and definition.lstrip().startswith("function ") and Path(relative).stem == name:
        return PURPOSES.get(relative, "Implements the file's public MATLAB entry point.")
    if name.startswith("verify_"):
        return "Runs the named regression and asserts its pass/fail tolerance."
    if name.startswith("build_"):
        return "Creates and wires the named generated model or build artifact."
    if name.startswith("run_"):
        return "Executes the named simulation, campaign or verification flow."
    if name.startswith("get") or name.startswith("is"):
        return "Provides metadata or a derived value used by the surrounding block."
    return f"Implements the `{name}` helper used by this file; inputs, outputs and operations are visible in the signature and source below."


def explain_line(line):
    s = line.strip()
    if s.startswith("classdef "):
        return "Declares the MATLAB class and its base type."
    if s.startswith("function "):
        return "Declares a callable function or System object method, including its inputs and outputs."
    if s.startswith("properties"):
        return "Begins a property group; nontunable values become fixed after System object setup."
    if s.startswith("methods"):
        return "Begins a method group; protected methods define System object execution behavior."
    if "run('sim3d_params.m')" in s:
        return "Loads the single authoritative project parameter structure P."
    if s.startswith("assert(") or s.startswith("validateattributes("):
        return "Rejects an invalid dimension, type, geometry or configuration before processing."
    if s.startswith("for ") or s.startswith("for("):
        return "Begins a bounded loop over samples, channels, candidates or trials."
    if s.startswith("if "):
        return "Applies the stated runtime condition without changing the defined interface."
    if s.startswith("switch ") or s.startswith("case "):
        return "Selects the requested algorithm, waveform, mode or profile."
    if "covariance" in s.lower():
        return "Creates, conditions or consumes the four-channel spatial covariance matrix."
    if "steering" in s.lower() or "direction" in s.lower():
        return "Computes an array direction/steering quantity using the calibrated geometry."
    if "#pragma HLS PIPELINE" in s:
        return "Requests a pipelined hardware loop; the target is one 512-bit beat per clock."
    if "#pragma HLS UNROLL" in s:
        return "Replicates this bounded loop in parallel hardware."
    if s.startswith("#pragma HLS INTERFACE"):
        return "Defines an AXI-Stream or AXI-Lite hardware port."
    if s.startswith("add_line("):
        return "Connects two generated Simulink block ports."
    if "add_block(" in s or "addSystem(" in s:
        return "Creates or configures a generated Simulink block."
    if s.startswith("set_part"):
        return "Targets the XCZU48DR device used by the ZCU208."
    if s.startswith("create_clock"):
        return "Sets the requested HLS clock period."
    if s.startswith("csim_design"):
        return "Runs the self-checking C simulation before synthesis."
    if s.startswith("csynth_design"):
        return "Synthesizes the C++ into an RTL architecture and reports timing/resources."
    if s.startswith("export_design"):
        return "Exports the synthesized RTL as an IP-catalog component."
    if "vitis_hls" in s:
        return "Invokes Vitis HLS with the supplied build script."
    if s.startswith("error(") or s.startswith("warning("):
        return "Reports a configuration, accuracy or runtime failure explicitly."
    if s.startswith("fprintf("):
        return "Prints a traceable status, metric or next command."
    if "=" in s:
        return "Assigns the left-hand variable/property from the expression on the right."
    return "Executes this control, function-call or interface statement in source order."


def key_lines(lines):
    declarations = []
    algorithm = []
    assignments = []
    tokens = ("run('sim3d_params.m')", "assert(", "covariance", "steering",
              "direction", "#pragma HLS", "add_line(", "add_block(", "set_part",
              "create_clock", "csim_design", "csynth_design", "export_design",
              "vitis_hls", "switch ", "case ", "polyfit(", "acosd(", "angle(")
    for number, line in enumerate(lines, 1):
        stripped = line.strip()
        if not stripped or stripped.startswith(("%", "//", "/*", "*")):
            continue
        if stripped.startswith(("classdef ", "function ", "extern \"C\"", "def ", "class ")):
            declarations.append((number, stripped))
        if any(token in stripped for token in tokens):
            algorithm.append((number, stripped))
        if "=" in stripped and not stripped.startswith(("if ", "while ", "#")):
            assignments.append((number, stripped))
    chosen = declarations[:8] + algorithm[:12] + assignments[:8]
    unique = []
    seen = set()
    for item in chosen:
        if item[0] not in seen:
            unique.append(item)
            seen.add(item[0])
    return sorted(unique, key=lambda item: item[0])[:24]


def escape_table(value):
    return value.replace("|", "\\|").replace("`", "\\`")


all_files = [path for _, _, paths in BLOCKS for path in paths]
assert len(all_files) == len(set(all_files)), "A source file appears in more than one block."
for relative in all_files:
    assert (ROOT / relative).is_file(), f"Missing source file: {relative}"

lines_out = [
    "# Complete V7 file, function and source-code guide",
    "",
    "This is the single-document code reference requested for the realistic 2x2 DOA and ZU48DR HIL project. It starts with the overall project diagram, then provides a clickable block/file index. Every distributed implementation source appears once with its purpose, edit guidance, definitions, important-line explanation, and complete source code.",
    "",
    "![Overall V7 project block diagram](docs/diagrams/01-overall-system.jpg)",
    "",
    "## Document header index",
    "",
    "- [How to use this guide](#how-to-use-this-guide)",
    "- [Clickable block and file index](#clickable-block-and-file-index)",
]
for index, (title, _, _) in enumerate(BLOCKS, 1):
    lines_out.append(f"- [Block {index}: {title}](#block-{index}-{anchor(title)[5:]})")

lines_out += [
    "",
    "## How to use this guide",
    "",
    "- Start with `sim3d_params.m`, then follow the blocks in numeric order.",
    "- The definition table identifies every class, MATLAB function/method, C++ function, Tcl procedure or Make target and its source line.",
    "- The important-line table explains the lines that determine interfaces, geometry, covariance sign, bounded loops, verification and hardware synthesis.",
    "- Expand **Complete source code** to inspect or copy the exact distributed file.",
    "- Line numbers refer to this V7 delivery. Regenerate this document after code edits with `python3 docs/generate_complete_file_code_guide.py`.",
    "- Behavioral source, GUI and vehicle dynamics are simulation code. Only explicitly identified HDL/HLS blocks are intended for PL synthesis.",
    "",
    "## Clickable block and file index",
    "",
]

for block_index, (title, _, paths) in enumerate(BLOCKS, 1):
    lines_out += [f"### Block {block_index}: {title}", ""]
    for path in paths:
        lines_out.append(f"- [`{path}`](#{anchor(path)})")
    lines_out.append("")

for block_index, (title, image, paths) in enumerate(BLOCKS, 1):
    block_anchor = f"block-{block_index}-{anchor(title)[5:]}"
    lines_out += [f'<a id="{block_anchor}"></a>', "", f"# Block {block_index}: {title}", "",
                  f"![{title}](docs/diagrams/{image})", "",
                  f"This block contains {len(paths)} implementation source file(s). Use the file links below to jump directly to the code explanation.", ""]
    lines_out += [f"- [`{path}`](#{anchor(path)})" for path in paths]
    lines_out.append("")
    for relative in paths:
        path = ROOT / relative
        text = path.read_text(encoding="utf-8", errors="replace")
        source_lines = text.splitlines()
        suffix = path.suffix.lower()
        language = LANGUAGE.get(suffix, "makefile" if path.name == "Makefile" else "text")
        purpose = PURPOSES.get(relative, first_comment(source_lines, suffix))
        defs = definitions(source_lines, suffix)
        keys = key_lines(source_lines)
        lines_out += [f'<a id="{anchor(relative)}"></a>', "", f"## File: `{relative}`", "",
                      "### Purpose", "", purpose, "",
                      "### Where it runs", ""]
        if "rfsoc_buildkit_overlay" in relative:
            location = "Vitis HLS / programmable-logic build flow."
        elif relative.endswith(("ZU48DRChannelizer4.m", "build_rfsoc_hdl_frontend_model.m", "generate_rfsoc_hdl_frontend.m", "design_pfb_coefficients.m")):
            location = "MATLAB/DSP HDL reference and HDL Coder flow."
        elif relative.startswith("docs/"):
            location = "Documentation-generation host utility; not part of runtime processing."
        else:
            location = "MATLAB R2024a behavioral, processor-reference or verification environment."
        lines_out += [location, "", "### Editing guidance", "",
                      EDIT_NOTES.get(relative, "Edit only with the interfaces, dimensions and conventions in the surrounding block preserved."), "",
                      f"### Size", "", f"{len(source_lines)} source lines.", "",
                      "### Functions, classes and build targets", ""]
        if defs:
            lines_out += ["| Line | Kind | Definition | What the function/definition does |", "| ---: | --- | --- | --- |"]
            for number, kind, definition in defs:
                role = definition_role(kind, definition, relative)
                lines_out.append(f"| {number} | {kind} | `{escape_table(definition)}` | {role} |")
        else:
            lines_out.append("This is an execution/configuration script and does not declare a separate function or class.")
        lines_out += ["", "### Important code lines explained", "",
                      "| Line | Source statement | Function of the line |", "| ---: | --- | --- |"]
        for number, statement in keys:
            shortened = statement if len(statement) <= 150 else statement[:147] + "..."
            lines_out.append(f"| {number} | `{escape_table(shortened)}` | {explain_line(statement)} |")
        lines_out += ["", "### Complete source code", "", "<details>",
                      f"<summary>Open the complete {relative} source</summary>", "", f"```{language}",
                      text.rstrip(), "```", "", "</details>", "", "[Back to the document index](#document-header-index)", ""]

lines_out += [
    "# Documentation-only files",
    "",
    "The following Markdown/JPEG artifacts do not execute, so their contents are not duplicated as source code here:",
    "",
    "- `REALISTIC_DOA_ENGINEERING_GUIDE.md`: illustrated block-level operating guide.",
    "- `HIL_ZU48DR_GUIDE.md`: board integration and capture procedure.",
    "- `PROJECT_VALIDATION_REPORT.md`: completed checks and evidence boundary.",
    "- `docs/blocks/*.md`: twelve focused block pages.",
    "- `docs/diagrams/*.jpg`: twelve block diagrams.",
    "- README, changelog and historical reference documents.",
    "",
]

OUTPUT.write_text("\n".join(lines_out), encoding="utf-8")
print(f"Generated {OUTPUT.name}: {len(all_files)} source files, {len(lines_out)} document records")
