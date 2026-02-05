#!/usr/bin/env bash
set -euo pipefail

IMAGE="${CARDANO_DOCKER_IMAGE:-ghcr.io/intersectmbo/cardano-node:latest}"

if command -v cardano-cli >/dev/null 2>&1; then
  exec cardano-cli "$@"
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: cardano-cli not found and docker not installed. Install cardano-cli or docker." >&2
  exit 1
fi

ARGS=(docker run --rm -i -v "$PWD":/work -w /work)

if [[ "${CARDANO_NODE_SOCKET_PATH:-}" != "" ]]; then
  SOCK_DIR="$(cd "$(dirname "$CARDANO_NODE_SOCKET_PATH")" && pwd)"
  SOCK_NAME="$(basename "$CARDANO_NODE_SOCKET_PATH")"
  ARGS+=(-v "$SOCK_DIR":/ipc -e "CARDANO_NODE_SOCKET_PATH=/ipc/$SOCK_NAME")
fi

ARGS+=("$IMAGE" cardano-cli)
exec "${ARGS[@]}" "$@"
