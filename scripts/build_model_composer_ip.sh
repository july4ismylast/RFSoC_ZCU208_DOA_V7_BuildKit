#!/usr/bin/env bash
# Build the channelizer IP with Model Composer 2023.2 -- headless, no GUI.
#
# Why not the Model Composer launcher: it evals its own arguments into
#   exec matlab <your args> -r "<its startup; xmcStart;>"
# so a MATLAB statement passed after -batch loses its quotes, and MATLAB refuses
# -batch together with -r anyway.  A real run on the ZCU208 host failed exactly
# there (docs/evidence/2026-11-07-host-probe/model_composer_launcher_eval_bug.txt).
#
# So this runs R2022b directly in -batch, with the Model Composer and System
# Generator paths added inside MATLAB by mc_batch_export.m.
#
# Usage: build_model_composer_ip.sh /absolute/path/channelizer.slx
set -euo pipefail
# shellcheck source=scripts/mc_env.sh
source "$(cd "$(dirname "$0")" && pwd)/mc_env.sh"
cd "$mc_root_repo"

die() { echo "ERROR: $*" >&2; exit 2; }

model="${1:-${MODEL_COMPOSER_MODEL:-}}"
[[ -n "$model" ]] || die "no model given: build_model_composer_ip.sh /abs/path/model.slx"
if [[ ! -f "$model" ]]; then
    die "model not found: $model
  A path like /absolute/path/channelizer.slx is a placeholder.  Build one from
  scratch with:  make mc-scratch     (then: make mc)
  Or create/edit it in the GUI:  make mc-gui"
fi
model="$(cd "$(dirname "$model")" && pwd)/$(basename "$model")"
echo "model:                $model"
echo "IP_REPO:              $IP_REPO"
echo "running:              matlab -batch mc_batch_export"
echo

model_ml="${model//\'/\'\'}"   # single quotes doubled for the MATLAB string
"$MATLAB_2022B" -batch "addpath('$mc_root_repo/ip/model_composer/channelizer'); mc_batch_export('$model_ml')"
