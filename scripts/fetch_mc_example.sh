#!/usr/bin/env bash
# Fetch a real, release-matched Model Composer example to compare against.
#
# READ THIS FIRST: Xilinx/Vitis_Model_Composer has no LICENSE file, so those
# models are "all rights reserved" -- they are NOT committed here, and the only
# thing that is committed is this script.  It downloads into build/ (ignored) so
# you can open the vendor model next to ours and copy the blocks you want.
#
# The default is the release matching this kit: branch 2023.2, and an RFSoC
# example with super-sample-rate down conversion, i.e. the same job as our
# channelizer: four streams, vector FIRs, gateways, Hub.
#
# Usage: fetch_mc_example.sh [path/in/repo.slx]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
branch="${MC_EXAMPLE_BRANCH:-2023.2}"
repo="${MC_EXAMPLE_REPO:-Xilinx/Vitis_Model_Composer}"
path="${1:-Examples/HDL/RFSoC/SSR_Digital_Down_Conversion/SSRDDC.slx}"
dest_dir="$root/build/mc_examples"
dest="$dest_dir/$(basename "$path")"

mkdir -p "$dest_dir"
echo "repo:   $repo (branch $branch)"
echo "file:   $path"
echo "saving: $dest"

if command -v gh >/dev/null 2>&1; then
    gh api "repos/$repo/contents/$path?ref=$branch" --jq '.content' | base64 -d > "$dest"
else
    curl -fsSL "https://raw.githubusercontent.com/$repo/$branch/$path" -o "$dest"
fi

if [[ ! -s "$dest" ]]; then
    echo "ERROR: download produced nothing" >&2
    exit 3
fi
size="$(wc -c < "$dest" | tr -d ' ')"
echo "got $size bytes"
echo
echo "open it next to ours:"
echo "  make mc-gui      then in MATLAB:  open_system('$dest')"
echo
cat <<'NOTE'
licence: this example is AMD's, published without a LICENSE file, so it is
downloaded for reference only and stays out of git (build/ is ignored).  Do not
commit it; build the equivalent with `make mc-scratch` and edit that instead.
NOTE
