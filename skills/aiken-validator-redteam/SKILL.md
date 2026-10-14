---
name: aiken-validator-redteam
description: Executable multi-agent adversarial red-team for Plutus V3 Aiken validators — fans out one attacker per eUTxO exploit class, each writing PoC Aiken tests where a PASSING test proves a fund-stealing vulnerability, then skeptic-verifies every claim and returns a GREEN/AMBER/RED verdict. A harness-checked companion to aiken-dex-security-audit's manual playbook.
metadata:
  domain: cardano
  language: aiken
  category: security-audit
---

# aiken-validator-redteam

An *executable* red-team harness for Aiken/Plutus V3 validators. Where
`aiken-dex-security-audit` is a manual review playbook that produces a report,
this skill runs an adversarial campaign whose findings are **proven by the
compiler**: it fans out one attacker agent per known Cardano eUTxO exploit
class, each writes proof-of-concept Aiken tests, and **a test that PASSES means
the validator accepted a fund-stealing transaction — a confirmed vulnerability.**
Every claim is then independently reproduced by a skeptic pass, and a creative
"novel" round hunts for emergent cross-redeemer attacks.

Use it as an in-house pre-mainnet gate, or alongside a formal audit.

## When to use

- Before any mainnet deploy of new or changed validators (hard gate).
- After any validator source change (hashes change ⇒ re-run).
- When you want reproducible, PoC-backed evidence — not a checklist opinion.

If a vulnerability is confirmed: fix the validator → recompile → re-run this
campaign. Only a clean **GREEN** verdict (zero confirmed vulns across all
classes and the novel round) clears the gate.

## The core inversion (why it works)

A normal test asserts the validator **rejects** bad input. A red-team test
asserts the validator **accepts** a fund-stealing / invariant-breaking input:

- **A PASSING attack test = a CONFIRMED VULNERABILITY** (the validator returned
  `True` on a malicious tx).
- **A FAILING / crashing attack test = DEFENDED** (correctly rejected).

The attacker controls the *entire* transaction **except** the spent UTxO and
its real on-chain datum — every other input, output, ordering, index, the mint
field, redeemers, and the validity range are hostile.

## Structure (deterministic workflow)

1. **Attack** — one high-effort agent per exploit class, in parallel. Each
   writes `lib/tests/redteam_<class>.ak` full of adversarial transactions, runs
   `aiken check`, and reports confirmed vulns + the attacks it tried that were
   correctly rejected.
2. **Novel** — a few creative agents that COMBINE primitives across validators
   and invent emergent / multi-tx / economic attacks single-class agents miss.
3. **Verify** — a skeptic independently reproduces EVERY claim (per-class and
   novel) from scratch and confirms it is a real fund-loss, not a fixture
   artifact. It also classifies the **deployment precondition** (see below).
4. **Synthesize** — return `{classesRun, confirmedVulns, refutedClaims,
   verdict}`.

### Verdict levels

- **GREEN** — no confirmed vuln survived verification.
- **AMBER** — the protocol default is safe, but a confirmed finding depends on a
  *deployment footgun* (e.g. an order deployed behind a permissionless/shared
  stake script rather than the owner's own verification-key credential). Harden
  and/or enforce the safe deployment, and correct any overstated code comments.
- **RED** — a *permissionless* (protocol-wide) drain or forgery was confirmed.
  Fix before mainnet.

Distinguishing "permissionless" from "footgun-only" matters: a finding that
only bites a mis-configured deployment is a different severity from one any
third party can trigger against the default. The verify pass records which.

## Exploit taxonomy (the classes)

Universal eUTxO fund-loss vectors. Adapt the specifics to the contract under
test; the *categories* generalize across DEXes, lending, staking, launchpads,
beacon-token (CIP-0089) dApps, and any value-locking validator set.

| Class | What the attacker tries |
|---|---|
| `double_sat` | One output satisfying two+ script inputs (two positions, or position+fee counting the same payout), especially in a batched multi-action tx. |
| `value_underpay` | Pay owner/fee/vault less than owed; exploit ratio floor/ceil rounding; mint value from nowhere; a partial action releasing more than the ratio allows; zero/negative amounts. |
| `mint_integrity` | Mint EXTRA tokens under a policy; wrong token names (not the hash of the datum they attest); create-without-burn on close; leak a policy token to a non-script output; net-zero cheats. |
| `auth` | Cancel/close/reprice/update WITHOUT the owner credential; key-vs-script credential confusion; spoof the owner via a permissionless stake script (withdraw-zero); missing required signatory. |
| `index` | Wrong input/output index so an `*_at` lookup resolves a DIFFERENT input/output; reorder inputs/outputs to shift indices; out-of-range → crash-open vs fail-closed. |
| `continuation` | Continuation output to a WRONG address; tamper an immutable datum field; bypass a value-conservation check via a second output, token substitution, or negatives. |
| `terms` | Re-quote an order/position to adverse economic terms while value+owner+pair stay pinned (the value check holds), then let a permissionless action drain via the counterparty path — a cross-redeemer composition the per-redeemer checks miss. |
| `receipt` | Forge a proof/receipt token with no real action; attributes not matching the enforced amounts; multiple proofs per action; duplicate-claim guards defeated by padding. |
| `refscript` | Spend with a WRONG/attacker reference script; reference-input disjointness tricks; forged spend script + real policy reference; inline-script substitution. |
| `composed` | Siphon value between positions in one tx; index collisions across a batch; mix action types; one payout covering two positions. |
| `directional` | (Two-way / AMM) fill at a better-than-set price; asymmetric take draining one reserve; price rational overflow/rounding; min-take bypass. |
| `datum_decode` | Malformed / extra-field / wrong-type datum as state or continuation; force crash-OPEN vs fail-closed; InlineDatum vs DatumHash confusion; wrong version tag. |
| `time` | Act past a validity/deadline; unbounded validity accepted; upper bound > deadline; time interacting with partials/re-quotes/two-way; `None` edge. |
| `oracle_premium` | (If coverage/oracle) underpay a premium; skip/wrong vault; premium rounding to zero; a path that fails to enforce the oracle/coverage. |
| `novel_*` | Combine the above; multi-tx sequences; economic griefing; policy-vs-script-hash parameterization mismatch; a footgun credential combined with any path. |

## How to run

Pass the aiken project location (and optionally a remote build host) via `args`:

```
Workflow({ name: "aiken-validator-redteam", args: { project: "contracts", remoteHost: null } })
```

or run the bundled script directly:

```
Workflow({ scriptPath: ".../skills/aiken-validator-redteam/redteam-workflow.js",
           args: { project: "contracts" } })
```

- `args.project` — path to the aiken project (the dir containing `aiken.toml`,
  `validators/`, `lib/`). Defaults to `.`.
- `args.remoteHost` — optional ssh host with aiken installed. **Leave null to
  compile locally.** Set it to offload compiles when your orchestration box is
  memory-constrained: a fan-out of many parallel Rust/aiken compiles can OOM a
  small host, so point this at a bigger machine and each agent will `cp` its
  copy and `aiken check` there over ssh.

Edit the `CLASSES` array's `.focus` strings to match your contract's redeemers
and datums. Keep the attack/verify/novel agents at high reasoning effort.

## Reading the result honestly

- A GREEN verdict is only trustworthy if agents **actually ran** — confirm the
  attack agents executed `aiken check` and the run spent real tokens. A verdict
  with zero agent activity is a harness error, not a pass.
- Confirmed vulns must be **reproduced by the verify pass**, not merely claimed
  by an attacker — attackers over-claim; skeptics filter.
- **Time / validity-range findings need a ledger-consistency check.** A unit test
  calls the validator directly and can present a `validity_range` the chain would
  never include — the ledger only admits a tx when the real slot is inside
  `[lower_bound, upper_bound]`, so a width bound like `hi - lo <= max_skew` pins
  `hi` to within `max_skew` of real time. An attack that only "accepts" because
  the datum's timestamps and the `[lo,hi]` range describe timelines that can't
  coexist on one real chain (records stamped seconds ago but `hi` set years
  ahead) is a **unit-test artifact**, not an exploit. Before confirming a
  time-based finding, reproduce it under a single consistent timeline: every
  timestamp the validator stamps equals the `hi` of the tx that created it, each
  such tx's real slot lies in its own `[lo,hi]`, and every `[lo,hi]` respects the
  width bound. If it no longer accepts, it is REFUTED. (The verify pass enforces
  this, but read time-based CONFIRMED findings with this in mind.)
- This clears an *in-house* gate. It does not replace a formal third-party audit
  where one is contractually required. Pair it with
  `aiken-dex-security-audit` for the written threat model, invariants, and
  deployment checklist.

## Non-negotiable rules

- Assume a hostile attacker crafting arbitrary transactions: multi-input,
  multi-action, weird datums, weird token bundles.
- Never handle seed phrases or private keys; the campaign only needs source.
- Evidence over vibes: a minimal tx shape as a failing/passing Aiken test, run
  by the compiler — never a "looks fine" assertion.
- Do not modify validator source during the campaign — attackers only ADD test
  files in isolated copies.
