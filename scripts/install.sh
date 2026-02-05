#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-Flux-Point-Studios/cardano-agent-skills}"
SCOPE="project" # project|global
YES=0

usage() {
  cat <<'EOF'
Usage: scripts/install.sh [--project|--global] [--yes]

Installs Flux Point Studios' Cardano Agent Skills for BOTH:
  - Claude Code (agent: claude-code)  -> .claude/skills/ or ~/.claude/skills
  - OpenClaw   (agent: openclaw)      -> ./skills/ or ~/.moltbot/skills (as installed by the skills CLI)

Notes:
  - OpenClaw loads workspace skills from <workspace>/skills and managed skills from ~/.openclaw/skills.
  - The skills CLI currently installs OpenClaw globally to ~/.moltbot/skills; this script bridges that by symlinking
    ~/.openclaw/skills -> ~/.moltbot/skills when possible, or prints the extraDirs fallback.

Examples:
  ./scripts/install.sh --project --yes
  ./scripts/install.sh --global --yes

Env overrides:
  REPO=owner/repo  (default Flux-Point-Studios/cardano-agent-skills)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) SCOPE="project"; shift ;;
    --global)  SCOPE="global"; shift ;;
    -y|--yes)  YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need node
need npm
need npx

NPM_YES=()
CLI_YES=()
if [[ "$YES" -eq 1 ]]; then
  NPM_YES=(-y)
  CLI_YES=(-y)
fi

SCOPE_FLAG=()
if [[ "$SCOPE" == "global" ]]; then
  SCOPE_FLAG=(-g)
fi

echo "== Installing Cardano Agent Skills =="
echo "Repo:   $REPO"
echo "Scope:  $SCOPE"
echo "Agents: claude-code + openclaw"
echo

npx "${NPM_YES[@]}" skills add "$REPO" --skill '*' -a claude-code -a openclaw "${SCOPE_FLAG[@]}" "${CLI_YES[@]}"

echo
echo "== Post-install sanity =="

if [[ "$SCOPE" == "project" ]]; then
  [[ -d ".claude/skills" ]] && echo "OK Claude Code skills present: .claude/skills/" || echo "WARN Claude Code skills not found at .claude/skills"
  [[ -d "skills" ]] && echo "OK OpenClaw workspace skills present: ./skills/" || echo "WARN OpenClaw workspace skills not found at ./skills"
fi

if [[ "$SCOPE" == "global" ]]; then
  MOLTBOT_SKILLS="${HOME}/.moltbot/skills"
  OPENCLAW_SKILLS="${HOME}/.openclaw/skills"

  [[ -d "${HOME}/.claude/skills" ]] && echo "OK Claude Code global skills present: ~/.claude/skills/" || echo "WARN Claude Code global skills not found at ~/.claude/skills"
  [[ -d "$MOLTBOT_SKILLS" ]] && echo "OK OpenClaw (skills CLI) global skills present: ~/.moltbot/skills/" || echo "WARN OpenClaw (skills CLI) global skills not found at ~/.moltbot/skills"

  if [[ ! -e "$OPENCLAW_SKILLS" && -d "$MOLTBOT_SKILLS" ]]; then
    mkdir -p "$(dirname "$OPENCLAW_SKILLS")"
    ln -s "$MOLTBOT_SKILLS" "$OPENCLAW_SKILLS" 2>/dev/null || true
    if [[ -L "$OPENCLAW_SKILLS" ]]; then
      echo "OK Linked ~/.openclaw/skills -> ~/.moltbot/skills (compat)"
    else
      echo "WARN Could not symlink ~/.openclaw/skills. Alternative:"
      echo "    Add skills.load.extraDirs: [\"$MOLTBOT_SKILLS\"] in ~/.openclaw/openclaw.json"
    fi
  fi
fi

echo
echo "Done."
