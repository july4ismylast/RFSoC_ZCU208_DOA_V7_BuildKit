#!/usr/bin/env bash
# Create the channelizer model from scratch, in MATLAB R2022b, with no GUI.
#
# The deliverable is the *script*, not a binary: a .slx cannot be reviewed in a
# diff, so ip/model_composer/channelizer/make_channelizer_model.m builds it and
# this script just runs that script and checks something real appeared.
#
# Usage: create_model_composer_model.sh [destination.slx]
set -euo pipefail
# shellcheck source=scripts/mc_env.sh
source "$(cd "$(dirname "$0")" && pwd)/mc_env.sh"
cd "$mc_root_repo"

dest="${1:-ip/model_composer/channelizer/channelizer.slx}"
[[ "$dest" = /* ]] || dest="$mc_root_repo/$dest"
mkdir -p "$(dirname "$dest")"
dest_ml="${dest//\'/\'\'}"
echo "building model:       $dest"
if ! ls "$mc_root_repo"/build/mc_examples/*.slx >/dev/null 2>&1; then
    echo
    echo "note: no template model in build/mc_examples, so the Hub comes straight"
    echo "      from the library.  That route reported 'Target hardware is not"
    echo "      selected' on a real run; the template route takes the Hub from an"
    echo "      AMD example that is already initialised:"
    echo
    echo "        make mc-example      # downloads it into build/ (not committed)"
    echo "        make mc-scratch      # rebuilds using it"
    echo
fi
echo

"$MATLAB_2022B" -batch "addpath('$mc_root_repo/ip/model_composer/channelizer'); make_channelizer_model('$dest_ml')"

if [[ ! -s "$dest" ]]; then
    echo "ERROR: the builder reported success but $dest does not exist" >&2
    exit 3
fi
size="$(wc -c < "$dest" | tr -d ' ')"
echo
echo "created $dest ($size bytes)"
echo "next: make mc        (exports IP Catalog IP from it)"
