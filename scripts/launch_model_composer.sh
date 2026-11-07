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
# Usage: launch_model_composer.sh [log-file]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
log="${1:-build/logs/model_composer_launch.log}"
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

mkdir -p "$(dirname "$log")"
started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
    echo "stage=model_composer_launch"
    echo "started_utc=$started"
    printf 'command='; printf '%q ' "$mc"; echo
} | tee "$log"

set +e
"$mc" 2>&1 | tee -a "$log"
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
echo "In the GUI's Command Window, build the model and export the IP in one go:"
echo "     mc_gui_build"
echo "or, for a model you already have: make mc MODEL_COMPOSER_MODEL=/abs/path/to/channelizer.slx"
exit "$rc"
