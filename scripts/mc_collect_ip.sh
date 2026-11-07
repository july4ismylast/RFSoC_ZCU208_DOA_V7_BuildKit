#!/usr/bin/env bash
# Install the IP a Model Composer GUI compile left next to the model.
#
# The fallback route, for when `make mc` reports that only the GUI can
# initialise Model Composer: open `make mc-gui`, run the System Generator token
# (or in the Command Window: export_model_composer_ip('<model>')), then run
# `make mc-verify`, which calls this script and then checks the artifact.
#
# Usage: mc_collect_ip.sh /absolute/path/model.slx [ip-repo]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
model="${1:-${MODEL_COMPOSER_MODEL:-}}"
ip_repo="${2:-${IP_REPO:-$root/build/ip_repo}}"

die() { echo "ERROR: $*" >&2; exit 2; }

[[ -n "$model" ]] || die "no model given: mc_collect_ip.sh /abs/path/model.slx"
[[ -f "$model" ]] || die "model not found: $model (a placeholder path cannot be compiled)"
folder="$(cd "$(dirname "$model")" && pwd)"

# Prefer the folder Model Composer names after the model (<name>_ip); otherwise
# take the newest component.xml, never one that is already in the IP repository.
base="$(basename "$model" .slx)"
newest=""
if [[ -f "$folder/${base}_ip/component.xml" ]]; then
    newest="$folder/${base}_ip/component.xml"
else
    newest="$(find "$folder" -name component.xml -type f \
        -not -path "*/ip_repo/*" -not -path "*/model_composer_channelizer/*" \
        -printf '%T@ %p\n' 2>/dev/null \
        | sort -n | tail -n 1 | cut -d' ' -f2- || true)"
fi
[[ -n "$newest" ]] || die "no component.xml under $folder
  Compile the model's System Generator token first: make mc-gui, open the
  token, set Compilation target to IP Catalog, click Generate."

dest_dir="$ip_repo/model_composer_channelizer"
mkdir -p "$dest_dir"
dest="$dest_dir/component.xml"
source_dir="$(dirname "$newest")"
[[ "$source_dir" -ef "$dest_dir" ]] || cp -r "$source_dir"/. "$dest_dir"/

echo "collected IP from: $source_dir"
echo "installed to:      $dest_dir"
ls -l "$dest" | awk '{print "  size " $5 " bytes, " $6 " " $7 " " $8}'
version="$(grep -o '<spirit:version>[^<]*' "$dest" | head -n 1 | cut -d'>' -f2 || true)"
[[ -n "$version" ]] && echo "  version $version"
exit 0
