#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <component.xml> <expected-vendor:library:name:version>" >&2
    exit 2
fi

component_xml="$1"
expected_vlnv="$2"

actual_vlnv="$(python3 - "$component_xml" <<'PYEOF'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
root = ET.parse(path).getroot()

def local_name(tag):
    return tag.rsplit('}', 1)[-1].rsplit(':', 1)[-1]

values = {}
# The IP-XACT identity fields are direct children of <spirit:component>.
# Reading only those avoids picking up a nested <name> or <version> from a
# bus interface, file set, or parameter later in the document.
for child in list(root):
    name = local_name(child.tag)
    if name in ("vendor", "library", "name", "version") and child.text:
        values[name] = child.text.strip()

missing = [k for k in ("vendor", "library", "name", "version") if k not in values]
if missing:
    sys.exit(f"component.xml missing identity fields {missing}: {path}")
print(":".join(values[k] for k in ("vendor", "library", "name", "version")))
PYEOF
)"

if [[ "$actual_vlnv" != "$expected_vlnv" ]]; then
    echo "ERROR: packaged IP VLNV mismatch" >&2
    echo "  component.xml: $component_xml" >&2
    echo "  expected:      $expected_vlnv" >&2
    echo "  actual:        $actual_vlnv" >&2
    exit 4
fi

echo "PASS packaged VLNV $actual_vlnv"
