function plot_simulink_results(simulationOutput)
%PLOT_SIMULINK_RESULTS Plot the complete English dashboard from model logs.
if nargin<1, simulationOutput=[]; end
try
    run('sim3d_params.m');
    [time,range]=readLoggedSeries('log_range',simulationOutput);
    [~,position]=readLoggedSeries('log_pos',simulationOutput);
    [~,yaw]=readLoggedSeries('log_yaw',simulationOutput);
    [~,pitch]=readLoggedSeries('log_pitch',simulationOutput);
    [~,roll]=readLoggedSeries('log_roll',simulationOutput);
    [~,doaAz]=readLoggedSeries('log_doa_az',simulationOutput);
    [~,doaEl]=readLoggedSeries('log_doa_el',simulationOutput);
    [~,trueAz]=readLoggedSeries('log_true_az',simulationOutput);
    [~,trueEl]=readLoggedSeries('log_true_el',simulationOutput);
    [~,azError]=readLoggedSeries('log_az_error',simulationOutput);
    [~,elError]=readLoggedSeries('log_el_error',simulationOutput);
    [~,angularError]=readLoggedSeries('log_angular_error',simulationOutput);
    [~,detected]=readLoggedSeries('log_candidate_valid',simulationOutput);
    [~,centerHz]=readLoggedSeries('log_fc_hz',simulationOutput);
    [~,bandwidthHz]=readLoggedSeries('log_bw_hz',simulationOutput);
    [~,signalPeak_dB]=readLoggedSeries('log_signal_peak_db',simulationOutput);
    [~,snr_dB]=readLoggedSeries('log_snr_db',simulationOutput);
    [~,arrived]=readLoggedSeries('log_arrived',simulationOutput);

    values={time,position,yaw,pitch,roll,range,doaAz,doaEl,trueAz,trueEl, ...
        azError,elError,angularError,detected,centerHz,bandwidthHz, ...
        signalPeak_dB,snr_dB,arrived};
    numberRows=min(cellfun(@(value)size(value,1),values));
    for index=1:numel(values), values{index}=values{index}(1:numberRows,:); end
    [time,position,yaw,pitch,roll,range,doaAz,doaEl,trueAz,trueEl, ...
        azError,elError,angularError,detected,centerHz,bandwidthHz, ...
        signalPeak_dB,snr_dB,arrived]=values{:};

    logData=struct( ...
        'time',time,'pos',position,'yaw',yaw,'pitch',pitch,'roll',roll, ...
        'range',range,'doaAz',doaAz,'doaEl',doaEl, ...
        'trueAz',trueAz,'trueEl',trueEl,'azError',azError, ...
        'elError',elError,'angularError',angularError, ...
        'detected',logical(detected),'fc_Hz',centerHz,'bw_Hz',bandwidthHz, ...
        'signalPeak_dB',signalPeak_dB,'snr',snr_dB);
    plot_homing_results(logData,P);
    valid=logical(detected) & isfinite(angularError);
    if any(valid)
        azRMSE=sqrt(mean(azError(valid).^2));
        elRMSE=sqrt(mean(elError(valid).^2));
        rmse3d=sqrt(mean(angularError(valid).^2));
        fprintf(['SIMULINK DOA RMSE: Az %.4f deg | El %.4f deg | ' ...
            '3-D %.4f deg | %s\n'],azRMSE,elRMSE,rmse3d, ...
            passText(rmse3d<=P.Accuracy.Required3DRMSE_deg));
    end

    [~,spectrum_dB]=readLoggedSeries('log_spectrum_db',simulationOutput);
    [~,frequencyHz]=readLoggedSeries('log_frequency_hz',simulationOutput);
    spectrum_dB=spectrum_dB(end,:);
    frequencyHz=frequencyHz(end,:);
    figure('Name','Simulink RF Source Spectrum','Position',[180 120 1100 620]);
    plot((P.Source.CenterFreqHz+frequencyHz)/1e9,spectrum_dB, ...
        'LineWidth',1.2,'Color',[0 0.4470 0.7410]);
    hold on;
    xline((P.Source.CenterFreqHz-P.Source.BandwidthHz/2)/1e9,'--r','Source band edge');
    xline((P.Source.CenterFreqHz+P.Source.BandwidthHz/2)/1e9,'--r','Source band edge');
    grid on; xlabel('RF Frequency (GHz)'); ylabel('Power (dB)');
    title(sprintf([ ...
        'Detected RF Spectrum | %.3f GHz | %s | BW %.1f MHz | Power %.1f dBm'], ...
        P.Source.CenterFreqHz/1e9,P.Source.ModulationType, ...
        P.Source.BandwidthHz/1e6,P.Source.PowerdBm));

    if any(logical(arrived))
        fprintf('SIMULINK RESULT: arrived within %.1f m at %.2f s.\n', ...
            P.Nav.ArrivalRadius,time(find(logical(arrived),1)));
    else
        fprintf('SIMULINK RESULT: final source range %.2f m.\n',range(end));
    end
catch exception
    warning('DOA3D:ResultsDashboard', ...
        'Could not build the results dashboard: %s',exception.message);
end
end

function text=passText(value)
if value, text='PASS'; else, text='FAIL'; end
end

function [time,data]=readLoggedSeries(variableName,simulationOutput)
found=false;
if ~isempty(simulationOutput) && isa(simulationOutput,'Simulink.SimulationOutput')
    try
        value=simulationOutput.get(variableName);
        found=true;
    catch
        found=false;
    end
end
if ~found && evalin('base',sprintf('exist(''%s'',''var'')',variableName))
    value=evalin('base',variableName);
    found=true;
end
if ~found
    error('DOA3D:MissingLog', ...
        ['Required Simulink log "%s" is missing. Pass the object returned by ' ...
         'simulationOutput=sim(''DOA_3D_Homing'') to plot_simulink_results.'], ...
        variableName);
end
if isa(value,'timeseries')
    time=value.Time(:);
    data=squeeze(value.Data);
elseif isstruct(value) && isfield(value,'time') && isfield(value,'signals')
    time=value.time(:);
    data=squeeze(value.signals.values);
else
    data=squeeze(value);
    time=(0:size(data,1)-1).';
end

if isvector(data)
    data=data(:);
elseif size(data,1)~=numel(time)
    timeDimension=find(size(data)==numel(time),1,'first');
    if isempty(timeDimension)
        error('DOA3D:LogShape','Cannot align time with log "%s".',variableName);
    end
    order=[timeDimension,setdiff(1:ndims(data),timeDimension,'stable')];
    data=permute(data,order);
    data=reshape(data,numel(time),[]);
else
    data=reshape(data,numel(time),[]);
end
end
