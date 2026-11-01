function verify_full_attitude_geometry()
%VERIFY_FULL_ATTITUDE_GEOMETRY Validate combined yaw, pitch, and roll frames.
run('sim3d_params.m');
worldDirection=[.72;.51;.47]; worldDirection=worldDirection/norm(worldDirection);
attitudes=[0 0 0;35 18 12;-47 21 -19;130 -25 31];
truth=TruthErrorMonitor3D('SourcePosition',1000*worldDirection.');
for index=1:size(attitudes,1)
    yaw=attitudes(index,1); pitch=attitudes(index,2); roll=attitudes(index,3);
    rotation=body_to_navigation_dcm(yaw,pitch,roll);
    assert(norm(rotation'*rotation-eye(3),'fro')<1e-12, ...
        'Body/navigation DCM is not orthonormal.');
    body=rotation'*worldDirection;
    azimuth=atan2d(body(2),body(1));
    elevation=atan2d(body(3),hypot(body(1),body(2)));
    [trueAz,trueEl,azError,elError,error3d]=truth( ...
        [0;0;0],yaw,pitch,roll,azimuth,elevation);
    assert(abs(trueAz-azimuth)<1e-10 && abs(trueEl-elevation)<1e-10, ...
        'Truth monitor attitude transform mismatch.');
    assert(abs(azError)<1e-10 && abs(elError)<1e-10 && error3d<1e-6, ...
        'Full-attitude truth error is not zero.');
end
release(truth);
fprintf('PASS: full yaw/pitch/roll body-navigation geometry.\n');
end
