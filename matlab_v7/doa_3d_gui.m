function handles=doa_3d_gui(P)
%DOA_3D_GUI Create a lightweight live visualization window.
handles.Figure=figure('Name','Live 3D Moving-Target DOA Homing', ...
    'Color',[0.08 0.09 0.12],'Position',[40 40 1400 820]);
layout=tiledlayout(handles.Figure,2,3,'TileSpacing','compact','Padding','compact');
title(layout,sprintf([ ...
    'Four-Channel RFSoC Moving Target / Receiver Homing | %.3f GHz | %s | BW %.1f MHz | %.1f dBm'], ...
    P.Source.CenterFreqHz/1e9,P.Source.ModulationType, ...
    P.Source.BandwidthHz/1e6,P.Source.PowerdBm), ...
    'Color','w','FontWeight','bold');

handles.TrajectoryAxes=nexttile(layout,[2 1]);
hold(handles.TrajectoryAxes,'on'); grid(handles.TrajectoryAxes,'on');
handles.Path=plot3(handles.TrajectoryAxes,nan,nan,nan,'Color',[0.1 0.7 1], ...
    'LineWidth',2);
handles.Start=plot3(handles.TrajectoryAxes,P.Platform.Position0(1), ...
    P.Platform.Position0(2),P.Platform.Position0(3),'go','MarkerFaceColor','g');
handles.Source=plot3(handles.TrajectoryAxes,P.Source.Position(1), ...
    P.Source.Position(2),P.Source.Position(3),'r*','MarkerSize',15,'LineWidth',2);
xlabel(handles.TrajectoryAxes,'X (m)'); ylabel(handles.TrajectoryAxes,'Y (m)');
zlabel(handles.TrajectoryAxes,'Z (m)');
title(handles.TrajectoryAxes,'3D Target / Receiver Trajectory');
axis(handles.TrajectoryAxes,'equal'); view(handles.TrajectoryAxes,35,25);

handles.SpectrumAxes=nexttile(layout);
handles.Spectrum=plot(handles.SpectrumAxes,nan,nan,'Color',[0.2 0.8 1],'LineWidth',1.2);
grid(handles.SpectrumAxes,'on'); xlabel(handles.SpectrumAxes,'Offset (MHz)');
ylabel(handles.SpectrumAxes,'Power (dB)'); title(handles.SpectrumAxes,'PFB Spectrum');

handles.DoaAxes=nexttile(layout);
handles.DoaImage=imagesc(handles.DoaAxes,P.DOA.AzScanRange,P.DOA.ElScanRange,zeros(2));
axis(handles.DoaAxes,'xy'); colorbar(handles.DoaAxes);
xlabel(handles.DoaAxes,'Azimuth (deg)'); ylabel(handles.DoaAxes,'Elevation (deg)');
title(handles.DoaAxes,'DOA Pseudospectrum');

handles.AngleAxes=nexttile(layout);
hold(handles.AngleAxes,'on');
handles.EstimatedAz=plot(handles.AngleAxes,nan,nan,'Color',[0.1 0.7 1],'LineWidth',1.5);
handles.TrueAz=plot(handles.AngleAxes,nan,nan,'--','Color',[1 0.55 0.2],'LineWidth',1.2);
grid(handles.AngleAxes,'on'); xlabel(handles.AngleAxes,'Time (s)');
ylabel(handles.AngleAxes,'Azimuth (deg)'); title(handles.AngleAxes,'Estimated vs True Azimuth');
legend(handles.AngleAxes,'Estimated','True','Location','best');

handles.StatusAxes=nexttile(layout);
axis(handles.StatusAxes,'off');
handles.Status=text(handles.StatusAxes,0.03,0.95,'Starting...', ...
    'Units','normalized','VerticalAlignment','top','Color','w', ...
    'FontName','Courier New','FontSize',12);

allAxes=[handles.TrajectoryAxes handles.SpectrumAxes handles.DoaAxes handles.AngleAxes handles.StatusAxes];
for index=1:numel(allAxes)
    set(allAxes(index),'Color',[0.12 0.13 0.17],'XColor',[0.85 0.85 0.85], ...
        'YColor',[0.85 0.85 0.85],'ZColor',[0.85 0.85 0.85]);
end
drawnow;
end
