import type { Request } from 'express';
import { getPool, sql } from '../config/db.js';

export async function audit(req: Request, action: string, entityName: string, entityId?: string, metadata?: unknown) {
  const pool = await getPool();
  await pool.request()
    .input('TenantId', sql.Int, req.user?.tenantId ?? null)
    .input('UserId', sql.Int, req.user?.userId ?? null)
    .input('Action', sql.NVarChar(120), action)
    .input('EntityName', sql.NVarChar(120), entityName)
    .input('EntityId', sql.NVarChar(80), entityId ?? null)
    .input('IpAddress', sql.NVarChar(80), req.ip)
    .input('Metadata', sql.NVarChar(sql.MAX), metadata ? JSON.stringify(metadata) : null)
    .query(`
      INSERT INTO dbo.AuditLogs (TenantId, UserId, Action, EntityName, EntityId, IpAddress, Metadata)
      VALUES (@TenantId, @UserId, @Action, @EntityName, @EntityId, @IpAddress, @Metadata)
    `);
}

