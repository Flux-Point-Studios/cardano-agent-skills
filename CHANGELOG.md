# Changelog

All notable changes to Cardano Agent Skills are documented here.

## [v6] — 2026-03-11

**MCP provider integration + Koios agent wallet (community PR)**

### Added
- **4 focused MCP skills** for `@indigoprotocol/cardano-mcp` integration (mirrors upstream grouping):
  - `cardano-mcp-balances` — read-only: `get_balances`, `get_addresses`, `get_utxos`
  - `cardano-mcp-identity` — read-only: `get_adahandles` (ADAHandle lookup)
  - `cardano-mcp-staking` — read-only: `get_stake_delegation` (pool + rewards)
  - `cardano-mcp-transactions` — high-risk: `submit_transaction` with mandatory structured preview-confirm flow (network, source, outputs, fee, CBOR fingerprint)
  - Provider detection: MCP → Koios → CLI fallback; fail closed on uncertain network
- **`koios-agent-wallet` skill** (merged from PR #2, author: @ThaMacroMan)
  - Key-based Cardano wallet setup with MeshJS + KoiosProvider
  - `scripts/agent-wallet.js` — send ADA, stake, sign+submit dApp txs
  - `scripts/generate-key-based-wallet.js` — generate wallet without mnemonic or cardano-cli
  - CSL dual-key signing for staking (payment + stake witnesses)
- **`shared/mcp-provider.md`** — MCP provider architecture doc: provider selection rules, capability matrix, trust model diagram

### Changed
- README.md updated with MCP provider section, provider architecture, and skill count (25)
- Architecture diagram now shows provider selection layer (MCP / Koios / CLI / Docker)
- Network wording: "assumes mainnet unless testnet support is explicitly validated" (not hardcoded claim)

### Stats
- Total skills: **25** (17 guidance + 8 operator)

---

## [v5] — 2026-02-05

**OpenClaw operators, Docker fallback, and exec approval infrastructure**

### Added
- **OpenClaw operator infrastructure** — `openclaw/` directory with exec-approvals template and documentation
- **Install & approval scripts** — `scripts/install.sh`, `scripts/install.ps1`, `scripts/apply-approvals.sh`, `scripts/apply-approvals.ps1`
- **`oc-safe.sh`** — single allowlisted entrypoint for OpenClaw exec dispatch; rejects shell metacharacters
- **`cardano-cli-operator` skill** — consolidated manual-only operator with OpenClaw exec dispatch frontmatter
- **Docker fallback wrappers** — `cardano-cli.sh` added to 7 cardano-cli skills; `hydra-node.sh` added to 3 hydra skills; `hydra-api.sh` added to hydra-head-operator
- **`docker-fallback.md`** reference doc added to 9 skills
- **`OPENCLAW_METADATA_SNIPPETS.md`** — reference doc for OpenClaw metadata format
- OpenClaw `metadata` line added to frontmatter of 12 SKILL.md files
- Docker fallback mode section added to body of 12 SKILL.md files

### Changed
- README.md rewritten with OpenClaw sections, architecture diagram, and updated skill count (20)
- `validate-skills.js` regex fixed for Windows CRLF line endings (`\r?\n`)

### Stats
- 44 files changed, 1424 insertions, 7 deletions
- Total skills: **20** (12 guidance + 8 operator)

---

## [v4] — 2026-02-04

**Devnet-in-a-box with deterministic rehearsal stack**

### Added
- **`cardano-devnet-in-a-box` skill** — full local devnet orchestrator
- **`devnet-in-a-box/` directory** with:
  - `run.sh` — main orchestrator (212 lines)
  - `scripts/rehearsal.sh` — deterministic rehearsal flow (488 lines)
  - `scripts/hydra_ws.py` — WebSocket test harness for Hydra (296 lines)
  - `scripts/smoke.sh` — quick smoke tests (46 lines)
  - `docker-compose.override.yml` — Hydra overlay config
  - `assets/always-true.plutus` and `assets/datum.json` — test fixtures

### Stats
- 10 files changed, 1421 insertions
- Total skills: **19**

---

## [v3.1] — 2026-01-27

**Aiken DEX security audit skill**

### Added
- **`aiken-dex-security-audit` skill** — guidance skill for auditing Aiken-based DEX validators
  - `references/audit-framework.md` — comprehensive audit methodology
  - `references/findings-severity-guide.md` — severity classification guide
  - `templates/audit-report.md` — structured audit report template
  - `templates/invariants-checklist.md` — validator invariants checklist
  - `templates/tx-shapes.md` — transaction shape analysis template
- **`aiken-dex-security-audit-operator` skill** — matching operator skill

### Fixed
- YAML frontmatter formatting in `aiken-dex-security-audit-operator` (85d241d)

### Stats
- 7 files changed, 384 insertions

---

## [v3] — 2026-01-25

**Major upgrade: self-calibrating, safe-by-design skill pack**

### Added
- **CI validation pipeline** — `.github/workflows/validate-skills.yml` + `validate-skills.js`
- **Operator skills** (manual-only, `disable-model-invocation: true`):
  - `cardano-cli-plutus-scripts-operator`
  - `cardano-cli-staking-operator`
  - `cardano-cli-transactions-operator`
  - `cardano-cli-wallets-operator`
  - `hydra-head-operator`
- **Source reference docs** — `reference/sources.md` for hydra-head and hydra-head-troubleshooter

### Changed
- All 10 existing guidance skills rewritten with:
  - Structured YAML frontmatter (`allowed-tools`, `context`, `user-invocable`)
  - Self-calibrating operating rules and safety disclaimers
  - Expanded templates, examples, and reference material
- README expanded with skill matrix, architecture notes, and installation instructions

### Stats
- 21 files changed, 2776 insertions, 391 deletions
- Total skills: **16** (11 guidance + 5 operator)

---

## [v2] — 2026-01-24

**Hydra and diagnostics skills**

### Added
- **`hydra-head` skill** — guidance for Hydra Head protocol operations
  - `reference/hydra-best-practices.md`
  - `templates/runbook.md`
- **`hydra-head-troubleshooter` skill** — Hydra diagnostics and incident response
  - `reference/probes.md`
  - `templates/incident-worksheet.md`
- **`cardano-cli-doctor` skill** — node health checks and environment diagnostics
  - `reference/doctor.md`
  - `scripts/cardano-cli-doctor.sh`

### Stats
- 9 files changed, 419 insertions
- Total skills: **10**

---

## [v1] — 2026-01-23

**Initial release: core Cardano CLI skills**

### Added
- **7 core skills**:
  - `aiken-smart-contracts` — Aiken project structure, validators, blueprints
  - `cardano-cli-plutus-scripts` — Plutus script transactions via CLI
  - `cardano-cli-staking` — stake key registration, delegation, rewards
  - `cardano-cli-transactions` — standard transaction building and submission
  - `cardano-cli-wallets` — key generation, addresses, UTxO management
  - `cardano-protocol-params` — protocol parameter queries and fee analysis
  - `meshjs-cardano` — MeshJS transaction building and wallet connectors
  - `plutus-v3-conway` — Plutus V3 / Conway era notes and migration guide
- **`shared/PRINCIPLES.md`** — cross-skill safety and design principles
- LICENSE and README

### Stats
- 19 files changed, 512 insertions
- Total skills: **7** (guidance only, listed as 8 including shared principles)
