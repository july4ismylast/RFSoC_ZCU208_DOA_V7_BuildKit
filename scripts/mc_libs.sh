#!/usr/bin/env bash
# Where are the Model Composer block libraries, and can MATLAB see them?
#
# This is the diagnostic for "There is no block named 'vmcUtilities/Vitis Model
# Composer Hub'": a batch MATLAB session does not inherit the GUI launcher's
# path, so the libraries must be found and added explicitly.  Nothing is built
# here; it only reports what mc_paths() finds.
set -euo pipefail
# shellcheck source=scripts/mc_env.sh
source "$(cd "$(dirname "$0")" && pwd)/mc_env.sh"
cd "$mc_root_repo"
echo "MC_LIBS_CACHE:        ${MC_LIBS_CACHE:-(unset)}"
echo
"$MATLAB_2022B" -batch "addpath('$mc_root_repo/ip/model_composer/channelizer'); info = mc_paths(); fprintf('\n'); fprintf('libraries on the path: %s\n', strjoin(info.libraries, ', ')); fprintf('MC_ROOT:  %s\n', info.mcRoot); fprintf('MC_LIBS_CACHE written: %s\n', getenv('MC_LIBS_CACHE'));"
