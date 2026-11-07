#!/usr/bin/env python3
"""Print the VLNV and the ports of a packaged IP, so the log proves what was built.

Usage: check_ip_component.py build/ip_repo/channelizer_ip/component.xml
Exit status is non-zero when the file is not a complete component.
"""
import sys
import xml.etree.ElementTree as ET


def local(tag):
    return tag.rsplit("}", 1)[-1].rsplit(":", 1)[-1]


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: check_ip_component.py <component.xml>")
    root = ET.parse(sys.argv[1]).getroot()

    wanted = ("vendor", "library", "name", "version")
    values = {}
    for element in root.iter():
        key = local(element.tag)
        if key in wanted and key not in values and element.text and element.text.strip():
            values[key] = element.text.strip()
    missing = [key for key in wanted if key not in values]
    if missing:
        sys.exit(f"component.xml is missing {missing}: {sys.argv[1]}")
    print("VLNV: " + ":".join(values[key] for key in wanted))

    ports = []
    for element in root.iter():
        if local(element.tag) == "port":
            name = None
            direction = None
            width = None
            # direction/left live under spirit:wire, so walk the whole subtree
            for child in element.iter():
                key = local(child.tag)
                if key == "name" and child.text and name is None:
                    name = child.text.strip()
                elif key == "direction" and child.text:
                    direction = child.text.strip()
                elif key == "left" and child.text:
                    width = child.text.strip()
            if name:
                ports.append(f"{name} ({direction or '?'}, {width or '?'})")
    print(f"ports ({len(ports)}): " + ", ".join(ports))

    for needed in ("clk", "din", "dout"):
        if not any(port.startswith(needed) for port in ports):
            sys.exit(f"port {needed} is missing from {sys.argv[1]}")
    print("CHECK_IP_OK")


if __name__ == "__main__":
    main()
