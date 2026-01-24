---
name: cardano-cli-doctor
description: "Diagnose the local cardano-cli: supported eras, legacy vs era-prefixed syntax, network flags, and produce a compatibility report + recommended command style."
---

# cardano-cli-doctor

## When to use
- Use when you need to figure out which `cardano-cli` command style the user should use (era-prefixed like `cardano-cli conway ...` vs legacy flags like `--babbage-era`).
- Use before generating complex CLI workflows (script spends, staking, governance) to avoid wrong flags.

## Operating rules (must follow)
- Never ask for or log secret key contents.
- Prefer **read-only** diagnostics first (`--help`, `version`, `query tip`).
- If the user is on an air-gapped machine, avoid commands that require network connectivity unless they explicitly want that.
- Output a **Compat Report** and a **Recommended Style** (with example commands).

## Workflow
1) Collect environment facts
   - OS / shell
   - `cardano-cli version` output
   - `cardano-cli --help` output (first ~40 lines is enough)
   - Check for era-prefixed command availability:
     - `cardano-cli conway --help`
     - `cardano-cli latest --help` (if present)
   - Check for legacy era flags in transaction help:
     - `cardano-cli transaction build --help` (look for `--babbage-era` / `--alonzo-era` etc)

2) Decide command style
   - If `cardano-cli conway --help` works ⇒ **era-prefixed supported**
   - If `--babbage-era` exists in help ⇒ **legacy era flags supported**
   - If both exist ⇒ prefer **era-prefixed** (newer) unless user is pinned to legacy scripts

3) Network sanity checks (optional)
   - If user provides node socket env / connection, run:
     - `cardano-cli query tip --mainnet` or `--testnet-magic <N>`
   - Detect and report common misconfig (missing socket, wrong magic, wrong network)

4) Produce a Compat Report
   - CLI version + commit
   - Supported era prefix commands (conway, babbage, alonzo, shelley, latest)
   - Legacy flag support detected (yes/no)
   - Recommended command style (era-prefixed vs legacy)
   - Network flags to use (`--mainnet` vs `--testnet-magic`)
   - Next-step templates to copy/paste

## Safety / key handling
- Avoid commands that print or touch `.skey` files.
- Recommend `chmod 600 *.skey` and offline keygen for real funds.

## References used by this skill
- `shared/PRINCIPLES.md` (repo)
