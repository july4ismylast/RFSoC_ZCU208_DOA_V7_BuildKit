function table=step5_ladder_costs(cell_row,tracks)
%STEP5_LADDER_COSTS The ladder's cost, rung by rung, for one cell vs N tracks.
%   TABLE=STEP5_LADDER_COSTS(CELL, TRACKS) returns a struct array with one row
%   per track:
%
%       .mod_distance  0 or 9        (a different label is a rejection)
%       .dir_distance  |d_az,d_el|/0.5 deg
%       .bw_distance   |log(bw_cell/bw_track)|/0.35
%       .cost          sum of the three squares
%       .passes        every rung inside its gate
%
%   This is the same arithmetic as step5_r5_tracking/py/ladder.py.  V07
%   section 19.15 is the derivation; the gates are
%       modulation 0.5   direction 1.5   bandwidth 1.0   cadence 1.2

sigma_dir_deg=0.5;
sigma_bw=0.35;
gate_dir=1.5;
gate_bw=1.0;
gate_mod=0.5;

table=struct('id',{},'mod_distance',{},'dir_distance',{}, ...
             'bw_distance',{},'cost',{},'passes',{});
for index=1:numel(tracks)
    track=tracks(index);
    if strcmp(cell_row.mod,track.mod)
        mod_distance=0;
    else
        mod_distance=9;
    end
    dir_distance=hypot(cell_row.az-track.az,cell_row.el-track.el)/sigma_dir_deg;
    bw_distance=abs(log(max(cell_row.bw_hz,1e6)/max(track.bw_hz,1e6)))/sigma_bw;
    table(index).id=track.id;
    table(index).mod_distance=mod_distance;
    table(index).dir_distance=dir_distance;
    table(index).bw_distance=bw_distance;
    table(index).cost=mod_distance^2+dir_distance^2+bw_distance^2;
    table(index).passes=(mod_distance<=gate_mod)&&(dir_distance<=gate_dir)&& ...
        (bw_distance<=gate_bw);
end
for index=1:numel(table)
    fprintf('track %d: mod %.1f  dir %.2f  bw %.2f  cost %6.2f  %s\n', ...
            table(index).id,table(index).mod_distance,table(index).dir_distance, ...
            table(index).bw_distance,table(index).cost, ...
            string(table(index).passes));
end
end
