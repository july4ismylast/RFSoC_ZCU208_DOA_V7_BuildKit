function ok = mc_platform_attempts(hub, model, hubOptions)
%MC_PLATFORM_ATTEMPTS Try the hardware-selection variants the Hub allows.
%   xmcGenerate dies with "Index exceeds the number of array elements" and nothing
%   names a field.  The Hub's empty parameters are Platform and the AI Engine
%   paths; a Zynq UltraScale+ RFSoC design is exactly the case where Model
%   Composer expects a board (platform) rather than a bare part, so the allowed
%   PlatformType strings are tried with the board from config.mk (BOARD_PART).
%   Whatever worked is printed; the original PlatformType is restored otherwise.
arguments
    hub (1, :) char
    model (1, :) char
    hubOptions struct = struct()
end
ok = false;
board = getenv('MC_BOARD');
try
    originalType = get_param(hub, 'PlatformType');
catch problem
    fprintf(2, '  no PlatformType on %s: %s\n', hub, problem.message);
    return;
end

types = {};
if isfield(hubOptions, 'PlatformType')
    types = hubOptions.PlatformType;
end
if isempty(types)
    types = {originalType};
end
platforms = {''};
if ~isempty(board)
    platforms = {board, ''};
end
if isfield(hubOptions, 'Platform') && ~isempty(hubOptions.Platform)
    platforms = [hubOptions.Platform(:)', platforms]; %#ok<AGROW>
end

fprintf('\n  trying hardware-selection variants (board: %s)\n', printable(board));
for typeIndex = 1:numel(types)
    for platformIndex = 1:numel(platforms)
        name = types{typeIndex};
        platform = platforms{platformIndex};
        if ~setQuietly(hub, 'PlatformType', name)
            continue;
        end
        if ~isempty(platform)
            if ~setQuietly(hub, 'Platform', platform)
                continue;
            end
        end
        fprintf('    PlatformType = %-14s Platform = %s\n', name, printable(platform));
        try
            xmcGenerate(model, 'closeProgressWindow', 1);
            fprintf('  generation started with PlatformType = %s, Platform = %s\n', ...
                name, printable(platform));
            ok = true;
            % Keep the configuration that worked in the model, so the next run
            % does not have to search for it again.
            try
                save_system(model);
                fprintf('  saved %s with that selection\n', model);
            catch saveProblem
                fprintf('  note: could not save %s: %s\n', model, saveProblem.message);
            end
            return;
        catch problem
            fprintf(2, '      failed: %s\n', problem.message);
        end
    end
end
if ~ok
    setQuietly(hub, 'PlatformType', originalType);
    fprintf(2, '  no hardware-selection variant started generation\n');
end
end

function worked = setQuietly(block, parameter, value)
%SETQUIETLY Write a popup parameter, reporting only whether it took.
worked = false;
try
    set_param(block, parameter, value);
    worked = true;
catch problem
    fprintf('      %s = %s rejected: %s\n', parameter, printable(value), problem.message);
end
end

function text = printable(value)
if isempty(value)
    text = '(empty)';
else
    text = char(value);
end
end
