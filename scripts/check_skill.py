#!/usr/bin/env python3
"""Keep the AI skill true to the repository.

The skill in skills/ exists so a chat bot can answer questions about this build without inventing
numbers.  That only works if every number, path, VLNV and make target in it is still in the source.
This script is the guard:

  1. SKILL.md frontmatter is valid and matches its folder;
  2. every relative link between skill files resolves;
  3. every custom-IP VLNV matches config/ip_versions.tcl (and config.mk);
  4. every `make <target>` mentioned in the skill exists in the Makefile;
  5. every repository path cited in backticks exists (build/ paths exempt: they are git-ignored);
  6. every row of references/numbers.md finds its proof file and its literal evidence token,
     including the gate-status count.

Usage:
    python3 scripts/check_skill.py [--quiet]

Exit code 0 = the skill still agrees with the repository.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SKILL_DIR = ROOT / "skills" / "rfsoc-doa-v7"
SKILL_MD = SKILL_DIR / "SKILL.md"

failures: list[str] = []
checks: list[str] = []


def fail(message: str) -> None:
    failures.append(message)


def ok(message: str) -> None:
    checks.append(message)


def squashed(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def skill_files() -> list[pathlib.Path]:
    """Every markdown file the skill ships, including its README one level up."""
    return sorted([SKILL_DIR.parent / "README.md"] + list(SKILL_DIR.rglob("*.md")))


# --------------------------------------------------------------------------- 1. frontmatter
def check_frontmatter() -> None:
    if not SKILL_MD.exists():
        fail(f"missing {SKILL_MD.relative_to(ROOT)}")
        return
    text = SKILL_MD.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        fail("SKILL.md does not start with YAML frontmatter")
        return
    end = text.find("\n---", 4)
    if end < 0:
        fail("SKILL.md frontmatter is not closed with ---")
        return
    block = text[4:end]
    fields: dict[str, str] = {}
    for line in block.splitlines():
        m = re.match(r"^([a-zA-Z_][a-zA-Z0-9_-]*):\s*(.*)$", line)
        if m:
            fields[m.group(1)] = m.group(2).strip()
    name = fields.get("name", "")
    description = fields.get("description", "")
    if not name:
        fail("SKILL.md frontmatter has no 'name'")
    elif name != SKILL_DIR.name:
        fail(f"SKILL.md name '{name}' does not match folder '{SKILL_DIR.name}'")
    if not description:
        fail("SKILL.md frontmatter has no 'description'")
    elif len(description) > 1024:
        fail(f"SKILL.md description is {len(description)} chars (max 1024)")
    if name and description:
        ok(f"frontmatter: name '{name}', description {len(description)} chars")


# --------------------------------------------------------------------------- 2. links
LINK = re.compile(r"\]\(([^)\s]+)\)")


def check_links() -> None:
    count = 0
    for path in skill_files():
        for target in LINK.findall(path.read_text(encoding="utf-8")):
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            clean = target.split("#", 1)[0]
            if not clean:
                continue
            count += 1
            resolved = (path.parent / clean).resolve()
            if not resolved.exists():
                fail(f"{path.relative_to(ROOT)}: link '{target}' does not resolve")
    ok(f"links: {count} relative links resolve")


# --------------------------------------------------------------------------- 3. VLNVs
def parse_ip_versions() -> tuple[dict[str, str], dict[str, str]]:
    """Return (name -> version, ipver_var -> version) from config/ip_versions.tcl."""
    tcl = (ROOT / "config" / "ip_versions.tcl").read_text(encoding="utf-8")
    versions: dict[str, str] = {}
    for m in re.finditer(r'set ::IPVER_([A-Z0-9_]+)\s+\[::doa_versions::env_or\s+IPVER_[A-Z0-9_]+\s+"([0-9.]+)"\]', tcl):
        versions[m.group(1)] = m.group(2)
    names: dict[str, str] = {}
    for m in re.finditer(
        r'set ::IPVLNV\([a-z0-9_]+\)\s+"\$::CUSTOM_IP_VENDOR:\$::CUSTOM_IP_LIBRARY:([a-z0-9_]+):\$::IPVER_([A-Z0-9_]+)"',
        tcl,
    ):
        names[m.group(1)] = versions.get(m.group(2), "")
    return names, versions


def check_vlnvs() -> None:
    names, versions = parse_ip_versions()
    if not names:
        fail("could not parse any custom IP VLNV from config/ip_versions.tcl")
        return

    mk = (ROOT / "config.mk").read_text(encoding="utf-8")
    mk_versions = dict(re.findall(r"^(IPVER_[A-Z0-9_]+)\s*\?=\s*([0-9.]+)\s*$", mk, re.M))
    for var, version in versions.items():
        mk_var = f"IPVER_{var}"
        if mk_var in mk_versions and mk_versions[mk_var] != version:
            fail(f"{mk_var}: config.mk says {mk_versions[mk_var]}, config/ip_versions.tcl says {version}")

    cited = 0
    for path in skill_files():
        text = path.read_text(encoding="utf-8")
        for m in re.finditer(r"openai:doa:([a-z0-9_]+):([0-9]+\.[0-9]+)", text):
            cited += 1
            ip_name, version = m.group(1), m.group(2)
            if ip_name not in names:
                fail(f"{path.relative_to(ROOT)}: unknown custom IP '{ip_name}'")
            elif names[ip_name] != version:
                fail(
                    f"{path.relative_to(ROOT)}: {ip_name} cited as {version}, "
                    f"config/ip_versions.tcl pins {names[ip_name] or 'nothing'}"
                )
    ok(f"VLNVs: {cited} citations, {len(names)} custom IPs pinned, config.mk agrees")


# --------------------------------------------------------------------------- 4. make targets
# Only backticked command spans are checked: `make step11_impl`, `make -C ip/... all`.  Prose such
# as "the make target wins" is not a command mention and must not be read as one.
MAKESPAN = re.compile(r"`make ([^`]+)`")


def makefile_targets(makefile: pathlib.Path) -> set[str]:
    if not makefile.exists():
        return set()
    text = makefile.read_text(encoding="utf-8", errors="replace")
    return set(re.findall(r"^([a-zA-Z0-9_][a-zA-Z0-9_.-]*):", text, re.M))


def check_make_targets() -> None:
    top = makefile_targets(ROOT / "Makefile")
    if not top:
        fail("could not parse any target from the Makefile")
        return
    checked = 0
    for path in skill_files():
        text = path.read_text(encoding="utf-8")
        for span in MAKESPAN.findall(text):
            tokens = span.split()
            directory = ROOT
            targets = top
            i = 0
            while i < len(tokens):
                token = tokens[i]
                if token in ("-C", "--directory") and i + 1 < len(tokens):
                    directory = ROOT / tokens[i + 1]
                    targets = makefile_targets(directory / "Makefile")
                    i += 2
                    continue
                if token.startswith("-") or "=" in token or "$" in token:
                    i += 1
                    continue
                token = token.rstrip(".,;:")
                if "<" in token or ">" in token or token == "all" and directory == ROOT:
                    i += 1
                    continue
                if re.fullmatch(r"[a-z][a-z0-9_.-]*", token):
                    checked += 1
                    if token not in targets:
                        where = directory.relative_to(ROOT).as_posix() or "."
                        fail(
                            f"{path.relative_to(ROOT)}: `make {span}` — '{token}' is not a target "
                            f"in {where}/Makefile"
                        )
                i += 1
    ok(f"make targets: {checked} command spans, all defined")


# --------------------------------------------------------------------------- 5. paths
PATH_TOKEN = re.compile(
    r"`([A-Za-z0-9_][A-Za-z0-9_./-]*\.(?:md|tcl|xdc|cpp|hpp|v|sv|py|mk|rpt|txt|log|c|h|m|tsv|bit|xsa|sha256))`"
)
EXEMPT_PREFIX = ("build/", "upstream/")
EXEMPT_NAMES = ("config.local.mk",)


def check_paths() -> None:
    """Only *paths* are checked — a token with a directory separator, or a file next to the skill.

    Bare filenames in prose ("`package_ip.tcl` does …") are deliberately not resolved: they name a
    file in the repository by context, and requiring a unique match would forbid ordinary writing.
    """
    checked = 0
    for path in skill_files():
        for token in PATH_TOKEN.findall(path.read_text(encoding="utf-8")):
            if token.startswith(EXEMPT_PREFIX) or token in EXEMPT_NAMES or "*" in token:
                continue
            if "/" not in token:
                continue
            checked += 1
            candidates = (ROOT / token, path.parent / token, SKILL_DIR / token)
            if not any(c.exists() for c in candidates):
                fail(f"{path.relative_to(ROOT)}: cites '{token}', which does not exist")
    ok(f"paths: {checked} backticked repository paths exist")


# --------------------------------------------------------------------------- 6. numbers
NUMBERS = SKILL_DIR / "references" / "numbers.md"
# A citation is `path`::`tok`,`tok`,…  The path span is followed by '::', then the evidence tokens are
# the remaining backticked spans until the next citation in the same row.
CITATION = re.compile(r"`([^`]+)`::")
TOKEN_SPAN = re.compile(r"`([^`]+)`")


def check_numbers() -> None:
    if not NUMBERS.exists():
        fail("missing references/numbers.md")
        return
    checked = 0
    tokens_checked = 0
    for line in NUMBERS.read_text(encoding="utf-8").splitlines():
        if "::" not in line:
            continue
        claim = line.split("|")[1].strip() if line.count("|") > 2 else line.strip()
        if claim.lower() in ("claim", "token form"):
            continue  # header and documentation rows show the format, not a citation
        marks = list(CITATION.finditer(line))
        for index, mark in enumerate(marks):
            rel = mark.group(1).strip()
            region_end = marks[index + 1].start() if index + 1 < len(marks) else len(line)
            tokens = [t.strip() for t in TOKEN_SPAN.findall(line[mark.end():region_end])]
            checked += 1
            source = ROOT / rel
            if not source.exists():
                fail(f"numbers.md: proof file '{rel}' does not exist (row: {claim})")
                continue
            raw = source.read_text(encoding="utf-8", errors="replace")
            body = squashed(raw)
            for token in tokens:
                if not token or "/" in token:
                    continue
                tokens_checked += 1
                if token.startswith("gate:"):
                    gate_token, _, wanted = token[5:].partition("=")
                    rows = [ln for ln in raw.splitlines() if re.match(r"^\|\s*G[0-9]", ln)]
                    found = sum(1 for ln in rows if gate_token.strip() in ln)
                    if str(found) != wanted.strip():
                        fail(
                            f"numbers.md: {rel} has {found} gate rows with '{gate_token.strip()}', "
                            f"the skill claims {wanted.strip()} (row: {claim})"
                        )
                elif token.startswith("re:"):
                    pattern = token[3:]
                    if not re.search(pattern, raw):
                        fail(
                            f"numbers.md: pattern '{pattern}' not found in {rel} "
                            f"(row: {claim})"
                        )
                elif token not in body:
                    fail(f"numbers.md: '{token}' not found in {rel} (row: {claim})")
    ok(f"numbers: {checked} proof citations, {tokens_checked} evidence tokens verified")


# --------------------------------------------------------------------------- main
def main() -> int:
    quiet = "--quiet" in sys.argv[1:]
    for check in (
        check_frontmatter,
        check_links,
        check_vlnvs,
        check_make_targets,
        check_paths,
        check_numbers,
    ):
        check()

    if failures:
        print("FAIL: the AI skill no longer agrees with the repository:\n", file=sys.stderr)
        for item in failures:
            print(f"  - {item}", file=sys.stderr)
        print(
            f"\n{len(failures)} problem(s). Fix the skill or the source — the skill is never the "
            "authority.",
            file=sys.stderr,
        )
        return 1

    if not quiet:
        for line in checks:
            print(f"PASS: {line}")
    print(f"PASS: AI skill in skills/rfsoc-doa-v7 agrees with the repository ({len(checks)} checks)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
