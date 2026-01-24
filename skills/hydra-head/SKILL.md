---
name: hydra-head
description: "Hydra Head (hydra.family) best practices: run/operate hydra-node, configure keys/peers, open/close heads, commit/deposit/decommit, and production hardening."
---

# hydra-head

## When to use
- Use when you are setting up or operating `hydra-node` and `hydra-tui`, or integrating a dApp/client with Hydra Head.
- Use when debugging head lifecycle issues: peer connectivity, key mismatches, contestation/deposit periods, chain sync, or config drift.

## Operating rules (must follow)
- Always identify the target network: `mainnet` vs `preprod` vs `preview` (or devnet).
- Prefer **hydra.family docs** semantics and terminology; avoid mixing in outdated community lore.
- Treat Cardano `.sk` / `.skey` and Hydra `.sk` as secrets. Never print key contents.
- For any command/flag, prefer `hydra-node --help` and `hydra-node run --help` to confirm your installed version.
- Provide reproducible steps: config file/flags, directory layout, and a “how to verify it worked” check.

## Core best practices (from hydra.family docs)
1) Separate key roles
   - Cardano keys: identify the participant on L1 and pay fees for protocol transactions.
   - Hydra keys: used to multi-sign snapshots inside the head.
2) Connectivity requirements
   - hydra-node must connect to Cardano (via node socket + magic, or via Blockfrost project file).
   - hydra-node must connect to peers via `--peer host:port` and you should see PeerConnected signals/messages.
3) Lifecycle correctness
   - Contestation period (CP) governs the safety window after Close for Contest.
   - Deposit period (DP) influences when deposits are recognized; ensure deadlines are set safely beyond `now + DP`.
4) Production posture
   - Orchestrators should restart hydra-node if Cardano node is still revalidating and sockets aren’t ready.
   - Keep a strict “compatibility bundle”: scripts tx id for the network, correct signing keys, and peer vkeys.

## Workflow
1) Decide your topology and participants
   - Basic head: N hydra-nodes connected to each other and to Cardano; local client (hydra-tui) talks to one node.

2) Generate keys
   - Cardano payment keys (`cardano-cli address key-gen`)
   - Hydra keys (`hydra-node gen-hydra-key --output-file <name>`)

3) Configure and run hydra-node
   - Choose Cardano connection mode:
     - Direct to cardano-node: `--node-socket ...` plus `--testnet-magic <N>` or `--mainnet`
     - Blockfrost: `--blockfrost <project-file>` (do NOT also pass `--mainnet/--testnet-magic`)
   - Set protocol parameters:
     - `--contestation-period <Xs>`
     - `--deposit-period <Xs>` (if used in your setup)
   - Provide identity & peers:
     - `--cardano-signing-key ...`
     - `--cardano-verification-key ...` (for each peer)
     - `--hydra-signing-key ...`
     - `--hydra-verification-key ...` (for each peer)
     - `--peer host:port` for each peer

4) Open a head (client-driven)
   - Use hydra-tui or client API to:
     - Init
     - Commit
     - Open
   - Verify the head is open by observing status in client/logs.

5) Operate inside the head
   - Submit L2 transactions through the hydra-node API/client.
   - For adding funds after open: use deposits (if supported/needed).
   - For taking funds out: decommit workflow (incl. incremental decommits if enabled).

6) Close and settle safely
   - Close head
   - Monitor contestation window; ensure nodes will automatically Contest if needed.
   - Fanout / finalize on L1.
   - Verify final UTxO distribution on Cardano.

7) Debug checklist (common failure modes)
   - Wrong network / magic or Blockfrost misconfiguration
   - cardano-node not ready (socket not open yet)
   - Wrong scripts transaction id for the network
   - Signing key mismatch vs Init tx verification key
   - Peers not connected (bad `--peer` host:port)
   - Hydra key mismatch (AckSn / snapshot signing issues)

## Safety / key handling
- Prefer offline key generation for real funds.
- Restrict permissions on key files and keep separate directories per participant.
- Use testnets/devnet for rehearsal before mainnet.

## References used by this skill
- hydra.family Head protocol docs (configuration, getting started, tutorials, operating hydra-node)
- `shared/PRINCIPLES.md` (repo)
