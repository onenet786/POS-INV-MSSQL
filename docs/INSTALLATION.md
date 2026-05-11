# Installation Guide

## Requirements

- Flutter 3.30+
- Node.js 22+
- Microsoft SQL Server 2019+
- SQL Server command line tools or SSMS

## Database

Run `database/schema.sql`, then `database/seed.sql`.

The schema uses:

- Identity primary keys
- Foreign keys for tenant, branch, warehouse, stock, invoice, and payment integrity
- Audit log table for secure event tracking
- Stored procedures for dashboard, stock movement, and invoice posting
- Indexes for barcode, SKU, branch, warehouse, invoice number, and report filtering

## Backend

Create `backend/.env` from `backend/.env.example`.

```bash
cd backend
npm install
npm run dev
```

Swagger is available at `http://localhost:4100/docs`.

## Flutter

```bash
flutter create --platforms=windows,android,ios .
flutter pub get
flutter run -d windows
```

