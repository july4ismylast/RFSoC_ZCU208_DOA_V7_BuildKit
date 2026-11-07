#!/usr/bin/env bash
# Run Model Composer MATLAB code from the Ubuntu shell, with the helper folder
# already on the MATLAB path -- so nobody has to type an absolute path.
#
#   make mc-eval CODE="mc_gui_build"
#   make mc-eval CODE="info = mc_paths(); disp(info.libraries)"
#
# Batch mode: MATLAB exits when the code finishes.  For an interactive GUI
# session use `make mc-gui` (which passes -sd build/mc_startup, so the helpers
# are on the path when the window opens).
set -euo pipefail
# shellcheck source=scripts/mc_env.sh
source "$(cd "$(dirname "$0")" && pwd)/mc_env.sh"
cd "$mc_root_repo"

helper_dir="$mc_root_repo/ip/model_composer/channelizer"
code="${1:-${CODE:-}}"
if [[ -z "$code" ]]; then
    cat <<MSG
usage: make mc-eval CODE="matlab code"
example: make mc-eval CODE="mc_gui_build"

The helper folder is added for you:
  addpath('$helper_dir')
MSG
    exit 2
fi
echo "helper path:          $helper_dir"
echo "code:                 $code"
echo
exec "$MATLAB_2022B" -batch "addpath('$helper_dir'); $code"
