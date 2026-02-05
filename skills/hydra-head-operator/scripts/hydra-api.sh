#!/usr/bin/env bash
set -euo pipefail

PORT="${1:-}"
ACTION="${2:-head}"

if [[ -z "$PORT" ]]; then
  echo "Usage: hydra-api.sh <port> [head|health|metrics]" >&2
  exit 2
fi

BASE="http://127.0.0.1:${PORT}"

case "$ACTION" in
  head)    curl -fsS "$BASE/head" ;;
  health)  curl -fsS "$BASE/health" ;;
  metrics) curl -fsS "$BASE/metrics" ;;
  *) echo "Unknown action: $ACTION (use head|health|metrics)" >&2; exit 2 ;;
esac
echo
