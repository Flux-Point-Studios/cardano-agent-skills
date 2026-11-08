#!/usr/bin/env bash
set -euo pipefail

# oc-safe.sh — allowlist-friendly command wrapper
#
# Purpose:
# - Provide a single, easy-to-allowlist entrypoint for OpenClaw Exec allowlist mode.
# - Avoid shell features (pipes/redirects/chaining) by NOT accepting them and by dispatching to fixed wrappers.
#
# Usage:
#   ./scripts/oc-safe.sh cardano version
#   ./scripts/oc-safe.sh cardano query tip --mainnet
#
# Notes:
# - This script refuses common shell metacharacters in arguments.
# - It dispatches only to known wrapper scripts in this repo.
#
# You should allowlist THIS script path (not bash) in exec approvals.

die() { echo "ERROR: $*" >&2; exit 2; }

if [[ $# -lt 1 ]]; then
  die "Usage: oc-safe.sh cardano [args...]"
fi

# Reject metacharacters (defense-in-depth; Exec allowlist also rejects many)
for a in "$@"; do
  case "$a" in
    *"|"*|*";"*|*"&&"*|*"||"*|*">"*|*"<"*|*'$('*|*'`'*)
      die "Refusing shell metacharacters in args: $a"
      ;;
  esac
done

verb="$1"; shift

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$verb" in
  cardano)
    exec "$ROOT/skills/cardano-cli-operator/scripts/cardano-cli.sh" "$@"
    ;;
  *)
    die "Unknown verb: $verb (use cardano)"
    ;;
esac
