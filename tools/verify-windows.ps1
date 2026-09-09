<#
.SYNOPSIS
  Prove — on a real Windows machine — whether a clone made by this tool actually
  runs and gets its own data directory.

.DESCRIPTION
  Clones the target app twice: once in the default mode (which rewrites
  app.asar) and once in --mode link (which only creates a shortcut). Launches
  each from its Start Menu entry, exactly the way a user would, and counts the
  files each one writes into its own %APPDATA% directory.

  Writing files is the only honest evidence: the data directory existing proves
  nothing, because the clone step creates it whether or not the app ever starts.

.PARAMETER Source
  Install folder or .exe to clone. Defaults to auto-detecting Claude Desktop.

.PARAMETER Keep
  Leave the two clones in place instead of removing them at the end.

.EXAMPLE
  .\tools\verify-windows.ps1
  .\tools\verify-windows.ps1 -Source "$env:LOCALAPPDATA\Programs\slack"

.OUTPUTS
  Exit 0 = the default mode works.  1 = only link mode works.  2 = neither.
#>
[CmdletBinding()]
param(
  [string] $Source,
  [switch] $Keep
)

$ErrorActionPreference = 'Continue'
$repo = Split-Path $PSScriptRoot -Parent
$settle = 50   # seconds to let Electron start and write its profile

function Section($t) { Write-Host ""; Write-Host "== $t" -ForegroundColor Cyan }

# --- resolve the app to clone ------------------------------------------------
if (-not $Source) {
  $claude = Get-ChildItem "$env:LOCALAPPDATA\AnthropicClaude" -Directory -Filter 'app-*' `
              -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
  if (-not $claude) {
    Write-Host "Claude Desktop not found. Install it, or pass -Source <install folder>." -ForegroundColor Yellow
    exit 2
  }
  $Source = $claude.FullName
}
if (-not (Test-Path $Source)) { Write-Host "No such path: $Source" -ForegroundColor Red; exit 2 }
Section "Source"; Write-Host "  $Source"

$startMenu = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
$destDir   = Join-Path $env:TEMP 'dualizer-verify'
$names     = @{ inject = 'Dualizer Check Inject'; link = 'Dualizer Check Link' }

function Remove-Clone($name) {
  & node "$repo\bin\dualize.js" remove "$name" --purge *> $null
  Remove-Item (Join-Path $destDir $name) -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $startMenu "$name.lnk") -Force -ErrorAction SilentlyContinue
  Remove-Item "$env:APPDATA\$name" -Recurse -Force -ErrorAction SilentlyContinue
}

function Stop-All($name) {
  Get-Process ([IO.Path]::GetFileNameWithoutExtension($name)) -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
}

# Launch a clone the way a user does — via its Start Menu shortcut — and report
# how many files it writes into its own profile.
function Measure-Clone($name) {
  $lnk  = Join-Path $startMenu "$name.lnk"
  $data = "$env:APPDATA\$name"
  if (-not (Test-Path $lnk)) { return [pscustomobject]@{ Shortcut=$false; Flag=''; Procs=0; Files=0 } }

  $sc   = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
  $flag = if ($sc.Arguments -match '--user-data-dir') { $sc.Arguments } else { '' }

  Start-Process -FilePath $lnk -ErrorAction SilentlyContinue | Out-Null
  Start-Sleep -Seconds $settle

  $procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
             Where-Object { $_.CommandLine -like "*$name*" }).Count
  $files = @(Get-ChildItem $data -Recurse -File -ErrorAction SilentlyContinue).Count
  Stop-All $name
  Start-Sleep -Seconds 5
  [pscustomobject]@{ Shortcut=$true; Flag=$flag; Procs=$procs; Files=$files }
}

# --- control: the untouched app must run, or nothing below means anything ----
Section "Control — does the ORIGINAL run on this machine?"
$origExe = if ((Get-Item $Source).PSIsContainer) {
             (Get-ChildItem $Source -Filter *.exe | Sort-Object Length -Descending | Select-Object -First 1).FullName
           } else { $Source }
Start-Process -FilePath $origExe -ErrorAction SilentlyContinue | Out-Null
Start-Sleep -Seconds $settle
$ctrl = @(Get-Process -ErrorAction SilentlyContinue |
          Where-Object { $_.Path -eq $origExe }).Count
Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $origExe } | Stop-Process -Force
Start-Sleep -Seconds 5
Write-Host "  processes: $ctrl"
if ($ctrl -eq 0) {
  Write-Host "  The original itself did not start — this machine can't host the app." -ForegroundColor Yellow
  Write-Host "  Nothing below would be interpretable. Stopping." -ForegroundColor Yellow
  exit 2
}

# --- build both clones -------------------------------------------------------
foreach ($n in $names.Values) { Remove-Clone $n }

Section "Clone A — default mode (rewrites app.asar)"
& "$repo\clone-app.ps1" -Source $Source -Name $names.inject -DestDir $destDir | Out-Host

Section "Clone B — --mode link (shortcut only, no copy)"
& "$repo\clone-app.ps1" -Source $Source -Name $names.link -DestDir $destDir --mode link | Out-Host

# --- launch each and measure -------------------------------------------------
Section "Launching Clone A from its Start Menu entry"
$a = Measure-Clone $names.inject
Section "Launching Clone B from its Start Menu entry"
$b = Measure-Clone $names.link

# --- verdict -----------------------------------------------------------------
Section "Result"
"{0,-22} {1,9} {2,7} {3,7}" -f 'clone', 'shortcut', 'procs', 'files' | Write-Host
foreach ($r in @(@{n='default (inject)'; v=$a}, @{n='link'; v=$b})) {
  "{0,-22} {1,9} {2,7} {3,7}" -f $r.n, $r.v.Shortcut, $r.v.Procs, $r.v.Files | Write-Host
}
Write-Host ""
Write-Host "A clone is only working if it wrote files. An empty data directory"
Write-Host "means it never started — the clone step creates that folder regardless."

$code = 2
if ($a.Files -gt 0) {
  Write-Host "`nPASS — the default clone runs and keeps its own data." -ForegroundColor Green
  $code = 0
} elseif ($b.Files -gt 0) {
  Write-Host "`nFAIL — the default clone never started; --mode link works." -ForegroundColor Red
  Write-Host "Use --mode link for this app until that is fixed." -ForegroundColor Yellow
  $code = 1
} else {
  Write-Host "`nFAIL — neither clone started." -ForegroundColor Red
}

if (-not $Keep) { foreach ($n in $names.Values) { Remove-Clone $n } ; Write-Host "`ncleaned up." }
else { Write-Host "`nclones kept in $destDir" }
exit $code
