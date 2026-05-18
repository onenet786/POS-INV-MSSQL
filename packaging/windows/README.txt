POS-INV-MSSQL Windows Installer Package

Install:
1. Install Node.js LTS if it is not already installed.
2. Double-click POS-INV-MSSQL-Setup.exe.

The setup executable installs the app, backend files, database scripts, shortcuts, and local API startup task.

Manual ZIP install is also available. Extract POS-INV-MSSQL-Windows.zip, then run:

powershell -ExecutionPolicy Bypass -File .\install.ps1

The default install location is:
%LOCALAPPDATA%\Programs\POS-INV-MSSQL

For all users, run PowerShell as Administrator and use:

powershell -ExecutionPolicy Bypass -File .\install.ps1 -AllUsers

What is included:
- Flutter Windows desktop app
- Node.js API build and dependency lock file
- SQL Server database scripts from the database folder
- Start Menu shortcuts for the app, API, API docs, database initialization, and uninstall
- Scheduled task to start the local API when the user logs in

During installation, if backend node_modules is not bundled, install.ps1 runs npm install --omit=dev inside the installed backend folder.

Database:
The installer copies all SQL scripts into the installation folder. To initialize SQL Server during installation, run:

powershell -ExecutionPolicy Bypass -File .\install.ps1 -InstallDatabase -SqlServer localhost -SqlPort 1433 -SqlUser sa -SqlPassword "YourStrong!Passw0rd"

You can also initialize later from the Start Menu shortcut named "Initialize POS-INV-MSSQL Database".

Backend:
The local API runs on http://127.0.0.1:4100 by default. Logs are written to the installation folder under logs.

Uninstall:
Use the "Uninstall POS-INV-MSSQL" shortcut in the Start Menu.

Build this package from the repository root with:

powershell -ExecutionPolicy Bypass -File .\packaging\windows\build-package.ps1

The build creates:
- dist\windows-installer\POS-INV-MSSQL-Setup.exe
- dist\windows-installer\POS-INV-MSSQL-Windows.zip

To compile the Flutter app with a specific API URL:

powershell -ExecutionPolicy Bypass -File .\packaging\windows\build-package.ps1 -ApiBaseUrl "http://127.0.0.1:4100/api"

To create a larger offline-style package that includes backend node_modules:

powershell -ExecutionPolicy Bypass -File .\packaging\windows\build-package.ps1 -BundleNodeModules
