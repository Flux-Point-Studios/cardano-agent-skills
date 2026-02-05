# OpenClaw Exec Approvals (template + how to apply)

OpenClaw host execution (`exec` on `gateway` or `node`) is gated by **Exec approvals**, stored on the execution host at:

- `~/.openclaw/exec-approvals.json`

This repo includes a starter template:

- `openclaw/exec-approvals.template.json`

## Apply the template (recommended)
Use the OpenClaw CLI approvals helper to replace approvals from a file:

```bash
openclaw approvals set --file ./openclaw/exec-approvals.template.json
# or target gateway / node specifically:
openclaw approvals set --gateway --file ./openclaw/exec-approvals.template.json
openclaw approvals set --node <id|name|ip> --file ./openclaw/exec-approvals.template.json
```

## Why this template is safe-ish (and still usable)
- Defaults are `deny` (no accidental host RCE).
- Agent `main` is `allowlist` + `ask=on-miss` + `askFallback=deny`.
- `autoAllowSkills=true` lets the node treat skill-referenced executables as allowlisted where supported.

## Important: update allowlist patterns to match your machine
Allowlist patterns must resolve to **paths**, not basenames. Add patterns for where your binaries live, e.g.:

- `/opt/homebrew/bin/docker`
- `/usr/bin/docker`

You can also add patterns using the CLI helper:

```bash
openclaw approvals allowlist add "/opt/homebrew/bin/docker"
openclaw approvals allowlist add "~/Projects/**/cardano-agent-skills/scripts/oc-safe.sh"
```

## Exec session defaults (per session)
You can set session overrides inside OpenClaw:

```text
/exec host=gateway security=allowlist ask=on-miss
```

(Approvals still apply; `security=full` is the "I know what I'm doing" mode and skips approvals.)


## One-command apply (recommended)

From repo root:

```bash
./scripts/apply-approvals.sh --local
# or
./scripts/apply-approvals.sh --gateway
# or
./scripts/apply-approvals.sh --node <id|name|ip>
```

This replaces approvals from `openclaw/exec-approvals.template.json` and then allowlists `scripts/oc-safe.sh` plus any common binaries found on PATH.


## Final-boss flags

- `--dry-run` prints what would be changed without applying anything.
- `--broad-paths` also adds broad directory globs (dangerous).
