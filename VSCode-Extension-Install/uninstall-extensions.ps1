<#
.SYNOPSIS
  Uninstalls VS Code extensions listed in extensions.txt, or all installed
  extensions when -All is passed (full reset).

.PARAMETER File
  Path to the extensions list. Default: extensions.txt next to this script.

.PARAMETER CodeCmd
  Name of the VS Code CLI to use. Default: 'code'.

.PARAMETER All
  Uninstall ALL installed extensions (full reset). Prompts for confirmation.

.PARAMETER DryRun
  Show what would be done without making changes.

.EXAMPLE
  .\uninstall-extensions.ps1
  .\uninstall-extensions.ps1 -All
  .\uninstall-extensions.ps1 -DryRun
#>

[CmdletBinding()]
param(
  [string]$File    = (Join-Path $PSScriptRoot 'extensions.txt'),
  [string]$CodeCmd = 'code',
  [switch]$All,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Resolve-CodeCli {
  param([string]$Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'),
    (Join-Path ${env:ProgramFiles} 'Microsoft VS Code\bin\code.cmd'),
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft VS Code\bin\code.cmd')
  )
  foreach ($c in $candidates) {
    if ($c -and (Test-Path $c)) { return $c }
  }
  return $null
}

$codeExe = Resolve-CodeCli -Name $CodeCmd
if (-not $codeExe) {
  Write-Host "ERROR: '$CodeCmd' CLI not found." -ForegroundColor Red
  exit 1
}

# Snapshot installed extensions (no versions needed for uninstall)
$installed = @(& $codeExe --list-extensions 2>$null | Where-Object { $_ -ne '' })
$installedSet = @{}
foreach ($i in $installed) { $installedSet[$i.ToLower()] = $true }

# Build target list
$targets = @()
if ($All) {
  $targets = $installed
  if (-not $targets) {
    Write-Host "No extensions installed; nothing to do."
    exit 0
  }
  Write-Host "About to uninstall ALL $($targets.Count) installed extensions."
  if (-not $DryRun) {
    $ans = Read-Host "Are you sure? [y/N]"
    if ($ans -notmatch '^(y|Y|yes|YES)$') {
      Write-Host "Aborted."
      exit 0
    }
  }
} else {
  if (-not (Test-Path $File)) {
    Write-Host "ERROR: extensions file not found: $File" -ForegroundColor Red
    exit 1
  }
  $targets = Get-Content -LiteralPath $File |
    ForEach-Object { ($_ -replace '#.*$', '').Trim() } |
    Where-Object   { $_ -ne '' } |
    ForEach-Object { ($_ -split '@')[0] }
}

$ok = 0; $skip = 0; $fail = 0
foreach ($id in $targets) {
  if (-not $id) { continue }

  if (-not $installedSet.ContainsKey($id.ToLower())) {
    Write-Host "○ $id (not installed, skipping)"
    $skip++
    continue
  }

  if ($DryRun) {
    Write-Host "→ Would uninstall $id"
    $ok++
    continue
  }

  Write-Host "→ Uninstalling $id"
  & $codeExe --uninstall-extension $id | Out-Null
  if ($LASTEXITCODE -eq 0) {
    $ok++
  } else {
    Write-Host "✗ Failed to uninstall $id" -ForegroundColor Red
    $fail++
  }
}

Write-Host ""
Write-Host "Summary: $ok uninstalled, $skip not present, $fail failed"
if ($fail -gt 0) { exit 1 }
