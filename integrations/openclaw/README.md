# Sotto for OpenClaw

A thin packaging entry point for an OpenClaw agent running on macOS 14.2+ with Apple Silicon. Sotto provides local speech recognition and access to saved transcripts, meeting artifacts, and derived knowledge cards.

## Install and discover

```bash
SOTTO=/Applications/Sotto.app/Contents/MacOS/sotto-cli
"$SOTTO" --version
"$SOTTO" spec --json
"$SOTTO" health --json
```

The CLI ships inside the installed app. Inspect that binary's version and catalog rather than assuming it matches this checkout's unreleased candidate. Model readiness and optional repairs are covered by the canonical integration guide; do not download or change shared defaults merely to initialize a skill.

## Package for ClawHub

- Adapt the existing [`sotto-stt` skill directory](../skill/sotto-stt/SKILL.md), rather than maintaining a second command catalog or prompt here.
- Use `SKILL.md` with frontmatter, not `SOUL.md`. Verify ClawHub's current [skill format](https://docs.openclaw.ai/clawhub/skill-format) and publishing instructions before registration; this repository does not pin an external registry manifest or publication command.
- Declare the macOS/Apple Silicon host requirement and `sotto-cli` executable dependency. The host binary ships inside `Sotto.app`.
- Preserve the skill's consent, evidence, privacy, and isolation guidance. Optional provider credentials are not prerequisites for local speech recognition or deterministic transcript retrieval.

## Canonical references

- [Integration guide](../README.md): command recipes, JSON/error handling, retrieval citations, shared-state boundaries, and network behavior.
- [Reusable agent skill](../skill/sotto-stt/SKILL.md): operating instructions.
- Installed `sotto-cli spec --json`: runtime command/option catalog.
- [CLI changelog](../../Sources/CLI/CHANGELOG.md): versioned compatibility.
- [Repository agent guide](../../AGENTS.md): source-development rules only.

## Status

Publication to ClawHub remains pending in this integration record; this candidate documentation update does not establish registry publication. Track packaging work under the repository's [`integration` issues](https://github.com/buluma/sotto/issues?q=is%3Aissue+label%3Aintegration).
