import { Router } from 'express';
import { z } from 'zod';
import { getPool, sql } from '../config/db.js';
import { requireAuth, requirePermission } from '../middleware/auth.js';
import { audit } from '../services/audit.js';

export const invoicesRouter = Router();

invoicesRouter.get('/', requireAuth, requirePermission('sales.read'), async (req, res, next) => {
  try {
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .query(`
        SELECT i.*, b.Name BranchName, c.Name CustomerName
        FROM dbo.Invoices i
        INNER JOIN dbo.Branches b ON b.BranchId = i.BranchId
        LEFT JOIN dbo.Customers c ON c.CustomerId = i.CustomerId
        WHERE i.TenantId = @TenantId
        ORDER BY i.CreatedAt DESC
      `);
    res.json(result.recordset);
  } catch (error) {
    next(error);
  }
});

invoicesRouter.get('/:id', requireAuth, requirePermission('sales.read'), async (req, res, next) => {
  try {
    const pool = await getPool();
    const invoice = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('InvoiceId', sql.BigInt, req.params.id)
      .query(`
        SELECT i.*, b.Name BranchName, c.Name CustomerName, u.FullName CreatedByName
        FROM dbo.Invoices i
        INNER JOIN dbo.Branches b ON b.BranchId = i.BranchId
        LEFT JOIN dbo.Customers c ON c.CustomerId = i.CustomerId
        LEFT JOIN dbo.Users u ON u.UserId = i.CreatedBy
        WHERE i.TenantId = @TenantId AND i.InvoiceId = @InvoiceId
      `);

    if (!invoice.recordset[0]) return res.status(404).json({ message: 'Invoice not found' });

    const items = await pool.request()
      .input('InvoiceId', sql.BigInt, req.params.id)
      .query(`
        SELECT ii.*, p.Name ProductName, p.SKU, p.Barcode, u.Symbol UnitSymbol
        FROM dbo.InvoiceItems ii
        INNER JOIN dbo.Products p ON p.ProductId = ii.ProductId
        INNER JOIN dbo.Units u ON u.UnitId = p.UnitId
        WHERE ii.InvoiceId = @InvoiceId
      `);

    const payments = await pool.request()
      .input('ReferenceId', sql.BigInt, req.params.id)
      .query(`
        SELECT * FROM dbo.Payments 
        WHERE ReferenceType = 'Invoice' AND ReferenceId = @ReferenceId
      `);

    res.json({
      ...invoice.recordset[0],
      items: items.recordset,
      payments: payments.recordset,
    });
  } catch (error) {
    next(error);
  }
});

invoicesRouter.post('/:id/void', requireAuth, requirePermission('sales.void'), async (req, res, next) => {
  const pool = await getPool();
  const transaction = new sql.Transaction(pool);
  try {
    await transaction.begin();
    const request = new sql.Request(transaction);
    
    // Check if already voided
    const invoice = await request
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('InvoiceId', sql.BigInt, req.params.id)
      .query('SELECT Status, BranchId FROM dbo.Invoices WHERE TenantId = @TenantId AND InvoiceId = @InvoiceId');
    
    if (!invoice.recordset[0]) return res.status(404).json({ message: 'Invoice not found' });
    if (invoice.recordset[0].Status === 'Void') return res.status(400).json({ message: 'Invoice already voided' });

    const branchId = invoice.recordset[0].BranchId;

    // Update Status
    await new sql.Request(transaction)
      .input('InvoiceId', sql.BigInt, req.params.id)
      .query("UPDATE dbo.Invoices SET Status = 'Void' WHERE InvoiceId = @InvoiceId");

    // Reverse Stock Movement
    const items = await new sql.Request(transaction)
      .input('InvoiceId', sql.BigInt, req.params.id)
      .query('SELECT ProductId, BatchId, Quantity FROM dbo.InvoiceItems WHERE InvoiceId = @InvoiceId');

    for (const item of items.recordset) {
      await new sql.Request(transaction)
        .input('TenantId', sql.Int, req.user!.tenantId)
        .input('BranchId', sql.Int, branchId)
        .input('WarehouseId', sql.Int, 1) // Default warehouse or should we track it?
        .input('ProductId', sql.Int, item.ProductId)
        .input('BatchId', sql.Int, item.BatchId)
        .input('MovementType', sql.NVarChar(30), 'Void')
        .input('Quantity', sql.Decimal(18, 3), Math.abs(item.Quantity))
        .input('ReferenceType', sql.NVarChar(40), 'InvoiceVoid')
        .input('ReferenceId', sql.BigInt, req.params.id)
        .input('CreatedBy', sql.Int, req.user!.userId)
        .input('Notes', sql.NVarChar(500), 'Stock reversal after invoice void')
        .execute('dbo.sp_RecordStockMovement');
    }

    await transaction.commit();
    await audit(req, 'sales.invoice.void', 'Invoices', String(req.params.id));
    res.json({ message: 'Invoice voided successfully' });
  } catch (error) {
    try { await transaction.rollback(); } catch {}
    next(error);
  }
});

invoicesRouter.post('/', requireAuth, requirePermission('sales.create'), async (req, res, next) => {
  const pool = await getPool();
  const transaction = new sql.Transaction(pool);
  try {
    const body = z.object({
      branchId: z.number(),
      warehouseId: z.number(),
      customerId: z.number().nullable().optional(),
      discountAmount: z.number().default(0),
      payments: z.array(z.object({ method: z.string(), amount: z.number() })).default([]),
      items: z.array(z.object({
        productId: z.number(),
        batchId: z.number().nullable().optional(),
        quantity: z.number().positive(),
        unitPrice: z.number().nonnegative(),
        discountAmount: z.number().default(0),
        taxAmount: z.number().default(0),
      })).min(1),
    }).parse(req.body);

    const subtotal = body.items.reduce((sum, item) => sum + item.quantity * item.unitPrice, 0);
    const taxAmount = body.items.reduce((sum, item) => sum + item.taxAmount, 0);
    const total = subtotal - body.discountAmount + taxAmount;
    const paidAmount = body.payments.reduce((sum, payment) => sum + payment.amount, 0);
    const invoiceNo = `INV-${Date.now()}`;

    await transaction.begin();
    const request = new sql.Request(transaction);
    const invoice = await request
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('BranchId', sql.Int, body.branchId)
      .input('CustomerId', sql.Int, body.customerId ?? null)
      .input('InvoiceNo', sql.NVarChar(60), invoiceNo)
      .input('Subtotal', sql.Decimal(18, 2), subtotal)
      .input('DiscountAmount', sql.Decimal(18, 2), body.discountAmount)
      .input('TaxAmount', sql.Decimal(18, 2), taxAmount)
      .input('Total', sql.Decimal(18, 2), total)
      .input('PaidAmount', sql.Decimal(18, 2), paidAmount)
      .input('CreatedBy', sql.Int, req.user!.userId)
      .query(`
        INSERT INTO dbo.Invoices (TenantId, BranchId, CustomerId, InvoiceNo, Subtotal, DiscountAmount, TaxAmount, Total, PaidAmount, CreatedBy)
        OUTPUT INSERTED.InvoiceId, INSERTED.InvoiceNo
        VALUES (@TenantId, @BranchId, @CustomerId, @InvoiceNo, @Subtotal, @DiscountAmount, @TaxAmount, @Total, @PaidAmount, @CreatedBy)
      `);

    const invoiceId = invoice.recordset[0].InvoiceId;
    for (const item of body.items) {
      const lineTotal = item.quantity * item.unitPrice - item.discountAmount + item.taxAmount;
      await new sql.Request(transaction)
        .input('InvoiceId', sql.BigInt, invoiceId)
        .input('ProductId', sql.Int, item.productId)
        .input('BatchId', sql.Int, item.batchId ?? null)
        .input('Quantity', sql.Decimal(18, 3), item.quantity)
        .input('UnitPrice', sql.Decimal(18, 2), item.unitPrice)
        .input('DiscountAmount', sql.Decimal(18, 2), item.discountAmount)
        .input('TaxAmount', sql.Decimal(18, 2), item.taxAmount)
        .input('LineTotal', sql.Decimal(18, 2), lineTotal)
        .query(`
          INSERT INTO dbo.InvoiceItems (InvoiceId, ProductId, BatchId, Quantity, UnitPrice, DiscountAmount, TaxAmount, LineTotal)
          VALUES (@InvoiceId, @ProductId, @BatchId, @Quantity, @UnitPrice, @DiscountAmount, @TaxAmount, @LineTotal)
        `);

      await new sql.Request(transaction)
        .input('TenantId', sql.Int, req.user!.tenantId)
        .input('BranchId', sql.Int, body.branchId)
        .input('WarehouseId', sql.Int, body.warehouseId)
        .input('ProductId', sql.Int, item.productId)
        .input('BatchId', sql.Int, item.batchId ?? null)
        .input('MovementType', sql.NVarChar(30), 'Sale')
        .input('Quantity', sql.Decimal(18, 3), -Math.abs(item.quantity))
        .input('ReferenceType', sql.NVarChar(40), 'Invoice')
        .input('ReferenceId', sql.BigInt, invoiceId)
        .input('CreatedBy', sql.Int, req.user!.userId)
        .input('Notes', sql.NVarChar(500), 'Auto stock deduction after sale')
        .execute('dbo.sp_RecordStockMovement');
    }

    for (const payment of body.payments) {
      await new sql.Request(transaction)
        .input('TenantId', sql.Int, req.user!.tenantId)
        .input('BranchId', sql.Int, body.branchId)
        .input('PartyType', sql.NVarChar(30), 'Customer')
        .input('PartyId', sql.Int, body.customerId ?? null)
        .input('ReferenceType', sql.NVarChar(40), 'Invoice')
        .input('ReferenceId', sql.BigInt, invoiceId)
        .input('Method', sql.NVarChar(40), payment.method)
        .input('Amount', sql.Decimal(18, 2), payment.amount)
        .query(`
          INSERT INTO dbo.Payments (TenantId, BranchId, PartyType, PartyId, ReferenceType, ReferenceId, Method, Amount)
          VALUES (@TenantId, @BranchId, @PartyType, @PartyId, @ReferenceType, @ReferenceId, @Method, @Amount)
        `);
    }

    await transaction.commit();
    await audit(req, 'sales.invoice.create', 'Invoices', String(invoiceId), body);
    res.status(201).json({ invoiceId, invoiceNo, total, paidAmount, dueAmount: total - paidAmount });
  } catch (error) {
    try {
      await transaction.rollback();
    } catch {
      // The transaction may not have started or may already be closed.
    }
    next(error);
  }
});
