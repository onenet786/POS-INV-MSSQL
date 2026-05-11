import { Router } from 'express';
import { z } from 'zod';
import { getPool, sql } from '../config/db.js';
import { requireAuth, requirePermission } from '../middleware/auth.js';
import { audit } from '../services/audit.js';

export const purchasesRouter = Router();

purchasesRouter.get('/', requireAuth, requirePermission('purchases.read'), async (req, res, next) => {
  try {
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .query(`
        SELECT po.*, b.Name BranchName, s.Name SupplierName
        FROM dbo.PurchaseOrders po
        INNER JOIN dbo.Branches b ON b.BranchId = po.BranchId
        INNER JOIN dbo.Suppliers s ON s.SupplierId = po.SupplierId
        WHERE po.TenantId = @TenantId
        ORDER BY po.CreatedAt DESC
      `);
    res.json(result.recordset);
  } catch (error) {
    next(error);
  }
});

purchasesRouter.post('/', requireAuth, requirePermission('purchases.create'), async (req, res, next) => {
  try {
    const body = z.object({
      branchId: z.number(),
      supplierId: z.number(),
      orderNo: z.string().min(2),
      total: z.number().nonnegative(),
    }).parse(req.body);

    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('BranchId', sql.Int, body.branchId)
      .input('SupplierId', sql.Int, body.supplierId)
      .input('OrderNo', sql.NVarChar(60), body.orderNo)
      .input('Total', sql.Decimal(18, 2), body.total)
      .query(`
        INSERT INTO dbo.PurchaseOrders (TenantId, BranchId, SupplierId, OrderNo, Total)
        OUTPUT INSERTED.*
        VALUES (@TenantId, @BranchId, @SupplierId, @OrderNo, @Total)
      `);
    await audit(req, 'purchases.create', 'PurchaseOrders', String(result.recordset[0].PurchaseOrderId), body);
    res.status(201).json(result.recordset[0]);
  } catch (error) {
    next(error);
  }
});
