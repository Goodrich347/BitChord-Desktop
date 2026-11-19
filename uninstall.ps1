# Removes BitChord Desktop on Windows: stops the server, removes autostart and files.
$ErrorActionPreference = 'Continue'
$AppHome = if ($env:BITCHORD_HOME) { $env:BITCHORD_HOME } else { Join-Path $env:LOCALAPPDATA 'BitChord' }
Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" |
  Where-Object { $_.CommandLine -like '*BitChord*server.mjs*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Remove-Item -Force (Join-Path ([Environment]::GetFolderPath('Startup')) 'BitChord Server.vbs') -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force $AppHome -ErrorAction SilentlyContinue
Write-Host 'Removed. Also remove the BitChord extension from chrome://extensions.'
