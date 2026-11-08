#!/usr/bin/env bash
set -euo pipefail

# Final-boss OpenClaw approvals applier.
#
# Features:
# - OS-aware suggested allowlist patterns (brew + standard locations)
# - --dry-run to preview actions
# - optional broad path globs (dangerous) behind --broad-paths

usage() {
  cat <<'EOF'
Usage: scripts/apply-approvals.sh [--local|--gateway|--node <id|name|ip>] [--agent <name>] [--yes] [--dry-run] [--broad-paths]

Targets:
  --local      (default) edit local approvals file on this host
  --gateway    edit approvals on the gateway host (requires gateway caps)
  --node ...   edit approvals on a specific node host

Options:
  --agent <name>      approvals agent scope (default: main)
  --yes               skip interactive prompt
  --dry-run           print the OpenClaw CLI commands that would be executed, then exit 0
  --broad-paths       ALSO add broad directory globs as allowlist patterns (DANGEROUS!)

Examples:
  ./scripts/apply-approvals.sh --local --dry-run
  ./scripts/apply-approvals.sh --gateway --yes
  ./scripts/apply-approvals.sh --node mac-1 --yes
  ./scripts/apply-approvals.sh --local --yes --broad-paths

Notes:
  - Requires OpenClaw CLI: `openclaw approvals set|allowlist add`
  - Allowlist patterns are case-insensitive glob matches and should resolve to binary paths.
    Basename-only entries are ignored.
EOF
}

TARGET_ARGS=()
NODE=""
AGENT="main"
YES=0
DRY=0
BROAD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local) TARGET_ARGS=(); shift ;;
    --gateway) TARGET_ARGS=(--gateway); shift ;;
    --node) NODE="${2:-}"; [[ -z "$NODE" ]] && { echo "Missing node id/name/ip" >&2; exit 2; }; TARGET_ARGS=(--node "$NODE"); shift 2 ;;
    --agent) AGENT="${2:-main}"; shift 2 ;;
    -y|--yes) YES=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --broad-paths) BROAD=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need openclaw

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT/openclaw/exec-approvals.template.json"
OCSAFE="$ROOT/scripts/oc-safe.sh"

[[ -f "$TEMPLATE" ]] || { echo "ERROR: Missing template: $TEMPLATE" >&2; exit 1; }
[[ -f "$OCSAFE" ]] || { echo "ERROR: Missing oc-safe wrapper: $OCSAFE" >&2; exit 1; }

os_name="$(uname -s | tr '[:upper:]' '[:lower:]' || true)"

echo "== OpenClaw approvals apply (final boss) =="
echo "Target: ${TARGET_ARGS[*]:-(local)}"
echo "Agent:  $AGENT"
echo "Repo:   $ROOT"
echo "OS:     $os_name"
echo "Dry:    $DRY"
echo "Broad:  $BROAD"
echo

if [[ "$DRY" -eq 1 ]]; then
  YES=1
fi

if [[ "$YES" -ne 1 ]]; then
  echo "This will overwrite approvals using:"
  echo "  $TEMPLATE"
  echo "and then add allowlist entries for:"
  echo "  $OCSAFE"
  echo
  echo "Optional (dangerous): --broad-paths adds globs like /opt/homebrew/bin/* and /usr/bin/*."
  echo
  read -r -p "Proceed? [y/N] " ans
  case "${ans:-}" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

run() {
  if [[ "$DRY" -eq 1 ]]; then
    printf '+ %q ' "$@"; echo
    return 0
  fi
  "$@"
}

# 1) Replace approvals from file
run openclaw approvals set "${TARGET_ARGS[@]}" --file "$TEMPLATE"

# 2) Allowlist repo-specific oc-safe (exact path)
run openclaw approvals allowlist add "${TARGET_ARGS[@]}" --agent "$AGENT" "$OCSAFE"

# 3) Add resolved binary paths for common deps (if present)
maybe_add_bin() {
  local bin="$1"
  local path=""
  path="$(command -v "$bin" 2>/dev/null || true)"
  if [[ -n "$path" ]]; then
    run openclaw approvals allowlist add "${TARGET_ARGS[@]}" --agent "$AGENT" "$path" >/dev/null 2>&1 || true
    echo "OK allowlisted: $path"
  fi
}

echo
echo "== Adding common binaries (resolved paths, if found) =="
for b in docker docker-compose colima curl git python3 node npm npx; do
  maybe_add_bin "$b" || true
done

# 4) OS-aware common location patterns (safe-ish: targeted, not "everything")
# These patterns help when PATH differs between interactive shell and daemon.
echo
echo "== Adding OS-aware path patterns (safe-ish) =="
# Always add the repo pattern too (portable across machines)
run openclaw approvals allowlist add "${TARGET_ARGS[@]}" --agent "$AGENT" "~/Projects/**/cardano-agent-skills/scripts/oc-safe.sh" >/dev/null 2>&1 || true
echo "OK allowlisted: ~/Projects/**/cardano-agent-skills/scripts/oc-safe.sh"

if [[ "$os_name" == "darwin" ]]; then
  # Homebrew Intel + Apple Silicon common locations (for specific bins)
  for p in \
    "/opt/homebrew/bin/docker" \
    "/opt/homebrew/bin/docker-compose" \
    "/opt/homebrew/bin/colima" \
    "/opt/homebrew/bin/curl" \
    "/opt/homebrew/bin/git" \
    "/usr/local/bin/docker" \
    "/usr/local/bin/docker-compose" \
    "/usr/local/bin/colima" \
    "/usr/bin/curl" \
    "/usr/bin/git" \
    "/usr/bin/python3" \
  ; do
    run openclaw approvals allowlist add "${TARGET_ARGS[@]}" --agent "$AGENT" "$p" >/dev/null 2>&1 || true
    echo "OK allowlisted: $p"
  done
else
  # Linux common locations (for specific bins)
  for p in \
    "/usr/bin/docker" \
    "/usr/bin/docker-compose" \
    "/usr/bin/curl" \
    "/usr/bin/git" \
    "/usr/bin/python3" \
    "/usr/local/bin/docker" \
    "/usr/local/bin/docker-compose" \
    "/usr/local/bin/curl" \
    "/usr/local/bin/git" \
  ; do
    run openclaw approvals allowlist add "${TARGET_ARGS[@]}" --agent "$AGENT" "$p" >/dev/null 2>&1 || true
    echo "OK allowlisted: $p"
  done
fi

# 5) OPTIONAL broad patterns (requested) — dangerous: effectively "allow many binaries"
if [[ "$BROAD" -eq 1 ]]; then
  echo
  echo "== Adding BROAD directory globs (DANGEROUS) =="
  if [[ "$os_name" == "darwin" ]]; then
    for pat in "/opt/homebrew/bin/*" "/usr/local/bin/*" "/usr/bin/*"; do
      run openclaw approvals allowlist add "${TARGET_ARGS[@]}" --agent "$AGENT" "$pat" >/dev/null 2>&1 || true
      echo "WARNING allowlisted: $pat"
    done
  else
    for pat in "/usr/local/bin/*" "/usr/bin/*"; do
      run openclaw approvals allowlist add "${TARGET_ARGS[@]}" --agent "$AGENT" "$pat" >/dev/null 2>&1 || true
      echo "WARNING allowlisted: $pat"
    done
  fi
  echo "WARNING Broad globs reduce safety. Prefer allowlisting oc-safe + specific binaries."
fi

echo
echo "Done. Recommended session defaults inside OpenClaw:"
echo "  /exec host=gateway security=allowlist ask=on-miss"
