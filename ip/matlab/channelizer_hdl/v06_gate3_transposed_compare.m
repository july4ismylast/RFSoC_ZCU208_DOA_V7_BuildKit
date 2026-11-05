function v06_gate3_transposed_compare()
%V06_GATE3_TRANSPOSED_COMPARE Freeze transposed channelizer numerics.
%
% Stage V06 Gate 3 is MATLAB-only.  It does not generate HDL, package
% IP, open Vivado, or modify a block design.  The DUT is the same
% ZU48DRChannelizer wrapper and exact production-size configuration
% used for the transposed Gate-1 RTL and Gate-2T OOC synthesis:
%
%   * 1024 bands, SSR-8, 12 taps/band (12,288 coefficients), 100 dB;
%   * Direct form transposed, Normalize=false;
%   * signed 16-bit/fraction-15 complex input;
%   * signed 26-bit/fraction-24 complex output.
%
% The reference is a floating-point dsp.Channelizer with the same
% prototype design and decimation factor 1024.  Both objects receive
% exactly the same quantized sample values: the DUT receives them as
% fi data and the reference receives double(fi data).
%
% Sixteen deterministic tones are placed exactly on channel centres
% across DC/Nyquist, positive/negative frequencies, snapshot beats
% and all eight SSR lanes.  Forty snapshots are collected, so the
% comparison runs well beyond the 12-snapshot prototype-fill time.
% Startup snapshots are discarded before steady-state gain/phase are
% measured.
%
% R2024a has no dsphdl.Channelizer PreservePhase property.  MathWorks'
% documented sample-alignment method is therefore reproduced in the
% primary run by prepending NumFrequencyBands-1 zero samples to the
% DUT stream.  A constrained search then determines the snapshot
% offset, the reference-column map (identity or a 512-column circular
% shift), and the sign of the external per-bin phase correction
% exp(+/-j*2*pi*k/1024).  A no-pad DUT run is also logged as a
% diagnostic.  The production stream does not have to insert those
% one-time alignment zeros if all four hardware channels remain
% bit-identical; Gate 3 records the resulting common phase relation.
%
% Report:
%   <repo>/build/output/v06_gate3_transposed_numerics.rpt

numBands = env_integer('CHANNELIZER_NUM_BANDS', 1024);
ssr = env_integer('WIDEBAND_SAMPLES_PER_CLOCK', 8);
tapsPerBand = env_integer('V06_TAPS_PER_BAND', ...
    env_integer('CHANNELIZER_TAPS_PER_BAND', 12));
stopbandDb = env_integer('V06_STOPBAND_DB', ...
    env_integer('CHANNELIZER_STOPBAND_DB', 100));
normalizeFlag = env_integer('V06_NORMALIZE', ...
    env_integer('CHANNELIZER_NORMALIZE', 0));
snapshotsToCollect = env_integer('V06_GATE3_SNAPSHOTS', 40);
discardSnapshots = env_integer('V06_GATE3_DISCARD_SNAPSHOTS', 16);
filterStructureChoice = env_choice('V06_FILTER_STRUCTURE', ...
    env_choice('CHANNELIZER_FILTER_STRUCTURE', 'transposed', ...
        {'systolic', 'transposed'}), {'systolic', 'transposed'});
switch filterStructureChoice
    case 'systolic'
        filterStructure = 'Direct form systolic';
    case 'transposed'
        filterStructure = 'Direct form transposed';
end

% Fixed V06 production assumptions used only to report physical
% frequencies.  The numerical comparison itself is sample-rate
% independent.
complexSampleRateHz = 2.0e9;
rfCentreHz = 3.0e9;
binSpacingHz = complexSampleRateHz / numBands;

% Exact-bin tones.  Bins >=512 are negative frequencies in natural
% FFT order.  The set covers beats/lanes across the whole serialized
% 1024-output snapshot, including bins adjacent to DC and Nyquist.
toneBins = [1 18 35 68 133 198 255 320 ...
    447 511 514 645 770 900 1000 1023];
numTones = numel(toneBins);
toneRelativeAmplitudes = 0.82 + 0.03 * (0:(numTones - 1));
tonePhasesRad = mod(0.731 * (0:(numTones - 1)) .^ 2 + ...
    0.193 * (0:(numTones - 1)), 2 * pi);

% Gate 3 acceptance thresholds.  They are intentionally recorded in
% the report so a FAIL can be reviewed against the measured values
% rather than silently retuned.
alignmentNrmseLimit = 0.02;
candidateSeparationMinimum = 1.5;
steadyNrmseLimit = 0.02;
steadyCorrelationMinimum = 0.9995;
globalGainMagnitudeMinimum = 0.98;
globalGainMagnitudeMaximum = 1.02;
globalGainPhaseLimitDeg = 2.0;
toneGainResidualLimit = 0.03;
tonePhaseResidualLimitDeg = 3.0;
steadyMagnitudeCvLimit = 0.01;
steadyPhaseCoherenceMinimum = 0.999;
toneNeighbourRatioMinimum = 10.0;

scriptDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(fileparts(fileparts(scriptDir)));
reportDir = fullfile(repoRoot, 'build', 'output');
if ~exist(reportDir, 'dir')
    mkdir(reportDir);
end
reportFile = fullfile(reportDir, 'v06_gate3_transposed_numerics.rpt');
fid = fopen(reportFile, 'w');
if fid < 0
    error('V06:ReportOpenFailed', 'Cannot open Gate-3 report: %s', reportFile);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
log_line = @(varargin) v06_log(fid, sprintf(varargin{:}));

gate0ReportFile = fullfile(reportDir, ...
    'v06_channelizer_probe_transposed.rpt');
gate1ReportFile = fullfile(reportDir, ...
    'v06_gate1_hdl_generation_transposed.rpt');
gate2tReportFile = fullfile(reportDir, ...
    'v06_gate2t_transposed_ooc_synthesis.rpt');
generatedTopFile = fullfile(scriptDir, 'hdl_prj', ...
    'hdlsrc_transposed', 'zu48dr_channelizer_ip', 'Channelizer_DUT.v');

log_line('# V06 Gate 3: transposed numerical ordering/scaling/phase');
log_line('GATE3_SCRIPT_REVISION=1-transposed-reference');
log_line('MATLAB_VERSION=%s', version);
log_line('NUM_BANDS=%d', numBands);
log_line('SSR_SAMPLES_PER_CYCLE=%d', ssr);
log_line('TAPS_PER_BAND=%d', tapsPerBand);
log_line('STOPBAND_DB=%d', stopbandDb);
log_line('NORMALIZE=%d', normalizeFlag);
log_line('FILTER_STRUCTURE_CHOICE=%s', filterStructureChoice);
log_line('FILTER_STRUCTURE=%s', filterStructure);
log_line('SNAPSHOTS_TO_COLLECT=%d', snapshotsToCollect);
log_line('DISCARD_STARTUP_SNAPSHOTS=%d', discardSnapshots);
log_line('COMPLEX_SAMPLE_RATE_HZ=%.12g', complexSampleRateHz);
log_line('RF_CENTRE_HZ=%.12g', rfCentreHz);
log_line('BIN_SPACING_HZ=%.12g', binSpacingHz);
log_line('TONE_COUNT=%d', numTones);
log_line('TONE_BINS0=%s', format_integer_list(toneBins));
log_line('MAX_ALIGNMENT_NRMSE=%.12g', alignmentNrmseLimit);
log_line('MIN_CANDIDATE_SEPARATION=%.12g', candidateSeparationMinimum);
log_line('MAX_STEADY_NRMSE=%.12g', steadyNrmseLimit);
log_line('MIN_STEADY_CORRELATION=%.12g', steadyCorrelationMinimum);
log_line('GLOBAL_GAIN_MAGNITUDE_RANGE=[%.12g %.12g]', ...
    globalGainMagnitudeMinimum, globalGainMagnitudeMaximum);
log_line('MAX_GLOBAL_GAIN_PHASE_DEG=%.12g', globalGainPhaseLimitDeg);
log_line('MAX_TONE_GAIN_RESIDUAL_FRACTION=%.12g', ...
    toneGainResidualLimit);
log_line('MAX_TONE_PHASE_RESIDUAL_DEG=%.12g', ...
    tonePhaseResidualLimitDeg);
log_line('GATE0_REPORT=%s', gate0ReportFile);
log_line('GATE1_REPORT=%s', gate1ReportFile);
log_line('GATE2T_REPORT=%s', gate2tReportFile);
log_line('GENERATED_TOP=%s', generatedTopFile);
log_line('REPORT=%s', reportFile);

try
    if exist('dsphdl.Channelizer', 'class') ~= 8
        error('V06:MissingDSPHDL', ...
            'dsphdl.Channelizer is not available; DSP HDL Toolbox is required.');
    end
    if exist('dsp.Channelizer', 'class') ~= 8
        error('V06:MissingDSPChannelizer', ...
            'dsp.Channelizer is not available; DSP System Toolbox is required.');
    end

    % Gate 3 is defined only for the exact production-size transposed
    % configuration already proved by Gate 0/Gate 1/Gate 2T.
    if numBands ~= 1024 || ssr ~= 8 || tapsPerBand ~= 12 || ...
            stopbandDb ~= 100 || normalizeFlag ~= 0 || ...
            ~strcmp(filterStructureChoice, 'transposed')
        error('V06:Gate3Configuration', ...
            ['Gate 3 requires 1024 bands, SSR-8, 12 taps/band, ' ...
             '100 dB, Normalize=false and Direct form transposed. ' ...
             'Run: make -C ip/matlab/channelizer_hdl gate3-transposed']);
    end
    if snapshotsToCollect < 32 || discardSnapshots < 12 || ...
            discardSnapshots + 8 > snapshotsToCollect
        error('V06:Gate3SnapshotCount', ...
            ['Gate 3 requires at least 32 snapshots, at least 12 ' ...
             'discarded startup snapshots, and at least 8 steady snapshots.']);
    end

    gate0Text = require_report(gate0ReportFile, 'transposed Gate 0');
    require_contains(gate0Text, 'V06 CHANNELIZER PROBE RESULT=PASS', ...
        'transposed Gate 0 PASS');
    require_contains(gate0Text, ...
        'FILTER_STRUCTURE=Direct form transposed', ...
        'transposed Gate 0 architecture');
    gate0Latency = str2double(report_value(gate0Text, ...
        'GETLATENCY_CYCLES'));
    gate0MeasuredLatency = str2double(report_value(gate0Text, ...
        'MEASURED_LATENCY_CYCLES'));
    log_line('GATE0_GETLATENCY_CYCLES=%.12g', gate0Latency);
    log_line('GATE0_MEASURED_LATENCY_CYCLES=%.12g', ...
        gate0MeasuredLatency);
    if gate0Latency ~= 351 || gate0MeasuredLatency ~= 351
        error('V06:Gate3Gate0Latency', ...
            'Transposed Gate-0 latency is not the proved 351 cycles.');
    end

    gate1Text = require_report(gate1ReportFile, 'transposed Gate 1');
    require_contains(gate1Text, ...
        'V06 GATE1 HDL GENERATION RESULT=PASS', ...
        'transposed Gate 1 PASS');
    require_contains(gate1Text, ...
        'FILTER_STRUCTURE=Direct form transposed', ...
        'transposed Gate 1 architecture');
    gate1Latency = str2double(report_value(gate1Text, ...
        'EXPECTED_OBJECT_LATENCY_CYCLES'));
    log_line('GATE1_EXPECTED_OBJECT_LATENCY_CYCLES=%.12g', ...
        gate1Latency);
    if gate1Latency ~= 351
        error('V06:Gate3Gate1Latency', ...
            'Transposed Gate-1 expected latency is not 351 cycles.');
    end
    if exist(generatedTopFile, 'file') ~= 2
        error('V06:Gate3GeneratedTopMissing', ...
            'Transposed Gate-1 generated top is missing: %s', ...
            generatedTopFile);
    end
    log_line('GENERATED_TOP_EXISTS=1');

    gate2tText = require_report(gate2tReportFile, 'Gate 2T');
    require_contains(gate2tText, ...
        'V06 GATE2T TRANSPOSED OOC SYNTHESIS RESULT=PASS', ...
        'Gate 2T PASS');
    require_contains(gate2tText, ...
        'RESOURCE_IMPROVEMENT_MATERIAL=1', ...
        'Gate 2T material resource improvement');
    log_line('GATE2T_EVIDENCE_CHECK=PASS');

    % Use exactly the build_model.m prototype extraction path.
    designChannelizer = dsp.Channelizer( ...
        NumFrequencyBands=numBands, ...
        NumTapsPerBand=tapsPerBand, ...
        StopbandAttenuation=stopbandDb);
    [coefficients, prototypeDenominator] = tf(designChannelizer);
    release(designChannelizer);
    expectedCoefficients = numBands * tapsPerBand;
    log_line('COEFFICIENT_COUNT=%d', numel(coefficients));
    log_line('COEFFICIENT_EXPECTED=%d', expectedCoefficients);
    log_line('COEFFICIENT_MAX_ABS=%.12g', max(abs(coefficients)));
    log_line('COEFFICIENT_SUM=%.12g', sum(coefficients));
    if numel(coefficients) ~= expectedCoefficients
        error('V06:CoefficientCount', ...
            'Prototype has %d coefficients, expected %d.', ...
            numel(coefficients), expectedCoefficients);
    end
    if numel(prototypeDenominator) ~= 1 || ...
            double(prototypeDenominator(1)) ~= 1
        error('V06:UnexpectedPrototypeDenominator', ...
            'Prototype tf denominator is not scalar 1.');
    end

    % Record the raw object's latency and public fixed-point defaults.
    % The stepped DUT below remains the ZU48DRChannelizer wrapper,
    % i.e. the object actually placed in the HDL generation model.
    rawChannelizer = dsphdl.Channelizer( ...
        'NumFrequencyBands', numBands, ...
        'FilterCoefficients', coefficients, ...
        'FilterStructure', filterStructure, ...
        'OutputSize', 'Same as input size', ...
        'Normalize', false);
    reportedLatency = getLatency(rawChannelizer, numBands, ssr, true);
    log_line('RAW_DSPHDL_GETLATENCY_CYCLES=%.12g', reportedLatency);
    log_optional_property(log_line, rawChannelizer, 'RoundingMethod');
    log_optional_property(log_line, rawChannelizer, 'OverflowAction');
    log_optional_property(log_line, rawChannelizer, ...
        'FilterOutputDataType');
    log_optional_property(log_line, rawChannelizer, ...
        'CoefficientsDataType');
    log_optional_property(log_line, rawChannelizer, ...
        'ComplexMultiplication');
    release(rawChannelizer);

    % Build one deterministic multi-tone waveform.  Eight extra
    % snapshots of waveform are generated solely so the DUT pipeline
    % can emit all requested snapshots while valid input continues.
    flushSnapshots = 8;
    waveformSamples = (snapshotsToCollect + flushSnapshots) * numBands;
    sampleIndex = (0:(waveformSamples - 1)).';
    toneMatrix = exp(1j * (2 * pi * sampleIndex * ...
        (toneBins / numBands) + tonePhasesRad));
    waveformUnscaled = toneMatrix * toneRelativeAmplitudes.';
    waveformScale = 0.70 / max(abs(waveformUnscaled));
    waveformDouble = waveformUnscaled * waveformScale;
    toneEffectiveAmplitudes = toneRelativeAmplitudes * waveformScale;
    inputType = numerictype(1, 16, 15);
    waveformFi = fi(waveformDouble, inputType);
    waveformQuantized = double(waveformFi);
    log_line('WAVEFORM_SAMPLES_GENERATED=%d', waveformSamples);
    log_line('WAVEFORM_FLUSH_SNAPSHOTS=%d', flushSnapshots);
    log_line('WAVEFORM_SCALE_TO_MAX_0P70=%.12g', waveformScale);
    log_line('WAVEFORM_MAX_MAGNITUDE=%.12g', ...
        max(abs(waveformQuantized)));
    log_line('WAVEFORM_MAX_COMPONENT=%.12g', ...
        max(max(abs(real(waveformQuantized))), ...
            max(abs(imag(waveformQuantized)))));
    log_line('INPUT_TYPE=%s', describe_type(waveformFi));
    log_line('INPUT_LSB=%.12g', 2^(-inputType.FractionLength));
    if max(abs(waveformQuantized)) >= 0.99
        error('V06:Gate3InputHeadroom', ...
            'Gate-3 waveform does not retain fixed-point headroom.');
    end

    % Floating-point reference.  The explicit positional (M,D) form
    % matches matlab_v7/design_pfb_coefficients.m and fixes the
    % critically sampled D=1024 contract in R2024a.
    referenceChannelizer = dsp.Channelizer(numBands, numBands, ...
        'Specification', ...
        'Number of taps per band and stopband attenuation', ...
        'NumTapsPerBand', tapsPerBand, ...
        'StopbandAttenuation', stopbandDb);
    centreFrequenciesRawHz = centerFrequencies( ...
        referenceChannelizer, complexSampleRateHz);
    referenceInput = waveformQuantized( ...
        1:(snapshotsToCollect * numBands));
    referenceSnapshots = referenceChannelizer(referenceInput);
    release(referenceChannelizer);
    log_line('REFERENCE_INPUT_SAMPLES=%d', numel(referenceInput));
    log_line('REFERENCE_OUTPUT_SIZE=[%d %d]', ...
        size(referenceSnapshots, 1), size(referenceSnapshots, 2));
    log_line('REFERENCE_OUTPUT_CLASS=%s', class(referenceSnapshots));
    if ~isequal(size(referenceSnapshots), ...
            [snapshotsToCollect numBands])
        error('V06:Gate3ReferenceSize', ...
            'Reference output is [%d %d], expected [%d %d].', ...
            size(referenceSnapshots, 1), size(referenceSnapshots, 2), ...
            snapshotsToCollect, numBands);
    end
    if numel(centreFrequenciesRawHz) ~= numBands
        error('V06:Gate3CentreFrequencyCount', ...
            'centerFrequencies returned %d values, expected %d.', ...
            numel(centreFrequenciesRawHz), numBands);
    end

    allBins0 = 0:(numBands - 1);
    signedBinsAll = allBins0;
    signedBinsAll(signedBinsAll >= numBands / 2) = ...
        signedBinsAll(signedBinsAll >= numBands / 2) - numBands;
    expectedCentreFrequenciesHz = signedBinsAll * binSpacingHz;
    centreRawMaxErrorHz = max(abs(double( ...
        centreFrequenciesRawHz(:).') - expectedCentreFrequenciesHz));
    centreShiftedHz = circshift(double( ...
        centreFrequenciesRawHz(:).'), numBands / 2);
    centreShiftedMaxErrorHz = max(abs(centreShiftedHz - ...
        expectedCentreFrequenciesHz));
    log_line('CENTRE_FREQUENCIES_RAW_FIRST_HZ=%.12g', ...
        centreFrequenciesRawHz(1));
    log_line('CENTRE_FREQUENCIES_RAW_MIDDLE_HZ=%.12g', ...
        centreFrequenciesRawHz(numBands / 2 + 1));
    log_line('CENTRE_FREQUENCIES_RAW_MATCH_NATURAL_MAX_ERROR_HZ=%.12g', ...
        centreRawMaxErrorHz);
    log_line(['CENTRE_FREQUENCIES_CIRCSHIFT512_MATCH_NATURAL_' ...
        'MAX_ERROR_HZ=%.12g'], centreShiftedMaxErrorHz);

    % Primary documented alignment and a no-pad diagnostic.  The
    % sample stream is formed before SSR reshaping, so the 1023-zero
    % prefix is a true sample-stream shift rather than a whole-beat
    % approximation.
    [dutPaddedSnapshots, paddedInfo] = run_dut(coefficients, ...
        filterStructure, waveformQuantized, inputType, ...
        numBands - 1, snapshotsToCollect, numBands, ssr);
    log_dut_info(log_line, 'PAD1023', paddedInfo);
    [dutNoPadSnapshots, noPadInfo] = run_dut(coefficients, ...
        filterStructure, waveformQuantized, inputType, ...
        0, snapshotsToCollect, numBands, ssr);
    log_dut_info(log_line, 'NOPAD', noPadInfo);

    outputWordLength = paddedInfo.outputWordLength;
    outputFractionLength = paddedInfo.outputFractionLength;
    outputLsb = 2^(-outputFractionLength);
    log_line('OUTPUT_LSB=%.12g', outputLsb);

    % Candidate search uses the transient snapshots, where a wrong
    % snapshot offset cannot hide behind the eventual periodic
    % steady state.  The search remains constrained to the two
    % plausible reference-column maps and the documented one-sample
    % per-bin phase ramp (or no ramp).
    alignmentDutIndices = 2:min(24, snapshotsToCollect);
    [paddedCandidates, selected, candidateSeparation] = ...
        search_candidates(log_line, 'PAD1023', referenceSnapshots, ...
            dutPaddedSnapshots, alignmentDutIndices, numBands, true);
    log_line('SELECTED_PAD_SAMPLES=%d', numBands - 1);
    log_line('SELECTED_SNAPSHOT_OFFSET=%+d', ...
        selected.snapshotOffset);
    log_line(['SNAPSHOT_OFFSET_DEFINITION=' ...
        'referenceSnapshotIndex1=dutSnapshotIndex1+offset']);
    log_line('SELECTED_REFERENCE_COLUMN_SHIFT=%d', selected.mapShift);
    log_line(['REFERENCE_COLUMN_MAP_DEFINITION=' ...
        'referenceColumn0=mod(rawDutBin0+shift,1024)']);
    log_line('SELECTED_PHASE_CORRECTION_SIGN=%+d', ...
        selected.phaseSign);
    log_line(['PHASE_CORRECTION_TO_MATCH_DSP=' ...
        'multiply raw DUT bin k by exp(1j*(%+d)*2*pi*k/1024)'], ...
        selected.phaseSign);
    log_line(['RAW_DUT_PHASE_RELATION=' ...
        'rawDut(k) approximately globalGain*reference(k)*' ...
        'exp(1j*(%+d)*2*pi*k/1024)'], -selected.phaseSign);
    log_line('SELECTED_ALIGNMENT_NRMSE=%.12g', selected.nrmse);
    log_line('SELECTED_ALIGNMENT_CORRELATION=%.12g', ...
        selected.correlation);
    log_line('SELECTED_ALIGNMENT_GAIN_REAL=%.12g', ...
        real(selected.gain));
    log_line('SELECTED_ALIGNMENT_GAIN_IMAG=%.12g', ...
        imag(selected.gain));
    log_line('CANDIDATE_SEPARATION_SECOND_OVER_BEST=%.12g', ...
        candidateSeparation);
    log_line('CANDIDATE_COUNT=%d', numel(paddedCandidates));

    [~, noPadBest, noPadSeparation] = search_candidates(log_line, ...
        'NOPAD', referenceSnapshots, dutNoPadSnapshots, ...
        alignmentDutIndices, numBands, false);
    log_line(['NOPAD_BEST_DIAGNOSTIC=' ...
        'offset=%+d shift=%d phaseSign=%+d nrmse=%.12g ' ...
        'correlation=%.12g separation=%.12g'], ...
        noPadBest.snapshotOffset, noPadBest.mapShift, ...
        noPadBest.phaseSign, noPadBest.nrmse, ...
        noPadBest.correlation, noPadSeparation);

    % Raw DUT ordering is established directly from known input tone
    % frequencies, independently of how dsp.Channelizer labels its
    % output columns.  Serialized DUT index s is in SSR beat
    % floor(s/8), lane mod(s,8).
    steadyDutIndices = (discardSnapshots + 1):snapshotsToCollect;
    dutSteadyMeanMagnitude = mean(abs( ...
        dutPaddedSnapshots(steadyDutIndices, :)), 1);
    [~, dutSortedIndices] = sort(dutSteadyMeanMagnitude, 'descend');
    dutTopBins0 = dutSortedIndices(1:numTones) - 1;
    dutTopExact = isequal(sort(dutTopBins0), sort(toneBins));
    log_line('DUT_STEADY_TOP16_BINS0=%s', ...
        format_integer_list(sort(dutTopBins0)));
    log_line('DUT_STEADY_TOP16_EXACT=%d', dutTopExact);

    referenceSteadyMeanMagnitude = mean(abs( ...
        referenceSnapshots(steadyDutIndices, :)), 1);
    [~, referenceSortedIndices] = sort( ...
        referenceSteadyMeanMagnitude, 'descend');
    referenceTopBins0 = referenceSortedIndices(1:numTones) - 1;
    referenceIdentityExpected = toneBins;
    referenceShiftExpected = mod(toneBins + numBands / 2, numBands);
    referenceIdentityMatches = numel(intersect( ...
        referenceTopBins0, referenceIdentityExpected));
    referenceShiftMatches = numel(intersect(referenceTopBins0, ...
        referenceShiftExpected));
    log_line('REFERENCE_STEADY_TOP16_COLUMNS0=%s', ...
        format_integer_list(sort(referenceTopBins0)));
    log_line('REFERENCE_TOP16_IDENTITY_MATCH_COUNT=%d', ...
        referenceIdentityMatches);
    log_line('REFERENCE_TOP16_CIRCSHIFT512_MATCH_COUNT=%d', ...
        referenceShiftMatches);

    % Steady-state selected comparison.
    [dutSteadyCorrected, referenceSteadyAligned, ...
        steadyDutUsed, steadyReferenceUsed] = align_snapshots( ...
            referenceSnapshots, dutPaddedSnapshots, ...
            selected.phaseSign, selected.mapShift, ...
            selected.snapshotOffset, steadyDutIndices);
    steadyMetrics = compare_snapshots(referenceSnapshots, ...
        dutPaddedSnapshots, selected.phaseSign, selected.mapShift, ...
        selected.snapshotOffset, steadyDutIndices);
    globalGain = steadyMetrics.gain;
    globalGainMagnitude = abs(globalGain);
    globalGainPhaseDeg = angle(globalGain) * 180 / pi;
    steadyError = dutSteadyCorrected - ...
        globalGain * referenceSteadyAligned;
    log_line('STEADY_DUT_SNAPSHOTS_USED=%s', ...
        format_integer_list(steadyDutUsed));
    log_line('STEADY_REFERENCE_SNAPSHOTS_USED=%s', ...
        format_integer_list(steadyReferenceUsed));
    log_line('STEADY_GLOBAL_GAIN_REAL=%.12g', real(globalGain));
    log_line('STEADY_GLOBAL_GAIN_IMAG=%.12g', imag(globalGain));
    log_line('STEADY_GLOBAL_GAIN_MAGNITUDE=%.12g', ...
        globalGainMagnitude);
    log_line('STEADY_GLOBAL_GAIN_MAGNITUDE_DB=%.12g', ...
        20 * log10(globalGainMagnitude));
    log_line('STEADY_GLOBAL_GAIN_PHASE_DEG=%.12g', ...
        globalGainPhaseDeg);
    log_line('STEADY_NRMSE=%.12g', steadyMetrics.nrmse);
    log_line('STEADY_CORRELATION=%.12g', steadyMetrics.correlation);
    log_line('STEADY_MAX_ABS_ERROR=%.12g', max(abs(steadyError(:))));
    log_line('STEADY_MAX_ABS_ERROR_OUTPUT_LSB=%.12g', ...
        max(abs(steadyError(:))) / outputLsb);
    log_line('STEADY_RMS_ERROR_OUTPUT_LSB=%.12g', ...
        sqrt(mean(abs(steadyError(:)) .^ 2)) / outputLsb);

    dutMeanSnapshot = mean(dutSteadyCorrected, 1);
    referenceMeanSnapshot = mean(referenceSteadyAligned, 1);
    dutSnapshotDeviation = 0;
    referenceSnapshotDeviation = 0;
    for rowIndex = 1:size(dutSteadyCorrected, 1)
        dutSnapshotDeviation = max(dutSnapshotDeviation, ...
            norm(dutSteadyCorrected(rowIndex, :) - dutMeanSnapshot) / ...
            max(norm(dutMeanSnapshot), eps));
        referenceSnapshotDeviation = max( ...
            referenceSnapshotDeviation, ...
            norm(referenceSteadyAligned(rowIndex, :) - ...
                referenceMeanSnapshot) / ...
            max(norm(referenceMeanSnapshot), eps));
    end
    log_line('STEADY_DUT_MAX_SNAPSHOT_DEVIATION_FRACTION=%.12g', ...
        dutSnapshotDeviation);
    log_line(['STEADY_REFERENCE_MAX_SNAPSHOT_DEVIATION_' ...
        'FRACTION=%.12g'], referenceSnapshotDeviation);

    maxToneGainResidualFraction = 0;
    maxTonePhaseResidualDeg = 0;
    maxDutMagnitudeCv = 0;
    maxReferenceMagnitudeCv = 0;
    minPhaseCoherence = 1;
    minNeighbourRatio = Inf;
    for toneIndex = 1:numTones
        rawBin0 = toneBins(toneIndex);
        signedBin = rawBin0;
        if signedBin >= numBands / 2
            signedBin = signedBin - numBands;
        end
        basebandHz = signedBin * binSpacingHz;
        rfHz = rfCentreHz + basebandHz;
        ssrBeat0 = floor(rawBin0 / ssr);
        ssrLane0 = mod(rawBin0, ssr);
        dutRank = find(dutSortedIndices == rawBin0 + 1, 1, 'first');
        neighbourBins0 = mod([rawBin0 - 1 rawBin0 + 1], numBands);
        neighbourMagnitude = max(dutSteadyMeanMagnitude( ...
            neighbourBins0 + 1));
        neighbourRatio = dutSteadyMeanMagnitude(rawBin0 + 1) / ...
            max(neighbourMagnitude, eps);
        minNeighbourRatio = min(minNeighbourRatio, neighbourRatio);

        referenceColumn0 = mod(rawBin0 + selected.mapShift, numBands);
        dutToneValues = dutSteadyCorrected(:, referenceColumn0 + 1);
        referenceToneValues = referenceSteadyAligned(:, ...
            referenceColumn0 + 1);
        toneGain = sum(conj(referenceToneValues) .* dutToneValues) / ...
            sum(abs(referenceToneValues) .^ 2);
        toneResidual = toneGain / globalGain;
        toneGainResidualFraction = abs(abs(toneResidual) - 1);
        tonePhaseResidualDeg = abs(angle(toneResidual) * 180 / pi);
        maxToneGainResidualFraction = max( ...
            maxToneGainResidualFraction, toneGainResidualFraction);
        maxTonePhaseResidualDeg = max(maxTonePhaseResidualDeg, ...
            tonePhaseResidualDeg);
        dutMagnitudeCv = std(abs(dutToneValues)) / ...
            max(mean(abs(dutToneValues)), eps);
        referenceMagnitudeCv = std(abs(referenceToneValues)) / ...
            max(mean(abs(referenceToneValues)), eps);
        maxDutMagnitudeCv = max(maxDutMagnitudeCv, dutMagnitudeCv);
        maxReferenceMagnitudeCv = max(maxReferenceMagnitudeCv, ...
            referenceMagnitudeCv);
        phaseCoherence = abs(mean(exp(1j * angle( ...
            dutToneValues .* conj(referenceToneValues)))));
        minPhaseCoherence = min(minPhaseCoherence, phaseCoherence);

        log_line(['TONE_%02d rawBin0=%d signedBin=%+d ' ...
            'basebandMHz=%.9g rfMHz=%.9g beat0=%d lane0=%d ' ...
            'refColumn0=%d dutRank=%d neighbourRatio=%.9g ' ...
            'inputAmp=%.9g gainMag=%.9g gainPhaseDeg=%.9g ' ...
            'residualMagFraction=%.9g residualPhaseDeg=%.9g ' ...
            'dutMagCv=%.9g refMagCv=%.9g phaseCoherence=%.9g'], ...
            toneIndex, rawBin0, signedBin, basebandHz / 1e6, ...
            rfHz / 1e6, ssrBeat0, ssrLane0, referenceColumn0, ...
            dutRank, neighbourRatio, ...
            toneEffectiveAmplitudes(toneIndex), abs(toneGain), ...
            angle(toneGain) * 180 / pi, toneGainResidualFraction, ...
            tonePhaseResidualDeg, dutMagnitudeCv, ...
            referenceMagnitudeCv, phaseCoherence);
    end
    log_line('MAX_TONE_GAIN_RESIDUAL_FRACTION=%.12g', ...
        maxToneGainResidualFraction);
    log_line('MAX_TONE_PHASE_RESIDUAL_DEG=%.12g', ...
        maxTonePhaseResidualDeg);
    log_line('MAX_DUT_STEADY_MAGNITUDE_CV=%.12g', ...
        maxDutMagnitudeCv);
    log_line('MAX_REFERENCE_STEADY_MAGNITUDE_CV=%.12g', ...
        maxReferenceMagnitudeCv);
    log_line('MIN_STEADY_PHASE_COHERENCE=%.12g', ...
        minPhaseCoherence);
    log_line('MIN_TONE_NEIGHBOUR_RATIO=%.12g', minNeighbourRatio);
    log_line(['OUTPUT_SCALAR_ORDER=first valid SSR beat contains ' ...
        'raw bins 0..7 on lanes 0..7; beat b contains raw bins ' ...
        '8*b..8*b+7']);
    log_line(['BIN_FREQUENCY_MAP=signedBin(k)=k for k<512, ' ...
        'k-1024 for k>=512; fBb=signedBin*1.953125 MHz; ' ...
        'fRf=3000 MHz+fBb']);
    log_line('BIN512_NOTE=Nyquist bin aliases -1000 MHz/+1000 MHz');
    log_line(['PRODUCTION_PHASE_NOTE=recorded correction is a ' ...
        'common deterministic per-bin relation; no PreservePhase ' ...
        'property or production phase correction is selected here']);

    % Assertions are deliberately after all diagnostic metrics.
    if reportedLatency ~= 351 || ...
            paddedInfo.firstValidCycle - 1 ~= 351 || ...
            noPadInfo.firstValidCycle - 1 ~= 351
        error('V06:Gate3Latency', ...
            'Transposed Gate-3 latency is not 351 cycles in all runs.');
    end
    expectedValidBeats = snapshotsToCollect * numBands / ssr;
    if paddedInfo.validBeats ~= expectedValidBeats || ...
            noPadInfo.validBeats ~= expectedValidBeats
        error('V06:Gate3ValidBeats', ...
            'Gate-3 valid-beat count is not %d in both DUT runs.', ...
            expectedValidBeats);
    end
    if outputWordLength ~= 26 || outputFractionLength ~= 24 || ...
            noPadInfo.outputWordLength ~= 26 || ...
            noPadInfo.outputFractionLength ~= 24
        error('V06:Gate3OutputType', ...
            'Gate-3 output is not signed 26-bit/fraction-24 in both runs.');
    end
    if min(centreRawMaxErrorHz, centreShiftedMaxErrorHz) > 1.0
        error('V06:Gate3CentreFrequencyMap', ...
            ['Neither raw nor 512-shifted centerFrequencies output ' ...
             'matches the natural signed-bin map within 1 Hz.']);
    end
    if ~dutTopExact
        error('V06:Gate3DutOrdering', ...
            'Raw DUT steady-state top tone bins are not the exact input tone set.');
    end
    if referenceIdentityMatches ~= numTones && ...
            referenceShiftMatches ~= numTones
        error('V06:Gate3ReferenceOrdering', ...
            ['Reference steady-state top tone columns match neither ' ...
             'the identity nor the 512-shifted tone set.']);
    end
    if selected.phaseSign == 0 || ...
            selected.nrmse > alignmentNrmseLimit || ...
            candidateSeparation < candidateSeparationMinimum
        error('V06:Gate3Alignment', ...
            ['Documented 1023-zero alignment did not uniquely select ' ...
             'a per-bin phase ramp within the Gate-3 thresholds.']);
    end
    if steadyMetrics.nrmse > steadyNrmseLimit || ...
            steadyMetrics.correlation < steadyCorrelationMinimum
        error('V06:Gate3SteadyError', ...
            'Steady-state DUT/reference error exceeds Gate-3 thresholds.');
    end
    if globalGainMagnitude < globalGainMagnitudeMinimum || ...
            globalGainMagnitude > globalGainMagnitudeMaximum || ...
            abs(globalGainPhaseDeg) > globalGainPhaseLimitDeg
        error('V06:Gate3GlobalGain', ...
            'Steady-state global gain/phase is outside Gate-3 limits.');
    end
    if maxToneGainResidualFraction > toneGainResidualLimit || ...
            maxTonePhaseResidualDeg > tonePhaseResidualLimitDeg
        error('V06:Gate3PerToneGainPhase', ...
            'Per-tone steady-state gain/phase exceeds Gate-3 limits.');
    end
    if maxDutMagnitudeCv > steadyMagnitudeCvLimit || ...
            maxReferenceMagnitudeCv > steadyMagnitudeCvLimit || ...
            minPhaseCoherence < steadyPhaseCoherenceMinimum || ...
            dutSnapshotDeviation > steadyNrmseLimit || ...
            referenceSnapshotDeviation > steadyNrmseLimit
        error('V06:Gate3SteadyStability', ...
            'Selected snapshots are not sufficiently steady.');
    end
    if minNeighbourRatio < toneNeighbourRatioMinimum
        error('V06:Gate3ToneIsolation', ...
            'A tone bin does not dominate its immediate neighbours.');
    end

    log_line('PACKAGING_PERFORMED=0');
    log_line('HDL_GENERATION_PERFORMED=0');
    log_line('V06 GATE3 TRANSPOSED NUMERICS RESULT=PASS');
catch exception
    log_line('GATE3_EXCEPTION_ID=%s', exception.identifier);
    log_line('GATE3_EXCEPTION_MESSAGE=%s', exception.message);
    if ~isempty(exception.stack)
        log_line('GATE3_EXCEPTION_AT=%s:%d', ...
            exception.stack(1).file, exception.stack(1).line);
    end
    log_line('PACKAGING_PERFORMED=0');
    log_line('HDL_GENERATION_PERFORMED=0');
    log_line('V06 GATE3 TRANSPOSED NUMERICS RESULT=FAIL');
    rethrow(exception);
end
end

function [snapshots, info] = run_dut(coefficients, filterStructure, ...
    waveformQuantized, inputType, padSamples, snapshotsToCollect, ...
    numBands, ssr)
% MATLAB R2022b fails to chain the generated name/value constructor for
% this matlab.System subclass (NoMatchingSuperConstructor).  Assign the
% nontunable properties before the first step call instead; the System
% object remains unlocked until that first call.
dut = ZU48DRChannelizer();
dut.NumBands = numBands;
dut.Coefficients = coefficients;
dut.FilterStructure = filterStructure;
dut.NormalizeFFT = false;

streamDouble = [complex(zeros(padSamples, 1)); waveformQuantized(:)];
cycleCount = ceil(numel(streamDouble) / ssr);
endPadSamples = cycleCount * ssr - numel(streamDouble);
if endPadSamples > 0
    streamDouble = [streamDouble; complex(zeros(endPadSamples, 1))];
end
streamFi = fi(streamDouble, inputType);
inputMatrix = reshape(streamFi, ssr, cycleCount);

targetOutputs = snapshotsToCollect * numBands;
collected = complex(zeros(targetOutputs, 1));
collectedCount = 0;
validBeats = 0;
firstValidCycle = 0;
cyclesRun = 0;
outputSize = [];
outputWordLength = NaN;
outputFractionLength = NaN;
outputSignedness = '<none>';

for cycle = 1:cycleCount
    cyclesRun = cycle;
    [dataOut, validOut] = dut(inputMatrix(:, cycle), true);
    if cycle == 1
        outputSize = size(dataOut);
        if isfi(dataOut)
            nt = numerictype(dataOut);
            outputWordLength = nt.WordLength;
            outputFractionLength = nt.FractionLength;
            outputSignedness = nt.Signedness;
        end
        if ~isequal(outputSize, [ssr 1])
            release(dut);
            error('V06:Gate3OutputSize', ...
                'DUT output size is [%d %d], expected [%d 1].', ...
                outputSize(1), outputSize(2), ssr);
        end
    end
    if any(validOut(:))
        if firstValidCycle == 0
            firstValidCycle = cycle;
        end
        validBeats = validBeats + 1;
        values = double(dataOut(:));
        takeCount = min(numel(values), targetOutputs - collectedCount);
        collected(collectedCount + (1:takeCount)) = values(1:takeCount);
        collectedCount = collectedCount + takeCount;
        if collectedCount >= targetOutputs
            break;
        end
    end
end
release(dut);

if firstValidCycle == 0 || collectedCount < targetOutputs
    error('V06:Gate3ShortDutRun', ...
        ['DUT collected %d of %d outputs with padSamples=%d; ' ...
         'firstValidCycle=%d.'], collectedCount, targetOutputs, ...
        padSamples, firstValidCycle);
end

snapshots = reshape(collected, numBands, snapshotsToCollect).';
info = struct( ...
    'padSamples', padSamples, ...
    'firstValidCycle', firstValidCycle, ...
    'validBeats', validBeats, ...
    'cyclesRun', cyclesRun, ...
    'outputWordLength', outputWordLength, ...
    'outputFractionLength', outputFractionLength, ...
    'outputSignedness', outputSignedness);
end

function log_dut_info(log_line, label, info)
log_line('%s_PAD_SAMPLES=%d', label, info.padSamples);
log_line('%s_FIRST_VALID_CYCLE=%d', label, info.firstValidCycle);
log_line('%s_MEASURED_LATENCY_CYCLES=%d', label, ...
    info.firstValidCycle - 1);
log_line('%s_VALID_BEATS=%d', label, info.validBeats);
log_line('%s_CYCLES_RUN=%d', label, info.cyclesRun);
log_line('%s_OUTPUT_TYPE=fi signedness=%s wordLength=%d fractionLength=%d', ...
    label, info.outputSignedness, info.outputWordLength, ...
    info.outputFractionLength);
end

function [candidates, best, separation] = search_candidates(log_line, ...
    label, referenceSnapshots, dutSnapshots, dutIndices, numBands, ...
    logAllCandidates)
candidates = repmat(struct( ...
    'snapshotOffset', 0, 'mapShift', 0, 'phaseSign', 0, ...
    'gain', complex(0, 0), 'nrmse', Inf, 'correlation', 0), 0, 1);
for snapshotOffset = -2:2
    for mapShift = [0 numBands / 2]
        for phaseSign = [-1 0 1]
            metrics = compare_snapshots(referenceSnapshots, ...
                dutSnapshots, phaseSign, mapShift, snapshotOffset, ...
                dutIndices);
            candidate = struct( ...
                'snapshotOffset', snapshotOffset, ...
                'mapShift', mapShift, ...
                'phaseSign', phaseSign, ...
                'gain', metrics.gain, ...
                'nrmse', metrics.nrmse, ...
                'correlation', metrics.correlation);
            candidates(end + 1, 1) = candidate; %#ok<AGROW>
            if logAllCandidates
                log_line(['CANDIDATE_%s offset=%+d shift=%d ' ...
                    'phaseSign=%+d nrmse=%.9g correlation=%.9g ' ...
                    'gainMag=%.9g gainPhaseDeg=%.9g'], label, ...
                    snapshotOffset, mapShift, phaseSign, ...
                    metrics.nrmse, metrics.correlation, ...
                    abs(metrics.gain), angle(metrics.gain) * 180 / pi);
            end
        end
    end
end
[~, order] = sort([candidates.nrmse]);
candidates = candidates(order);
best = candidates(1);
if numel(candidates) > 1 && best.nrmse > 0
    separation = candidates(2).nrmse / best.nrmse;
elseif best.nrmse == 0
    separation = Inf;
else
    separation = NaN;
end
end

function metrics = compare_snapshots(referenceSnapshots, dutSnapshots, ...
    phaseSign, mapShift, snapshotOffset, dutIndices)
[dutCorrected, referenceAligned] = align_snapshots( ...
    referenceSnapshots, dutSnapshots, phaseSign, mapShift, ...
    snapshotOffset, dutIndices);
metrics = struct('gain', complex(NaN, NaN), 'nrmse', Inf, ...
    'correlation', 0);
if isempty(dutCorrected)
    return;
end
referenceEnergy = sum(abs(referenceAligned(:)) .^ 2);
dutEnergy = sum(abs(dutCorrected(:)) .^ 2);
if referenceEnergy <= 0 || dutEnergy <= 0
    return;
end
metrics.gain = sum(conj(referenceAligned(:)) .* ...
    dutCorrected(:)) / referenceEnergy;
errorValues = dutCorrected - metrics.gain * referenceAligned;
metrics.nrmse = norm(errorValues(:)) / sqrt(dutEnergy);
metrics.correlation = abs(sum(conj(referenceAligned(:)) .* ...
    dutCorrected(:))) / sqrt(referenceEnergy * dutEnergy);
end

function [dutCorrected, referenceAligned, dutUsed, referenceUsed] = ...
    align_snapshots(referenceSnapshots, dutSnapshots, phaseSign, ...
    mapShift, snapshotOffset, dutIndices)
numBands = size(dutSnapshots, 2);
referenceIndices = dutIndices + snapshotOffset;
mask = dutIndices >= 1 & dutIndices <= size(dutSnapshots, 1) & ...
    referenceIndices >= 1 & ...
    referenceIndices <= size(referenceSnapshots, 1);
dutUsed = dutIndices(mask);
referenceUsed = referenceIndices(mask);
dutCorrected = dutSnapshots(dutUsed, :);
referenceAligned = referenceSnapshots(referenceUsed, :);
if phaseSign ~= 0
    bins0 = 0:(numBands - 1);
    phaseCorrection = exp(1j * phaseSign * 2 * pi * bins0 / numBands);
    dutCorrected = dutCorrected .* phaseCorrection;
end
if mapShift ~= 0
    dutCorrected = circshift(dutCorrected, mapShift, 2);
end
end

function text = require_report(pathName, label)
if exist(pathName, 'file') ~= 2
    error('V06:Gate3MissingEvidence', '%s report is missing: %s', ...
        label, pathName);
end
text = fileread(pathName);
end

function require_contains(text, needle, label)
if isempty(strfind(text, needle)) %#ok<STREMP>
    error('V06:Gate3EvidenceCheck', ...
        'Required %s evidence was not found: %s', label, needle);
end
end

function value = report_value(text, key)
% Parse strictly line-by-line, matching the proved Gate-1 helper.
% Do not use a regexp dot capture here: in MATLAB '.' can match
% newline characters, so a one-line report value can accidentally
% capture the remainder of the file.
lines = cellstr(splitlines(string(text)));
prefix = [key '='];
for lineIndex = 1:numel(lines)
    line = lines{lineIndex};
    if strncmp(line, prefix, numel(prefix))
        value = strtrim(line(numel(prefix) + 1:end));
        return;
    end
end
value = '';
end

function log_optional_property(log_line, objectValue, propertyName)
try
    if isprop(objectValue, propertyName)
        propertyValue = objectValue.(propertyName);
        log_line('RAW_DSPHDL_%s=%s', upper(propertyName), ...
            property_to_text(propertyValue));
    else
        log_line('RAW_DSPHDL_%s=<not present>', upper(propertyName));
    end
catch propertyException
    log_line('RAW_DSPHDL_%s=<unavailable:%s>', ...
        upper(propertyName), propertyException.identifier);
end
end

function text = property_to_text(value)
if isa(value, 'numerictype')
    text = sprintf(['numerictype signedness=%s wordLength=%d ' ...
        'fractionLength=%d'], value.Signedness, value.WordLength, ...
        value.FractionLength);
elseif ischar(value)
    text = value;
elseif isstring(value)
    text = char(value);
elseif isnumeric(value) || islogical(value)
    text = sprintf('%.12g', double(value));
else
    text = ['<' class(value) '>'];
end
end

function text = format_integer_list(values)
if isempty(values)
    text = '<none>';
    return;
end
parts = cell(1, numel(values));
for index = 1:numel(values)
    parts{index} = sprintf('%d', values(index));
end
text = strjoin(parts, ',');
end

function description = describe_type(value)
if isfi(value)
    nt = numerictype(value);
    description = sprintf( ...
        'fi signedness=%s wordLength=%d fractionLength=%d', ...
        nt.Signedness, nt.WordLength, nt.FractionLength);
else
    description = class(value);
end
end

function value = env_integer(name, defaultValue)
text = getenv(name);
if isempty(text)
    value = defaultValue;
    return;
end
value = str2double(text);
if ~isfinite(value) || value ~= round(value)
    error('V06:BadEnvironment', '%s must be an integer, got "%s".', ...
        name, text);
end
value = round(value);
end

function value = env_choice(name, defaultValue, allowedValues)
text = lower(strtrim(getenv(name)));
if isempty(text)
    value = defaultValue;
    return;
end
if ~ismember(text, allowedValues)
    error('V06:BadEnvironment', '%s must be one of {%s}, got "%s".', ...
        name, strjoin(allowedValues, ', '), text);
end
value = text;
end

function v06_log(fid, line)
fprintf('%s\n', line);
fprintf(fid, '%s\n', line);
end
