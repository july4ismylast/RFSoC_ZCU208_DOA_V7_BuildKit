#!/usr/bin/env python3
"""Print the VLNV and the ports of a packaged IP, so the log proves what was built.

Usage: check_ip_component.py <component.xml> [--any-ports]
Exit status is non-zero when the file is not a complete component.

--any-ports prints the ports without demanding clk/din/dout: AMD's example exports
its own names, and reading them is how a bisect artifact gets compared with ours.
"""
import sys
import xml.etree.ElementTree as ET


def local(tag):
    return tag.rsplit("}", 1)[-1].rsplit(":", 1)[-1]


def main():
    arguments = [argument for argument in sys.argv[1:] if not argument.startswith("--")]
    flags = {argument for argument in sys.argv[1:] if argument.startswith("--")}
    if len(arguments) != 1:
        sys.exit("usage: check_ip_component.py <component.xml> [--any-ports]")
    root = ET.parse(arguments[0]).getroot()

    wanted = ("vendor", "library", "name", "version")
    values = {}
    for element in root.iter():
        key = local(element.tag)
        if key in wanted and key not in values and element.text and element.text.strip():
            values[key] = element.text.strip()
    missing = [key for key in wanted if key not in values]
    if missing:
        sys.exit(f"component.xml is missing {missing}: {arguments[0]}")
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

    if "--any-ports" in flags:
        print("CHECK_IP_OK (ports not constrained)")
        return
    for needed in ("clk", "din", "dout"):
        if not any(port.startswith(needed) for port in ports):
            sys.exit(f"port {needed} is missing from {arguments[0]}")
    print("CHECK_IP_OK")


if __name__ == "__main__":
    main()
