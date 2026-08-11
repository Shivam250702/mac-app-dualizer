#Requires -Version 5.1
<#
.SYNOPSIS
  Clone a Windows app so you can run a second, fully independent instance —
  its own data directory, its own login.

.DESCRIPTION
  The Windows counterpart to clone-app.sh. Best support is for Electron apps
  (Slack, Claude, Notion, VS Code, Discord, ...).

  Two modes:
    clone  Copy the app, give it its own name and icon, and inject an isolated
           data directory into app.asar. An app auto-update overwrites the copy,
           so re-run `dualize repair` afterwards.
    link   Create only a shortcut that launches the original app with a separate
           --user-data-dir. Nothing is copied and nothing can be reverted by an
           update, but both instances share one taskbar icon.

  The real work lives in Node (src/win/clone.js); this script is a thin wrapper
  so the command line matches the macOS script.

.PARAMETER Source
  Path to the app's .exe, or the folder containing it. Required.

.PARAMETER Name
  Display name for the clone, e.g. "Slack Work". Required.

.PARAMETER DestDir
  Where to write the clone. Default: %LOCALAPPDATA%\Programs

.PARAMETER Mode
  'clone' (default) or 'link'.

.PARAMETER NoIsolate
  Do not inject a separate data directory into app.asar.

.PARAMETER Desktop
  Also create a Desktop shortcut.

.PARAMETER Tint
  Icon badge color as "#RRGGBB". Default: picked from the clone name.

.PARAMETER NoTint
  Do not badge the clone's icon.

.EXAMPLE
  .\clone-app.ps1 -Source "$env:LOCALAPPDATA\Programs\Slack\slack.exe" -Name "Slack Work"

.EXAMPLE
  .\clone-app.ps1 --source "C:\Program Files\Claude\Claude.exe" --name "Claude 2" --desktop

.NOTES
  Requires Node.js 18+. Run `npm install` in the repo first.
#>
# PowerShell matches parameter names case-insensitively, so `-source` already
# binds to $Source — declaring it as an alias too is an error. Only genuinely
# different spellings are aliased here; the GNU-style `--flag` forms are folded
# in from $Rest below.
[CmdletBinding()]
param(
  [string]$Source,
  [string]$Name,
  [Alias('dest-dir')][string]$DestDir,
  [ValidateSet('clone', 'link')][string]$Mode = 'clone',
  [Alias('no-isolate')][switch]$NoIsolate,
  [switch]$Desktop,
  [string]$Tint,
  [Alias('no-tint')][switch]$NoTint,
  # Anything not matched above, so GNU-style `--source X` also works.
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# PowerShell splits `--source` into an unbound argument rather than a parameter,
# so fold any GNU-style flags from $Rest back into the typed parameters above.
if ($Rest) {
  for ($i = 0; $i -lt $Rest.Count; $i++) {
    $token = $Rest[$i]
    $value = if ($i + 1 -lt $Rest.Count) { $Rest[$i + 1] } else { $null }
    switch -Regex ($token) {
      '^--source$'     { $Source = $value; $i++ }
      '^--name$'       { $Name = $value; $i++ }
      '^--dest-dir$'   { $DestDir = $value; $i++ }
      '^--mode$'       { $Mode = $value; $i++ }
      '^--tint$'       { $Tint = $value; $i++ }
      '^--no-isolate$' { $NoIsolate = $true }
      '^--desktop$'    { $Desktop = $true }
      '^--no-tint$'    { $NoTint = $true }
      '^-h$|^--help$'  { Get-Help $MyInvocation.MyCommand.Path -Detailed; exit 0 }
      default {
        Write-Error "Unknown argument: $token"
        exit 1
      }
    }
  }
}

if (-not $Source -or -not $Name) {
  Write-Error 'error: -Source and -Name are required. Run with -? for help.'
  exit 1
}

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
  Write-Error 'error: Node.js 18+ is required but was not found on PATH. See https://nodejs.org'
  exit 1
}

$dualize = Join-Path $root 'bin\dualize.js'
if (-not (Test-Path $dualize)) {
  Write-Error "error: bin\dualize.js is missing at $dualize"
  exit 1
}

$argList = @('clone', '--source', $Source, '--name', $Name, '--mode', $Mode)
if ($DestDir)   { $argList += @('--dest-dir', $DestDir) }
if ($Tint)      { $argList += @('--tint', $Tint) }
if ($NoTint)    { $argList += '--no-tint' }
if ($NoIsolate) { $argList += '--no-isolate' }
if ($Desktop)   { $argList += '--desktop' }

& node $dualize @argList
exit $LASTEXITCODE
