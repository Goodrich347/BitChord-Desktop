# BitChord Desktop installer for Windows (PowerShell 5.1+ or 7).
# Builds the BitChord web player + extension from the pinned upstream commit,
# applies this repo's patches, installs to %LOCALAPPDATA%\BitChord and starts
# a tiny local server (Node) at login. No administrator rights needed.
# Run via install.cmd (double-click) or:
#   powershell -ExecutionPolicy Bypass -File install.ps1
$ErrorActionPreference = 'Stop'

$Upstream    = if ($env:BITCHORD_UPSTREAM) { $env:BITCHORD_UPSTREAM } else { 'https://github.com/kushagrasinghx/BitChord.git' }
$Commit      = if ($env:BITCHORD_COMMIT) { $env:BITCHORD_COMMIT } else { 'acf219a7e4a7f52f026d4336d5c7ac5cf7bfafcc' }
$PnpmVersion = '12.11.2'
$Port        = 5173
$PartyUrl    = if ($env:VITE_PARTY_SERVER_URL) { $env:VITE_PARTY_SERVER_URL } else { 'https://api.bitchord.kushagrasingh.in' }
$Here        = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppHome     = if ($env:BITCHORD_HOME) { $env:BITCHORD_HOME } else { Join-Path $env:LOCALAPPDATA 'BitChord' }
# Our own temp dir is removed whole; a user-given BITCHORD_BUILD_DIR only loses what we put in it.
$OwnBuild    = -not $env:BITCHORD_BUILD_DIR
$Build       = if ($env:BITCHORD_BUILD_DIR) { $env:BITCHORD_BUILD_DIR } else { Join-Path $env:TEMP ('bitchord-build-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
function Cleanup {
  if ($env:BITCHORD_KEEP_BUILD -or -not $Build -or -not (Test-Path $Build)) { return }
  $targets = if ($OwnBuild) { @($Build) } else { @((Join-Path $Build 'src'), (Join-Path $Build 'tools')) }
  foreach ($t in $targets) { if (Test-Path $t) { Remove-Item -Recurse -Force $t -ErrorAction SilentlyContinue } }
}

function Say($m) { Write-Host "==> $m" -ForegroundColor Magenta }
function Die($m) {
  Write-Host "Error: $m" -ForegroundColor Red
  Cleanup
  exit 1
}
function Run($exe, [string[]]$argv) {
  & $exe @argv
  if ($LASTEXITCODE -ne 0) { Die "$exe $($argv -join ' ') failed ($LASTEXITCODE)" }
}

# 1. Requirements
if (-not (Get-Command git -ErrorAction SilentlyContinue))  { Die 'git is required: winget install Git.Git' }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Die 'Node.js 22+ is required: winget install OpenJS.NodeJS.LTS' }
$nodeMajor = [int]((node -p 'process.versions.node.split(String.fromCharCode(46))[0]').Trim())
if ($nodeMajor -lt 22) { Die "Node.js 22+ is required (found $(node -v))." }
$Node = (Get-Command node).Source

# 2. Source (LF line endings so the patch applies)
Say "Fetching BitChord ($Commit) into $Build"
New-Item -ItemType Directory -Force -Path $Build | Out-Null
$Src = Join-Path $Build 'src'
if (Test-Path $Src) { Remove-Item -Recurse -Force $Src }
Run git @('init', '-q', $Src)
Run git @('-C', $Src, 'config', 'core.autocrlf', 'false')
Run git @('-C', $Src, 'config', 'core.longpaths', 'true')
Run git @('-C', $Src, 'remote', 'add', 'origin', $Upstream)
Run git @('-C', $Src, 'fetch', '-q', '--depth', '1', '--filter=blob:limit=5m', 'origin', $Commit)
Run git @('-C', $Src, 'sparse-checkout', 'set', 'web')
Run git @('-C', $Src, 'checkout', '-q', 'FETCH_HEAD')

# 3. Patches
Get-ChildItem (Join-Path $Here 'patches') -Filter *.patch | Sort-Object Name | ForEach-Object {
  Say "Applying $($_.Name)"
  & git -C $Src apply --whitespace=nowarn $_.FullName
  if ($LASTEXITCODE -ne 0) { Die "Patch $($_.Name) does not apply to $Commit." }
}

# 4. Build
$Web = Join-Path $Src 'web'
Say 'Installing dependencies (~560 MB, build-time only)'
# npx's pnpm shim is broken on Windows (pnpm 12 ships a native binary), so
# install pnpm into the build folder and run its JS entry with Node directly.
$Tools = Join-Path $Build 'tools'
Run npm @('install', '--prefix', $Tools, '--no-save', '--no-audit', '--no-fund', '--loglevel=error', "pnpm@$PnpmVersion")
$PnpmJs = Join-Path $Tools 'node_modules\pnpm\bin\pnpm.mjs'
Run $Node @($PnpmJs, '--dir', $Web, 'install', '--frozen-lockfile')

Say 'Building the extension'
$env:BITCHORD_SITE_ORIGINS = "http://localhost:$Port,https://bitchord.in,https://bitchord-8bw.pages.dev"
Push-Location (Join-Path $Web 'extension')
try { Run (Join-Path $PWD 'node_modules\.bin\wxt.cmd') @('build') } finally { Pop-Location }

Say 'Building the site'
$AppDir = Join-Path $Web 'app'
Set-Content -Path (Join-Path $AppDir '.env.local') -Value "VITE_PARTY_SERVER_URL=$PartyUrl" -Encoding ascii
Push-Location $AppDir
try {
  Run (Join-Path $PWD 'node_modules\.bin\tsc.cmd') @('-p', '.')
  Run (Join-Path $PWD 'node_modules\.bin\vite.cmd') @('build')
} finally { Pop-Location }

# 5. Install (outputs only, ~50 MB). Stop a running server first so files aren't locked.
Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" |
  Where-Object { $_.CommandLine -like '*BitChord*server.mjs*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Say "Installing to $AppHome"
New-Item -ItemType Directory -Force -Path $AppHome | Out-Null
foreach ($d in 'site', 'extension') { $p = Join-Path $AppHome $d; if (Test-Path $p) { Remove-Item -Recurse -Force $p } }
Copy-Item -Recurse (Join-Path $AppDir 'dist') (Join-Path $AppHome 'site')
Copy-Item -Recurse (Join-Path $Web 'extension\.output\chrome-mv3') (Join-Path $AppHome 'extension')
Copy-Item (Join-Path $Here 'scripts\server.mjs') (Join-Path $AppHome 'server.mjs') -Force
Cleanup

# 6. Autostart: a hidden launcher in the user's Startup folder (no admin needed)
$Server = Join-Path $AppHome 'server.mjs'
$Vbs = Join-Path $AppHome 'start-server.vbs'
Set-Content -Path $Vbs -Encoding ascii -Value @(
  'Set sh = CreateObject("WScript.Shell")',
  ('sh.Run """' + $Node + '"" ""' + $Server + '""", 0, False')
)
if ($env:BITCHORD_NO_SERVICE) {
  Say "Skipping autostart (BITCHORD_NO_SERVICE). Run: node `"$Server`""
} else {
  $Startup = [Environment]::GetFolderPath('Startup')
  Copy-Item $Vbs (Join-Path $Startup 'BitChord Server.vbs') -Force
  Start-Process -FilePath 'wscript.exe' -ArgumentList "`"$Vbs`""
}

Write-Host ''
Write-Host "BitChord is installed.  Site: http://localhost:$Port" -ForegroundColor Green
Write-Host ''
Write-Host 'One-time browser setup (Chrome / Edge / Brave):'
Write-Host '  1. Open chrome://extensions (edge://extensions) and turn on Developer mode'
Write-Host "  2. Load unpacked -> $(Join-Path $AppHome 'extension')"
Write-Host "  3. Open http://localhost:$Port, then menu -> Cast, save and share -> Install page as app"
Write-Host 'After updating, press Reload on the extension card.'
