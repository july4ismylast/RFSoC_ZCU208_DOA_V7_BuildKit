classdef DOAEstimator4Ch < matlab.System
    % Four-channel 2x2 DOA estimator with an RFSoC-oriented fast path.
    %
    % HYBRID_CAL_WPI_ML_EKF performs:
    %   1) per-channel complex gain/phase calibration;
    %   2) accumulation of a 4x4 spatial covariance matrix;
    %   3) six-baseline, coherence-weighted phase least squares;
    %   4) a fixed 36-candidate off-grid single-source ML refinement; and
    %   5) a normalized constant-rate unit-vector EKF.
    %
    % The default array lies in the Y-Z plane and therefore needs the known
    % forward-hemisphere (+X) constraint.  It cannot distinguish a source in
    % front of the array from its mirror source behind the array.
    properties (Nontunable)
        Algorithm = 'HYBRID_CAL_WPI_ML_EKF'
        CenterFreqHz = 4e9
        ArrayPositions = [0 -0.0125 -0.0125; 0 0.0125 -0.0125; ...
                          0 -0.0125  0.0125; 0 0.0125  0.0125]
        NumSignals = 1
        AzScanRange = [-55 55]
        ElScanRange = [-45 45]
        ScanResolution = 1
        ForwardBackwardAvg = true
        CalibrationGain_dB = [0 0 0 0]
        CalibrationPhase_deg = [0 0 0 0]
        CalibrationDecouplingMatrix = eye(4)
        MLStepSchedule_deg = [0.5 0.1 0.02 0.005]
        EnableGNPolish = true
        GNIterations = 2
        GNMaxStep_deg = 0.05
        EnableTracking = true
        TrackerDt = 0.1
        EKFProcessNoise = 2e-5
        EKFMeasurementNoise = 1.5e-5
        c = 299792458
    end
    properties (Access=private)
        AzimuthGrid
        ElevationGrid
        TrackerState
        TrackerCovariance
        TrackerInitialized
    end
    methods
        function obj=DOAEstimator4Ch(varargin)
            setProperties(obj,nargin,varargin{:});
        end
    end
    methods (Access=protected)
        function setupImpl(obj,~,~,~,~)
            validateattributes(obj.ArrayPositions,{'numeric'}, ...
                {'size',[4 3],'real','finite'},mfilename,'ArrayPositions');
            validateattributes(obj.CalibrationGain_dB,{'numeric'}, ...
                {'vector','numel',4,'real','finite'},mfilename,'CalibrationGain_dB');
            validateattributes(obj.CalibrationPhase_deg,{'numeric'}, ...
                {'vector','numel',4,'real','finite'},mfilename,'CalibrationPhase_deg');
            validateattributes(obj.CalibrationDecouplingMatrix,{'numeric'}, ...
                {'size',[4 4],'finite'},mfilename,'CalibrationDecouplingMatrix');
            obj.AzimuthGrid=obj.AzScanRange(1):obj.ScanResolution:obj.AzScanRange(2);
            obj.ElevationGrid=obj.ElScanRange(1):obj.ScanResolution:obj.ElScanRange(2);
            obj.TrackerState=zeros(6,1);
            obj.TrackerCovariance=eye(6);
            obj.TrackerInitialized=false;

            lambda=obj.c/obj.CenterFreqHz;
            maximumBaseline=0;
            for first=1:3
                for second=first+1:4
                    maximumBaseline=max(maximumBaseline, ...
                        norm(obj.ArrayPositions(second,:)-obj.ArrayPositions(first,:)));
                end
            end
            if maximumBaseline>lambda/2+10*eps(lambda)
                error('DOA2x2:AmbiguousBaseline', ...
                    ['The largest baseline is %.5f m, greater than lambda/2 ' ...
                     '(%.5f m). Weighted phase LS would need phase unwrapping.'], ...
                    maximumBaseline,lambda/2);
            end
        end

        function [azimuth,elevation,spectrum]=stepImpl( ...
                obj,snapshots,platformYaw,platformPitch,platformRoll)
            calibrated=obj.applyCalibration(snapshots);
            covariance=(calibrated.'*conj(calibrated))/size(calibrated,1);
            covariance=(covariance+covariance')/2;
            if obj.ForwardBackwardAvg
                exchange=fliplr(eye(4));
                covariance=0.5*(covariance+exchange*conj(covariance)*exchange);
            end

            switch upper(char(obj.Algorithm))
                case {'HYBRID_CAL_WPI_ML_EKF','HYBRID','WPI_ML_EKF'}
                    [rawAzimuth,rawElevation]=obj.weightedPhaseSeed(covariance);
                    [rawAzimuth,rawElevation]=obj.localMLRefinement( ...
                        covariance,rawAzimuth,rawElevation);
                    if obj.EnableGNPolish
                        [rawAzimuth,rawElevation]=obj.gaussNewtonPolish( ...
                            covariance,rawAzimuth,rawElevation);
                    end
                    if obj.EnableTracking
                        [azimuth,elevation]=obj.unitVectorEKF( ...
                            rawAzimuth,rawElevation,platformYaw,platformPitch,platformRoll);
                    else
                        azimuth=rawAzimuth;
                        elevation=rawElevation;
                    end
                    spectrum=obj.markerSpectrum(azimuth,elevation);
                case 'PHASE_INTERFEROMETRY'
                    [azimuth,elevation]=obj.weightedPhaseSeed(covariance);
                    spectrum=obj.markerSpectrum(azimuth,elevation);
                case 'MVDR'
                    [azimuth,elevation,spectrum]=obj.mvdrDOA(covariance);
                case 'ESPRIT'
                    % For a single source on this non-shift-invariant 2x2
                    % ordering, calibrated phase LS is the fast solution.
                    [azimuth,elevation]=obj.weightedPhaseSeed(covariance);
                    spectrum=obj.markerSpectrum(azimuth,elevation);
                otherwise
                    [azimuth,elevation,spectrum]=obj.musicDOA(covariance);
            end
        end

        function resetImpl(obj)
            obj.TrackerState=zeros(6,1);
            obj.TrackerCovariance=eye(6);
            obj.TrackerInitialized=false;
        end

        function [a,b,c]=getOutputSizeImpl(obj)
            a=[1 1]; b=[1 1];
            numberAz=numel(obj.AzScanRange(1):obj.ScanResolution:obj.AzScanRange(2));
            numberEl=numel(obj.ElScanRange(1):obj.ScanResolution:obj.ElScanRange(2));
            c=[numberEl numberAz];
        end
        function [a,b,c]=getOutputDataTypeImpl(~), a='double'; b='double'; c='double'; end
        function [a,b,c]=isOutputComplexImpl(~), a=false; b=false; c=false; end
        function [a,b,c]=isOutputFixedSizeImpl(~), a=true; b=true; c=true; end
        function [a,b,c,d]=getInputNamesImpl(~)
            a='X4_snapshots'; b='PlatformYaw_deg'; c='PlatformPitch_deg';
            d='PlatformRoll_deg';
        end
        function [a,b,c]=getOutputNamesImpl(~), a='Az_deg'; b='El_deg'; c='DOA_Spectrum'; end
        function icon=getIconImpl(obj), icon=sprintf('2x2 %s\ncal + WPI + ML + EKF',obj.Algorithm); end
    end

    methods (Access=private)
        function calibrated=applyCalibration(obj,snapshots)
            calibrated=snapshots;
            for channel=1:4
                correction=10^(-obj.CalibrationGain_dB(channel)/20)* ...
                    exp(-1j*deg2rad(obj.CalibrationPhase_deg(channel)));
                calibrated(:,channel)=calibrated(:,channel)*correction;
            end
            calibrated=calibrated*obj.CalibrationDecouplingMatrix.';
        end

        function [azimuth,elevation]=weightedPhaseSeed(obj,covariance)
            pairs=[1 2; 1 3; 1 4; 2 3; 2 4; 3 4];
            baseline=zeros(6,2);
            phase=zeros(6,1);
            weight=zeros(6,1);
            for pairIndex=1:6
                first=pairs(pairIndex,1);
                second=pairs(pairIndex,2);
                difference=obj.ArrayPositions(second,:)-obj.ArrayPositions(first,:);
                baseline(pairIndex,:)=difference(2:3);
                crossValue=covariance(second,first);
                phase(pairIndex)=angle(crossValue);
                denominator=max(real(covariance(first,first))* ...
                    real(covariance(second,second)),eps);
                coherence=min(0.999,max(0.001,abs(crossValue)^2/denominator));
                weight(pairIndex)=min(100,max(0.05,coherence/(1-coherence)));
            end
            normal=baseline'*(weight.*baseline);
            rightSide=baseline'*(weight.*phase);
            waveNumber=2*pi*obj.CenterFreqHz/obj.c;
            directionYZ=-(normal+1e-12*eye(2))\rightSide/waveNumber;
            magnitude=norm(directionYZ);
            if magnitude>0.999999
                directionYZ=directionYZ*(0.999999/magnitude);
            end
            [azimuth,elevation]=obj.yzCosinesToAngles( ...
                directionYZ(1),directionYZ(2));
            azimuth=max(obj.AzScanRange(1),min(obj.AzScanRange(2),azimuth));
            elevation=max(obj.ElScanRange(1),min(obj.ElScanRange(2),elevation));
        end

        function [azimuth,elevation]=localMLRefinement(obj,covariance,azimuth,elevation)
            for stage=1:numel(obj.MLStepSchedule_deg)
                stepSize=obj.MLStepSchedule_deg(stage);
                bestScore=-inf;
                bestAzimuth=azimuth;
                bestElevation=elevation;
                for elevationOffset=-1:1
                    for azimuthOffset=-1:1
                        candidateAzimuth=max(obj.AzScanRange(1), ...
                            min(obj.AzScanRange(2),azimuth+azimuthOffset*stepSize));
                        candidateElevation=max(obj.ElScanRange(1), ...
                            min(obj.ElScanRange(2),elevation+elevationOffset*stepSize));
                        steering=obj.steeringVector(candidateAzimuth,candidateElevation);
                        score=real(steering'*covariance*steering)/4;
                        if score>bestScore
                            bestScore=score;
                            bestAzimuth=candidateAzimuth;
                            bestElevation=candidateElevation;
                        end
                    end
                end
                azimuth=bestAzimuth;
                elevation=bestElevation;
            end
        end

        function [azimuth,elevation]=gaussNewtonPolish( ...
                obj,covariance,azimuth,elevation)
            % A fixed four-step power iteration forms a rank-one signal
            % projector without a general eigendecomposition. Two bounded
            % Gauss-Newton updates then remove the last local grid residue.
            signalVector=obj.steeringVector(azimuth,elevation);
            for powerIteration=1:4
                signalVector=covariance*signalVector;
                signalVector=signalVector/max(norm(signalVector),eps);
            end
            noiseProjector=eye(4)-signalVector*signalVector';
            waveNumber=2*pi*obj.CenterFreqHz/obj.c;
            for iteration=1:obj.GNIterations
                azimuthRad=deg2rad(azimuth);
                elevationRad=deg2rad(elevation);
                direction=[cos(elevationRad)*cos(azimuthRad); ...
                    cos(elevationRad)*sin(azimuthRad); sin(elevationRad)];
                directionAz=[-cos(elevationRad)*sin(azimuthRad); ...
                    cos(elevationRad)*cos(azimuthRad); 0];
                directionEl=[-sin(elevationRad)*cos(azimuthRad); ...
                    -sin(elevationRad)*sin(azimuthRad); cos(elevationRad)];
                steering=exp(-1j*waveNumber*(obj.ArrayPositions*direction));
                derivative=[ ...
                    -1j*waveNumber*(obj.ArrayPositions*directionAz).*steering, ...
                    -1j*waveNumber*(obj.ArrayPositions*directionEl).*steering];
                gradient=2*real(derivative'*(noiseProjector*steering));
                hessian=2*real(derivative'*noiseProjector*derivative)+1e-7*eye(2);
                step_deg=rad2deg(hessian\gradient);
                stepNorm=norm(step_deg);
                if stepNorm>obj.GNMaxStep_deg
                    step_deg=step_deg*(obj.GNMaxStep_deg/stepNorm);
                end
                azimuth=azimuth-step_deg(1);
                elevation=elevation-step_deg(2);
                azimuth=max(obj.AzScanRange(1),min(obj.AzScanRange(2),azimuth));
                elevation=max(obj.ElScanRange(1),min(obj.ElScanRange(2),elevation));
            end
        end

        function [azimuth,elevation]=unitVectorEKF( ...
                obj,measuredAzimuth,measuredElevation,platformYaw,platformPitch,platformRoll)
            % The array measurement is in the rotating body frame. Track in
            % the navigation/world frame so commanded yaw and pitch do not
            % appear as fictitious target motion inside the EKF.
            bodyMeasurement=obj.anglesToUnitVector( ...
                measuredAzimuth,measuredElevation);
            rotation=body_to_navigation_dcm( ...
                platformYaw,platformPitch,platformRoll);
            measurement=rotation*bodyMeasurement;
            if ~obj.TrackerInitialized
                obj.TrackerState=[measurement; zeros(3,1)];
                obj.TrackerCovariance=diag([1e-4 1e-4 1e-4 1e-2 1e-2 1e-2]);
                obj.TrackerInitialized=true;
            else
                dt=obj.TrackerDt;
                transition=[eye(3) dt*eye(3); zeros(3) eye(3)];
                predicted=transition*obj.TrackerState;
                predicted(1:3)=obj.normalizeVector(predicted(1:3));
                predicted(4:6)=predicted(4:6)- ...
                    predicted(1:3)*(predicted(1:3)'*predicted(4:6));
                process=obj.EKFProcessNoise*diag([dt^2 dt^2 dt^2 1 1 1]);
                predictedCovariance=transition*obj.TrackerCovariance*transition'+process;
                observation=[eye(3) zeros(3)];
                measurementCovariance=obj.EKFMeasurementNoise*eye(3);
                innovationCovariance=observation*predictedCovariance* ...
                    observation'+measurementCovariance;
                gain=(predictedCovariance*observation')/innovationCovariance;
                updated=predicted+gain*(measurement-observation*predicted);
                updated(1:3)=obj.normalizeVector(updated(1:3));
                updated(4:6)=updated(4:6)- ...
                    updated(1:3)*(updated(1:3)'*updated(4:6));
                identity=eye(6);
                residual=identity-gain*observation;
                obj.TrackerCovariance=residual*predictedCovariance*residual'+ ...
                    gain*measurementCovariance*gain';
                obj.TrackerState=updated;
            end
            bodyEstimate=rotation.'*obj.TrackerState(1:3);
            [azimuth,elevation]=obj.unitVectorToAngles(bodyEstimate);
            azimuth=obj.wrap180(azimuth);
        end

        function steering=steeringVector(obj,azimuth,elevation)
            direction=obj.anglesToUnitVector(azimuth,elevation);
            delay=obj.ArrayPositions*direction/obj.c;
            steering=exp(-1j*2*pi*obj.CenterFreqHz*delay);
        end

        function [azimuth,elevation,spectrum]=musicDOA(obj,covariance)
            [vectors,values]=eig(covariance,'vector');
            [~,order]=sort(real(values),'descend');
            noiseSpace=vectors(:,order(obj.NumSignals+1:end));
            projector=noiseSpace*noiseSpace';
            spectrum=zeros(numel(obj.ElevationGrid),numel(obj.AzimuthGrid));
            for elIndex=1:numel(obj.ElevationGrid)
                for azIndex=1:numel(obj.AzimuthGrid)
                    steering=obj.steeringVector( ...
                        obj.AzimuthGrid(azIndex),obj.ElevationGrid(elIndex));
                    denominator=abs(steering'*projector*steering);
                    spectrum(elIndex,azIndex)=1/max(denominator,eps);
                end
            end
            spectrum=10*log10(spectrum/max(spectrum(:))+1e-15);
            [~,maximum]=max(spectrum(:));
            [elIndex,azIndex]=ind2sub(size(spectrum),maximum);
            azimuth=obj.AzimuthGrid(azIndex);
            elevation=obj.ElevationGrid(elIndex);
        end

        function [azimuth,elevation,spectrum]=mvdrDOA(obj,covariance)
            inverse=(covariance+1e-6*trace(covariance)/4*eye(4))\eye(4);
            spectrum=zeros(numel(obj.ElevationGrid),numel(obj.AzimuthGrid));
            for elIndex=1:numel(obj.ElevationGrid)
                for azIndex=1:numel(obj.AzimuthGrid)
                    steering=obj.steeringVector( ...
                        obj.AzimuthGrid(azIndex),obj.ElevationGrid(elIndex));
                    spectrum(elIndex,azIndex)=1/max( ...
                        abs(steering'*inverse*steering),eps);
                end
            end
            spectrum=10*log10(spectrum/max(spectrum(:))+1e-15);
            [~,maximum]=max(spectrum(:));
            [elIndex,azIndex]=ind2sub(size(spectrum),maximum);
            azimuth=obj.AzimuthGrid(azIndex);
            elevation=obj.ElevationGrid(elIndex);
        end

        function spectrum=markerSpectrum(obj,azimuth,elevation)
            spectrum=-120*ones(numel(obj.ElevationGrid),numel(obj.AzimuthGrid));
            [~,azIndex]=min(abs(obj.AzimuthGrid-azimuth));
            [~,elIndex]=min(abs(obj.ElevationGrid-elevation));
            spectrum(elIndex,azIndex)=0;
        end

        function vector=anglesToUnitVector(~,azimuth,elevation)
            vector=[cosd(elevation)*cosd(azimuth); ...
                    cosd(elevation)*sind(azimuth); sind(elevation)];
        end

        function [azimuth,elevation]=unitVectorToAngles(~,vector)
            vector=vector/max(norm(vector),eps);
            azimuth=atan2d(vector(2),vector(1));
            elevation=asind(max(-1,min(1,vector(3))));
        end

        function [azimuth,elevation]=yzCosinesToAngles(~,uy,uz)
            uy=max(-0.999999,min(0.999999,real(uy)));
            uz=max(-0.999999,min(0.999999,real(uz)));
            horizontalYZ=uy^2+uz^2;
            if horizontalYZ>=1
                scale=0.999999/sqrt(horizontalYZ);
                uy=uy*scale;
                uz=uz*scale;
            end
            ux=sqrt(max(1-uy^2-uz^2,eps));
            azimuth=atan2d(uy,ux);
            elevation=asind(uz);
        end

        function vector=normalizeVector(~,vector)
            vector=vector/max(norm(vector),eps);
        end

        function angle=wrap180(~,angle)
            angle=mod(angle+180,360)-180;
        end
    end
end
