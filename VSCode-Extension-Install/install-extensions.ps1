<#
.SYNOPSIS
  Installs the team's standard VS Code extensions from extensions.txt.

.DESCRIPTION
  Reads extensions.txt (one publisher.name[@version] per line, # comments allowed)
  and installs each via the `code` CLI. Skips extensions already installed at the
  desired version.

.PARAMETER File
  Path to the extensions list. Default: extensions.txt next to this script.

.PARAMETER CodeCmd
  Name of the VS Code CLI to use. Default: 'code'. Try 'code-insiders' or 'cursor'.

.PARAMETER DryRun
  Show what would be done without making changes.

.EXAMPLE
  .\install-extensions.ps1
  .\install-extensions.ps1 -DryRun
  .\install-extensions.ps1 -CodeCmd cursor
#>

[CmdletBinding()]
param(
  [string]$File    = (Join-Path $PSScriptRoot 'extensions.txt'),
  [string]$CodeCmd = 'code',
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Resolve-CodeCli {
  param([string]$Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  # Common Windows install locations for VS Code
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
  Write-Host "  Install VS Code from https://code.visualstudio.com/ and ensure"
  Write-Host "  'Add to PATH' was selected, or pass -CodeCmd 'C:\path\to\code.cmd'."
  exit 1
}

if (-not (Test-Path $File)) {
  Write-Host "ERROR: extensions file not found: $File" -ForegroundColor Red
  exit 1
}

# Parse extensions file: strip comments, trim, drop blanks
$wanted = Get-Content -LiteralPath $File |
  ForEach-Object { ($_ -replace '#.*$', '').Trim() } |
  Where-Object   { $_ -ne '' }

if (-not $wanted) {
  Write-Host "No extensions listed in $File"
  exit 0
}

# Snapshot installed extensions: hashtable of id_lower -> version
$installedMap = @{}
$listing = & $codeExe --list-extensions --show-versions 2>$null
foreach ($line in $listing) {
  if ($line -match '^([^@]+)@(.+)$') {
    $installedMap[$matches[1].ToLower()] = $matches[2]
  }
}

$ok = 0; $skip = 0; $fail = 0
foreach ($entry in $wanted) {
  if ($entry -match '^(.+)@(.+)$') {
    $id     = $matches[1]
    $ver    = $matches[2]
    $target = "$id@$ver"
  } else {
    $id     = $entry
    $ver    = $null
    $target = $id
  }

  $key = $id.ToLower()
  if ($installedMap.ContainsKey($key)) {
    $cur = $installedMap[$key]
    if (-not $ver -or $cur -eq $ver) {
      if ($ver) {
        Write-Host "✓ $id@$ver (already installed)"
      } else {
        Write-Host "✓ $id (already installed: $cur)"
      }
      $skip++
      continue
    }
  }

  if ($DryRun) {
    Write-Host "→ Would install $target"
    $ok++
    continue
  }

  Write-Host "→ Installing $target"
  & $codeExe --install-extension $target --force | Out-Null
  if ($LASTEXITCODE -eq 0) {
    $ok++
  } else {
    Write-Host "✗ Failed to install $target" -ForegroundColor Red
    $fail++
  }
}

Write-Host ""
Write-Host "Summary: $ok installed, $skip already present, $fail failed"
if ($fail -gt 0) { exit 1 }
