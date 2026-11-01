classdef PlatformDynamics3D < matlab.System
    properties (Nontunable)
        Velocity = 25
        MaxTurnRate = 15
        MaxClimbRate = 10
        GuidanceLaw = 'proportional'
        ProNavGain = 3
        NavFilterAlpha = 0.3
        Dt = 0.1
        InitialPosition = [0 0 50]
        InitialYaw = 0
        InitialPitch = 0
        InitialRoll = 0
        ArrivalRadius = 10
    end
    properties (Access=private)
        Position
        Yaw
        Pitch
        Roll
        FilteredAz
        FilteredEl
        PreviousAz
        PreviousEl
        Initialized
    end
    methods
        function obj=PlatformDynamics3D(varargin)
            setProperties(obj,nargin,varargin{:});
        end
    end
    methods (Access=protected)
        function setupImpl(obj), obj.initializeState(); end
        function [position,yaw,pitch,roll,range,arrived]= ...
                stepImpl(obj,doaAz,doaEl,detectionValid,sourcePosition)
            % Simulink Constant blocks can propagate a 3-element vector as
            % 3x1.  Keep all Cartesian vectors explicitly 1x3 so implicit
            % expansion cannot turn a position difference into a 3x3 matrix.
            sourcePosition=reshape(sourcePosition,1,3);
            range=norm(sourcePosition-obj.Position);
            arrived=range<=obj.ArrivalRadius;
            if arrived
                position=obj.Position; yaw=obj.Yaw;
                pitch=obj.Pitch; roll=obj.Roll;
                return
            end
            yawCommand=0; pitchCommand=0;
            if detectionValid
                measuredAz=obj.wrap180(doaAz);
                if ~obj.Initialized
                    obj.FilteredAz=measuredAz; obj.FilteredEl=doaEl;
                    obj.PreviousAz=measuredAz; obj.PreviousEl=doaEl;
                    obj.Initialized=true;
                end
                alpha=obj.NavFilterAlpha;
                azInnovation=obj.wrap180(measuredAz-obj.FilteredAz);
                obj.FilteredAz=obj.wrap180(obj.FilteredAz+alpha*azInnovation);
                obj.FilteredEl=obj.FilteredEl+alpha*(doaEl-obj.FilteredEl);
                switch lower(obj.GuidanceLaw)
                    case 'proportional'
                        azRate=obj.wrap180(obj.FilteredAz-obj.PreviousAz)/obj.Dt;
                        elRate=(obj.FilteredEl-obj.PreviousEl)/obj.Dt;
                        yawCommand=obj.FilteredAz+obj.ProNavGain*azRate*obj.Dt;
                        pitchCommand=obj.FilteredEl+obj.ProNavGain*elRate*obj.Dt;
                    case 'lead'
                        yawCommand=1.2*obj.FilteredAz;
                        pitchCommand=1.2*obj.FilteredEl;
                    otherwise
                        yawCommand=obj.FilteredAz;
                        pitchCommand=obj.FilteredEl;
                end
                obj.PreviousAz=obj.FilteredAz;
                obj.PreviousEl=obj.FilteredEl;
            end
            yawRate=max(-obj.MaxTurnRate,min(obj.MaxTurnRate,yawCommand/obj.Dt));
            pitchRate=max(-obj.MaxClimbRate,min(obj.MaxClimbRate,pitchCommand/obj.Dt));
            obj.Yaw=obj.wrap180(obj.Yaw+yawRate*obj.Dt);
            obj.Pitch=max(-60,min(60,obj.Pitch+pitchRate*obj.Dt));
            obj.Roll=max(-45,min(45,-2*yawRate));
            velocity=[obj.Velocity*cosd(obj.Pitch)*cosd(obj.Yaw), ...
                obj.Velocity*cosd(obj.Pitch)*sind(obj.Yaw), ...
                obj.Velocity*sind(obj.Pitch)];
            obj.Position=obj.Position+velocity*obj.Dt;
            position=obj.Position; yaw=obj.Yaw; pitch=obj.Pitch; roll=obj.Roll;
            range=norm(sourcePosition-obj.Position);
            arrived=range<=obj.ArrivalRadius;
        end
        function resetImpl(obj), obj.initializeState(); end
        function [a,b,c,d,e,f]=getOutputSizeImpl(~)
            a=[1 3]; b=[1 1]; c=[1 1]; d=[1 1]; e=[1 1]; f=[1 1];
        end
        function [a,b,c,d,e,f]=getOutputDataTypeImpl(~)
            a='double'; b='double'; c='double'; d='double'; e='double'; f='logical';
        end
        function [a,b,c,d,e,f]=isOutputComplexImpl(~)
            a=false; b=false; c=false; d=false; e=false; f=false;
        end
        function [a,b,c,d,e,f]=isOutputFixedSizeImpl(~)
            a=true; b=true; c=true; d=true; e=true; f=true;
        end
        function [a,b,c,d]=getInputNamesImpl(~)
            a='DOA_Az'; b='DOA_El'; c='DetectionValid'; d='SourcePosition';
        end
        function [a,b,c,d,e,f]=getOutputNamesImpl(~)
            a='Position'; b='Yaw'; c='Pitch'; d='Roll'; e='Range'; f='Arrived';
        end
        function icon=getIconImpl(obj), icon=sprintf('Platform 3D\n%s, V=%.0f',obj.GuidanceLaw,obj.Velocity); end
    end
    methods (Access=private)
        function initializeState(obj)
            obj.Position=reshape(obj.InitialPosition,1,3);
            obj.Yaw=obj.InitialYaw; obj.Pitch=obj.InitialPitch; obj.Roll=obj.InitialRoll;
            obj.FilteredAz=0; obj.FilteredEl=0;
            obj.PreviousAz=0; obj.PreviousEl=0; obj.Initialized=false;
        end
        function angle=wrap180(~,angle)
            angle=mod(angle+180,360)-180;
        end
    end
end
