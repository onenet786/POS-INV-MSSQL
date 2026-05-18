param(
  [string]$Configuration = "Release",
  [string]$ApiBaseUrl = "",
  [switch]$SkipFlutterBuild,
  [switch]$SkipBackendBuild,
  [switch]$BundleNodeModules
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$distRoot = Join-Path $repoRoot "dist\windows-installer"
$packageRoot = Join-Path $distRoot "package"
$appName = "POS-INV-MSSQL"
$zipPath = Join-Path $distRoot "$appName-Windows.zip"
$flutterReleaseDir = Join-Path $repoRoot "build\windows\x64\runner\$Configuration"

if (-not $SkipBackendBuild) {
  Push-Location (Join-Path $repoRoot "backend")
  try {
    npm install
    npm run build
  } finally {
    Pop-Location
  }
}

if (-not $SkipFlutterBuild) {
  $flutterArgs = @("build", "windows", "--release")
  if (-not [string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    $flutterArgs += "--dart-define=API_BASE_URL=$ApiBaseUrl"
  }
  & flutter @flutterArgs
}

if (-not (Test-Path (Join-Path $flutterReleaseDir "pos_inv_mssql.exe"))) {
  throw "Flutter Windows release output was not found at $flutterReleaseDir"
}

if (-not (Test-Path (Join-Path $repoRoot "backend\dist\server.js"))) {
  throw "Backend build output was not found. Expected backend\dist\server.js"
}

if (Test-Path $packageRoot) {
  Remove-Item -LiteralPath $packageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null

$appPackage = Join-Path $packageRoot "app"
New-Item -ItemType Directory -Force -Path $appPackage | Out-Null
Copy-Item -Path (Join-Path $flutterReleaseDir "*") -Destination $appPackage -Recurse -Force

$backendPackage = Join-Path $packageRoot "backend"
New-Item -ItemType Directory -Force -Path $backendPackage | Out-Null
Copy-Item -Path (Join-Path $repoRoot "backend\dist") -Destination (Join-Path $backendPackage "dist") -Recurse -Force
Copy-Item -Path (Join-Path $repoRoot "backend\package.json") -Destination $backendPackage -Force
Copy-Item -Path (Join-Path $repoRoot "backend\package-lock.json") -Destination $backendPackage -Force
if ($BundleNodeModules -and (Test-Path (Join-Path $repoRoot "backend\node_modules"))) {
  Copy-Item -Path (Join-Path $repoRoot "backend\node_modules") -Destination (Join-Path $backendPackage "node_modules") -Recurse -Force
} else {
  Write-Host "Skipping backend node_modules. install.ps1 will run npm install --omit=dev on the target machine."
}

Copy-Item -Path (Join-Path $repoRoot "database") -Destination (Join-Path $packageRoot "database") -Recurse -Force
Copy-Item -Path (Join-Path $PSScriptRoot "install.ps1") -Destination $packageRoot -Force
Copy-Item -Path (Join-Path $PSScriptRoot "README.txt") -Destination $packageRoot -Force

if (Test-Path $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($packageRoot, $zipPath, [System.IO.Compression.CompressionLevel]::Fastest, $false)

Write-Host "Windows installer package created:"
Write-Host $zipPath
