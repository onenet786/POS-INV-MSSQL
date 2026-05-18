param(
  [switch]$AllUsers,
  [switch]$NoDesktopShortcut,
  [switch]$InstallDatabase,
  [switch]$SkipBackendTask,
  [string]$SqlServer = "localhost",
  [int]$SqlPort = 1433,
  [string]$SqlDatabase = "PosInvMssql",
  [string]$SqlUser = "sa",
  [string]$SqlPassword = "YourStrong!Passw0rd",
  [string]$Port = "4100",
  [string]$JwtSecret = ""
)

$ErrorActionPreference = "Stop"

$appName = "POS-INV-MSSQL"
$exeName = "pos_inv_mssql.exe"
$sourceDir = Join-Path $PSScriptRoot "app"
$backendSourceDir = Join-Path $PSScriptRoot "backend"
$databaseSourceDir = Join-Path $PSScriptRoot "database"

if (-not (Test-Path (Join-Path $sourceDir $exeName))) {
  throw "Application files were not found. Expected: $sourceDir\$exeName"
}

if (-not (Test-Path (Join-Path $backendSourceDir "dist\server.js"))) {
  throw "Backend files were not found. Expected: $backendSourceDir\dist\server.js"
}

if (-not (Test-Path (Join-Path $databaseSourceDir "schema.sql"))) {
  throw "Database scripts were not found. Expected: $databaseSourceDir\schema.sql"
}

$nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
if (-not $nodeCommand) {
  throw "Node.js is required for the local API. Install Node.js LTS, then run this installer again."
}

if ([string]::IsNullOrWhiteSpace($JwtSecret)) {
  $bytes = New-Object byte[] 32
  [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
  $JwtSecret = [Convert]::ToBase64String($bytes)
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
Copy-Item -Path $backendSourceDir -Destination (Join-Path $installDir "backend") -Recurse -Force
Copy-Item -Path $databaseSourceDir -Destination (Join-Path $installDir "database") -Recurse -Force

$backendDir = Join-Path $installDir "backend"
$logsDir = Join-Path $installDir "logs"
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

if (-not (Test-Path (Join-Path $backendDir "node_modules"))) {
  $npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue
  if (-not $npmCommand) {
    $npmCommand = Get-Command npm.exe -ErrorAction SilentlyContinue
  }
  if (-not $npmCommand) {
    throw "npm is required to install backend runtime dependencies. Install Node.js LTS, then run this installer again."
  }
  Push-Location $backendDir
  try {
    & $npmCommand.Source install --omit=dev
  } finally {
    Pop-Location
  }
}

$apiUrl = "http://127.0.0.1:$Port"
$envFile = @"
NODE_ENV=production
PORT=$Port
HOST=127.0.0.1
PUBLIC_API_URL=$apiUrl
SQL_SERVER=$SqlServer
SQL_PORT=$SqlPort
SQL_DATABASE=$SqlDatabase
SQL_USER=$SqlUser
SQL_PASSWORD=$SqlPassword
JWT_SECRET=$JwtSecret
JWT_EXPIRES_IN=8h
CORS_ORIGIN=*
"@
Set-Content -Path (Join-Path $backendDir ".env") -Value $envFile -Encoding UTF8

$startBackendScript = @"
`$ErrorActionPreference = "Stop"
`$installDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$backendDir = Join-Path `$installDir "backend"
`$logsDir = Join-Path `$installDir "logs"
`$pidFile = Join-Path `$installDir "backend.pid"
New-Item -ItemType Directory -Force -Path `$logsDir | Out-Null
if (Test-Path `$pidFile) {
  `$existingPid = Get-Content `$pidFile -ErrorAction SilentlyContinue
  if (`$existingPid -and (Get-Process -Id `$existingPid -ErrorAction SilentlyContinue)) {
    Write-Host "Backend is already running on process `$existingPid"
    exit 0
  }
}
`$node = (Get-Command node.exe -ErrorAction Stop).Source
`$server = Join-Path `$backendDir "dist\server.js"
`$out = Join-Path `$logsDir "backend.out.log"
`$err = Join-Path `$logsDir "backend.err.log"
`$process = Start-Process -FilePath `$node -ArgumentList "`"`$server`"" -WorkingDirectory `$backendDir -WindowStyle Hidden -PassThru -RedirectStandardOutput `$out -RedirectStandardError `$err
Set-Content -Path `$pidFile -Value `$process.Id -Encoding ASCII
Write-Host "Backend started on process `$(`$process.Id)"
"@
Set-Content -Path (Join-Path $installDir "start-backend.ps1") -Value $startBackendScript -Encoding UTF8

$stopBackendScript = @"
`$ErrorActionPreference = "SilentlyContinue"
`$installDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$pidFile = Join-Path `$installDir "backend.pid"
if (Test-Path `$pidFile) {
  `$pidValue = Get-Content `$pidFile
  if (`$pidValue) {
    Stop-Process -Id `$pidValue -Force
  }
  Remove-Item -LiteralPath `$pidFile -Force
}
"@
Set-Content -Path (Join-Path $installDir "stop-backend.ps1") -Value $stopBackendScript -Encoding UTF8

$initDatabaseScript = @"
param(
  [string]`$SqlServer = "$SqlServer",
  [int]`$SqlPort = $SqlPort,
  [string]`$SqlUser = "$SqlUser",
  [string]`$SqlPassword = "$SqlPassword"
)
`$ErrorActionPreference = "Stop"
`$installDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$databaseDir = Join-Path `$installDir "database"
`$sqlcmd = Get-Command sqlcmd.exe -ErrorAction SilentlyContinue
if (-not `$sqlcmd) {
  throw "sqlcmd.exe was not found. Install Microsoft SQL Server Command Line Utilities, then run this script again."
}
`$serverName = "`$SqlServer,`$SqlPort"
& `$sqlcmd.Source -S `$serverName -U `$SqlUser -P `$SqlPassword -b -i (Join-Path `$databaseDir "schema.sql")
& `$sqlcmd.Source -S `$serverName -U `$SqlUser -P `$SqlPassword -b -i (Join-Path `$databaseDir "seed.sql")
Get-ChildItem -Path `$databaseDir -Filter "*.sql" |
  Where-Object { `$_.Name -notin @("schema.sql", "seed.sql") } |
  Sort-Object Name |
  ForEach-Object {
    & `$sqlcmd.Source -S `$serverName -U `$SqlUser -P `$SqlPassword -b -i `$_.FullName
  }
Write-Host "Database scripts completed."
"@
Set-Content -Path (Join-Path $installDir "init-database.ps1") -Value $initDatabaseScript -Encoding UTF8

if ($InstallDatabase) {
  & powershell.exe -ExecutionPolicy Bypass -File (Join-Path $installDir "init-database.ps1") -SqlServer $SqlServer -SqlPort $SqlPort -SqlUser $SqlUser -SqlPassword $SqlPassword
}

$shell = New-Object -ComObject WScript.Shell
$targetExe = Join-Path $installDir $exeName

New-Item -ItemType Directory -Force -Path $startMenuDir | Out-Null
$startShortcut = $shell.CreateShortcut((Join-Path $startMenuDir "$appName.lnk"))
$startShortcut.TargetPath = $targetExe
$startShortcut.WorkingDirectory = $installDir
$startShortcut.Save()

$backendShortcut = $shell.CreateShortcut((Join-Path $startMenuDir "Start $appName API.lnk"))
$backendShortcut.TargetPath = "powershell.exe"
$backendShortcut.Arguments = "-ExecutionPolicy Bypass -File `"$installDir\start-backend.ps1`""
$backendShortcut.WorkingDirectory = $installDir
$backendShortcut.Save()

$databaseShortcut = $shell.CreateShortcut((Join-Path $startMenuDir "Initialize $appName Database.lnk"))
$databaseShortcut.TargetPath = "powershell.exe"
$databaseShortcut.Arguments = "-ExecutionPolicy Bypass -File `"$installDir\init-database.ps1`""
$databaseShortcut.WorkingDirectory = $installDir
$databaseShortcut.Save()

$docsShortcut = $shell.CreateShortcut((Join-Path $startMenuDir "$appName API Docs.lnk"))
$docsShortcut.TargetPath = "$apiUrl/docs/"
$docsShortcut.Save()

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

$taskName = "$appName API"
if (-not $SkipBackendTask) {
  $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$installDir\start-backend.ps1`""
  $taskTrigger = New-ScheduledTaskTrigger -AtLogOn
  Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -Description "Starts the POS-INV-MSSQL local API" -Force | Out-Null
  Start-ScheduledTask -TaskName $taskName
}

$uninstallScript = @"
`$ErrorActionPreference = "Stop"
`$appName = "$appName"
`$taskName = "$taskName"
`$installDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
& powershell.exe -ExecutionPolicy Bypass -File (Join-Path `$installDir "stop-backend.ps1")
Unregister-ScheduledTask -TaskName `$taskName -Confirm:`$false -ErrorAction SilentlyContinue
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
Write-Host "Local API configured at $apiUrl"
Write-Host "Start Menu shortcut created in $startMenuDir"
if (-not $InstallDatabase) {
  Write-Host "Database scripts are installed in $installDir\database"
  Write-Host "Run the Start Menu database shortcut or rerun install.ps1 with -InstallDatabase to initialize SQL Server."
}
