# Skills — this repository, for AI assistants

A *skill* is a folder an assistant loads when a question touches a topic: a short `SKILL.md` that is
always read, plus `references/` it opens only when needed. This directory packages the ZCU208 DOA V7
project that way, so a chat bot can answer questions about the design without the whole repository in
its context — and without inventing numbers.

```
skills/
├── README.md                       ← this file
└── rfsoc-doa-v7/
    ├── SKILL.md                    the operating manual (frontmatter + rules + map)
    ├── references/
    │   ├── architecture.md         layers, clock domains, widths, control map
    │   ├── signal-chain.md         block by block, with the code that implements each
    │   ├── algorithms.md           step 0–7: geometry, MTS, DOA chain, AMC, ladder
    │   ├── build-and-gates.md      the 20 stages, 14 gates, make targets, evidence
    │   ├── ip-and-ide.md           the 8 IPs, VLNVs, clock constraints, IDE routes
    │   ├── numbers.md              measured values, each with its proof file and token
    │   └── answering-rules.md      traps, style, glossary, good/bad examples
    ├── prompts/
    │   └── chatbot-system-prompt.md  flattened system prompt for bots with no tools
    └── evals/
        └── questions.md          24 graded questions, 10 of them traps
```

## Install

**Claude Code / any agent with a filesystem.** Copy or symlink the folder into a skills directory:

```bash
mkdir -p ~/.claude/skills
cp -r skills/rfsoc-doa-v7 ~/.claude/skills/
```

Project-scoped instead: `.claude/skills/rfsoc-doa-v7/` inside the repo (git-ignored or committed, your
choice). The assistant reads `SKILL.md` when a question matches its `description`.

**Claude.ai / ChatGPT / any upload-based bot.** Zip the folder and upload it as a skill or knowledge
file; if the platform only accepts flat documents, upload `SKILL.md` plus the `references/*.md` you
expect to need (start with `architecture.md`, `numbers.md`, `build-and-gates.md`).

**Custom GPT, Gem, Copilot, AnythingLLM, a bare API call.** Paste
`prompts/chatbot-system-prompt.md` as the system message. It is self-contained: facts, gates, commands,
refusal rules.

**RAG.** Chunk on `##`/`###` headings; every file here is already sectioned for that. Keep
`numbers.md` as one chunk if you can — its rows are only meaningful next to their proof column.

## Why bother

The failure mode this project punishes is the confident wrong number: "the DOA clock is 128 MHz", "the
channelizer came from HLS", "72.5 % field accuracy", "it's validated because there's a bitstream". The
skill exists to make those answers hard to give: rules in `SKILL.md` §2, traps in
`answering-rules.md`, and a machine check on every number.

## Keeping it true

```bash
make skill-check          # or: python3 scripts/check_skill.py
```

It verifies, in about a second:

- `SKILL.md` has valid frontmatter, and the name matches the folder;
- every relative link between skill files resolves;
- every `openai:doa:<ip>:<version>` in the skill matches `config/ip_versions.tcl` and `config.mk`;
- every `make <target>` mentioned in the skill exists in the top-level `Makefile`;
- every repository path cited in backticks exists;
- every row of `references/numbers.md` still finds its file **and** its evidence token, and the gate
  status count still matches `docs/GATES_G1_G7.md`.

`make lint` runs it too, so a skill that drifts fails the same check as a Tcl that no longer parses.

## When the project changes

| change | what to edit |
|---|---|
| a stage is added or renamed | `references/build-and-gates.md` §2, `SKILL.md` §1 |
| a gate closes | `references/build-and-gates.md` §3, `numbers.md` gate row, `SKILL.md` frontmatter `state` |
| an IP version is bumped | `references/ip-and-ide.md` §1, `references/numbers.md` |
| a new measured number | add a row to `numbers.md` with its proof file and a literal token |
| new IDE procedure | `docs/BLOCK_GUIDE.md` Part 6 first, then a summary line in `references/ip-and-ide.md` |

Never put a number in the skill that is not in a file with a token in it. That single rule is what
makes the whole thing worth having.
