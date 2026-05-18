USE PosInvMssql;
GO

IF OBJECT_ID('dbo.BranchTypes', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.BranchTypes (
        BranchTypeId INT IDENTITY(1,1) PRIMARY KEY,
        TenantId INT NOT NULL,
        Name NVARCHAR(80) NOT NULL,
        Code NVARCHAR(32) NOT NULL,
        IsActive BIT NOT NULL DEFAULT 1,
        CONSTRAINT FK_BranchTypes_Tenants FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId),
        CONSTRAINT UQ_BranchTypes_Code UNIQUE (TenantId, Code)
    );
END
GO

IF COL_LENGTH('dbo.BranchTypes', 'TenantId') IS NULL
BEGIN
    ALTER TABLE dbo.BranchTypes ADD TenantId INT NULL;
END
GO

IF COL_LENGTH('dbo.BranchTypes', 'Name') IS NULL
BEGIN
    ALTER TABLE dbo.BranchTypes ADD Name NVARCHAR(80) NULL;
END
GO

IF COL_LENGTH('dbo.BranchTypes', 'Code') IS NULL
BEGIN
    ALTER TABLE dbo.BranchTypes ADD Code NVARCHAR(32) NULL;
END
GO

IF COL_LENGTH('dbo.BranchTypes', 'IsActive') IS NULL
BEGIN
    ALTER TABLE dbo.BranchTypes ADD IsActive BIT NOT NULL CONSTRAINT DF_BranchTypes_IsActive DEFAULT 1;
END
GO

IF COL_LENGTH('dbo.Branches', 'BranchTypeId') IS NULL
BEGIN
    ALTER TABLE dbo.Branches ADD BranchTypeId INT NULL;
END
GO

IF COL_LENGTH('dbo.Users', 'BranchTypeId') IS NULL
BEGIN
    ALTER TABLE dbo.Users ADD BranchTypeId INT NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Branches_BranchTypes')
BEGIN
    ALTER TABLE dbo.Branches
    ADD CONSTRAINT FK_Branches_BranchTypes FOREIGN KEY (BranchTypeId) REFERENCES dbo.BranchTypes(BranchTypeId);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Users_BranchTypes')
BEGIN
    ALTER TABLE dbo.Users
    ADD CONSTRAINT FK_Users_BranchTypes FOREIGN KEY (BranchTypeId) REFERENCES dbo.BranchTypes(BranchTypeId);
END
GO

IF COL_LENGTH('dbo.Products', 'PosPriority') IS NULL
BEGIN
    ALTER TABLE dbo.Products ADD PosPriority INT NOT NULL CONSTRAINT DF_Products_PosPriority DEFAULT 0;
END
GO

EXEC sp_executesql N'
INSERT INTO dbo.BranchTypes (TenantId, Name, Code)
SELECT t.TenantId, v.Name, v.Code
FROM dbo.Tenants t
CROSS APPLY (VALUES (''Retail'', ''RETAIL''), (''Restaurant'', ''RESTAURANT''), (''Hotel'', ''HOTEL'')) v(Name, Code)
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.BranchTypes bt WHERE bt.TenantId = t.TenantId AND bt.Code = v.Code
);';
GO

EXEC sp_executesql N'
UPDATE b
SET BranchTypeId = bt.BranchTypeId
FROM dbo.Branches b
INNER JOIN dbo.BranchTypes bt ON bt.TenantId = b.TenantId AND bt.Code = ''RETAIL''
WHERE b.BranchTypeId IS NULL;';
GO

EXEC sp_executesql N'
UPDATE u
SET BranchTypeId = b.BranchTypeId
FROM dbo.Users u
INNER JOIN dbo.Branches b ON b.TenantId = u.TenantId AND b.BranchId = u.BranchId
WHERE u.BranchTypeId IS NULL AND b.BranchTypeId IS NOT NULL;';
GO
