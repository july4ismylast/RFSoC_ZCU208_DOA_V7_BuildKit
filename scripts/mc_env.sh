#!/usr/bin/env bash
# Shared environment for the Model Composer MATLAB runs.  Source it, do not run it.
#
# Sets and exports:
#   MC_ROOT, MC_VIVADO_ROOT   the two installs whose paths Model Composer needs
#   PATH                      MATLAB R2022b first, so "matlab" means R2022b
# Checks, and dies with an actionable message:
#   MATLAB_2022B exists and is R2022b (read from VersionInfo.xml, no licence)
#   the Vivado System Generator scripts exist
set -euo pipefail

mc_die() { echo "ERROR: $*" >&2; exit 2; }

mc_root_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

matlab22="${MATLAB_2022B:-}"
[[ -n "$matlab22" ]] || mc_die "MATLAB_2022B is unset. Model Composer 2023.2 needs MATLAB R2022b;
  put MATLAB_2022B=/abs/path/R2022b/bin/matlab in config.local.mk"
[[ -x "$matlab22" ]] || mc_die "MATLAB_2022B is not executable: $matlab22"
matlab_root="$(cd "$(dirname "$matlab22")/.." && pwd)"
if [[ -f "$matlab_root/VersionInfo.xml" ]]; then
    release="$(sed -n 's:.*<release>\([^<]*\)</release>.*:\1:p' "$matlab_root/VersionInfo.xml" | head -n 1)"
    echo "MATLAB for this run:  $matlab22 ($release)"
    if [[ -n "$release" && "$release" != "R2022b" && "${MC_ALLOW_ANY_MATLAB:-0}" != "1" ]]; then
        mc_die "Model Composer 2023.2 ships R2022b; $matlab22 is $release.
  Set MATLAB_2022B to the R2022b binary, or MC_ALLOW_ANY_MATLAB=1 to try anyway."
    fi
fi

mc="${MODEL_COMPOSER:-}"
if [[ -n "$mc" && -e "$mc" ]]; then
    mc_root="$(cd "$(dirname "$mc")/.." && pwd)"
    echo "Model Composer root:  $mc_root"
else
    mc_root=""
    echo "Model Composer root:  MODEL_COMPOSER not set; System Generator paths only"
fi

vivado_root="${XILINX_VIVADO:-}"
if [[ -z "$vivado_root" ]]; then
    resolved="$(readlink -f "$(command -v vivado 2>/dev/null || true)" || true)"
    [[ -n "$resolved" ]] && vivado_root="$(cd "$(dirname "$resolved")/.." && pwd)"
fi
[[ -n "$vivado_root" ]] || mc_die "cannot find Vivado: set XILINX_VIVADO (System Generator scripts live there)"
[[ -d "$vivado_root/scripts/sysgen/matlab" ]] || mc_die "System Generator scripts not found under $vivado_root
  Is XILINX_VIVADO pointing at the 2023.2 Vivado that Model Composer uses?"
echo "Vivado root:          $vivado_root"

export MC_ROOT="$mc_root"
export MC_VIVADO_ROOT="$vivado_root"
export PATH="$(dirname "$matlab22"):$PATH"
export IP_REPO="${IP_REPO:-$mc_root_repo/build/ip_repo}"
export MC_LIBS_CACHE="${MC_LIBS_CACHE:-$mc_root_repo/build/mc_libs.txt}"
