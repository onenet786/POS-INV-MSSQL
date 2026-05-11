import { Router } from 'express';
import { getPool, sql } from '../config/db.js';
import { requireAuth, requirePermission } from '../middleware/auth.js';

export const reportsRouter = Router();

reportsRouter.get('/sales', requireAuth, requirePermission('reports.read'), async (req, res, next) => {
  try {
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('FromDate', sql.Date, req.query.fromDate ?? null)
      .input('ToDate', sql.Date, req.query.toDate ?? null)
      .query(`
        SELECT i.InvoiceNo, i.CreatedAt, b.Name BranchName, c.Name CustomerName,
          i.Subtotal, i.DiscountAmount, i.TaxAmount, i.Total, i.PaidAmount, i.DueAmount
        FROM dbo.Invoices i
        INNER JOIN dbo.Branches b ON b.BranchId = i.BranchId
        LEFT JOIN dbo.Customers c ON c.CustomerId = i.CustomerId
        WHERE i.TenantId = @TenantId
          AND (@FromDate IS NULL OR CAST(i.CreatedAt AS DATE) >= @FromDate)
          AND (@ToDate IS NULL OR CAST(i.CreatedAt AS DATE) <= @ToDate)
        ORDER BY i.CreatedAt DESC
      `);
    res.json(result.recordset);
  } catch (error) {
    next(error);
  }
});

reportsRouter.get('/inventory-valuation', requireAuth, requirePermission('reports.stock'), async (req, res, next) => {
  try {
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .query(`
        SELECT p.Name, p.SKU, SUM(sb.Quantity) Quantity,
          p.PurchasePrice, SUM(sb.Quantity * p.PurchasePrice) Valuation
        FROM dbo.StockBalances sb
        INNER JOIN dbo.Products p ON p.ProductId = sb.ProductId
        WHERE sb.TenantId = @TenantId
        GROUP BY p.Name, p.SKU, p.PurchasePrice
        ORDER BY Valuation DESC
      `);
    res.json(result.recordset);
  } catch (error) {
    next(error);
  }
});

reportsRouter.get('/low-stock', requireAuth, requirePermission('reports.stock'), async (req, res, next) => {
  try {
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .query(`
        SELECT p.Name, p.SKU, p.Barcode, SUM(sb.Quantity) Quantity, p.MinStockLevel
        FROM dbo.Products p
        LEFT JOIN dbo.StockBalances sb ON sb.ProductId = p.ProductId
        WHERE p.TenantId = @TenantId
        GROUP BY p.Name, p.SKU, p.Barcode, p.MinStockLevel
        HAVING SUM(ISNULL(sb.Quantity, 0)) <= p.MinStockLevel
        ORDER BY Quantity ASC
      `);
    res.json(result.recordset);
  } catch (error) {
    next(error);
  }
});

