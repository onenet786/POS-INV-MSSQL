USE PosInvMssql;
GO

INSERT INTO dbo.Tenants (Name, DefaultCurrency)
VALUES ('InvPro Demo Company', 'PKR');

DECLARE @TenantId INT = SCOPE_IDENTITY();

INSERT INTO dbo.BranchTypes (TenantId, Name, Code)
VALUES (@TenantId, 'Retail', 'RETAIL'), (@TenantId, 'Restaurant', 'RESTAURANT'), (@TenantId, 'Hotel', 'HOTEL');

DECLARE @RetailBranchTypeId INT = (SELECT TOP 1 BranchTypeId FROM dbo.BranchTypes WHERE TenantId = @TenantId AND Code = 'RETAIL');

INSERT INTO dbo.Branches (TenantId, BranchTypeId, Name, Code, Address)
VALUES (@TenantId, @RetailBranchTypeId, 'Main Branch', 'MAIN', 'Head office and retail counter');

DECLARE @BranchId INT = SCOPE_IDENTITY();

INSERT INTO dbo.Warehouses (TenantId, BranchId, Name, Code)
VALUES (@TenantId, @BranchId, 'Main Warehouse', 'WH-MAIN');

DECLARE @WarehouseId INT = SCOPE_IDENTITY();

INSERT INTO dbo.AppSettings (TenantId, SettingKey, SettingValue)
VALUES (@TenantId, 'receiptPrinterName', '');

INSERT INTO dbo.Roles (TenantId, Name, Permissions)
VALUES
(@TenantId, 'Admin', '["*"]'),
(@TenantId, 'Manager', '["dashboard.read","products.*","inventory.*","sales.*","purchase.*","reports.read"]'),
(@TenantId, 'Cashier', '["dashboard.read","products.read","sales.*","customers.read"]'),
(@TenantId, 'Warehouse Staff', '["products.read","inventory.*","reports.stock"]'),
(@TenantId, 'Accountant', '["finance.*","reports.*","payments.*"]');

INSERT INTO dbo.Units (TenantId, Name, Symbol)
VALUES (@TenantId, 'Pieces', 'PCS'), (@TenantId, 'Kilogram', 'KG'), (@TenantId, 'Box', 'BOX'), (@TenantId, 'Liter', 'L');

INSERT INTO dbo.Categories (TenantId, Name)
VALUES (@TenantId, 'Electronics'), (@TenantId, 'Pharmacy'), (@TenantId, 'Grocery');

INSERT INTO dbo.Brands (TenantId, Name)
VALUES (@TenantId, 'Samsung'), (@TenantId, 'Medica'), (@TenantId, 'FreshCo');

DECLARE @UnitId INT = (SELECT TOP 1 UnitId FROM dbo.Units WHERE TenantId = @TenantId AND Symbol = 'PCS');
DECLARE @CategoryId INT = (SELECT TOP 1 CategoryId FROM dbo.Categories WHERE TenantId = @TenantId AND Name = 'Electronics');
DECLARE @BrandId INT = (SELECT TOP 1 BrandId FROM dbo.Brands WHERE TenantId = @TenantId AND Name = 'Samsung');

INSERT INTO dbo.Products (TenantId, CategoryId, BrandId, UnitId, Name, SKU, Barcode, QRPayload, SalePrice, PurchasePrice, TaxRate, MinStockLevel, PosPriority)
VALUES
(@TenantId, @CategoryId, @BrandId, @UnitId, 'Samsung USB-C Charger 25W', 'SKU-000001', '100000000001', '{"sku":"SKU-000001","name":"Samsung USB-C Charger 25W"}', 2800, 1900, 18, 10, 1),
(@TenantId, @CategoryId, @BrandId, @UnitId, 'Bluetooth Headset Pro', 'SKU-000002', '100000000002', '{"sku":"SKU-000002","name":"Bluetooth Headset Pro"}', 5500, 3600, 18, 5, 2);

EXEC dbo.sp_RecordStockMovement @TenantId, @BranchId, @WarehouseId, 1, NULL, 'Opening', 100, 'Seed', 1, NULL, 'Opening balance';
EXEC dbo.sp_RecordStockMovement @TenantId, @BranchId, @WarehouseId, 2, NULL, 'Opening', 32, 'Seed', 1, NULL, 'Opening balance';

INSERT INTO dbo.Customers (TenantId, Name, Phone, Email, CreditLimit, LoyaltyPoints)
VALUES (@TenantId, 'Walk-in Customer', NULL, NULL, 0, 0), (@TenantId, 'Metro Wholesale Buyer', '+92-300-0000000', 'buyer@example.com', 250000, 120);

INSERT INTO dbo.Suppliers (TenantId, Name, Phone, Email, TaxNumber)
VALUES (@TenantId, 'Global Electronics Supply', '+92-321-0000000', 'supply@example.com', 'NTN-123456');

INSERT INTO dbo.Users (TenantId, BranchId, BranchTypeId, RoleId, FullName, Email, PasswordHash)
SELECT @TenantId, @BranchId, @RetailBranchTypeId, RoleId, 'System Admin', 'admin@invpro.local', '$2b$12$Y7h33FUBvSVV70oz3g7B8.lJ5VZ0KDNppkB5c49RjIHLoY5NVxx6G' FROM dbo.Roles WHERE TenantId = @TenantId AND Name = 'Admin'
UNION ALL
SELECT @TenantId, @BranchId, @RetailBranchTypeId, RoleId, 'Store Manager', 'manager@invpro.local', '$2b$12$qrcMqeBI3Z68plafu58ikeZ/e1WPsVxIYrbVZ4Sz38OezvYkEBoa2' FROM dbo.Roles WHERE TenantId = @TenantId AND Name = 'Manager'
UNION ALL
SELECT @TenantId, @BranchId, @RetailBranchTypeId, RoleId, 'Counter Cashier', 'cashier@invpro.local', '$2b$12$le.EwabQYkz0u.C.GrhelOxRas8GgnAfhvkyE6vmz1nupchtKhs5O' FROM dbo.Roles WHERE TenantId = @TenantId AND Name = 'Cashier';
