Param(
  [ValidateSet("project","global")]
  [string]$Scope = "project",
  [switch]$Yes,
  [string]$Repo = "Flux-Point-Studios/cardano-agent-skills"
)

$ErrorActionPreference = "Stop"

function Need($cmd) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    throw "Missing dependency: $cmd"
  }
}

Need node
Need npm
Need npx

Write-Host "== Installing Cardano Agent Skills =="
Write-Host "Repo:   $Repo"
Write-Host "Scope:  $Scope"
Write-Host "Agents: claude-code + openclaw"
Write-Host ""

$npmyes = @()
$cliyes = @()
if ($Yes) { $npmyes = @("-y"); $cliyes = @("-y") }

$scopeFlag = @()
if ($Scope -eq "global") { $scopeFlag = @("-g") }

& npx @npmyes skills add $Repo --skill '*' -a claude-code -a openclaw @scopeFlag @cliyes

Write-Host ""
Write-Host "== Post-install sanity =="

if ($Scope -eq "project") {
  if (Test-Path ".claude/skills") { Write-Host "OK Claude Code skills present: .claude/skills/" }
  else { Write-Host "WARN Claude Code skills not found at .claude/skills" }

  if (Test-Path "skills") { Write-Host "OK OpenClaw workspace skills present: ./skills/" }
  else { Write-Host "WARN OpenClaw workspace skills not found at ./skills" }
}

if ($Scope -eq "global") {
  $home = $HOME
  $moltbot = Join-Path $home ".moltbot/skills"
  $openclaw = Join-Path $home ".openclaw/skills"

  if (Test-Path (Join-Path $home ".claude/skills")) { Write-Host "OK Claude Code global skills present: ~/.claude/skills/" }
  else { Write-Host "WARN Claude Code global skills not found at ~/.claude/skills" }

  if (Test-Path $moltbot) { Write-Host "OK OpenClaw (skills CLI) global skills present: ~/.moltbot/skills/" }
  else { Write-Host "WARN OpenClaw (skills CLI) global skills not found at ~/.moltbot/skills" }

  if (-not (Test-Path $openclaw) -and (Test-Path $moltbot)) {
    New-Item -ItemType Directory -Force (Split-Path $openclaw) | Out-Null
    try {
      cmd /c "mklink /D `"$openclaw`" `"$moltbot`"" | Out-Null
      if (Test-Path $openclaw) { Write-Host "OK Linked ~/.openclaw/skills -> ~/.moltbot/skills (compat)" }
    } catch {
      Write-Host "WARN Could not create symlink ~/.openclaw/skills. Alternative:"
      Write-Host "    Add skills.load.extraDirs: [`"$moltbot`"] in ~/.openclaw/openclaw.json"
    }
  }
}

Write-Host ""
Write-Host "Done."
