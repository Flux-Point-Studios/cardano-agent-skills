#!/usr/bin/env bash
set -euo pipefail

CMD="${1:-up}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR_DIR="$ROOT_DIR/.vendor"
HYDRA_DIR="$VENDOR_DIR/hydra"
DEMO_DIR="$HYDRA_DIR/demo"

COMPOSE_BIN="docker compose"
if ! docker compose version >/dev/null 2>&1; then
  # docker-compose legacy fallback
  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_BIN="docker-compose"
  else
    echo "ERROR: docker compose (v2) or docker-compose (v1) is required." >&2
    exit 1
  fi
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing required command: $1" >&2
    exit 1
  }
}

ensure_hydra_repo() {
  require_cmd git
  mkdir -p "$VENDOR_DIR"
  if [ ! -d "$HYDRA_DIR/.git" ]; then
    echo "[devnet] Cloning Hydra repo into: $HYDRA_DIR"
    git clone --depth 1 https://github.com/cardano-scaling/hydra.git "$HYDRA_DIR"
  fi

  if [ ! -d "$DEMO_DIR" ]; then
    echo "ERROR: expected Hydra demo dir at $DEMO_DIR" >&2
    exit 1
  fi
}

ensure_override() {
  local src="$ROOT_DIR/docker-compose.override.yml"
  local dst="$DEMO_DIR/docker-compose.override.yml"
  if [ ! -f "$src" ]; then
    echo "ERROR: missing override file: $src" >&2
    exit 1
  fi
  cp "$src" "$dst"
}

cd_demo() {
  cd "$DEMO_DIR"
}

print_endpoints() {
  cat <<'TXT'

✅ Devnet-in-a-Box is up.

Endpoints:
- Ogmios (WS):        ws://localhost:1337
- Kupo (HTTP):        http://localhost:1442
- Hydra API (Alice):  http://localhost:4001
- Hydra API (Bob):    http://localhost:4002
- Hydra API (Carol):  http://localhost:4003

Handy commands (run from this devnet-in-a-box folder):
- Start:   ./run.sh up
- TUI:     ./run.sh tui 1   # or 2 / 3
- Logs:    ./run.sh logs cardano-node
- Stop:    ./run.sh down
- Reset:   ./run.sh reset

TXT
}

wait_for_node() {
  # Wait until cardano-cli can query the tip.
  # We intentionally run cardano-cli inside the container so the host doesn't need it.
  echo "[devnet] Waiting for cardano-node to answer queries..."
  for i in {1..60}; do
    if $COMPOSE_BIN exec -T cardano-node cardano-cli query tip --testnet-magic 42 --socket-path /devnet/node.socket >/dev/null 2>&1; then
      echo "[devnet] cardano-node is responding."
      return 0
    fi
    sleep 1
  done
  echo "ERROR: cardano-node did not become ready in time." >&2
  echo "Try: ./run.sh logs cardano-node" >&2
  return 1
}

chmod_socket() {
  # Hydra docs sometimes recommend chmod on the node.socket when using volumes.
  # We do this from inside the container as root to avoid requiring sudo on the host.
  $COMPOSE_BIN exec -T -u root cardano-node sh -lc 'chmod a+w /devnet/node.socket || true' >/dev/null 2>&1 || true
}

case "$CMD" in
  up)
    require_cmd docker
    ensure_hydra_repo
    ensure_override
    cd_demo

    echo "[devnet] Pulling images (Hydra demo + Ogmios + Kupo)..."
    $COMPOSE_BIN pull

    echo "[devnet] Preparing devnet config (genesis start time, keys, etc.)..."
    ./prepare-devnet.sh

    echo "[devnet] Starting cardano-node..."
    $COMPOSE_BIN up -d cardano-node

    chmod_socket
    wait_for_node

    echo "[devnet] Seeding devnet (publish Hydra scripts + fund parties)..."
    ./seed-devnet.sh

    echo "[devnet] Starting Hydra nodes + Ogmios + Kupo..."
    $COMPOSE_BIN up -d hydra-node-1 hydra-node-2 hydra-node-3 ogmios kupo

    print_endpoints
    ;;

  tui)
    require_cmd docker
    ensure_hydra_repo
    ensure_override
    cd_demo

    WHICH="${2:-1}"
    case "$WHICH" in
      1|2|3) ;;
      *) echo "usage: ./run.sh tui [1|2|3]" >&2; exit 1;;
    esac

    # Run TUI container interactively.
    $COMPOSE_BIN run --rm "hydra-tui-$WHICH"
    ;;

  monitor)
    require_cmd docker
    ensure_hydra_repo
    ensure_override
    cd_demo
    $COMPOSE_BIN up -d prometheus grafana
    echo "Grafana: http://localhost:3000 (admin/admin)"
    ;;

  logs)
    require_cmd docker
    ensure_hydra_repo
    ensure_override
    cd_demo
    shift || true
    $COMPOSE_BIN logs -f "$@"
    ;;

  down)
    require_cmd docker
    ensure_hydra_repo
    ensure_override
    cd_demo
    $COMPOSE_BIN down --remove-orphans
    ;;

  reset)
    require_cmd docker
    ensure_hydra_repo
    ensure_override
    cd_demo
    $COMPOSE_BIN down -v --remove-orphans
    rm -rf "$DEMO_DIR/devnet" || true
    echo "[devnet] Reset complete (containers stopped, volumes removed, devnet folder deleted)."
    ;;

  update)
    require_cmd git
    ensure_hydra_repo
    echo "[devnet] Updating Hydra repo..."
    git -C "$HYDRA_DIR" pull --ff-only
    echo "[devnet] Done."
    ;;

smoke)
  "$ROOT_DIR/scripts/smoke.sh"
  ;;

rehearsal)
  "$ROOT_DIR/scripts/rehearsal.sh"
  ;;

  *)
    cat <<'USAGE'
Usage:
  ./run.sh up        # clone hydra demo, prepare devnet, seed, start services
  ./run.sh tui 1     # run hydra-tui for node 1 (or 2 / 3)
  ./run.sh monitor   # start prometheus + grafana (optional)
  ./run.sh logs ...  # follow logs
  ./run.sh down      # stop everything
  ./run.sh reset     # nuke volumes + devnet folder
  ./run.sh smoke     # quick health check (node + hydra APIs)
  ./run.sh rehearsal # deterministic end-to-end rehearsal (green/red)
  ./run.sh update    # git pull hydra upstream
USAGE
    exit 1
    ;;
esac
