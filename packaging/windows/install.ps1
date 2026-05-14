param(
  [switch]$AllUsers,
  [switch]$NoDesktopShortcut
)

$ErrorActionPreference = "Stop"

$appName = "POS-INV-MSSQL"
$exeName = "pos_inv_mssql.exe"
$sourceDir = Join-Path $PSScriptRoot "app"

if (-not (Test-Path (Join-Path $sourceDir $exeName))) {
  throw "Application files were not found. Expected: $sourceDir\$exeName"
}

if ($AllUsers) {
  $installDir = Join-Path ${env:ProgramFiles} $appName
  $startMenuDir = Join-Path ${env:ProgramData} "Microsoft\Windows\Start Menu\Programs\$appName"
} else {
  $installDir = Join-Path $env:LOCALAPPDATA "Programs\$appName"
  $startMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$appName"
}

New-Item -ItemType Directory -Force -Path $installDir | Out-Null
Copy-Item -Path (Join-Path $sourceDir "*") -Destination $installDir -Recurse -Force

$shell = New-Object -ComObject WScript.Shell
$targetExe = Join-Path $installDir $exeName

New-Item -ItemType Directory -Force -Path $startMenuDir | Out-Null
$startShortcut = $shell.CreateShortcut((Join-Path $startMenuDir "$appName.lnk"))
$startShortcut.TargetPath = $targetExe
$startShortcut.WorkingDirectory = $installDir
$startShortcut.Save()

$uninstallShortcut = $shell.CreateShortcut((Join-Path $startMenuDir "Uninstall $appName.lnk"))
$uninstallShortcut.TargetPath = "powershell.exe"
$uninstallShortcut.Arguments = "-ExecutionPolicy Bypass -File `"$installDir\uninstall.ps1`""
$uninstallShortcut.WorkingDirectory = $installDir
$uninstallShortcut.Save()

if (-not $NoDesktopShortcut) {
  $desktopDir = if ($AllUsers) { [Environment]::GetFolderPath("CommonDesktopDirectory") } else { [Environment]::GetFolderPath("DesktopDirectory") }
  $desktopShortcut = $shell.CreateShortcut((Join-Path $desktopDir "$appName.lnk"))
  $desktopShortcut.TargetPath = $targetExe
  $desktopShortcut.WorkingDirectory = $installDir
  $desktopShortcut.Save()
}

$uninstallScript = @"
`$ErrorActionPreference = "Stop"
`$appName = "$appName"
`$installDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$startMenuCandidates = @(
  Join-Path `$env:APPDATA "Microsoft\Windows\Start Menu\Programs\`$appName",
  Join-Path `$env:ProgramData "Microsoft\Windows\Start Menu\Programs\`$appName"
)
foreach (`$path in `$startMenuCandidates) {
  if (Test-Path `$path) { Remove-Item -LiteralPath `$path -Recurse -Force }
}
`$desktopCandidates = @(
  Join-Path ([Environment]::GetFolderPath("DesktopDirectory")) "`$appName.lnk",
  Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) "`$appName.lnk"
)
foreach (`$path in `$desktopCandidates) {
  if (Test-Path `$path) { Remove-Item -LiteralPath `$path -Force }
}
Start-Sleep -Milliseconds 300
Remove-Item -LiteralPath `$installDir -Recurse -Force
"@

Set-Content -Path (Join-Path $installDir "uninstall.ps1") -Value $uninstallScript -Encoding UTF8

Write-Host "$appName installed to $installDir"
Write-Host "Start Menu shortcut created in $startMenuDir"
