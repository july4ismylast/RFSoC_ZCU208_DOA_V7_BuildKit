function plot_homing_results(logData,P)
%PLOT_HOMING_RESULTS Comprehensive English report for MATLAB execution.
figure('Name','3D DOA Homing - Complete Results','Position',[40 40 1500 900]);
layout=tiledlayout(3,3,'TileSpacing','compact','Padding','compact');
title(layout,sprintf([ ...
    'Moving Target / Receiver Homing on RF Source | %.3f GHz | %s | BW %.1f MHz | Power %.1f dBm | DOA %s'], ...
    P.Source.CenterFreqHz/1e9,P.Source.ModulationType,P.Source.BandwidthHz/1e6, ...
    P.Source.PowerdBm,P.DOA.Algorithm),'FontWeight','bold');

nexttile;
plot3(logData.pos(:,1),logData.pos(:,2),logData.pos(:,3),'b-','LineWidth',2); hold on;
plot3(P.Source.Position(1),P.Source.Position(2),P.Source.Position(3), ...
    'r*','MarkerSize',14,'LineWidth',2);
plot3(logData.pos(1,1),logData.pos(1,2),logData.pos(1,3),'go','MarkerFaceColor','g');
grid on; axis equal; xlabel('X (m)'); ylabel('Y (m)'); zlabel('Z (m)');
title('Target / Receiver Trajectory');
legend('Moving target path','RF source','Start','Location','best');

nexttile;
plot(logData.time,logData.range,'LineWidth',1.5); hold on;
yline(P.Nav.ArrivalRadius,'--r','Arrival radius');
grid on; xlabel('Time (s)'); ylabel('Range (m)'); title('Range to RF Source');

nexttile;
yyaxis left; stairs(logData.time,double(logData.detected),'LineWidth',1.2);
ylabel('Detection valid'); ylim([-0.1 1.1]);
yyaxis right; plot(logData.time,logData.snr,'LineWidth',1.2); ylabel('Peak SNR (dB)');
grid on; xlabel('Time (s)'); title('Detection and Signal SNR');

nexttile;
plot(logData.time,logData.doaAz,'LineWidth',1.2); hold on;
plot(logData.time,logData.trueAz,'--','LineWidth',1.2);
grid on; xlabel('Time (s)'); ylabel('Azimuth (deg)');
title('Azimuth: Estimated vs Truth'); legend('Estimated','Truth');

nexttile;
plot(logData.time,logData.azError,'LineWidth',1.2); hold on; yline(0,'k:');
grid on; xlabel('Time (s)'); ylabel('Error (deg)'); title('Azimuth Estimation Error');

nexttile;
plot(logData.time,logData.doaEl,'LineWidth',1.2); hold on;
plot(logData.time,logData.trueEl,'--','LineWidth',1.2);
grid on; xlabel('Time (s)'); ylabel('Elevation (deg)');
title('Elevation: Estimated vs Truth'); legend('Estimated','Truth');

nexttile;
plot(logData.time,logData.elError,'LineWidth',1.2); hold on;
plot(logData.time,logData.angularError,'LineWidth',1.2);
grid on; xlabel('Time (s)'); ylabel('Error (deg)');
title('DOA Error'); legend('Elevation error','Total angular error');

nexttile;
rfGHz=(P.Source.CenterFreqHz+logData.fc_Hz)/1e9;
rfGHz(~logData.detected)=NaN;
bwMHz=logData.bw_Hz/1e6; bwMHz(~logData.detected)=NaN;
yyaxis left; plot(logData.time,rfGHz,'.-'); ylabel('Selected RF center (GHz)');
yyaxis right; plot(logData.time,bwMHz,'.-'); ylabel('Estimated BW (MHz)');
grid on; xlabel('Time (s)'); title('Detected Source Parameters');

nexttile;
plot(logData.time,logData.yaw,'LineWidth',1.1); hold on;
plot(logData.time,logData.pitch,'LineWidth',1.1);
plot(logData.time,logData.roll,'LineWidth',1.1);
grid on; xlabel('Time (s)'); ylabel('Angle (deg)');
title('Target / Receiver Attitude'); legend('Yaw','Pitch','Roll');

valid=logical(logData.detected) & isfinite(logData.angularError);
if any(valid)
    azRMSE=sqrt(mean(logData.azError(valid).^2));
    elRMSE=sqrt(mean(logData.elError(valid).^2));
    totalRMSE=sqrt(mean(logData.angularError(valid).^2));
else
    azRMSE=NaN; elRMSE=NaN; totalRMSE=NaN;
end
subtitle(layout,sprintf([ ...
    'Start range %.1f m | Final range %.1f m | Detection %.1f%% | ' ...
    'Az RMSE %.3f deg | El RMSE %.3f deg | 3-D RMSE %.3f deg'], ...
    logData.range(1),logData.range(end),100*mean(logData.detected), ...
    azRMSE,elRMSE,totalRMSE));
end
