param(
  [string]$Configuration = "Release",
  [string]$ApiBaseUrl = "",
  [switch]$SkipFlutterBuild,
  [switch]$SkipBackendBuild,
  [switch]$BundleNodeModules,
  [switch]$SkipExeInstaller
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$distRoot = Join-Path $repoRoot "dist\windows-installer"
$packageRoot = Join-Path $distRoot "package"
$appName = "POS-INV-MSSQL"
$zipPath = Join-Path $distRoot "$appName-Windows.zip"
$exePath = Join-Path $distRoot "$appName-Setup.exe"
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

if (-not $SkipExeInstaller) {
  $bootstrapRoot = Join-Path $distRoot "setup-bootstrap"
  if (Test-Path $bootstrapRoot) {
    Remove-Item -LiteralPath $bootstrapRoot -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $bootstrapRoot | Out-Null

  $payloadZip = Join-Path $bootstrapRoot "payload.zip"
  Copy-Item -Path $zipPath -Destination $payloadZip -Force

  if (Test-Path $exePath) {
    Remove-Item -LiteralPath $exePath -Force
  }

  $bootstrapSource = Join-Path $bootstrapRoot "SetupBootstrap.cs"
  $bootstrapCode = @'
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;

internal static class SetupBootstrap
{
    [STAThread]
    private static int Main()
    {
        try
        {
            string tempRoot = Path.Combine(Path.GetTempPath(), "POS-INV-MSSQL-Setup-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(tempRoot);

            using (Stream payload = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
            {
                if (payload == null)
                {
                    throw new InvalidOperationException("The setup payload is missing.");
                }

                string zipPath = Path.Combine(tempRoot, "payload.zip");
                using (FileStream output = File.Create(zipPath))
                {
                    payload.CopyTo(output);
                }

                ZipFile.ExtractToDirectory(zipPath, tempRoot);
            }

            string installer = Path.Combine(tempRoot, "install.ps1");
            if (!File.Exists(installer))
            {
                throw new FileNotFoundException("install.ps1 was not found in the setup payload.", installer);
            }

            ProcessStartInfo startInfo = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + installer + "\"",
                UseShellExecute = true,
                WorkingDirectory = tempRoot
            };

            using (Process process = Process.Start(startInfo))
            {
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "POS-INV-MSSQL Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
'@
  Set-Content -Path $bootstrapSource -Value $bootstrapCode -Encoding UTF8

  $cscCandidates = @(
    "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe",
    "C:\Program Files\Microsoft Visual Studio\18\Enterprise\MSBuild\Current\Bin\Roslyn\csc.exe"
  )
  $csc = $cscCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $csc) {
    $cscCommand = Get-Command csc.exe -ErrorAction SilentlyContinue
    if ($cscCommand) {
      $csc = $cscCommand.Source
    }
  }
  if (-not $csc) {
    throw "csc.exe was not found. Cannot compile the Windows setup executable on this machine."
  }

  $frameworkDir = Split-Path -Parent $csc
  $compressionDll = Join-Path $frameworkDir "System.IO.Compression.dll"
  $compressionFsDll = Join-Path $frameworkDir "System.IO.Compression.FileSystem.dll"

  $cscArgs = @(
    "/nologo",
    "/target:winexe",
    "/optimize+",
    "/out:$exePath",
    "/resource:$payloadZip,payload.zip",
    "/reference:System.Windows.Forms.dll",
    "/reference:$compressionDll",
    "/reference:$compressionFsDll",
    $bootstrapSource
  )
  & $csc @cscArgs

  if (-not (Test-Path $exePath)) {
    throw "The setup compiler did not create the expected installer executable at $exePath"
  }

  Write-Host "Windows setup executable created:"
  Write-Host $exePath
}
