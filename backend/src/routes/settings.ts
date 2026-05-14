import { Router } from 'express';
import { z } from 'zod';
import { getPool, sql } from '../config/db.js';
import { requireAuth } from '../middleware/auth.js';
import { audit } from '../services/audit.js';

export const settingsRouter = Router();

const receiptPrinterKey = 'receiptPrinterName';

async function ensureSettingsTable() {
  const pool = await getPool();
  await pool.request().query(`
    IF OBJECT_ID('dbo.AppSettings', 'U') IS NULL
    BEGIN
      CREATE TABLE dbo.AppSettings (
        SettingId INT IDENTITY(1,1) PRIMARY KEY,
        TenantId INT NOT NULL,
        SettingKey NVARCHAR(120) NOT NULL,
        SettingValue NVARCHAR(1000) NOT NULL DEFAULT '',
        UpdatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT FK_AppSettings_Tenants FOREIGN KEY (TenantId) REFERENCES dbo.Tenants(TenantId),
        CONSTRAINT UQ_AppSettings_Key UNIQUE (TenantId, SettingKey)
      )
    END
  `);
}

settingsRouter.get('/', requireAuth, async (req, res, next) => {
  try {
    await ensureSettingsTable();
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('SettingKey', sql.NVarChar(120), receiptPrinterKey)
      .query('SELECT SettingValue FROM dbo.AppSettings WHERE TenantId = @TenantId AND SettingKey = @SettingKey');

    res.json({ receiptPrinterName: result.recordset[0]?.SettingValue ?? '' });
  } catch (error) {
    next(error);
  }
});

settingsRouter.put('/receipt-printer-name', requireAuth, async (req, res, next) => {
  try {
    const body = z.object({ value: z.string().max(1000).optional().default('') }).parse(req.body);
    await ensureSettingsTable();
    const pool = await getPool();
    const value = body.value.trim();
    await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('SettingKey', sql.NVarChar(120), receiptPrinterKey)
      .input('SettingValue', sql.NVarChar(1000), value)
      .query(`
        MERGE dbo.AppSettings AS target
        USING (SELECT @TenantId TenantId, @SettingKey SettingKey, @SettingValue SettingValue) AS source
        ON target.TenantId = source.TenantId AND target.SettingKey = source.SettingKey
        WHEN MATCHED THEN
          UPDATE SET SettingValue = source.SettingValue, UpdatedAt = SYSUTCDATETIME()
        WHEN NOT MATCHED THEN
          INSERT (TenantId, SettingKey, SettingValue) VALUES (source.TenantId, source.SettingKey, source.SettingValue);
      `);

    await audit(req, 'settings.receipt-printer.update', 'AppSettings', receiptPrinterKey, { value });
    res.json({ receiptPrinterName: value });
  } catch (error) {
    next(error);
  }
});
