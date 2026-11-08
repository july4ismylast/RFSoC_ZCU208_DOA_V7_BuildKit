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
%   about the link, not about the parameter.  The fix is not a different spelling
%   of the parameter name; it is loading the library first.
%
%   Call this BEFORE open_system / load_system.  A link that failed to resolve
%   once stays unresolved until the model is closed and opened again.
arguments
    verbose (1, 1) logical = true
end

info = mc_paths(verbose);
wanted = {'vmcUtilities', 'hdlBasic', 'hdlUtilities', 'xilinxUtilities'};
missing = {};
for index = 1:numel(wanted)
    name = wanted{index};
    if exist(name, 'file') ~= 0
        continue
    end
    try
        load_system(name);
    catch problem
        missing{end + 1} = sprintf('%s (%s)', name, problem.message); %#ok<AGROW>
    end
end
ok = isempty(missing);
if ok
    if verbose
        fprintf('Model Composer libraries ready: %s\n', strjoin(wanted, ', '));
    end
    return
end
fprintf(2, 'the Model Composer block libraries are not on this path:\n');
for index = 1:numel(missing)
    fprintf(2, '  %s\n', missing{index});
end
fprintf(2, 'Model Composer root: %s\n', printable(info.mcRoot));
fprintf(2, ['A Hub block whose library is missing has no parameters, so every write ' ...
    'is refused\nwith "Reference block does not have a parameter named ...".  ' ...
    'Set MC_ROOT to the\nModel_Composer/<version> folder and call this again.\n']);
end

function text = printable(value)
if isempty(value)
    text = '(not found)';
else
    text = value;
end
end
