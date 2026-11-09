function ok = mc_require_libraries(verbose)
%MC_REQUIRE_LIBRARIES Put the AMD block libraries on the path before opening a model.
%   A real run reported this on AMD's own example:
%
%       hub SSRDDC/Vitis Model Composer Hub: ExportType=, device=
%       cannot write ExportType = IP Catalog ...
%       MaskType=, ReferenceBlock=
%       no mask parameters are visible on this block
%       Warning: Cannot find library called 'vmcUtilities'.
%
%   Every symptom has one cause: the block is a link into vmcUtilities, the
%   library is not on this session's path, so the link never resolves and the
%   masked block has no parameters at all.  Writing one then fails with
%   "Reference block does not have a parameter named 'ExportType'" -- a message
%   about the link, not about the parameter.
%
%   Call this BEFORE open_system / load_system, and mc_resolve_links immediately
%   after: a link that failed to resolve once stays unresolved until it is told to
%   resolve again.
%
%   Only vmcUtilities and hdlBasic are required -- the Hub and the gateway/delay
%   blocks this kit uses.  The rest are tried and reported, because a name that
%   exists in one release does not have to exist in another: xilinxUtilities, for
%   instance, is not in Model Composer 2023.2 at all, and demanding it stopped a
%   run that was otherwise ready.
arguments
    verbose (1, 1) logical = true
end

info = mc_paths(verbose);
required = {'vmcUtilities', 'hdlBasic'};
optional = {'hdlUtilities', 'xilinxUtilities'};
found = {};
absent = {};
for index = 1:numel(required)
    if libraryLoads(required{index})
        found{end + 1} = required{index}; %#ok<AGROW>
    else
        absent{end + 1} = required{index}; %#ok<AGROW>
    end
end
for index = 1:numel(optional)
    if libraryLoads(optional{index})
        found{end + 1} = optional{index}; %#ok<AGROW>
    end
end
ok = ~any(strcmp(absent, 'vmcUtilities')) && ~any(strcmp(absent, 'hdlBasic'));
if verbose
    if ~isempty(found)
        fprintf('libraries on this path: %s\n', strjoin(found, ', '));
    end
    if ~isempty(absent)
        fprintf('not found (not on this install): %s\n', strjoin(absent, ', '));
    end
end
if ok
    return
end
fprintf(2, 'the Model Composer block libraries needed here are not on this path:\n');
for index = 1:numel(absent)
    fprintf(2, '  %s\n', absent{index});
end
fprintf(2, 'Model Composer root: %s\n', printable(info.mcRoot));
fprintf(2, ['A Hub block whose library is missing has no parameters, so every write ' ...
    'is refused\nwith "Reference block does not have a parameter named ...".  ' ...
    'Set MC_ROOT to the\nModel_Composer/<version> folder and call this again.\n']);
end

function loads = libraryLoads(name)
loads = exist(name, 'file') ~= 0;
if loads
    return
end
try
    load_system(name);
    loads = true;
catch
    loads = false;
end
end

function text = printable(value)
if isempty(value)
    text = '(not found)';
else
    text = value;
end
end
