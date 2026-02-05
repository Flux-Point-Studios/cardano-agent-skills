# OpenClaw gating + install snippets

OpenClaw expects `metadata` to be a **single-line JSON object** in SKILL frontmatter. It uses `metadata.openclaw.requires.*` to gate skills and `metadata.openclaw.install` for one-click installs in the macOS UI.

See: https://docs.openclaw.ai/tools/skills

## Docker-first gating (recommended for this pack)
- For Cardano CLI skills: require `cardano-cli` OR `docker`
- For Hydra skills: require `hydra-node` OR `docker`
- For Aiken: require `aiken`

## Example installer spec (brew)
```yaml
metadata: {"openclaw":{"emoji":"...","requires":{"anyBins":["docker","cardano-cli"]},"install":[{"id":"brew","kind":"brew","formula":"colima docker docker-compose curl","bins":["colima","docker","docker-compose","curl"],"label":"Install Docker runtime (Colima) + Docker CLI + Compose + curl (brew)","os":["darwin","linux"]}]}}
```
