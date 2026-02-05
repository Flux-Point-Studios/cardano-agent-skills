#!/usr/bin/env bash
set -euo pipefail

IMAGE="${HYDRA_DOCKER_IMAGE:-ghcr.io/cardano-scaling/hydra-node}"

if command -v hydra-node >/dev/null 2>&1; then
  exec hydra-node "$@"
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: hydra-node not found and docker not installed. Install hydra-node or docker." >&2
  exit 1
fi

# Most useful for: --help, gen-hydra-key, tui quick checks.
# For full multi-node demo / head operations, prefer the hydra.family Docker Compose demo.
exec docker run --rm -i -v "$PWD":/work -w /work "$IMAGE" "$@"
