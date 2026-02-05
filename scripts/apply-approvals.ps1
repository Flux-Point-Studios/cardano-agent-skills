Param(
  [ValidateSet("local","gateway","node")]
  [string]$Target = "local",
  [string]$Node = "",
  [string]$Agent = "main",
  [switch]$Yes,
  [switch]$DryRun,
  [switch]$BroadPaths
)

$ErrorActionPreference = "Stop"

function Need($cmd) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    throw "Missing dependency: $cmd"
  }
}

Need openclaw

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Template = Join-Path $Root "openclaw/exec-approvals.template.json"
$OcSafe = Join-Path $Root "scripts/oc-safe.sh"

if (-not (Test-Path $Template)) { throw "Missing template: $Template" }
if (-not (Test-Path $OcSafe)) { throw "Missing oc-safe: $OcSafe" }

$TargetArgs = @()
if ($Target -eq "gateway") { $TargetArgs = @("--gateway") }
elseif ($Target -eq "node") {
  if ([string]::IsNullOrWhiteSpace($Node)) { throw "Target=node requires -Node <id|name|ip>" }
  $TargetArgs = @("--node", $Node)
}

$os = $PSVersionTable.OS
if (-not $os) { $os = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription }
$isMac = $os -match "Darwin|macOS|Mac"
$isLinux = $os -match "Linux"

Write-Host "== OpenClaw approvals apply (final boss) =="
Write-Host "Target: $Target"
Write-Host "Agent:  $Agent"
Write-Host "Repo:   $Root"
Write-Host "Dry:    $DryRun"
Write-Host "Broad:  $BroadPaths"
Write-Host ""

function RunCmd([string[]]$args) {
  if ($DryRun) {
    Write-Host ("+ openclaw " + ($args -join " "))
    return
  }
  & openclaw @args
}

if (-not $Yes -and -not $DryRun) {
  Write-Host "This will overwrite approvals using:"
  Write-Host "  $Template"
  Write-Host "and then add allowlist entries for:"
  Write-Host "  $OcSafe"
  Write-Host ""
  Write-Host "Optional (dangerous): -BroadPaths adds globs like /opt/homebrew/bin/* and /usr/bin/*."
  $ans = Read-Host "Proceed? [y/N]"
  if ($ans -notin @("y","Y","yes","YES")) { Write-Host "Aborted."; exit 0 }
}

# 1) Replace approvals from file
RunCmd @(@("approvals","set") + $TargetArgs + @("--file", "$Template"))

# 2) Allowlist repo-specific oc-safe (exact path)
RunCmd @(@("approvals","allowlist","add") + $TargetArgs + @("--agent",$Agent,"$OcSafe"))

# 3) Add resolved paths for common deps
Write-Host ""
Write-Host "== Adding common binaries (resolved paths, if found) =="
function MaybeAddBin($bin) {
  $cmd = Get-Command $bin -ErrorAction SilentlyContinue
  if ($cmd) {
    RunCmd @(@("approvals","allowlist","add") + $TargetArgs + @("--agent",$Agent,$cmd.Source))
    Write-Host "OK allowlisted: $($cmd.Source)"
  }
}
"docker","docker-compose","colima","curl","git","python3","node","npm","npx" | ForEach-Object { MaybeAddBin $_ }

# 4) OS-aware path patterns (safe-ish: targeted, not "everything")
Write-Host ""
Write-Host "== Adding OS-aware path patterns (safe-ish) =="

RunCmd @(@("approvals","allowlist","add") + $TargetArgs + @("--agent",$Agent,"~/Projects/**/cardano-agent-skills/scripts/oc-safe.sh"))
Write-Host "OK allowlisted: ~/Projects/**/cardano-agent-skills/scripts/oc-safe.sh"

if ($isMac) {
  $paths = @(
    "/opt/homebrew/bin/docker",
    "/opt/homebrew/bin/docker-compose",
    "/opt/homebrew/bin/colima",
    "/opt/homebrew/bin/curl",
    "/opt/homebrew/bin/git",
    "/usr/local/bin/docker",
    "/usr/local/bin/docker-compose",
    "/usr/local/bin/colima",
    "/usr/bin/curl",
    "/usr/bin/git",
    "/usr/bin/python3"
  )
} else {
  $paths = @(
    "/usr/bin/docker",
    "/usr/bin/docker-compose",
    "/usr/bin/curl",
    "/usr/bin/git",
    "/usr/bin/python3",
    "/usr/local/bin/docker",
    "/usr/local/bin/docker-compose",
    "/usr/local/bin/curl",
    "/usr/local/bin/git"
  )
}

foreach ($p in $paths) {
  RunCmd @(@("approvals","allowlist","add") + $TargetArgs + @("--agent",$Agent,$p))
  Write-Host "OK allowlisted: $p"
}

# 5) OPTIONAL broad patterns
if ($BroadPaths) {
  Write-Host ""
  Write-Host "== Adding BROAD directory globs (DANGEROUS) =="
  if ($isMac) {
    $globs = @("/opt/homebrew/bin/*","/usr/local/bin/*","/usr/bin/*")
  } else {
    $globs = @("/usr/local/bin/*","/usr/bin/*")
  }
  foreach ($g in $globs) {
    RunCmd @(@("approvals","allowlist","add") + $TargetArgs + @("--agent",$Agent,$g))
    Write-Host "WARNING allowlisted: $g"
  }
  Write-Host "WARNING Broad globs reduce safety. Prefer allowlisting oc-safe + specific binaries."
}

Write-Host ""
Write-Host "Done. Recommended session defaults inside OpenClaw:"
Write-Host "  /exec host=gateway security=allowlist ask=on-miss"
