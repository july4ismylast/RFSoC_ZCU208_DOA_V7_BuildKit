function coefficients=design_pfb_coefficients(numberBands,decimationFactor,tapsPerBand,attenuation_dB)
%DESIGN_PFB_COEFFICIENTS Share the behavioral prototype with the HDL DUT.
assert(decimationFactor==numberBands,'RFSoCHDL:CriticalSamplingRequired', ...
    'The R2024a dsphdl.Channelizer path requires DecimationFactor == NumBands.');
reference=dsp.Channelizer(numberBands,decimationFactor, ...
    'Specification','Number of taps per band and stopband attenuation', ...
    'NumTapsPerBand',tapsPerBand,'StopbandAttenuation',attenuation_dB);
coefficients=tf(reference);
release(reference);
coefficients=coefficients(:).';
end
