# Cardano Agent Skills

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/skills-19-green.svg)](#available-skills)

A comprehensive set of **small, focused Agent Skills** for Cardano development. Self-calibrating, safe by design, and built for Claude Code, Codex, Cursor, and other AI coding assistants.

## Features

- **Self-calibrating**: Skills detect your installed CLI version and adapt commands automatically
- **Safe by design**: Risky operations require explicit human invocation
- **Least privilege**: Each skill has restricted tool access appropriate to its function
- **Token-efficient**: Compact frontmatter with progressive detail loading

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

### Smart Contracts

| Skill | Description | Risk Level |
|-------|-------------|------------|
| `aiken-smart-contracts` | Aiken workflows: validators, building, blueprints, .plutus generation | Safe |
| `aiken-dex-security-audit` | Security audit playbook for Plutus V3 Aiken DEX contracts (guidance) | Safe (guidance) |
| `aiken-dex-security-audit-operator` | Execute security audit operations (findings, tests, reports) | Manual invoke |
| `plutus-v3-conway` | Plutus V3 under Conway: contexts, governance, V2→V3 migration | Safe |
| `meshjs-cardano` | MeshJS patterns: tx building, UTxO selection, wallet connectors | Safe |

### Hydra L2

| Skill | Description | Risk Level |
|-------|-------------|------------|
| `hydra-head` | Hydra Head best practices: setup, keys, peers, lifecycle (guidance) | Safe (guidance) |
| `hydra-head-operator` | Execute Hydra operations (init, commit, close) | Manual invoke |
| `hydra-head-troubleshooter` | Decision tree for Hydra issues: symptoms → fixes → verification | Safe |

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
│   │   ├── templates/         # Copy-paste templates, worksheets
│   │   └── examples/          # Expected output samples
│   └── ...
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

This means the skill reads your actual CLI output before giving advice—no more hallucinated flags.

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
