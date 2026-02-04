\
#!/usr/bin/env bash
set -euo pipefail

# Deterministic Hydra rehearsal:
# - smoke checks (cardano-node + hydra APIs + optional kupo health)
# - init head
# - commit: alice(script UTxO + collateral) + bob + carol
# - submit one L2 tx (spend the script UTxO inside the head)
# - close + wait contestation + fanout
#
# Output: "GREEN" on success, "RED" on failure.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_SH="$ROOT_DIR/run.sh"
HYDRA_DIR="$ROOT_DIR/.vendor/hydra"
DEMO_DIR="$HYDRA_DIR/demo"
CREDENTIALS_HOST="$HYDRA_DIR/hydra-cluster/config/credentials"
ASSETS_DIR="$ROOT_DIR/assets"
WS_PY="$ROOT_DIR/scripts/hydra_ws.py"

NETWORK_MAGIC="42"
NODE_SOCKET="/devnet/node.socket"

API_ALICE="http://localhost:4001"
API_BOB="http://localhost:4002"
API_CAROL="http://localhost:4003"

WS_ALICE_SEND="ws://localhost:4001?history=no"
WS_ALICE_HISTORY="ws://localhost:4001?history=yes"

TMP_HOST="$ROOT_DIR/.rehearsal-tmp"

log() { printf "[rehearsal] %s\n" "$*"; }
die() { printf "\n❌ RED — %s\n" "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

# docker compose v2 preferred, v1 fallback
COMPOSE_BIN="docker compose"
if ! docker compose version >/dev/null 2>&1; then
  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_BIN="docker-compose"
  else
    die "docker compose (v2) or docker-compose (v1) is required"
  fi
fi

compose() { (cd "$DEMO_DIR" && $COMPOSE_BIN "$@"); }
cardano_cli() { compose exec -T cardano-node cardano-cli "$@"; }

ensure_tmp() {
  rm -rf "$TMP_HOST"
  mkdir -p "$TMP_HOST"
}

# ---- JSON helpers (host-side python) ----
\
py_pick_utxo() {
  # Prints: "<txin> <lovelace>" picking the largest ADA-only UTxO.
  python3 - "$1" <<'PY'
import json, sys
path=sys.argv[1]
data=json.load(open(path))
if not data:
  raise SystemExit(2)

def ada_only(val):
  return isinstance(val, dict) and set(val.keys())=={"lovelace"}

cands=[]
for txin, info in data.items():
  val=info.get("value",{})
  lov=int(val.get("lovelace",0) or 0)
  if ada_only(val):
    cands.append((lov, txin))

if cands:
  cands.sort(reverse=True)
  lov, txin = cands[0]
else:
  txin = next(iter(data.keys()))
  lov = int(data[txin]["value"]["lovelace"])

print(f"{txin} {lov}")
PY
}

\
py_make_commit_request() {
  # args: utxo_json_file blueprint_json_file out_file
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
utxo_path, blueprint_path, out_path = sys.argv[1:4]
utxo=json.load(open(utxo_path))
blueprint=json.load(open(blueprint_path))
req={"utxo": utxo, "blueprintTx": blueprint}
json.dump(req, open(out_path,"w"), separators=(",",":"))
PY
}

\
py_wrap_newtx() {
  # args: signed_tx_json_file out_file
  python3 - "$1" "$2" <<'PY'
import json, sys
tx_path, out_path = sys.argv[1:3]
tx=json.load(open(tx_path))
msg={"tag":"NewTx","transaction":tx}
json.dump(msg, open(out_path,"w"), separators=(",",":"))
PY
}

\
py_snapshot_has_txin() {
  # args: snapshot_json_file txin  (exit 0 if present, 1 otherwise)
  python3 - "$1" "$2" <<'PY'
import json, sys
snap_path, txin = sys.argv[1:3]
snap=json.load(open(snap_path))
raise SystemExit(0 if txin in snap else 1)
PY
}

\
py_json_len() {
  python3 - "$1" <<'PY'
import json, sys
d=json.load(open(sys.argv[1]))
print(len(d))
PY
}

# ---- Container file staging ----
stage_into_cardano_node() {
  local cid
  cid="$(compose ps -q cardano-node)"
  [ -n "$cid" ] || die "cardano-node container not found (is the stack up?)"

  log "Staging credentials + assets into cardano-node container..."
  compose exec -T cardano-node sh -lc 'rm -rf /tmp/rehearsal /tmp/credentials && mkdir -p /tmp/rehearsal' >/dev/null

  # Copy creds dir into /tmp (becomes /tmp/credentials)
  docker cp "$CREDENTIALS_HOST" "${cid}:/tmp" >/dev/null

  docker cp "$ASSETS_DIR/always-true.plutus" "${cid}:/tmp/rehearsal/always-true.plutus" >/dev/null
  docker cp "$ASSETS_DIR/datum.json" "${cid}:/tmp/rehearsal/datum.json" >/dev/null
}

build_party_addresses() {
  log "Building party addresses..."
  cardano_cli address build \
    --payment-verification-key-file /tmp/credentials/alice-funds.vk \
    --testnet-magic "$NETWORK_MAGIC" \
    --out-file /tmp/rehearsal/alice.addr

  cardano_cli address build \
    --payment-verification-key-file /tmp/credentials/bob-funds.vk \
    --testnet-magic "$NETWORK_MAGIC" \
    --out-file /tmp/rehearsal/bob.addr

  cardano_cli address build \
    --payment-verification-key-file /tmp/credentials/carol-funds.vk \
    --testnet-magic "$NETWORK_MAGIC" \
    --out-file /tmp/rehearsal/carol.addr

  ALICE_ADDR="$(compose exec -T cardano-node cat /tmp/rehearsal/alice.addr | tr -d '\r\n')"
  BOB_ADDR="$(compose exec -T cardano-node cat /tmp/rehearsal/bob.addr | tr -d '\r\n')"
  CAROL_ADDR="$(compose exec -T cardano-node cat /tmp/rehearsal/carol.addr | tr -d '\r\n')"
}

wait_for_tip() {
  log "Waiting for cardano-node tip..."
  for _ in $(seq 1 60); do
    if cardano_cli query tip --testnet-magic "$NETWORK_MAGIC" --socket-path "$NODE_SOCKET" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  die "cardano-node did not become ready"
}

smoke_checks() {
  log "Running smoke checks..."

  wait_for_tip

  curl -sf "$API_ALICE/head" >/dev/null || die "Hydra API (alice) not responding at $API_ALICE/head"
  curl -sf "$API_BOB/head"   >/dev/null || die "Hydra API (bob) not responding at $API_BOB/head"
  curl -sf "$API_CAROL/head" >/dev/null || die "Hydra API (carol) not responding at $API_CAROL/head"

  if curl -sf "http://localhost:1442/health" >/dev/null 2>&1; then
    log "Kupo: healthy"
  else
    log "Kupo: /health not responding (continuing; endpoint may differ depending on image/tag)"
  fi

  log "Smoke checks passed."
}

pick_utxo_for_address() {
  # args: label address out_prefix
  local label="$1"
  local addr="$2"
  local prefix="$3"

  cardano_cli query utxo \
    --address "$addr" \
    --testnet-magic "$NETWORK_MAGIC" \
    --socket-path "$NODE_SOCKET" \
    --output-json >"$TMP_HOST/${prefix}-utxo.json"

  if [ "$(py_json_len "$TMP_HOST/${prefix}-utxo.json")" = "0" ]; then
    die "$label: no UTxOs found at $addr"
  fi

  py_pick_utxo "$TMP_HOST/${prefix}-utxo.json"
}

lock_script_utxo() {
  log "Creating an always-true script UTxO on L1 (10 ADA locked with inline datum 42)..."

  # Build script address
  cardano_cli address build \
    --payment-script-file /tmp/rehearsal/always-true.plutus \
    --testnet-magic "$NETWORK_MAGIC" \
    --out-file /tmp/rehearsal/always-true.addr
  SCRIPT_ADDR="$(compose exec -T cardano-node cat /tmp/rehearsal/always-true.addr | tr -d '\r\n')"

  # Pick funding UTxO from Alice
  read -r ALICE_FUND_TXIN ALICE_FUND_LOVELACE < <(pick_utxo_for_address "alice" "$ALICE_ADDR" "alice-fund") || die "failed to pick alice funding UTxO"

  # Build + sign + submit tx that pays 10 ADA to script address with inline datum
  compose exec -T cardano-node sh -lc "cardano-cli conway transaction build \
    --tx-in '$ALICE_FUND_TXIN' \
    --tx-out '$SCRIPT_ADDR+10000000' \
    --tx-out-inline-datum-file /tmp/rehearsal/datum.json \
    --change-address '$ALICE_ADDR' \
    --testnet-magic '$NETWORK_MAGIC' \
    --socket-path '$NODE_SOCKET' \
    --out-file /tmp/rehearsal/lock.txbody"

  compose exec -T cardano-node sh -lc "cardano-cli conway transaction sign \
    --tx-body-file /tmp/rehearsal/lock.txbody \
    --signing-key-file /tmp/credentials/alice-funds.sk \
    --out-file /tmp/rehearsal/lock.signed.json"

  compose exec -T cardano-node sh -lc "cardano-cli conway transaction submit \
    --tx-file /tmp/rehearsal/lock.signed.json \
    --testnet-magic '$NETWORK_MAGIC' \
    --socket-path '$NODE_SOCKET'"

  # Wait until the script UTxO shows up
  for _ in $(seq 1 60); do
    cardano_cli query utxo \
      --address "$SCRIPT_ADDR" \
      --testnet-magic "$NETWORK_MAGIC" \
      --socket-path "$NODE_SOCKET" \
      --output-json >"$TMP_HOST/script-utxo.json" || true

    if [ "$(py_json_len "$TMP_HOST/script-utxo.json")" != "0" ]; then
      read -r SCRIPT_TXIN SCRIPT_LOVELACE < <(py_pick_utxo "$TMP_HOST/script-utxo.json") || true
      if [ -n "${SCRIPT_TXIN:-}" ]; then
        log "Script UTxO: $SCRIPT_TXIN (lovelace=$SCRIPT_LOVELACE)"
        return 0
      fi
    fi
    sleep 1
  done

  die "script UTxO did not appear at $SCRIPT_ADDR"
}

pick_alice_collateral_utxo() {
  # Pick a fresh ADA-only UTxO at Alice to use as collateral (and commit it).
  read -r ALICE_COLL_TXIN ALICE_COLL_LOVELACE < <(pick_utxo_for_address "alice" "$ALICE_ADDR" "alice-coll") || die "failed to pick alice collateral UTxO"
  log "Alice collateral UTxO: $ALICE_COLL_TXIN (lovelace=$ALICE_COLL_LOVELACE)"
}

hydra_send() {
  local msg="$1"
  python3 "$WS_PY" send --url "$WS_ALICE_SEND" --message "$msg" >/dev/null
}

hydra_wait() {
  local tags="$1"
  local timeout="${2:-60}"
  python3 "$WS_PY" wait --url "$WS_ALICE_HISTORY" --wait-tags "$tags" --timeout "$timeout" >/dev/null
}

commit_via_api() {
  # args: party (alice|bob|carol) api_base_url txin lovelace kind(script|basic)
  local party="$1"
  local api="$2"
  local txin="$3"
  local lovelace="$4"
  local kind="$5"
local pay_addr=""
case "$party" in
  alice) pay_addr="$ALICE_ADDR" ;;
  bob) pay_addr="$BOB_ADDR" ;;
  carol) pay_addr="$CAROL_ADDR" ;;
  *) die "unknown party: $party" ;;
esac


  local blueprint_cont="/tmp/rehearsal/${party}-${kind}-blueprint.json"
  local blueprint_host="$TMP_HOST/${party}-${kind}-blueprint.json"
  local utxo_host="$TMP_HOST/${party}-${kind}-utxo.json"
  local req_host="$TMP_HOST/${party}-${kind}-commit-request.json"
  local commit_tx_host="$TMP_HOST/${party}-${kind}-commit-tx.json"

  log "Commit (${party}/${kind}) via $api/commit ..."

  # Build blueprint tx inside container
  if [ "$kind" = "script" ]; then
    compose exec -T cardano-node sh -lc "cardano-cli conway transaction build-raw \
      --tx-in '$txin' \
      --tx-in-script-file /tmp/rehearsal/always-true.plutus \
      --tx-in-inline-datum-present \
      --tx-in-redeemer-value 42 \
      --tx-in-execution-units '(1000000, 100000)' \
      --tx-out '$ALICE_ADDR+10000000' \
      --fee 0 \
      --out-file '$blueprint_cont'"
  else
    compose exec -T cardano-node sh -lc "cardano-cli conway transaction build-raw \
      --tx-in '$txin' \
      --tx-out '$pay_addr+$lovelace' \
      --fee 0 \
      --out-file '$blueprint_cont'"
  fi

  # Copy blueprint out to host
  compose exec -T cardano-node cat "$blueprint_cont" >"$blueprint_host"

  # UTxO context for txin (on L1)
  cardano_cli query utxo \
    --tx-in "$txin" \
    --testnet-magic "$NETWORK_MAGIC" \
    --socket-path "$NODE_SOCKET" \
    --output-json >"$utxo_host"

  py_make_commit_request "$utxo_host" "$blueprint_host" "$req_host"

  # POST /commit and capture tx body
  curl -sf -X POST \
    -H "Content-Type: application/json" \
    --data @"$req_host" \
    "$api/commit" >"$commit_tx_host" || die "commit request failed for $party ($kind)"

  # Copy commit tx body into container, sign, submit
  local cid
  cid="$(compose ps -q cardano-node)"
  docker cp "$commit_tx_host" "${cid}:/tmp/rehearsal/${party}-${kind}-commit-tx.json" >/dev/null

  compose exec -T cardano-node sh -lc "cardano-cli conway transaction sign \
    --tx-body-file /tmp/rehearsal/${party}-${kind}-commit-tx.json \
    --signing-key-file /tmp/credentials/${party}-funds.sk \
    --signing-key-file /tmp/credentials/${party}.sk \
    --out-file /tmp/rehearsal/${party}-${kind}-commit-signed.json"

  compose exec -T cardano-node sh -lc "cardano-cli conway transaction submit \
    --tx-file /tmp/rehearsal/${party}-${kind}-commit-signed.json \
    --testnet-magic '$NETWORK_MAGIC' \
    --socket-path '$NODE_SOCKET'"
}

wait_snapshot_txin_present() {
  local txin="$1"
  for _ in $(seq 1 60); do
    curl -sf "$API_ALICE/snapshot/utxo" >"$TMP_HOST/snapshot.json" || true
    if py_snapshot_has_txin "$TMP_HOST/snapshot.json" "$txin"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

submit_l2_spend_script() {
  log "Submitting L2 tx: spend the script UTxO inside the open Head..."

  log "Waiting until script txin is visible in snapshot..."
  wait_snapshot_txin_present "$SCRIPT_TXIN" || die "script txin not visible in snapshot; commit likely failed"

  # Build raw L2 tx (spend script txin, pay 10 ADA to Bob)
  compose exec -T cardano-node sh -lc "cardano-cli conway transaction build-raw \
    --tx-in '$SCRIPT_TXIN' \
    --tx-in-script-file /tmp/rehearsal/always-true.plutus \
    --tx-in-inline-datum-present \
    --tx-in-redeemer-value 42 \
    --tx-in-execution-units '(1000000, 100000)' \
    --tx-in-collateral '$ALICE_COLL_TXIN' \
    --tx-out '$BOB_ADDR+10000000' \
    --fee 0 \
    --out-file /tmp/rehearsal/l2.txbody"

  # Sign
  compose exec -T cardano-node sh -lc "cardano-cli conway transaction sign \
    --tx-body-file /tmp/rehearsal/l2.txbody \
    --signing-key-file /tmp/credentials/alice-funds.sk \
    --signing-key-file /tmp/credentials/alice.sk \
    --out-file /tmp/rehearsal/l2.signed.json"

  compose exec -T cardano-node cat /tmp/rehearsal/l2.signed.json >"$TMP_HOST/l2.signed.json"
  py_wrap_newtx "$TMP_HOST/l2.signed.json" "$TMP_HOST/newtx.json"

  python3 "$WS_PY" send --url "$WS_ALICE_SEND" --message-file "$TMP_HOST/newtx.json" >/dev/null

  # Verify it landed by polling snapshot UTxO until the script input is gone
  for _ in $(seq 1 60); do
    curl -sf "$API_ALICE/snapshot/utxo" >"$TMP_HOST/snapshot.json" || true
    if ! py_snapshot_has_txin "$TMP_HOST/snapshot.json" "$SCRIPT_TXIN"; then
      log "L2 tx confirmed (script txin spent in snapshot)."
      return 0
    fi
    sleep 1
  done

  die "L2 tx did not get confirmed (script txin still present in snapshot)"
}

main() {
  need docker
  need curl
  need python3
  need git

  ensure_tmp

  log "Reset stack to a known baseline..."
  "$RUN_SH" reset >/dev/null 2>&1 || true

  log "Bring devnet-in-a-box up..."
  "$RUN_SH" up >/dev/null

  [ -d "$DEMO_DIR" ] || die "missing demo dir at $DEMO_DIR"
  [ -d "$CREDENTIALS_HOST" ] || die "missing credentials dir at $CREDENTIALS_HOST"

  smoke_checks

  stage_into_cardano_node
  build_party_addresses

  lock_script_utxo
  pick_alice_collateral_utxo

  # Pick Bob + Carol commit UTxOs (after stack is up)
  read -r BOB_TXIN BOB_LOVELACE < <(pick_utxo_for_address "bob" "$BOB_ADDR" "bob") || die "failed to pick bob UTxO"
  read -r CAROL_TXIN CAROL_LOVELACE < <(pick_utxo_for_address "carol" "$CAROL_ADDR" "carol") || die "failed to pick carol UTxO"

  log "Init head (via WebSocket)..."
  hydra_send '{"tag":"Init"}'

  log "Waiting for HeadIsInitializing..."
  hydra_wait "HeadIsInitializing" 120 || die "Head did not enter initializing state"

  # Commit UTxOs (order doesn't really matter; keep it explicit)
  commit_via_api "alice" "$API_ALICE" "$SCRIPT_TXIN" "$SCRIPT_LOVELACE" "script"
  commit_via_api "alice" "$API_ALICE" "$ALICE_COLL_TXIN" "$ALICE_COLL_LOVELACE" "basic"
  commit_via_api "bob"   "$API_BOB"   "$BOB_TXIN"   "$BOB_LOVELACE"   "basic"
  commit_via_api "carol" "$API_CAROL" "$CAROL_TXIN" "$CAROL_LOVELACE" "basic"

  log "Waiting for HeadIsOpen..."
  hydra_wait "HeadIsOpen" 180 || die "Head did not open"

  submit_l2_spend_script

  log "Close head..."
  hydra_send '{"tag":"Close"}'

  log "Waiting for HeadIsClosed..."
  hydra_wait "HeadIsClosed" 180 || die "Head did not close"

  log "Waiting for ReadyToFanout (contestation period)..."
  hydra_wait "ReadyToFanout" 600 || die "Never became ready to fanout"

  log "Fanout..."
  hydra_send '{"tag":"Fanout"}'

  log "Waiting for fanout confirmation..."
  hydra_wait "HeadFannedOut,HeadIsFinalized" 600 || die "Fanout did not complete"

  printf "\n✅ GREEN — rehearsal succeeded (smoke + open/close + contract interaction)\n"
}

main "$@"
