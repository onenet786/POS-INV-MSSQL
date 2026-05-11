# POS-INV-MSSQL

Enterprise inventory, POS, invoicing, barcode/QR, reporting, and multi-branch management system built for Flutter clients and Microsoft SQL Server.

## Stack

- Frontend: Flutter for Windows, Android, iOS, and responsive layouts
- Backend: Node.js + Express + TypeScript
- Database: Microsoft SQL Server using `mssql` / `Microsoft.Data` style stored procedures and parameterized queries
- Auth: JWT, bcrypt password hashing, role permissions
- Docs: Swagger/OpenAPI
- Realtime-ready: Socket.IO event hooks
- Deployment: Docker Compose for API + SQL Server

## Quick Start

1. Create the database:
   ```sql
   sqlcmd -S localhost -U sa -P "YourStrong!Passw0rd" -i database/schema.sql
   sqlcmd -S localhost -U sa -P "YourStrong!Passw0rd" -i database/seed.sql
   ```

2. Configure backend:
   ```bash
   cd backend
   copy .env.example .env
   npm install
   npm run dev
   ```

3. Run Flutter:
   ```bash
   flutter pub get
   flutter run -d windows
   ```

> Note: Flutter generator was unavailable in this environment during scaffolding, so `lib/` and `pubspec.yaml` are provided. Run `flutter create --platforms=windows,android,ios .` once Flutter tooling is responsive to regenerate platform folders without overwriting app logic.

## Test Accounts

- Admin: `admin@invpro.local` / `Admin@12345`
- Manager: `manager@invpro.local` / `Manager@12345`
- Cashier: `cashier@invpro.local` / `Cashier@12345`

## Included Modules

- Dashboard analytics and alerts
- Products, categories, brands, units, variants, batches, serials
- Barcode and QR code generation endpoints
- Warehouses, branches, stock in/out, transfers, adjustments
- Purchases, suppliers, GRN, returns, payments
- POS, invoices, split/partial payments, returns, thermal/A4 templates
- Customers, ledgers, loyalty points
- Finance, expenses, journal entries, P&L foundations
- Reports with CSV-ready endpoints
- Users, roles, permissions, audit logs
- English/Urdu localization-ready Flutter UI with RTL support

