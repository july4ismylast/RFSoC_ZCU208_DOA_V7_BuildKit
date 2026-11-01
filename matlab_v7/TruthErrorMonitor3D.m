classdef TruthErrorMonitor3D < matlab.System
    % Compute ground-truth body-frame DOA and estimation errors.
    properties (Nontunable)
        SourcePosition = [500 300 200]
    end
    methods
        function obj=TruthErrorMonitor3D(varargin)
            setProperties(obj,nargin,varargin{:});
        end
    end
    methods (Access=protected)
        function [trueAz,trueEl,azError,elError,angularError]= ...
                stepImpl(obj,platformPosition,platformYaw,platformPitch,platformRoll, ...
                estimatedAz,estimatedEl)
            platformPosition=reshape(platformPosition,1,3);
            sourcePosition=reshape(obj.SourcePosition,1,3);
            delta=sourcePosition-platformPosition;
            worldDirection=delta(:)/max(norm(delta),eps);
            bodyDirection=body_to_navigation_dcm( ...
                platformYaw,platformPitch,platformRoll).'*worldDirection;
            trueAz=obj.wrap180(atan2d(bodyDirection(2),bodyDirection(1)));
            trueEl=atan2d(bodyDirection(3),hypot(bodyDirection(1),bodyDirection(2)));
            azError=obj.wrap180(estimatedAz-trueAz);
            elError=estimatedEl-trueEl;
            estimatedVector=[cosd(estimatedEl)*cosd(estimatedAz), ...
                cosd(estimatedEl)*sind(estimatedAz),sind(estimatedEl)];
            trueVector=[cosd(trueEl)*cosd(trueAz), ...
                cosd(trueEl)*sind(trueAz),sind(trueEl)];
            cosine=max(-1,min(1,dot(estimatedVector,trueVector)));
            angularError=acosd(cosine);
        end
        function [a,b,c,d,e]=getOutputSizeImpl(~), a=[1 1]; b=a; c=a; d=a; e=a; end
        function [a,b,c,d,e]=getOutputDataTypeImpl(~)
            a='double'; b='double'; c='double'; d='double'; e='double';
        end
        function [a,b,c,d,e]=isOutputComplexImpl(~)
            a=false; b=false; c=false; d=false; e=false;
        end
        function [a,b,c,d,e]=isOutputFixedSizeImpl(~)
            a=true; b=true; c=true; d=true; e=true;
        end
        function [a,b,c,d,e,f]=getInputNamesImpl(~)
            a='PlatformPosition'; b='PlatformYaw'; c='PlatformPitch';
            d='PlatformRoll'; e='EstimatedAz'; f='EstimatedEl';
        end
        function [a,b,c,d,e]=getOutputNamesImpl(~)
            a='TrueAz'; b='TrueEl'; c='AzError'; d='ElError'; e='AngularError';
        end
        function icon=getIconImpl(~), icon=sprintf('Truth + DOA Error\nAz / El / Total'); end
    end
    methods (Access=private)
        function angle=wrap180(~,angle), angle=mod(angle+180,360)-180; end
    end
end
