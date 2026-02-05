# Cardano Agent Skills

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/skills-20-green.svg)](#available-skills)

A comprehensive set of **small, focused Agent Skills** for Cardano development. Self-calibrating, safe by design, and built for Claude Code, OpenClaw, Codex, Cursor, and other AI coding assistants.

## Features

- **Self-calibrating**: Skills detect your installed CLI version and adapt commands automatically
- **Safe by design**: Risky operations require explicit human invocation
- **Least privilege**: Each skill has restricted tool access appropriate to its function
- **Token-efficient**: Compact frontmatter with progressive detail loading
- **Docker fallback**: Every CLI skill includes a wrapper that falls back to Docker if the binary isn't installed locally
- **OpenClaw compatible**: Skills include OpenClaw metadata for gating, install, and deterministic exec dispatch

## Quick Install

### Option A: Vercel Skills CLI
```bash
npx skills add Flux-Point-Studios/cardano-agent-skills
```

### Option B: add-skill (supports skill selection)
```bash
# Install all skills
npx add-skill Flux-Point-Studios/cardano-agent-skills -a claude-code

# Install specific skills only
npx add-skill Flux-Point-Studios/cardano-agent-skills --skill cardano-cli-wallets --skill cardano-cli-transactions -a claude-code
```

### Option C: Install for both Claude Code + OpenClaw

```bash
# Project scope (recommended)
./scripts/install.sh --project --yes

# Global scope
./scripts/install.sh --global --yes
```

PowerShell:
```powershell
.\scripts\install.ps1 -Scope project -Yes
```

## Available Skills

### Core CLI Operations

| Skill | Description | Risk Level |
|-------|-------------|------------|
| `cardano-cli-doctor` | Diagnose CLI version, detect era-prefixed vs legacy syntax, produce compatibility report | Safe (read-only) |
| `cardano-cli-wallets` | Create/manage keys, addresses, UTxO checks, wallet dossier output | Safe (guidance) |
| `cardano-cli-wallets-operator` | Execute wallet operations (key generation, address building) | Manual invoke |
| `cardano-cli-transactions` | Build, sign, submit standard transactions (guidance + templates) | Safe (guidance) |
| `cardano-cli-transactions-operator` | Execute transaction builds and submits | Manual invoke |
| `cardano-cli-staking` | Stake key registration, delegation, rewards withdrawal (guidance) | Safe (guidance) |
| `cardano-cli-staking-operator` | Execute staking operations | Manual invoke |
| `cardano-cli-plutus-scripts` | Plutus script transactions: datums, redeemers, collateral (guidance) | Safe (guidance) |
| `cardano-cli-plutus-scripts-operator` | Execute script spends and submits | Manual invoke |
| `cardano-protocol-params` | Fetch and validate protocol parameters | Safe |

### Operator Skills (deterministic exec dispatch)

| Skill | Description | Risk Level |
|-------|-------------|------------|
| `cardano-cli-operator` | Consolidated manual-only operator for all Cardano CLI commands (OpenClaw exec dispatch) | Manual invoke |
| `hydra-head-operator` | Execute Hydra operations (init, commit, close) with OpenClaw exec dispatch | Manual invoke |

### Smart Contracts

| Skill | Description | Risk Level |
|-------|-------------|------------|
| `aiken-smart-contracts` | Aiken workflows: validators, building, blueprints, .plutus generation | Safe |
| `aiken-dex-security-audit` | Security audit playbook for Plutus V3 Aiken DEX contracts (guidance) | Safe (guidance) |
| `aiken-dex-security-audit-operator` | Execute security audit operations (findings, tests, reports) | Manual invoke |
| `plutus-v3-conway` | Plutus V3 under Conway: contexts, governance, V2->V3 migration | Safe |
| `meshjs-cardano` | MeshJS patterns: tx building, UTxO selection, wallet connectors | Safe |

### Hydra L2

| Skill | Description | Risk Level |
|-------|-------------|------------|
| `hydra-head` | Hydra Head best practices: setup, keys, peers, lifecycle (guidance) | Safe (guidance) |
| `hydra-head-troubleshooter` | Decision tree for Hydra issues: symptoms -> fixes -> verification | Safe |

### Local Development

| Skill | Description | Risk Level |
|-------|-------------|------------|
| `cardano-devnet-in-a-box` | One-command local rehearsal stack: cardano-node + hydra + ogmios + kupo | Safe (local only) |

## Architecture

```
cardano-agent-skills/
├── shared/
│   └── PRINCIPLES.md          # Common safety rules across all skills
├── skills/
│   ├── <skill-name>/
│   │   ├── SKILL.md           # Skill definition (frontmatter + instructions)
│   │   ├── reference/         # Deep-dive docs, patterns, examples
│   │   ├── scripts/           # Docker fallback wrappers
│   │   ├── templates/         # Copy-paste templates, worksheets
│   │   └── examples/          # Expected output samples
│   └── ...
├── openclaw/
│   ├── exec-approvals.template.json  # OpenClaw exec allowlist template
│   └── EXEC_APPROVALS.md            # How to apply approvals
├── scripts/
│   ├── oc-safe.sh             # Single allowlisted entrypoint for OpenClaw
│   ├── apply-approvals.sh     # Apply exec approvals (bash)
│   ├── apply-approvals.ps1    # Apply exec approvals (PowerShell)
│   ├── install.sh             # Install for claude-code + openclaw (bash)
│   └── install.ps1            # Install for claude-code + openclaw (PowerShell)
├── devnet-in-a-box/
│   ├── run.sh                 # Orchestration (up/down/smoke/rehearsal)
│   ├── docker-compose.override.yml  # Ogmios + Kupo services
│   ├── scripts/               # rehearsal.sh, smoke.sh, hydra_ws.py
│   └── assets/                # always-true.plutus, datum.json
├── .github/
│   └── workflows/
│       └── validate-skills.yml  # CI validation
└── README.md
```

## Skill Design Principles

### 1. Self-Calibrating (Dynamic Context)

Skills that interact with CLI tools use dynamic context injection to adapt to your installed version:

```yaml
---
name: cardano-cli-doctor
context:
  - "!cardano-cli version"
  - "!cardano-cli --help | head -40"
  - "!cardano-cli conway --help 2>&1 | head -20"
---
```

This means the skill reads your actual CLI output before giving advice--no more hallucinated flags.

### 2. Safe by Design (Playbook + Operator Split)

Risky operations are split into two skills:

- **Playbook** (`cardano-cli-transactions`): Auto-discoverable, provides guidance, templates, and explanations. Cannot execute commands.
- **Operator** (`cardano-cli-transactions-operator`): Manual invoke only (`disable-model-invocation: true`). Can execute commands with explicit confirmation.

### 3. Least Privilege (Tool Restrictions)

Each skill declares exactly which tools it can use:

```yaml
---
name: cardano-cli-doctor
allowed-tools:
  - Bash(cardano-cli:*)
  - Bash(which:*)
  - Read
---
```

### 4. Token Efficiency

- Frontmatter `description` is always loaded (keep it tight)
- SKILL.md body loads when relevant
- Reference files load on demand
- Target: SKILL.md under 500 lines

### 5. Docker Fallback

Every CLI skill includes a `scripts/cardano-cli.sh` or `scripts/hydra-node.sh` wrapper that:
- Uses the native binary if installed
- Falls back to the official Docker image otherwise
- Mounts the working directory and node socket automatically

## OpenClaw Operator Skills

### Deterministic Exec Dispatch

Operator skills (`cardano-cli-operator`, `hydra-head-operator`) use OpenClaw's **command-dispatch: tool** mode to route commands directly to the **Exec Tool** without model invocation. This means:

- You type the command, it runs exactly what you typed
- No model hallucination of flags or parameters
- Gated by OpenClaw's exec approvals system

### Allowlist-Safe Wrapper

Use `scripts/oc-safe.sh` as a single allowlisted entrypoint in `security=allowlist` mode:

```bash
# Cardano CLI via oc-safe
./scripts/oc-safe.sh cardano version
./scripts/oc-safe.sh cardano query tip --mainnet

# Hydra via oc-safe
./scripts/oc-safe.sh hydra --help
./scripts/oc-safe.sh hydra-api 4001 head
```

### OpenClaw Fast-Secure Setup

```bash
# Apply exec approvals template
./scripts/apply-approvals.sh --local

# Preview changes without applying
./scripts/apply-approvals.sh --local --dry-run
```

Then in OpenClaw chat:

```text
/exec host=gateway security=allowlist ask=on-miss
```

See `openclaw/EXEC_APPROVALS.md` for full details.

## Devnet-in-a-Box (Local Cardano + Hydra + Ogmios + Kupo)

Folder: `devnet-in-a-box/`

Run deterministic green/red rehearsal:

```bash
cd devnet-in-a-box
./run.sh rehearsal
```

See `devnet-in-a-box/README.md` for full setup guide.

## Version Compatibility

Skills are tested against:
- `cardano-cli` 10.x+ (Conway era, era-prefixed commands)
- `cardano-node` 10.x+
- `hydra-node` 0.20.x+
- `aiken` 1.1.x+

The `cardano-cli-doctor` skill will detect your version and recommend the appropriate command style.

## Contributing

1. Fork the repo
2. Add/modify skills following the structure above
3. Ensure SKILL.md has valid frontmatter
4. Run validation: `npm run validate` (if available) or check CI
5. Submit PR

### Skill Naming Rules

- Lowercase with hyphens only
- Max 64 characters
- No reserved words (`claude`, `anthropic`, `skill`)
- Unique across the repo

## License

MIT - See [LICENSE](LICENSE)

## Links

- [Skills.sh](https://skills.sh) - Skill discovery and leaderboard
- [Claude Code Skills Docs](https://code.claude.com/docs/en/skills)
- [hydra.family](https://hydra.family) - Hydra Head documentation
- [Cardano Docs](https://docs.cardano.org)

---

Built by [Flux Point Studios](https://fluxpointstudios.com)
