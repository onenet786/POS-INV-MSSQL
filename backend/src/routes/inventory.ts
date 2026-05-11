import { Router } from 'express';
import { z } from 'zod';
import { getPool, sql } from '../config/db.js';
import { requireAuth, requirePermission } from '../middleware/auth.js';
import { audit } from '../services/audit.js';

export const inventoryRouter = Router();

inventoryRouter.post('/movement', requireAuth, requirePermission('inventory.adjust'), async (req, res, next) => {
  try {
    const body = z.object({
      branchId: z.number(),
      warehouseId: z.number(),
      productId: z.number(),
      batchId: z.number().nullable().optional(),
      movementType: z.enum(['StockIn', 'StockOut', 'Adjustment', 'Damaged', 'Return', 'Opening']),
      quantity: z.number(),
      notes: z.string().optional(),
    }).parse(req.body);

    const signedQuantity = ['StockOut', 'Damaged'].includes(body.movementType)
      ? -Math.abs(body.quantity)
      : body.quantity;

    const pool = await getPool();
    await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('BranchId', sql.Int, body.branchId)
      .input('WarehouseId', sql.Int, body.warehouseId)
      .input('ProductId', sql.Int, body.productId)
      .input('BatchId', sql.Int, body.batchId ?? null)
      .input('MovementType', sql.NVarChar(30), body.movementType)
      .input('Quantity', sql.Decimal(18, 3), signedQuantity)
      .input('ReferenceType', sql.NVarChar(40), 'Manual')
      .input('ReferenceId', sql.BigInt, null)
      .input('CreatedBy', sql.Int, req.user!.userId)
      .input('Notes', sql.NVarChar(500), body.notes ?? null)
      .execute('dbo.sp_RecordStockMovement');

    await audit(req, 'inventory.movement', 'StockMovements', undefined, body);
    res.status(201).json({ message: 'Stock movement recorded' });
  } catch (error) {
    next(error);
  }
});

inventoryRouter.get('/stock', requireAuth, requirePermission('inventory.read'), async (req, res, next) => {
  try {
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .query(`
        SELECT
          p.Name ProductName,
          p.SKU,
          p.Barcode,
          p.MinStockLevel,
          ISNULL(stock.EnteredQuantity, 0) EnteredQuantity,
          ISNULL(stock.SoldQuantity, 0) SoldQuantity,
          ISNULL(stock.OnHoldQuantity, 0) OnHoldQuantity,
          ISNULL(stock.EnteredQuantity, 0) - ISNULL(stock.SoldQuantity, 0) - ISNULL(stock.OnHoldQuantity, 0) Quantity
        FROM dbo.Products p
        LEFT JOIN (
          SELECT
            ProductId,
            SUM(EnteredQuantity) EnteredQuantity,
            SUM(SoldQuantity) SoldQuantity,
            SUM(OnHoldQuantity) OnHoldQuantity
          FROM (
            SELECT sm.ProductId,
              SUM(sm.Quantity) EnteredQuantity,
              CAST(0 AS DECIMAL(18, 3)) SoldQuantity,
              CAST(0 AS DECIMAL(18, 3)) OnHoldQuantity
            FROM dbo.StockMovements sm
            WHERE sm.TenantId = @TenantId
              AND ISNULL(sm.ReferenceType, '') NOT IN ('Invoice', 'InvoiceVoid', 'InvoiceDeleteRepair')
            GROUP BY sm.ProductId

            UNION ALL

            SELECT ii.ProductId,
              CAST(0 AS DECIMAL(18, 3)) EnteredQuantity,
              SUM(CASE WHEN i.Status NOT IN ('Void', 'Cancelled', 'Hold', 'OnHold') THEN ii.Quantity ELSE 0 END) SoldQuantity,
              SUM(CASE WHEN i.Status IN ('Hold', 'OnHold') THEN ii.Quantity ELSE 0 END) OnHoldQuantity
            FROM dbo.InvoiceItems ii
            INNER JOIN dbo.Invoices i ON i.InvoiceId = ii.InvoiceId
            WHERE i.TenantId = @TenantId
            GROUP BY ii.ProductId
          ) stockRows
          GROUP BY ProductId
        ) stock ON stock.ProductId = p.ProductId
        WHERE p.TenantId = @TenantId
        ORDER BY p.Name
      `);
    res.json(result.recordset);
  } catch (error) {
    next(error);
  }
});

inventoryRouter.post('/repair-orphan-invoice-stock', requireAuth, requirePermission('inventory.adjust'), async (req, res, next) => {
  const pool = await getPool();
  const transaction = new sql.Transaction(pool);
  try {
    await transaction.begin();

    const orphanMovements = await new sql.Request(transaction)
      .input('TenantId', sql.Int, req.user!.tenantId)
      .query(`
        SELECT sm.MovementId, sm.BranchId, sm.WarehouseId, sm.ProductId, sm.BatchId, sm.Quantity, sm.ReferenceId
        FROM dbo.StockMovements sm
        LEFT JOIN dbo.Invoices i
          ON i.InvoiceId = sm.ReferenceId
          AND i.TenantId = sm.TenantId
        WHERE sm.TenantId = @TenantId
          AND sm.ReferenceType = 'Invoice'
          AND sm.Quantity < 0
          AND i.InvoiceId IS NULL
          AND NOT EXISTS (
            SELECT 1
            FROM dbo.StockMovements reversal
            WHERE reversal.TenantId = sm.TenantId
              AND reversal.ReferenceType = 'InvoiceDeleteRepair'
              AND reversal.ReferenceId = sm.MovementId
          )
      `);

    for (const movement of orphanMovements.recordset) {
      await new sql.Request(transaction)
        .input('TenantId', sql.Int, req.user!.tenantId)
        .input('BranchId', sql.Int, movement.BranchId)
        .input('WarehouseId', sql.Int, movement.WarehouseId)
        .input('ProductId', sql.Int, movement.ProductId)
        .input('BatchId', sql.Int, movement.BatchId)
        .input('MovementType', sql.NVarChar(30), 'Repair')
        .input('Quantity', sql.Decimal(18, 3), Math.abs(movement.Quantity))
        .input('ReferenceType', sql.NVarChar(40), 'InvoiceDeleteRepair')
        .input('ReferenceId', sql.BigInt, movement.MovementId)
        .input('CreatedBy', sql.Int, req.user!.userId)
        .input('Notes', sql.NVarChar(500), `Restored stock for deleted invoice ${movement.ReferenceId}`)
        .execute('dbo.sp_RecordStockMovement');
    }

    await transaction.commit();
    await audit(req, 'inventory.repair-orphan-invoice-stock', 'StockMovements', undefined, { repaired: orphanMovements.recordset.length });
    res.json({ repaired: orphanMovements.recordset.length });
  } catch (error) {
    try {
      await transaction.rollback();
    } catch {
      // Transaction may already be closed.
    }
    next(error);
  }
});
