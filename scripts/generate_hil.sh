#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
[[ -d "$V7_MATLAB_ROOT" ]] || {
    echo "ERROR: V7_MATLAB_ROOT does not exist: $V7_MATLAB_ROOT" >&2
    echo "Point it at DOA_2x2_Realistic_HIL_R2024a_ZU48DR_V7." >&2
    exit 3
}
mkdir -p "$HIL_OUTPUT_DIR"
export DOA_V7_MATLAB_ROOT="$V7_MATLAB_ROOT"
export DOA_HIL_OUTPUT_DIR="$HIL_OUTPUT_DIR"
exec "$root/scripts/run_matlab_clean.sh" "$MATLAB" -batch "addpath(fullfile(pwd,'hil','matlab')); generate_zcu208_hil_vectors"
