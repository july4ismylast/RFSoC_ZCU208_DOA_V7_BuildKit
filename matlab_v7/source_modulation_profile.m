function waveform=source_modulation_profile(modulationType)
%SOURCE_MODULATION_PROFILE Return parameters for the selected source mode.
% Edit the appropriate case below to create an experiment-specific profile.

modulation=upper(char(modulationType));

% Complete defaults keep the SourceModel3D interface fixed in Simulink. A
% case only changes the parameters that are meaningful for that waveform.
waveform.BandwidthHz = 30e6;
waveform.ChipRateHz = 20e6;
waveform.SweepStartHz = -15e6;
waveform.SweepStopHz = 15e6;
waveform.SweepTimeSeconds = 4e-6;
waveform.ModulationToneHz = 2e6;
waveform.PMIndexRad = 2.5;
waveform.AMDepth = 0.8;
waveform.FMDeviationHz = 10e6;
waveform.FSKDeviationHz = 7.5e6;
waveform.NLFMShape = 2.0;
waveform.PulseWidthSeconds = 1e-6;
waveform.PRFHz = 250e3;

switch modulation
    case 'CW'
        waveform.BandwidthHz = 2e6;

    case 'BPSK'
        waveform.ChipRateHz = 20e6;
        waveform.BandwidthHz = 30e6;

    case 'QPSK'
        waveform.ChipRateHz = 20e6;
        waveform.BandwidthHz = 30e6;

    case '8PSK'
        waveform.ChipRateHz = 20e6;
        waveform.BandwidthHz = 30e6;

    case 'QAM16'
        waveform.ChipRateHz = 20e6;
        waveform.BandwidthHz = 30e6;

    case 'QAM64'
        waveform.ChipRateHz = 25e6;
        waveform.BandwidthHz = 40e6;

    case {'LFM','CHIRP'}
        waveform.SweepStartHz = -15e6;
        waveform.SweepStopHz = 15e6;
        waveform.SweepTimeSeconds = 4e-6;
        waveform.BandwidthHz = 30e6;

    case 'NLFM'
        waveform.SweepStartHz = -15e6;
        waveform.SweepStopHz = 15e6;
        waveform.SweepTimeSeconds = 4e-6;
        waveform.NLFMShape = 2.0;
        waveform.BandwidthHz = 30e6;

    case 'PM'
        waveform.ModulationToneHz = 2e6;
        waveform.PMIndexRad = 2.5;
        waveform.BandwidthHz = 20e6;

    case 'FM'
        waveform.ModulationToneHz = 1e6;
        waveform.FMDeviationHz = 8e6;
        waveform.BandwidthHz = 24e6;

    case 'AM'
        waveform.ModulationToneHz = 2e6;
        waveform.AMDepth = 0.8;
        waveform.BandwidthHz = 10e6;

    case 'FSK'
        waveform.ChipRateHz = 10e6;
        waveform.FSKDeviationHz = 7.5e6;
        waveform.BandwidthHz = 30e6;

    case {'PULSED_LFM','LFM_PULSE'}
        waveform.SweepStartHz = -25e6;
        waveform.SweepStopHz = 25e6;
        waveform.SweepTimeSeconds = 1e-6;
        waveform.PulseWidthSeconds = 1e-6;
        waveform.PRFHz = 250e3;
        waveform.BandwidthHz = 50e6;

    case {'NOISE','WIDEBAND_NOISE'}
        waveform.BandwidthHz = 30e6;

    otherwise
        error('DOA3D:ModulationProfile', ...
            ['No source profile exists for "%s". Add a case to ' ...
            'source_modulation_profile.m and SourceModel3D.m.'],modulationType);
end
end
