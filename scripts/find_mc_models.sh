#!/usr/bin/env bash
# Find Model Composer / Simulink models (.slx) that could be the channelizer.
#
# `make mc` needs a real file, and this repository does not ship one (a .slx is
# binary; the model is built once in the GUI).  So look for it instead of
# guessing: this prints every candidate with its date and gives the exact
# command to run for the newest one.
#
# Usage: find_mc_models.sh [extra-root ...]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
roots=("$root")
for extra in "$@"; do roots+=("$extra"); done
[[ -n "${HOME:-}" && -d "${HOME:-}" ]] && roots+=("$HOME")
for candidate in /media/joshua /media/"${USER:-}" /mnt /data; do
    [[ -d "$candidate" ]] && roots+=("$candidate")
done

echo "searching for *.slx under:"
for one in "${roots[@]}"; do echo "  $one"; done
echo

# One find per root, de-duplicated by path; HEAD-less boxes still work.
list="$(
    for one in "${roots[@]}"; do
        find "$one" -maxdepth 6 -type f -name '*.slx' -not -path '*/.git/*' \
             -printf '%T@|%p\n' 2>/dev/null || true
    done | sort -t'|' -k2,2 -u | sort -rn | head -n 25
)"

if [[ -z "$list" ]]; then
    cat <<'MSG'
No .slx found -- so there is no model to build yet, and no correct absolute path
to give you.  Create it once:

  make mc-gui                     # Model Composer 2023.2 with MATLAB R2022b
  # in the GUI: File > New > Blank Model, build the 4-channel channelizer,
  # add one Xilinx System Generator token, set Compilation target = IP Catalog,
  # save as  ip/model_composer/channelizer/channelizer.slx
  make mc                        # no path needed once the file is there
MSG
    exit 0
fi

echo "candidates (newest first):"
printf '%s\n' "$list" | while IFS='|' read -r stamp path; do
    when="$(date -u -d "@${stamp%%.*}" +%Y-%m-%d 2>/dev/null || echo '----------')"
    printf '  %s  %s\n' "$when" "$path"
done

newest="$(printf '%s\n' "$list" | head -n 1 | cut -d'|' -f2)"
echo
echo "to build the newest one:"
repo_model="$root/ip/model_composer/channelizer/channelizer.slx"
if [[ "$newest" == "$repo_model" ]]; then
    echo "  make mc"
else
    echo "  make mc MODEL_COMPOSER_MODEL=$newest"
    echo
    echo "or move it to the place the Makefile picks up by itself:"
    echo "  mv \"$newest\" \"$repo_model\" && make mc"
fi
