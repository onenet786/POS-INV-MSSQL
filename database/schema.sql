IF DB_ID('PosInvMssql') IS NULL
BEGIN
    CREATE DATABASE PosInvMssql;
END
GO

USE PosInvMssql;
GO

CREATE TABLE dbo.Tenants (
    TenantId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(160) NOT NULL,
    DefaultCurrency NVARCHAR(12) NOT NULL DEFAULT 'PKR',
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE dbo.Branches (
    BranchId INT IDENTITY(1,1) PRIMARY KEY,
    TenantId INT NOT NULL,
    Name NVARCHAR(160) NOT NULL,
    Code NVARCHAR(32) NOT NULL,
    Address NVARCHAR(500) NULL,
    IsActive BIT NOT NULL DEFAULT 1,
    CONSTRAINT FK_Branches_Tenants FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId),
    CONSTRAINT UQ_Branches_Code UNIQUE (TenantId, Code)
);

CREATE TABLE dbo.Warehouses (
    WarehouseId INT IDENTITY(1,1) PRIMARY KEY,
    TenantId INT NOT NULL,
    BranchId INT NOT NULL,
    Name NVARCHAR(160) NOT NULL,
    Code NVARCHAR(32) NOT NULL,
    IsActive BIT NOT NULL DEFAULT 1,
    CONSTRAINT FK_Warehouses_Tenants FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId),
    CONSTRAINT FK_Warehouses_Branches FOREIGN KEY (BranchId) REFERENCES dbo.Branches(BranchId),
    CONSTRAINT UQ_Warehouses_Code UNIQUE (TenantId, Code)
);

CREATE TABLE dbo.Roles (
    RoleId INT IDENTITY(1,1) PRIMARY KEY,
    TenantId INT NOT NULL,
    Name NVARCHAR(80) NOT NULL,
    Permissions NVARCHAR(MAX) NOT NULL,
    CONSTRAINT FK_Roles_Tenants FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId),
    CONSTRAINT UQ_Roles_Name UNIQUE (TenantId, Name)
);

CREATE TABLE dbo.Users (
    UserId INT IDENTITY(1,1) PRIMARY KEY,
    TenantId INT NOT NULL,
    BranchId INT NULL,
    BranchTypeId INT NULL,
    RoleId INT NOT NULL,
    FullName NVARCHAR(160) NOT NULL,
    Email NVARCHAR(180) NOT NULL,
    PasswordHash NVARCHAR(255) NOT NULL,
    TwoFactorEnabled BIT NOT NULL DEFAULT 0,
    IsActive BIT NOT NULL DEFAULT 1,
    LastLoginAt DATETIME2 NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_Users_Tenants FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId),
    CONSTRAINT FK_Users_Branches FOREIGN KEY (BranchId) REFERENCES dbo.Branches(BranchId),
    CONSTRAINT FK_Users_Roles FOREIGN KEY (RoleId) REFERENCES dbo.Roles(RoleId),
    CONSTRAINT UQ_Users_Email UNIQUE (Email)
);

CREATE TABLE dbo.AppSettings (
    SettingId INT IDENTITY(1,1) PRIMARY KEY,
    TenantId INT NOT NULL,
    SettingKey NVARCHAR(120) NOT NULL,
    SettingValue NVARCHAR(1000) NOT NULL DEFAULT '',
    UpdatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_AppSettings_Tenants FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId),
    CONSTRAINT UQ_AppSettings_Key UNIQUE (TenantId, SettingKey)
);

CREATE TABLE dbo.BranchTypes (
    BranchTypeId INT IDENTITY(1,1) PRIMARY KEY,
    TenantId INT NOT NULL,
    Name NVARCHAR(80) NOT NULL,
    Code NVARCHAR(32) NOT NULL,
    IsActive BIT NOT NULL DEFAULT 1,
    CONSTRAINT FK_BranchTypes_Tenants FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId),
    CONSTRAINT UQ_BranchTypes_Code UNIQUE (TenantId, Code)
);

ALTER TABLE dbo.Branches
ADD BranchTypeId INT NULL;

ALTER TABLE dbo.Branches
ADD CONSTRAINT FK_Branches_BranchTypes FOREIGN KEY (BranchTypeId) REFERENCES dbo.BranchTypes(BranchTypeId);

ALTER TABLE dbo.Users
ADD CONSTRAINT FK_Users_BranchTypes FOREIGN KEY (BranchTypeId) REFERENCES dbo.BranchTypes(BranchTypeId);

CREATE TABLE dbo.Categories (
    CategoryId INT IDENTITY(1,1) PRIMARY KEY,
    TenantId INT NOT NULL,
    ParentCategoryId INT NULL,
    Name NVARCHAR(140) NOT NULL,
    CONSTRAINT FK_Categories_Tenants FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId),
    CONSTRAINT FK_Categories_Parent FOREIGN KEY (ParentCategoryId) REFERENCES dbo.Categories(CategoryId)
);

CREATE TABLE dbo.Brands (
    BrandId INT IDENTITY(1,1) PRIMARY KEY,
    TenantId INT NOT NULL,
    Name NVARCHAR(140) NOT NULL,
    CONSTRAINT FK_Brands_Tenants FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId)
);

CREATE TABLE dbo.Units (
    UnitId INT IDENTITY(1,1) PRIMARY KEY,
    TenantId INT NOT NULL,
    Name NVARCHAR(40) NOT NULL,
    Symbol NVARCHAR(20) NOT NULL,
    CONSTRAINT FK_Units_Tenants FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId)
);

CREATE TABLE dbo.Products (
    ProductId INT IDENTITY(1,1) PRIMARY KEY,
    TenantId INT NOT NULL,
    CategoryId INT NULL,
    BrandId INT NULL,
    UnitId INT NOT NULL,
    Name NVARCHAR(220) NOT NULL,
    SKU NVARCHAR(64) NOT NULL,
    Barcode NVARCHAR(80) NOT NULL,
    QRPayload NVARCHAR(MAX) NULL,
    Description NVARCHAR(1000) NULL,
    ImageUrl NVARCHAR(500) NULL,
    SalePrice DECIMAL(18,2) NOT NULL DEFAULT 0,
    PurchasePrice DECIMAL(18,2) NOT NULL DEFAULT 0,
    TaxRate DECIMAL(9,4) NOT NULL DEFAULT 0,
    MinStockLevel DECIMAL(18,3) NOT NULL DEFAULT 0,
    PosPriority INT NOT NULL DEFAULT 0,
    HasExpiry BIT NOT NULL DEFAULT 0,
    TrackSerial BIT NOT NULL DEFAULT 0,
    IsActive BIT NOT NULL DEFAULT 1,
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_Products_Tenants FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId),
    CONSTRAINT FK_Products_Categories FOREIGN KEY (CategoryId) REFERENCES dbo.Categories(CategoryId),
    CONSTRAINT FK_Products_Brands FOREIGN KEY (BrandId) REFERENCES dbo.Brands(BrandId),
    CONSTRAINT FK_Products_Units FOREIGN KEY (UnitId) REFERENCES dbo.Units(UnitId),
    CONSTRAINT UQ_Products_SKU UNIQUE (TenantId, SKU),
    CONSTRAINT UQ_Products_Barcode UNIQUE (TenantId, Barcode)
);

CREATE TABLE dbo.ProductVariants (
    VariantId INT IDENTITY(1,1) PRIMARY KEY,
    ProductId INT NOT NULL,
    Size NVARCHAR(60) NULL,
    Color NVARCHAR(60) NULL,
    Model NVARCHAR(80) NULL,
    SKU NVARCHAR(80) NOT NULL,
    Barcode NVARCHAR(80) NOT NULL,
    CONSTRAINT FK_ProductVariants_Products FOREIGN KEY (ProductId) REFERENCES dbo.Products(ProductId)
);

CREATE TABLE dbo.StockBatches (
    BatchId INT IDENTITY(1,1) PRIMARY KEY,
    TenantId INT NOT NULL,
    ProductId INT NOT NULL,
    BatchNo NVARCHAR(80) NOT NULL,
    LotNo NVARCHAR(80) NULL,
    ExpiryDate DATE NULL,
    CostPrice DECIMAL(18,2) NOT NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_StockBatches_Tenants FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId),
    CONSTRAINT FK_StockBatches_Products FOREIGN KEY (ProductId) REFERENCES dbo.Products(ProductId)
);

CREATE TABLE dbo.StockBalances (
    StockBalanceId BIGINT IDENTITY(1,1) PRIMARY KEY,
    TenantId INT NOT NULL,
    BranchId INT NOT NULL,
    WarehouseId INT NOT NULL,
    ProductId INT NOT NULL,
    BatchId INT NULL,
    Quantity DECIMAL(18,3) NOT NULL DEFAULT 0,
    UpdatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_StockBalances_Tenants FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId),
    CONSTRAINT FK_StockBalances_Branches FOREIGN KEY (BranchId) REFERENCES dbo.Branches(BranchId),
    CONSTRAINT FK_StockBalances_Warehouses FOREIGN KEY (WarehouseId) REFERENCES dbo.Warehouses(WarehouseId),
    CONSTRAINT FK_StockBalances_Products FOREIGN KEY (ProductId) REFERENCES dbo.Products(ProductId),
    CONSTRAINT FK_StockBalances_Batches FOREIGN KEY (BatchId) REFERENCES dbo.StockBatches(BatchId)
);

CREATE TABLE dbo.StockMovements (
    MovementId BIGINT IDENTITY(1,1) PRIMARY KEY,
    TenantId INT NOT NULL,
    BranchId INT NOT NULL,
    WarehouseId INT NOT NULL,
    ProductId INT NOT NULL,
    BatchId INT NULL,
    MovementType NVARCHAR(30) NOT NULL,
    Quantity DECIMAL(18,3) NOT NULL,
    ReferenceType NVARCHAR(40) NULL,
    ReferenceId BIGINT NULL,
    Notes NVARCHAR(500) NULL,
    CreatedBy INT NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_StockMovements_Tenants FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId)
);

CREATE TABLE dbo.Customers (
    CustomerId INT IDENTITY(1,1) PRIMARY KEY,
    TenantId INT NOT NULL,
    Name NVARCHAR(180) NOT NULL,
    Phone NVARCHAR(50) NULL,
    Email NVARCHAR(180) NULL,
    CreditLimit DECIMAL(18,2) NOT NULL DEFAULT 0,
    LoyaltyPoints INT NOT NULL DEFAULT 0,
    CONSTRAINT FK_Customers_Tenants FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId)
);

CREATE TABLE dbo.Suppliers (
    SupplierId INT IDENTITY(1,1) PRIMARY KEY,
    TenantId INT NOT NULL,
    Name NVARCHAR(180) NOT NULL,
    Phone NVARCHAR(50) NULL,
    Email NVARCHAR(180) NULL,
    TaxNumber NVARCHAR(80) NULL,
    CONSTRAINT FK_Suppliers_Tenants FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId)
);

CREATE TABLE dbo.Invoices (
    InvoiceId BIGINT IDENTITY(1,1) PRIMARY KEY,
    TenantId INT NOT NULL,
    BranchId INT NOT NULL,
    CustomerId INT NULL,
    InvoiceNo NVARCHAR(60) NOT NULL,
    InvoiceType NVARCHAR(30) NOT NULL DEFAULT 'Sale',
    Status NVARCHAR(30) NOT NULL DEFAULT 'Posted',
    Subtotal DECIMAL(18,2) NOT NULL,
    DiscountAmount DECIMAL(18,2) NOT NULL DEFAULT 0,
    TaxAmount DECIMAL(18,2) NOT NULL DEFAULT 0,
    Total DECIMAL(18,2) NOT NULL,
    PaidAmount DECIMAL(18,2) NOT NULL DEFAULT 0,
    DueAmount AS (Total - PaidAmount),
    CreatedBy INT NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_Invoices_Tenants FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId),
    CONSTRAINT FK_Invoices_Branches FOREIGN KEY (BranchId) REFERENCES dbo.Branches(BranchId),
    CONSTRAINT FK_Invoices_Customers FOREIGN KEY (CustomerId) REFERENCES dbo.Customers(CustomerId),
    CONSTRAINT UQ_Invoices_No UNIQUE (TenantId, InvoiceNo)
);

CREATE TABLE dbo.InvoiceItems (
    InvoiceItemId BIGINT IDENTITY(1,1) PRIMARY KEY,
    InvoiceId BIGINT NOT NULL,
    ProductId INT NOT NULL,
    BatchId INT NULL,
    Quantity DECIMAL(18,3) NOT NULL,
    UnitPrice DECIMAL(18,2) NOT NULL,
    DiscountAmount DECIMAL(18,2) NOT NULL DEFAULT 0,
    TaxAmount DECIMAL(18,2) NOT NULL DEFAULT 0,
    LineTotal DECIMAL(18,2) NOT NULL,
    CONSTRAINT FK_InvoiceItems_Invoices FOREIGN KEY (InvoiceId) REFERENCES dbo.Invoices(InvoiceId),
    CONSTRAINT FK_InvoiceItems_Products FOREIGN KEY (ProductId) REFERENCES dbo.Products(ProductId)
);

CREATE TABLE dbo.Payments (
    PaymentId BIGINT IDENTITY(1,1) PRIMARY KEY,
    TenantId INT NOT NULL,
    BranchId INT NOT NULL,
    PartyType NVARCHAR(30) NOT NULL,
    PartyId INT NULL,
    ReferenceType NVARCHAR(40) NOT NULL,
    ReferenceId BIGINT NOT NULL,
    Method NVARCHAR(40) NOT NULL,
    Amount DECIMAL(18,2) NOT NULL,
    PaidAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_Payments_Tenants FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId)
);

CREATE TABLE dbo.PurchaseOrders (
    PurchaseOrderId BIGINT IDENTITY(1,1) PRIMARY KEY,
    TenantId INT NOT NULL,
    BranchId INT NOT NULL,
    SupplierId INT NOT NULL,
    OrderNo NVARCHAR(60) NOT NULL,
    Status NVARCHAR(30) NOT NULL DEFAULT 'Pending',
    Total DECIMAL(18,2) NOT NULL DEFAULT 0,
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_PurchaseOrders_Tenants FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId),
    CONSTRAINT FK_PurchaseOrders_Suppliers FOREIGN KEY (SupplierId) REFERENCES dbo.Suppliers(SupplierId)
);

CREATE TABLE dbo.Expenses (
    ExpenseId BIGINT IDENTITY(1,1) PRIMARY KEY,
    TenantId INT NOT NULL,
    BranchId INT NOT NULL,
    Category NVARCHAR(100) NOT NULL,
    Amount DECIMAL(18,2) NOT NULL,
    Notes NVARCHAR(500) NULL,
    ExpenseDate DATE NOT NULL,
    CONSTRAINT FK_Expenses_Tenants FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId)
);

CREATE TABLE dbo.AuditLogs (
    AuditLogId BIGINT IDENTITY(1,1) PRIMARY KEY,
    TenantId INT NULL,
    UserId INT NULL,
    Action NVARCHAR(120) NOT NULL,
    EntityName NVARCHAR(120) NOT NULL,
    EntityId NVARCHAR(80) NULL,
    IpAddress NVARCHAR(80) NULL,
    Metadata NVARCHAR(MAX) NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE INDEX IX_Products_Search ON dbo.Products(TenantId, Name, SKU, Barcode);
CREATE INDEX IX_StockBalances_ProductWarehouse ON dbo.StockBalances(TenantId, ProductId, WarehouseId);
CREATE INDEX IX_StockMovements_Report ON dbo.StockMovements(TenantId, CreatedAt, MovementType);
CREATE INDEX IX_Invoices_Report ON dbo.Invoices(TenantId, BranchId, CreatedAt, Status);
GO

CREATE OR ALTER PROCEDURE dbo.sp_GetDashboardSummary
    @TenantId INT,
    @BranchId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        (SELECT COUNT(*) FROM dbo.Products WHERE TenantId = @TenantId AND IsActive = 1) AS ProductCount,
        (SELECT COUNT(*) FROM dbo.StockBalances sb INNER JOIN dbo.Products p ON p.ProductId = sb.ProductId WHERE sb.TenantId = @TenantId AND (@BranchId IS NULL OR sb.BranchId = @BranchId) AND sb.Quantity <= p.MinStockLevel) AS LowStockCount,
        (SELECT COUNT(*) FROM dbo.StockBalances WHERE TenantId = @TenantId AND (@BranchId IS NULL OR BranchId = @BranchId) AND Quantity <= 0) AS OutOfStockCount,
        (SELECT ISNULL(SUM(Total), 0) FROM dbo.Invoices WHERE TenantId = @TenantId AND (@BranchId IS NULL OR BranchId = @BranchId) AND CAST(CreatedAt AS DATE) = CAST(SYSUTCDATETIME() AS DATE)) AS TodaysSales,
        (SELECT ISNULL(SUM(DueAmount), 0) FROM dbo.Invoices WHERE TenantId = @TenantId AND (@BranchId IS NULL OR BranchId = @BranchId) AND DueAmount > 0) AS PendingPayments;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_RecordStockMovement
    @TenantId INT,
    @BranchId INT,
    @WarehouseId INT,
    @ProductId INT,
    @BatchId INT = NULL,
    @MovementType NVARCHAR(30),
    @Quantity DECIMAL(18,3),
    @ReferenceType NVARCHAR(40) = NULL,
    @ReferenceId BIGINT = NULL,
    @CreatedBy INT = NULL,
    @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;

    INSERT INTO dbo.StockMovements (TenantId, BranchId, WarehouseId, ProductId, BatchId, MovementType, Quantity, ReferenceType, ReferenceId, CreatedBy, Notes)
    VALUES (@TenantId, @BranchId, @WarehouseId, @ProductId, @BatchId, @MovementType, @Quantity, @ReferenceType, @ReferenceId, @CreatedBy, @Notes);

    MERGE dbo.StockBalances AS target
    USING (SELECT @TenantId TenantId, @BranchId BranchId, @WarehouseId WarehouseId, @ProductId ProductId, @BatchId BatchId) AS source
    ON target.TenantId = source.TenantId
       AND target.BranchId = source.BranchId
       AND target.WarehouseId = source.WarehouseId
       AND target.ProductId = source.ProductId
       AND ISNULL(target.BatchId, 0) = ISNULL(source.BatchId, 0)
    WHEN MATCHED THEN
        UPDATE SET Quantity = Quantity + @Quantity, UpdatedAt = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (TenantId, BranchId, WarehouseId, ProductId, BatchId, Quantity)
        VALUES (@TenantId, @BranchId, @WarehouseId, @ProductId, @BatchId, @Quantity);

    COMMIT TRANSACTION;
END
GO
