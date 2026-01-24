---
name: hydra-head-troubleshooter
description: "Hydra Head troubleshooting decision tree: map symptoms/logs (PeerConnected, AckSn, no head observed, stuck peer out-of-sync, scripts tx id, cardano-node readiness) to exact fixes."
---

# hydra-head-troubleshooter

## When to use
- Use when Hydra Head **doesn't start**, **no head is observed**, **head doesn't make progress**, or peers are **out of sync**.
- Use when you see log keywords like `PeerConnected`, `AckSn`, `LogicOutcome`, `SnapshotAlreadySigned`, or when the node can't see the head on-chain.

## Operating rules (must follow)
- Always confirm network: `mainnet` / `preprod` / `preview` (and magic if applicable) and hydra-node version.
- Always ask for (or have the user run) these first:
  - `hydra-node --help` and `hydra-node run --help`
  - Last ~200 lines of hydra-node logs (JSON lines) from *each* participant, for the same time window
  - Peers list (`--peer ...`) and keys list (`--cardano-verification-key`, `--hydra-verification-key`)
- Never request or print key contents (`*.sk`, `*.skey`). File paths are fine.
- Output: (1) **Root cause hypothesis** (2) **Fix steps** (copy/paste) (3) **Verification checks**.

## Decision tree (fast)
### A) "No head is observed from the chain"
**Symptoms**
- Head never appears; node seems alive but no Init/Commit/Open progression.
- Client can't see head state.

**Most common causes + fixes**
1) Wrong network / cannot connect to cardano-node
   - Fix: validate `--network` (or `--mainnet/--testnet-magic`) matches the cardano-node you're connected to.
   - Fix: if using node socket, ensure cardano-node is fully ready; hydra-node can't connect until cardano-node finishes revalidation and opens connections.
   - Verify: `cardano-cli query tip ...` works and hydra-node logs show chain sync progress.

2) Scripts transaction id invalid (`--hydra-scripts-tx-id`)
   - Fix: use the scripts tx id from the hydra-node release notes for your network (preview/preprod/mainnet).
   - Verify: hydra-node should verify scripts are available on-chain and stop failing at startup.

3) Cardano signing key mismatch vs Init tx vkey
   - Fix: ensure `--cardano-signing-key` corresponds to the verification key used in the Init transaction.
   - Fix: ensure all peers have the correct `--cardano-verification-key` for your node.
   - Verify: peers can observe and advance head lifecycle after Init.

### B) "Head does not make progress"
**Symptoms**
- Head exists but doesn't move through phases; snapshots not confirmed; commands hang.

**Most common causes + fixes**
1) Peers not connected (`PeerConnected` missing or inconsistent across nodes)
   - Fix: verify every node has correct `--peer host:port` for every other node and that ports are reachable.
   - Verify: each node emits/observes `PeerConnected` consistently; metrics `hydra_head_peers_connected` reflects healthy connectivity.

2) Hydra keys mismatch / snapshot acks missing (`AckSn` not received by all parties)
   - Fix: verify each node's `--hydra-signing-key` belongs to the party and that all nodes have the correct `--hydra-verification-key` for peers.
   - Fix: check logs for `LogicOutcome` errors around snapshot signing.
   - Verify: `AckSn` observed and snapshots become confirmed.

### C) "Head stuck: peer out of sync"
**Symptoms**
- One node accepts txs while others reject; ledger states diverge.
- Snapshots stop being signed; submits appear to do nothing.

**Primary cause**
- Different local ledger views due to config drift (`--ledger-protocol-parameters`), version mismatches, or a peer being offline during tx submission.

**Fix (coordinated)**
- Use snapshot side-loading to revert peers back to latest confirmed snapshot:
  1) GET the latest confirmed snapshot from a healthy node: `GET /snapshot`
  2) POST that snapshot to out-of-sync peers: `POST /snapshot` with the ConfirmedSnapshot body
- This clears pending txs and aligns ledger state so consensus can resume.

**Verify**
- After side-load, snapshots resume and all parties sign again.

### D) Mirror nodes / HA weirdness
**Symptoms**
- You see `SnapshotAlreadySigned` occasionally.
- etcd quorum / connectivity flaps when too many mirror nodes go down.

**Reality**
- `SnapshotAlreadySigned` is transient and harmless when running mirror nodes with the same party keys.
- Keep mirror count < floor(n/2) so etcd quorum remains responsive.

## Verification checklist (always do)
- Confirm all nodes are running the same hydra-node version (or compatible range).
- Confirm scripts tx id matches the network.
- Confirm cardano-node readiness and correct network flags.
- Confirm peer mesh connectivity (PeerConnected everywhere).
- Confirm snapshots progress (AckSn + no LogicOutcome errors).
- Capture metrics endpoint if enabled (`--monitoring-port`).
