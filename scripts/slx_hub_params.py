#!/usr/bin/env python3
"""Print the Vitis Model Composer Hub settings stored inside a .slx file.

A .slx is a zip: the block diagram is XML, and a masked block keeps its parameter
values as ``InstanceData``.  That means the Hub settings of a saved model can be
read on a machine that has no MATLAB, which is the only way to check what a
scripted run actually wrote.

    python3 scripts/slx_hub_params.py build/mc_examples/SSRDDC.slx
    python3 scripts/slx_hub_params.py build/channelizer.slx --against build/mc_examples/SSRDDC.slx

Two facts found this way, both of which contradict earlier notes in this repo:

* the export target ships as ``System Generator``, not ``IP Catalog``;
* there is no ``SubsystemName`` and no ``IpName`` parameter.  The exported block
  and the IP identity live in one JSON string, ``IPInfoJsonString``.

Exit code is 0 unless ``--check`` is given and something is wrong.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

HUB_MARKERS = ("VMC Hub", "Vitis Model Composer Hub", "System Generator")
PARAMETER = re.compile(r'<P Name="([^"]+)">(.*?)</P>', re.S)
BLOCK = re.compile(r"<Block\s([^>]*)>(.*?)</Block>", re.S)
ATTRIBUTE = re.compile(r'(\w+)="([^"]*)"')


def unescape(text: str) -> str:
    return (
        text.replace("&quot;", '"')
        .replace("&apos;", "'")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&")
        .replace("&#xA;", "\n")
    )


def read_xml(archive: zipfile.ZipFile, name: str) -> str:
    try:
        return archive.read(name).decode("utf-8", "replace")
    except KeyError:
        return ""


def systems(archive: zipfile.ZipFile) -> dict[str, str]:
    return {
        name: read_xml(archive, name)
        for name in archive.namelist()
        if name.startswith("simulink/systems/") and name.endswith(".xml")
    }


def blocks(xml: str) -> list[dict]:
    found = []
    for attributes, body in BLOCK.findall(xml):
        entry = dict(ATTRIBUTE.findall(attributes))
        entry["parameters"] = {name: unescape(value) for name, value in PARAMETER.findall(body)}
        found.append(entry)
    return found


def is_hub(entry: dict) -> bool:
    text = " ".join(
        str(entry.get(key, ""))
        for key in ("Name", "SourceBlock", "SourceType", "MaskType", "Tag")
    )
    return any(marker in text for marker in HUB_MARKERS)


def hub_of(path: Path) -> tuple[dict, list[str], dict[str, str]]:
    """Return (hub block, every block name in the model, model callbacks)."""
    with zipfile.ZipFile(path) as archive:
        documents = systems(archive)
        diagram = read_xml(archive, "simulink/blockdiagram.xml")
    names: list[str] = []
    hub: dict = {}
    for document in documents.values():
        for entry in blocks(document):
            if "Name" in entry:
                names.append(entry["Name"])
            if not hub and is_hub(entry) and entry.get("parameters"):
                hub = entry
    callbacks = {
        name: unescape(body)
        for name, body in PARAMETER.findall(diagram)
        if name.endswith("Fcn")
    }
    return hub, sorted(set(names)), callbacks


def report(path: Path, against: Path | None) -> list[str]:
    hub, names, callbacks = hub_of(path)
    problems: list[str] = []
    print(f"model: {path}")
    if not hub:
        problems.append("no Vitis Model Composer Hub block in this model")
        print("  no Hub block")
        return problems
    source = hub.get("parameters", {}).get("SourceBlock", hub.get("SourceBlock", "?"))
    print(f"  hub block: {hub.get('Name', '?')}  ({source})")
    parameters = hub["parameters"]
    for name in sorted(parameters):
        print(f"    {name:24s} = {parameters[name]}")
    if against is not None:
        other, _, _ = hub_of(against)
        printed = False
        for name in sorted(set(parameters) | set(other.get("parameters", {}))):
            mine = parameters.get(name, "<absent>")
            theirs = other.get("parameters", {}).get(name, "<absent>")
            if mine != theirs:
                print(f"  differs from {against.name}: {name}: {mine!r} vs {theirs!r}")
                printed = True
        if not printed:
            print(f"  identical Hub parameters to {against.name}")
    export = parameters.get("ExportType", "")
    if "IP Catalog" not in export:
        problems.append(f"ExportType is {export!r}, not 'IP Catalog'")
    identity = parameters.get("IPInfoJsonString", "")
    if identity:
        try:
            subsystem = json.loads(identity)["HDLSubsystem"]
        except (ValueError, KeyError):
            problems.append(f"IPInfoJsonString is not the expected JSON: {identity!r}")
        else:
            name = subsystem.get("SubsystemName", "")
            print(f"  exported block: {name or '<empty>'}")
            if name and name not in names:
                problems.append(f"exported block {name!r} does not exist in the model")
            if not name:
                problems.append("IPInfoJsonString names no subsystem")
            print(
                "  VLNV: {}:{}:{}:{}".format(
                    subsystem.get("IPVendor", "?"),
                    subsystem.get("IPLibrary", "?"),
                    name or "?",
                    subsystem.get("IPVersion", "?"),
                )
            )
    else:
        problems.append("no IPInfoJsonString")
    if callbacks:
        print("  model callbacks:")
        for name in sorted(callbacks):
            first = " ".join(callbacks[name].split())[:60]
            print(f"    {name:12s} {first}")
            for variable in re.findall(r"\b(clk|sample_rate|SSR|Tclk|Ts)\b\s*=", callbacks[name]):
                print(f"      defines {variable}")
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", type=Path)
    parser.add_argument("--against", type=Path, default=None)
    parser.add_argument("--check", action="store_true", help="fail on any problem")
    parser.add_argument("--quiet", action="store_true")
    options = parser.parse_args(argv)
    if not options.model.is_file():
        print(f"not a file: {options.model}", file=sys.stderr)
        return 2
    if options.against is not None and not options.against.is_file():
        print(f"not a file: {options.against}", file=sys.stderr)
        return 2
    problems = report(options.model, options.against)
    if problems:
        print("findings:")
        for problem in problems:
            print(f"  - {problem}")
    else:
        print("SLX_HUB_OK")
    if options.check and problems:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
