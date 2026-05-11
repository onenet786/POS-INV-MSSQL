import { Router } from 'express';
import { requireAuth, requirePermission } from '../middleware/auth.js';
import { getPool, sql } from '../config/db.js';

export const dashboardRouter = Router();

dashboardRouter.get('/', requireAuth, requirePermission('dashboard.read'), async (req, res, next) => {
  try {
    const pool = await getPool();
    const summary = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('BranchId', sql.Int, req.query.branchId ? Number(req.query.branchId) : null)
      .execute('dbo.sp_GetDashboardSummary');

    const monthly = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .query(`
        SELECT FORMAT(CreatedAt, 'yyyy-MM') AS MonthName, SUM(Total) AS Sales, SUM(Total - TaxAmount) AS Revenue
        FROM dbo.Invoices
        WHERE TenantId = @TenantId AND CreatedAt >= DATEADD(MONTH, -11, SYSUTCDATETIME())
        GROUP BY FORMAT(CreatedAt, 'yyyy-MM')
        ORDER BY MonthName
      `);

    const topProducts = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .query(`
        SELECT TOP 10 p.Name, p.SKU, SUM(ii.Quantity) AS QuantitySold, SUM(ii.LineTotal) AS Sales
        FROM dbo.InvoiceItems ii
        INNER JOIN dbo.Invoices i ON i.InvoiceId = ii.InvoiceId
        INNER JOIN dbo.Products p ON p.ProductId = ii.ProductId
        WHERE i.TenantId = @TenantId
        GROUP BY p.Name, p.SKU
        ORDER BY QuantitySold DESC
      `);

    res.json({
      summary: summary.recordset[0],
      monthly: monthly.recordset,
      topProducts: topProducts.recordset,
    });
  } catch (error) {
    next(error);
  }
});

