# MCP Provider Architecture

This document describes how `cardano-agent-skills` integrates with MCP (Model Context Protocol) servers as optional runtime providers.

## Design principle

**MCP is a provider, not a replacement.**

The skill repo is the orchestration and safety layer. MCP servers are optional runtime backends that handle wallet state and signing. The agent picks the best available provider for each operation:

```
┌─────────────────────────────────────────────┐
│           cardano-agent-skills              │
│  (guidance, safety rules, tx patterns)      │
├─────────────────────────────────────────────┤
│         Provider selection layer            │
├──────────┬──────────┬──────────┬────────────┤
│  cardano │  Koios   │ CLI +    │  Docker    │
│  MCP     │ Provider │ node     │  fallback  │
│ (opt.)   │ (opt.)   │ (native) │  (auto)    │
└──────────┴──────────┴──────────┴────────────┘
```

## Provider capabilities

| Capability         | cardano MCP     | Koios (MeshJS)        | CLI (native/Docker) |
|--------------------|------------------|-----------------------|---------------------|
| Query balances     | `get_balances`   | `fetchAddressUTxOs`   | `cardano-cli query utxo` |
| Query UTxOs        | `get_utxos`      | `fetchAddressUTxOs`   | `cardano-cli query utxo` |
| Query addresses    | `get_addresses`  | `wallet.getChangeAddress` | `cardano-cli address build` |
| Query staking      | `get_stake_delegation` | `fetchAccountInfo` | `cardano-cli query stake-address-info` |
| ADAHandles         | `get_adahandles` | manual policy query   | not supported |
| Build transactions | not supported    | `MeshTxBuilder`       | `cardano-cli transaction build` |
| Sign transactions  | `submit_transaction` (auto-sign) | `wallet.signTx` | `cardano-cli transaction sign` |
| Submit transactions| `submit_transaction` | `wallet.submitTx` | `cardano-cli transaction submit` |
| Testnet support    | assumes mainnet*  | yes (any network) | yes (any network) |
| Plutus scripts     | not supported    | partial               | full support |
| Hydra              | not supported    | not supported         | via hydra-node |

*Current integration assumes mainnet unless testnet support is explicitly validated against the configured MCP server.

## Provider selection rules

These are **hard rules**, not suggestions. Follow in order:

### Read-only wallet state (balances, addresses, UTxOs, staking, handles)

1. If MCP is configured → use MCP skills (`cardano-mcp-balances`, `cardano-mcp-identity`, `cardano-mcp-staking`).
2. If MCP is not configured → use `koios-agent-wallet` or `cardano-cli-wallets`. Never error on missing MCP.
3. If user needs testnet → use Koios or CLI regardless of MCP availability.

### Transaction construction (building unsigned tx)

1. Always use CLI or existing builder skills (`cardano-cli-transactions`, `meshjs-cardano`, `koios-agent-wallet`).
2. MCP cannot build transactions — never attempt to use it for construction.

### Transaction signing + submission

1. MCP can sign+submit via `cardano-mcp-transactions` ONLY after the full preview-confirm flow.
2. If the agent cannot produce a structured preview (network, source, outputs, fee, CBOR fingerprint) → refuse.
3. If the network is uncertain or the user says testnet → do NOT use MCP. Route to Koios or CLI with explicit network flags.
4. **Fail closed:** unsupported or uncertain cases must refuse, not silently switch providers.

### Plutus scripts, Hydra, Aiken

1. MCP has no script or L2 support. Use dedicated skills exclusively.
2. Never fall back to MCP for these operations.

## Trust boundaries

```
┌─────────────────────────────┐
│  MCP server process         │
│  ┌───────────────────────┐  │
│  │ Seed phrase (env var) │  │  ← never leaves this boundary
│  │ Lucid wallet instance │  │
│  │ Local signing          │  │
│  └───────────────────────┘  │
│  Exposes: 6 read/submit     │
│  tools via MCP protocol     │
├─────────────────────────────┤
│  AI agent (Claude Code)     │
│  ┌───────────────────────┐  │
│  │ Skill operating rules │  │  ← enforces confirmation before submit
│  │ Provider selection    │  │
│  │ User-facing output    │  │
│  └───────────────────────┘  │
├─────────────────────────────┤
│  User                       │  ← approves/denies tool calls
│                             │  ← confirms transactions before submit
└─────────────────────────────┘
```

Key properties:
- The seed phrase never leaves the MCP server process.
- The MCP server has **no** server-side approval gate — it signs anything passed to `submit_transaction`.
- Safety is enforced by the skill's operating rules (require user confirmation) and the MCP client's tool approval UI.
- CLI keys (used by Koios/CLI providers) are handled via env vars or file paths, never by the LLM.

## Adding new MCP providers

If a new Cardano MCP server appears (e.g., with testnet support or tx building):

1. Create a new guidance skill in `skills/<provider-name>/SKILL.md`
2. Document its tools, capabilities, and limitations
3. Add it to the provider selection table above
4. Reference `shared/PRINCIPLES.md` for safety rules
5. Update `shared/mcp-provider.md` (this file)

## Upstream references

- `@indigoprotocol/cardano-mcp` — MIT-licensed generic Cardano MCP server
- `@indigoprotocol/cardano-ai` — optional companion (4 skills wrapping cardano-mcp)
- cardano-mcp is **not** a hard dependency. It is detected at runtime by skill availability.
