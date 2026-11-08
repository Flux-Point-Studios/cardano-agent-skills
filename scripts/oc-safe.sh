#!/usr/bin/env bash
set -euo pipefail

# oc-safe.sh — allowlist-friendly command wrapper
#
# Purpose:
# - Provide a single, easy-to-allowlist entrypoint for OpenClaw Exec allowlist mode.
# - Avoid shell features (pipes/redirects/chaining) by NOT accepting them and by dispatching to fixed wrappers.
# - Pass through read-only cardano-cli commands only. Anything that signs, submits,
#   generates keys or writes files goes through the manual operator skills instead.
#
# Usage:
#   ./scripts/oc-safe.sh cardano version
#   ./scripts/oc-safe.sh cardano query tip --mainnet
#   ./scripts/oc-safe.sh cardano conway transaction view --tx-file tx.signed
#
# Allowed cardano-cli commands (an optional era prefix such as `conway` or `latest` is accepted):
#   version, --version, query <any>, address info, transaction view, transaction txid
# Refused everywhere: --out-file and --output-file.
#
# You should allowlist THIS script path (not bash) in exec approvals.

die() { echo "ERROR: $*" >&2; exit 2; }

if [[ $# -lt 1 ]]; then
  die "Usage: oc-safe.sh cardano <read-only cardano-cli command>"
fi

# Reject metacharacters (defense-in-depth; Exec allowlist also rejects many)
for a in "$@"; do
  case "$a" in
    *"|"*|*";"*|*"&&"*|*"||"*|*">"*|*"<"*|*'$('*|*'`'*)
      die "Refusing shell metacharacters in args: $a"
      ;;
    --out-file|--out-file=*|--output-file|--output-file=*)
      die "Refusing file output: $a"
      ;;
  esac
done

verb="$1"; shift

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cardano_read_only() {
  local -a cmd=("$@")
  case "${cmd[0]:-}" in
    conway|latest|babbage|alonzo|mary|allegra|shelley) cmd=("${cmd[@]:1}") ;;
  esac
  case "${cmd[0]:-} ${cmd[1]:-}" in
    "version "*|"--version "*) return 0 ;;
    "query "?*) return 0 ;;
    "address info"|"transaction view"|"transaction txid") return 0 ;;
  esac
  return 1
}

case "$verb" in
  cardano)
    cardano_read_only "$@" || die "Refusing cardano-cli command (read-only allowlist): ${*:-<none>}"
    exec "$ROOT/skills/cardano-cli-operator/scripts/cardano-cli.sh" "$@"
    ;;
  *)
    die "Unknown verb: $verb (use cardano)"
    ;;
esac
