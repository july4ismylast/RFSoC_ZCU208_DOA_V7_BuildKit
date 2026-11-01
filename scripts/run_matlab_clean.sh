#!/usr/bin/env bash
set -euo pipefail

# Launch MATLAB without inheriting Xilinx/Vivado runtime libraries.  Model
# Composer can install a Xilinx-specific $HOME/.matlab7rc.sh; MATLAB normally
# sources that file before its own default and may then crash in the ELF loader.
# A temporary current-directory override lets MATLAB retain the real HOME (and
# therefore its licence/preferences) while bypassing only that startup hook.

if (($# < 1)); then
    echo "usage: run_matlab_clean.sh MATLAB_EXECUTABLE [MATLAB_ARGUMENT ...]" >&2
    exit 2
fi

matlab_cmd="$1"
shift

if [[ "$matlab_cmd" == */* ]]; then
    [[ -x "$matlab_cmd" ]] || {
        echo "ERROR: MATLAB executable is not executable: $matlab_cmd" >&2
        exit 127
    }
    matlab_exe="$(realpath "$matlab_cmd")"
else
    matlab_exe="$(command -v "$matlab_cmd" || true)"
    [[ -n "$matlab_exe" ]] || {
        echo "ERROR: MATLAB executable not found on PATH: $matlab_cmd" >&2
        exit 127
    }
    matlab_exe="$(realpath "$matlab_exe")"
fi

factory_rc="$(dirname "$matlab_exe")/.matlab7rc.sh"
[[ -r "$factory_rc" ]] || {
    echo "ERROR: MATLAB factory startup file is missing: $factory_rc" >&2
    echo "MATLAB executable resolved to: $matlab_exe" >&2
    exit 3
}

startup_dir="$(pwd -P)"
isolation_dir="$(mktemp -d -t doa-matlab-startup-XXXXXXXX)"
cleanup() {
    rm -rf -- "$isolation_dir"
}
trap cleanup EXIT HUP INT TERM

# MATLAB uses the first .matlab7rc.sh found in the current directory, HOME, or
# matlabroot/bin.  Copy the factory file into the temporary current directory:
# unlike an empty override, it initializes ARCH and other release-specific
# values, while still taking precedence over a legacy Xilinx file in HOME.
cp -- "$factory_rc" "$isolation_dir/.matlab7rc.sh"

if [[ -f "${HOME:-}/.matlab7rc.sh" ]]; then
    echo "INFO: bypassing user .matlab7rc.sh for this MATLAB build invocation"
fi
echo "INFO: MATLAB loader isolation enabled; startup directory=$startup_dir"
echo "INFO: MATLAB factory startup file=$factory_rc"

set +e
(
    cd "$isolation_dir"
    env \
        -u LD_LIBRARY_PATH \
        -u LD_PRELOAD \
        -u QT_PLUGIN_PATH \
        -u QT_QPA_PLATFORM_PLUGIN_PATH \
        -u GTK_PATH \
        "$matlab_exe" -nodisplay -nosplash -nodesktop -sd "$startup_dir" "$@"
)
rc=$?
set -e
exit "$rc"
