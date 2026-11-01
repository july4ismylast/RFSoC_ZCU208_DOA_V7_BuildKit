function rotation=body_to_navigation_dcm(yaw_deg,pitch_deg,roll_deg)
%BODY_TO_NAVIGATION_DCM ZYX body-to-navigation rotation for this project.
% Coordinates are right-handed X-forward, Y-right, Z-up. Positive yaw turns
% +X toward +Y, positive pitch raises the nose, and positive roll rotates
% +Y toward +Z.
cy=cosd(yaw_deg); sy=sind(yaw_deg);
cp=cosd(pitch_deg); sp=sind(pitch_deg);
cr=cosd(roll_deg); sr=sind(roll_deg);
rotation=[ ...
    cy*cp, -sy*cr-cy*sp*sr,  sy*sr-cy*sp*cr; ...
    sy*cp,  cy*cr-sy*sp*sr, -cy*sr-sy*sp*cr; ...
       sp,              cp*sr,              cp*cr];
end
