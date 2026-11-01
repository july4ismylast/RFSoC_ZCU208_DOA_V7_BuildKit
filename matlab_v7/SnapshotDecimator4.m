classdef SnapshotDecimator4 < matlab.System
    properties (Nontunable)
        FrameLength = 8192
        DecimationFactor = 1024
    end
    methods
        function obj=SnapshotDecimator4(varargin)
            setProperties(obj,nargin,varargin{:});
        end
    end
    methods (Access=protected)
        function output=stepImpl(obj,input), output=input(1:obj.DecimationFactor:end,:); end
        function sizeOut=getOutputSizeImpl(obj)
            sizeOut=[ceil(obj.FrameLength/obj.DecimationFactor) 4];
        end
        function typeOut=getOutputDataTypeImpl(~), typeOut='double'; end
        function value=isOutputComplexImpl(~), value=true; end
        function value=isOutputFixedSizeImpl(~), value=true; end
        function name=getInputNamesImpl(~), name='X4'; end
        function name=getOutputNamesImpl(~), name='Snapshots'; end
        function icon=getIconImpl(obj), icon=sprintf('Snapshots\n1:%d:end',obj.DecimationFactor); end
    end
end
