#!/usr/bin/env bash
# Build the channelizer IP with Model Composer 2023.2 -- headless, no GUI.
#
# Why not the Model Composer launcher: it evals its own arguments into
#   exec matlab <your args> -r "<its startup; xmcStart;>"
# so a MATLAB statement passed after -batch loses its quotes, and MATLAB refuses
# -batch together with -r anyway.  A real run on the ZCU208 host failed exactly
# there (docs/evidence/2026-11-07-host-probe/model_composer_launcher_eval_bug.txt).
#
# So this runs R2022b directly in -batch and puts on the MATLAB path the same
# directories the launcher prints in its environment banner:
#   <MC>/simulink, <MC>/simulink/{aie,hls}, <MC>/lib/lnx64.o[+/Ubuntu[/22]]
#   <Vivado>/scripts/sysgen/matlab[+/plugins/compilation], <Vivado>/lib/lnx64.o/matlab
#   <Vivado>/lib/classes/sysgen.jar
# then calls mc_batch_export.m, which starts Model Composer only if
# xlGenerateButton is still missing, runs the System Generator token, and
# installs component.xml in $(IP_REPO).
#
# Usage: build_model_composer_ip.sh /absolute/path/channelizer.slx
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"

die() { echo "ERROR: $*" >&2; exit 2; }

model="${1:-${MODEL_COMPOSER_MODEL:-}}"
[[ -n "$model" ]] || die "no model given: build_model_composer_ip.sh /abs/path/model.slx"
[[ -f "$model" ]] || die "model not found: $model
  A path like /absolute/path/channelizer.slx in a tutorial is a placeholder.
  Create or edit the real model with: make mc-gui"
model="$(cd "$(dirname "$model")" && pwd)/$(basename "$model")"

matlab22="${MATLAB_2022B:-}"
[[ -n "$matlab22" ]] || die "MATLAB_2022B is unset. Model Composer 2023.2 needs MATLAB R2022b;
  put MATLAB_2022B=/abs/path/R2022b/bin/matlab in config.local.mk"
[[ -x "$matlab22" ]] || die "MATLAB_2022B is not executable: $matlab22"
matlab_root="$(cd "$(dirname "$matlab22")/.." && pwd)"
if [[ -f "$matlab_root/VersionInfo.xml" ]]; then
    release="$(sed -n 's:.*<release>\([^<]*\)</release>.*:\1:p' "$matlab_root/VersionInfo.xml" | head -n 1)"
    echo "MATLAB for this build: $matlab22 ($release)"
    if [[ -n "$release" && "$release" != "R2022b" && "${MC_ALLOW_ANY_MATLAB:-0}" != "1" ]]; then
        die "Model Composer 2023.2 ships R2022b; $matlab22 is $release.
  Set MATLAB_2022B to the R2022b binary, or MC_ALLOW_ANY_MATLAB=1 to try anyway."
    fi
fi

# Model Composer install root: .../Model_Composer/2023.2/bin/model_composer
mc="${MODEL_COMPOSER:-}"
if [[ -n "$mc" && -e "$mc" ]]; then
    mc_root="$(cd "$(dirname "$mc")/.." && pwd)"
    echo "Model Composer root:   $mc_root"
else
    mc_root=""
    echo "Model Composer root:   MODEL_COMPOSER not set; using the System Generator paths only"
fi

# Vivado 2023.2 root: XILINX_VIVADO, else the one on PATH.
vivado_root="${XILINX_VIVADO:-}"
if [[ -z "$vivado_root" ]]; then
    resolved="$(readlink -f "$(command -v vivado 2>/dev/null || true)" || true)"
    [[ -n "$resolved" ]] && vivado_root="$(cd "$(dirname "$resolved")/.." && pwd)"
fi
[[ -n "$vivado_root" ]] || die "cannot find Vivado: set XILINX_VIVADO (System Generator scripts live there)"
echo "Vivado root:           $vivado_root"

sysgen="$vivado_root/scripts/sysgen/matlab"
jar="$vivado_root/lib/classes/sysgen.jar"
[[ -d "$sysgen" ]] || die "System Generator scripts not found: $sysgen
  Is XILINX_VIVADO pointing at the 2023.2 Vivado that Model Composer uses?"
[[ -f "$jar" ]] || echo "note: $jar not found; the token may still run without it" >&2

export MC_ROOT="$mc_root"
export MC_VIVADO_ROOT="$vivado_root"
export PATH="$(dirname "$matlab22"):$PATH"
export IP_REPO="${IP_REPO:-$root/build/ip_repo}"

echo "model:                 $model"
echo "IP_REPO:               $IP_REPO"
echo "running: matlab -batch mc_batch_export"
echo

# Single quotes are the only quoting MATLAB needs; double them.
model_ml="${model//\'/\'\'}"
"$matlab22" -batch "addpath('$root/ip/model_composer/channelizer'); mc_batch_export('$model_ml')"
