function part = mc_part_string(full)
%MC_PART_STRING Split a Vivado part name into the fields the Hub wants.
%   xczu48dr-fsvg1517-2-e becomes device xczu48dr, package fsvg1517, speed -2-e
%   and family zynquplus.  A live run needed every one of them: setting only
%   `part` made every sysgen block report "Target hardware is not selected".
arguments
    full (1, :) char = getenv('MC_PART')
end
if isempty(full)
    full = 'xczu48dr-fsvg1517-2-e';
end
pieces = strsplit(full, '-');
part = struct('full', full, 'device', pieces{1}, 'package', '', 'speed', '', ...
    'family', 'zynquplus');
if numel(pieces) >= 2
    part.package = pieces{2};
end
if numel(pieces) >= 4
    part.speed = ['-' pieces{3} '-' pieces{4}];
end
if contains(part.device, 'ku')
    part.family = 'kintexuplus';
elseif contains(part.device, 'vu')
    part.family = 'virtexuplus';
end
end
