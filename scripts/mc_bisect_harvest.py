#!/usr/bin/env python3
"""Find the IP that Model Composer finished writing, even if the GUI never said so.

A real run sat in "generation in progress" for 47 minutes after Vivado had already
logged "Exiting Vivado" and packaged the design; the component.xml was on disk the
whole time and the call simply never returned. Cancelling that window loses nothing
-- but it also means the step's artifact was never copied into build/ip_repo.

    python3 scripts/mc_bisect_harvest.py                     # what is on disk
    python3 scripts/mc_bisect_harvest.py --install step2     # adopt the newest one

--install copies the folder holding the newest component.xml to
build/ip_repo/<step>, which is the name the bisect (and step06) look for.
"""
from __future__ import annotations

import argparse
import re
import shutil
import sys
import time
from pathlib import Path
import xml.etree.ElementTree as ET


def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1].rsplit(":", 1)[-1]


def describe(path: Path) -> tuple[str, str]:
    """Return (VLNV, exported block name) for one component.xml."""
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        return "<unreadable>", "?"
    values: dict[str, str] = {}
    for element in root.iter():
        key = local(element.tag)
        if key in {"vendor", "library", "name", "version"} and key not in values:
            if element.text and element.text.strip():
                values[key] = element.text.strip()
    vlnv = ":".join(values.get(key, "?") for key in ("vendor", "library", "name", "version"))
    return vlnv, values.get("name", "?")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("build/mc_bisect"))
    parser.add_argument("--repo", type=Path, default=Path("build/ip_repo"))
    parser.add_argument("--install", default="", help="step label to copy the newest component into")
    options = parser.parse_args(argv)

    if not options.root.is_dir():
        print(f"no work folder {options.root}", file=sys.stderr)
        return 2
    found = sorted(options.root.rglob("component.xml"))
    if not found:
        print(f"no component.xml under {options.root}: nothing to harvest")
        return 1
    newest = max(found, key=lambda path: path.stat().st_mtime)
    for path in found:
        vlnv, name = describe(path)
        age = time.time() - path.stat().st_mtime
        marker = "  <- newest" if path == newest else ""
        print(f"{age / 60:7.1f} min  {vlnv:60s} block={name!r}{marker}")
        print(f"           {path.parent}")
    if not options.install:
        print("\nto adopt the newest: --install step<N>")
        return 0

    label = options.install
    if re.fullmatch(r"step\d+", label):
        label = "ssr_bisect_" + label
    destination = options.repo / label
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(newest.parent, destination)
    print(f"installed {newest.parent} -> {destination}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
