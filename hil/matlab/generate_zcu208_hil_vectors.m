function manifest=generate_zcu208_hil_vectors()
%GENERATE_ZCU208_HIL_VECTORS Board-named wrapper around the V7 vector generator.
v7Root=getenv('DOA_V7_MATLAB_ROOT');
outputDirectory=getenv('DOA_HIL_OUTPUT_DIR');
assert(isfolder(v7Root),'DOA_V7_MATLAB_ROOT is invalid: %s',v7Root);
if isempty(outputDirectory), outputDirectory=fullfile(pwd,'build','hil_vectors'); end
addpath(v7Root);
manifest=generate_zcu48dr_hil_vectors(outputDirectory);
manifest.board='ZCU208';
manifest.device='xczu48dr-fsvg1517-2-e';
manifest.stream_contract='AXI512: 4 lanes x 4 channels x complex int16';
file=fopen(fullfile(outputDirectory,'zcu208_manifest.json'),'w');
assert(file>=0,'Cannot create ZCU208 HIL manifest.');
fprintf(file,'%s',jsonencode(manifest,'PrettyPrint',true)); fclose(file);
fprintf('Created ZCU208 V7 HIL vectors in %s\n',outputDirectory);
end

