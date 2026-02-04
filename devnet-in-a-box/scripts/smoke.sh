\
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HYDRA_DIR="$ROOT_DIR/.vendor/hydra"
DEMO_DIR="$HYDRA_DIR/demo"

NETWORK_MAGIC="42"
NODE_SOCKET="/devnet/node.socket"

API_ALICE="http://localhost:4001"
API_BOB="http://localhost:4002"
API_CAROL="http://localhost:4003"

log() { printf "[smoke] %s\n" "$*"; }
die() { printf "\n❌ RED — %s\n" "$*" >&2; exit 1; }

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

log "Checking cardano-node tip..."
cardano_cli query tip --testnet-magic "$NETWORK_MAGIC" --socket-path "$NODE_SOCKET" >/dev/null || die "cardano-node not ready"

log "Checking Hydra node APIs..."
curl -sf "$API_ALICE/head" >/dev/null || die "alice hydra api not responding"
curl -sf "$API_BOB/head"   >/dev/null || die "bob hydra api not responding"
curl -sf "$API_CAROL/head" >/dev/null || die "carol hydra api not responding"

if curl -sf "http://localhost:1442/health" >/dev/null 2>&1; then
  log "Kupo: healthy"
else
  log "Kupo: /health not responding (continuing)"
fi

printf "\n✅ GREEN — smoke checks passed\n"
