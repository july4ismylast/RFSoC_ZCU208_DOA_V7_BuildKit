#!/usr/bin/env bash
# Model Composer 2023.2 must run with MATLAB R2022b, and it starts "matlab" from
# PATH -- so the two steps at a command prompt are:
#
#   1. export PATH="/media/joshua/Linux/Programs/R2022b/bin:$PATH"
#   2. /media/joshua/Linux/Programs/X20232/Model_Composer/2023.2/bin/model_composer \
#          2>&1 | tee build/logs/model_composer_launch.log
#
# This script does exactly those two steps from config.mk, refuses to start if
# PATH still resolves "matlab" to another release, and leaves a tracked page in
# docs/progress/model_composer_launch.md so a push shows the launch happened.
#
# It also writes build/mc_startup/startup.m and passes that folder as MATLAB's
# startup directory (-sd), so the helper functions are on the path the moment the
# GUI opens: typing `mc_gui_build` in the Command Window then works.  The -sd
# argument is a single plain path, which the launcher's own eval cannot mangle.
#
# Usage: launch_model_composer.sh [log-file] [interactive|build|example|bisect]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
log="${1:-build/logs/model_composer_launch.log}"
mode="${2:-interactive}"
mc="${MODEL_COMPOSER:-}"
m2="${MATLAB_2022B:-}"

if [[ -z "$mc" ]]; then
    cat >&2 <<'MSG'
MODEL_COMPOSER is not set, so there is nothing to launch.
Put it in config.local.mk (not tracked) or pass it:
  make mc MODEL_COMPOSER=/media/joshua/Linux/Programs/X20232/Model_Composer/2023.2/bin/model_composer
MSG
    exit 2
fi
[[ -x "$mc" ]] || { echo "MODEL_COMPOSER is not executable: $mc" >&2; exit 2; }

# Step 1: R2022b first on PATH. Step 2: say what "matlab" now means.
if [[ -n "$m2" ]]; then
    [[ -x "$m2" ]] || { echo "MATLAB_2022B is not executable: $m2" >&2; exit 2; }
    export PATH="$(dirname "$m2"):$PATH"
fi
matlab_now="$(command -v matlab || true)"
if [[ -z "$m2" ]]; then
    echo "MATLAB_2022B is unset: Model Composer will use ${matlab_now:-no matlab on PATH}" >&2
    echo "If that is not R2022b the export step fails with 'xlGenerateButton unavailable'." >&2
fi

# The GUI session needs the roots and IP_REPO: mc_gui_build writes the exported IP
# and mc_paths uses these instead of guessing.
export IP_REPO="${IP_REPO:-$root/build/ip_repo}"
export MC_VIVADO_ROOT="${XILINX_VIVADO:-$(cd "$(dirname "$(command -v vivado 2>/dev/null || echo /nonexistent/x)")/.." 2>/dev/null && pwd || true)}"
export MC_ROOT="$(cd "$(dirname "$mc")/.." && pwd)"
export MC_LIBS_CACHE="${MC_LIBS_CACHE:-$root/build/mc_libs.txt}"

# The MATLAB path a batch session does not have, handed to the GUI at startup.
helper_dir="$root/ip/model_composer/channelizer"
mc_root_dir="$(cd "$(dirname "$mc")/.." && pwd)"
vivado_root_dir="${XILINX_VIVADO:-}"
if [[ -z "$vivado_root_dir" ]]; then
    resolved_vivado="$(readlink -f "$(command -v vivado 2>/dev/null || true)" || true)"
    if [[ -n "$resolved_vivado" ]]; then
        vivado_root_dir="$(cd "$(dirname "$resolved_vivado")/.." && pwd)"
    fi
fi
if [[ -z "$vivado_root_dir" ]]; then
    echo "WARNING: cannot find Vivado; set XILINX_VIVADO so the System Generator paths are known" >&2
fi
# SysGen keeps a per-session temp tree and a shared-memory proxy.  A session that is
# cancelled leaves both behind, and the next session's proxy can then wait forever on
# them -- which is what a ten minute "generation in progress" after a cancel looks
# like.  Only ever cleared when no MATLAB is running, so a live session is safe.
clear_stale_sysgen() {
    if pgrep -x matlab >/dev/null 2>&1 || pgrep -x model_composer >/dev/null 2>&1; then
        echo "a MATLAB / Model Composer session is running: leaving its SysGen temp state alone" >&2
        return
    fi
    local cleaned=0
    if compgen -G "/tmp/sysgentmp-${USER}/*" >/dev/null; then
        rm -rf "/tmp/sysgentmp-${USER:?}"/* 2>/dev/null && cleaned=1
    fi
    if compgen -G "/dev/shm/sgproxy*" >/dev/null; then
        rm -f /dev/shm/sgproxy* 2>/dev/null && cleaned=1
    fi
    if [ "$cleaned" = 1 ]; then
        echo "cleared stale SysGen temp state (no MATLAB was running)"
    fi
}
clear_stale_sysgen

startup_dir="$root/build/mc_startup"
mkdir -p "$startup_dir"
{
    echo "addpath('$helper_dir');"
    # The GUI may be started by hand later; give the session the same variables
    # the shell passes, so mc_paths() never has to guess.
    echo "if isempty(getenv('MC_ROOT')), setenv('MC_ROOT', '$mc_root_dir'); end"
    echo "if isempty(getenv('MC_PART')), setenv('MC_PART', '${MC_PART:-xczu48dr-fsvg1517-2-e}'); end"
    echo "if isempty(getenv('MC_BOARD')), setenv('MC_BOARD', '${MC_BOARD:-xilinx.com:zcu208:part0:2.0}'); end"
    echo "if isempty(getenv('MC_VIVADO_ROOT')), setenv('MC_VIVADO_ROOT', '$vivado_root_dir'); end"
    echo "if isempty(getenv('IP_REPO')), setenv('IP_REPO', '$root/build/ip_repo'); end"
    echo "setenv('MC_LIBS_CACHE', '$root/build/mc_libs.txt');"
    echo "fprintf('Model Composer helpers ready: mc_gui_build, make_channelizer_model, export_model_composer_ip\\n');"
    echo "fprintf('repo: %s  MC_VIVADO_ROOT: %s\\n', '$root', getenv('MC_VIVADO_ROOT'));"
    if [[ "$mode" == "build" ]]; then
        echo "try"
        echo "    mc_gui_build;"
        echo "catch problem"
        echo "    fprintf(2, 'mc_gui_build failed: %s\\n', problem.message);"
        echo "end"
    elif [[ "$mode" == "example" ]]; then
        echo "try"
        echo "    mc_example_ip;"
        echo "catch problem"
        echo "    fprintf(2, 'mc_example_ip failed: %s\\n', problem.message);"
        echo "end"
    elif [[ "$mode" == "bisect" ]]; then
        echo "try"
        echo "    mc_bisect;"
        echo "catch problem"
        echo "    fprintf(2, 'mc_bisect failed: %s\\n', problem.message);"
        echo "end"
    fi
} > "$startup_dir/startup.m"

mkdir -p "$(dirname "$log")"
started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
    echo "stage=model_composer_launch"
    echo "started_utc=$started"
    printf 'command='; printf '%q ' "$mc" -sd "$startup_dir"; echo
    echo "startup=$startup_dir/startup.m ($mode)"
} | tee "$log"

set +e
"$mc" -sd "$startup_dir" 2>&1 | tee -a "$log"
rc=${PIPESTATUS[0]}
set -e
finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "finished_utc=$finished" | tee -a "$log"
result=PASS
if ((rc != 0)); then result=FAIL; echo "result=FAIL exit_code=$rc" | tee -a "$log"; else echo "result=PASS" | tee -a "$log"; fi

# The same tracked page every stage gets.
( "$root/scripts/stage_report.sh" --id model_composer_launch --log "$log" \
      --result "$result" --build "$(dirname "$(dirname "$log")")" ) || true
( "$root/scripts/progress_report.sh" "$(dirname "$(dirname "$log")")" ) >/dev/null || true

echo
echo "Model Composer closed (result $result, MATLAB on PATH: ${matlab_now:-unset})."
echo "The helper functions are already on the MATLAB path in that session, so"
echo "in its Command Window just type:"
echo
echo "     mc_gui_build"
echo
echo "and it builds ip/model_composer/channelizer/channelizer.slx and exports the"
echo "IP Catalog IP.  From an Ubuntu shell, without the GUI:"
echo
echo "     matlab -batch \"addpath('$helper_dir'); mc_gui_build\""
echo
echo "or, for a model you already have: make mc MODEL_COMPOSER_MODEL=/abs/path/to/channelizer.slx"
exit "$rc"
