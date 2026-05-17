import { Router } from 'express';
import QRCode from 'qrcode';
import { z } from 'zod';
import { getPool, sql } from '../config/db.js';
import { requireAuth, requirePermission } from '../middleware/auth.js';
import { audit } from '../services/audit.js';

export const productsRouter = Router();

const productSchema = z.object({
  name: z.string().min(2),
  categoryId: z.number().nullable().optional(),
  brandId: z.number().nullable().optional(),
  unitId: z.number(),
  sku: z.string().optional(),
  barcode: z.string().optional(),
  salePrice: z.number().nonnegative(),
  purchasePrice: z.number().nonnegative(),
  taxRate: z.number().nonnegative().default(0),
  minStockLevel: z.number().nonnegative().default(0),
  posPriority: z.number().int().nonnegative().default(0),
  stockQuantity: z.number().nonnegative().optional(),
  hasExpiry: z.boolean().default(false),
  trackSerial: z.boolean().default(false),
  isActive: z.boolean().optional(),
});

const stockFormula = `
  SELECT
    ProductId,
    SUM(EnteredQuantity) EnteredQuantity,
    SUM(SoldQuantity) SoldQuantity,
    SUM(OnHoldQuantity) OnHoldQuantity,
    SUM(EnteredQuantity) - SUM(SoldQuantity) - SUM(OnHoldQuantity) StockOnHand
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
  ) stock
  GROUP BY ProductId
`;

productsRouter.get('/', requireAuth, requirePermission('products.read'), async (req, res, next) => {
  try {
    const search = String(req.query.search ?? '');
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('Search', sql.NVarChar(220), `%${search}%`)
      .query(`
        SELECT p.*, c.Name CategoryName, b.Name BrandName, u.Symbol UnitSymbol,
          ISNULL(stock.EnteredQuantity, 0) EnteredQuantity,
          ISNULL(stock.SoldQuantity, 0) SoldQuantity,
          ISNULL(stock.OnHoldQuantity, 0) OnHoldQuantity,
          ISNULL(stock.StockOnHand, 0) StockOnHand
        FROM dbo.Products p
        LEFT JOIN dbo.Categories c ON c.CategoryId = p.CategoryId
        LEFT JOIN dbo.Brands b ON b.BrandId = p.BrandId
        INNER JOIN dbo.Units u ON u.UnitId = p.UnitId
        LEFT JOIN (${stockFormula}) stock ON stock.ProductId = p.ProductId
        WHERE p.TenantId = @TenantId
          AND (@Search = '%%' OR p.Name LIKE @Search OR p.SKU LIKE @Search OR p.Barcode LIKE @Search)
        ORDER BY CASE WHEN p.PosPriority > 0 THEN 0 ELSE 1 END, p.PosPriority, p.Name
      `);
    res.json(result.recordset);
  } catch (error) {
    next(error);
  }
});

productsRouter.get('/:id', requireAuth, requirePermission('products.read'), async (req, res, next) => {
  try {
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('ProductId', sql.Int, Number(req.params.id))
      .query(`
        SELECT p.*, c.Name CategoryName, b.Name BrandName, u.Symbol UnitSymbol,
          ISNULL(stock.EnteredQuantity, 0) EnteredQuantity,
          ISNULL(stock.SoldQuantity, 0) SoldQuantity,
          ISNULL(stock.OnHoldQuantity, 0) OnHoldQuantity,
          ISNULL(stock.StockOnHand, 0) StockOnHand
        FROM dbo.Products p
        LEFT JOIN dbo.Categories c ON c.CategoryId = p.CategoryId
        LEFT JOIN dbo.Brands b ON b.BrandId = p.BrandId
        INNER JOIN dbo.Units u ON u.UnitId = p.UnitId
        LEFT JOIN (${stockFormula}) stock ON stock.ProductId = p.ProductId
        WHERE p.TenantId = @TenantId AND p.ProductId = @ProductId
      `);
    if (!result.recordset[0]) return res.status(404).json({ message: 'Product not found' });
    res.json(result.recordset[0]);
  } catch (error) {
    next(error);
  }
});

productsRouter.post('/', requireAuth, requirePermission('products.create'), async (req, res, next) => {
  try {
    const body = productSchema.parse(req.body);
    const sku = body.sku?.trim() || `SKU-${Date.now()}`;
    const barcode = body.barcode?.trim() || String(Date.now()).slice(-12).padStart(12, '1');
    const qrPayload = JSON.stringify({ sku, barcode, name: body.name, price: body.salePrice });
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('CategoryId', sql.Int, body.categoryId ?? null)
      .input('BrandId', sql.Int, body.brandId ?? null)
      .input('UnitId', sql.Int, body.unitId)
      .input('Name', sql.NVarChar(220), body.name)
      .input('SKU', sql.NVarChar(64), sku)
      .input('Barcode', sql.NVarChar(80), barcode)
      .input('QRPayload', sql.NVarChar(sql.MAX), qrPayload)
      .input('SalePrice', sql.Decimal(18, 2), body.salePrice)
      .input('PurchasePrice', sql.Decimal(18, 2), body.purchasePrice)
      .input('TaxRate', sql.Decimal(9, 4), body.taxRate)
      .input('MinStockLevel', sql.Decimal(18, 3), body.minStockLevel)
      .input('PosPriority', sql.Int, body.posPriority)
      .input('HasExpiry', sql.Bit, body.hasExpiry)
      .input('TrackSerial', sql.Bit, body.trackSerial)
      .query(`
        INSERT INTO dbo.Products (TenantId, CategoryId, BrandId, UnitId, Name, SKU, Barcode, QRPayload, SalePrice, PurchasePrice, TaxRate, MinStockLevel, PosPriority, HasExpiry, TrackSerial)
        OUTPUT INSERTED.*
        VALUES (@TenantId, @CategoryId, @BrandId, @UnitId, @Name, @SKU, @Barcode, @QRPayload, @SalePrice, @PurchasePrice, @TaxRate, @MinStockLevel, @PosPriority, @HasExpiry, @TrackSerial)
      `);
    const created = result.recordset[0];
    if ((body.stockQuantity ?? 0) > 0) {
      await pool.request()
        .input('TenantId', sql.Int, req.user!.tenantId)
        .input('BranchId', sql.Int, req.user!.branchId ?? 1)
        .input('WarehouseId', sql.Int, 1)
        .input('ProductId', sql.Int, created.ProductId)
        .input('BatchId', sql.Int, null)
        .input('MovementType', sql.NVarChar(30), 'Opening')
        .input('Quantity', sql.Decimal(18, 3), body.stockQuantity)
        .input('ReferenceType', sql.NVarChar(40), 'ProductOpening')
        .input('ReferenceId', sql.BigInt, created.ProductId)
        .input('CreatedBy', sql.Int, req.user!.userId)
        .input('Notes', sql.NVarChar(500), 'Opening stock from product form')
        .execute('dbo.sp_RecordStockMovement');
    }
    await audit(req, 'products.create', 'Products', String(result.recordset[0].ProductId), body);
    res.status(201).json({ ...created, StockOnHand: body.stockQuantity ?? 0 });
  } catch (error) {
    next(error);
  }
});

productsRouter.put('/:id', requireAuth, requirePermission('products.update'), async (req, res, next) => {
  try {
    const body = productSchema.partial().parse(req.body);
    const pool = await getPool();
    
    // First get existing product to check if it exists and to merge for QR payload if SKU/Barcode changed
    const existing = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('ProductId', sql.Int, Number(req.params.id))
      .query('SELECT * FROM dbo.Products WHERE TenantId = @TenantId AND ProductId = @ProductId');
    
    if (!existing.recordset[0]) return res.status(404).json({ message: 'Product not found' });
    const p = existing.recordset[0];

    const sku = body.sku?.trim() || p.SKU;
    const barcode = body.barcode?.trim() || p.Barcode;
    const name = body.name ?? p.Name;
    const price = body.salePrice ?? p.SalePrice;
    const qrPayload = JSON.stringify({ sku, barcode, name, price });

    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('ProductId', sql.Int, Number(req.params.id))
      .input('CategoryId', sql.Int, body.categoryId === undefined ? p.CategoryId : body.categoryId)
      .input('BrandId', sql.Int, body.brandId === undefined ? p.BrandId : body.brandId)
      .input('UnitId', sql.Int, body.unitId ?? p.UnitId)
      .input('Name', sql.NVarChar(220), name)
      .input('SKU', sql.NVarChar(64), sku)
      .input('Barcode', sql.NVarChar(80), barcode)
      .input('QRPayload', sql.NVarChar(sql.MAX), qrPayload)
      .input('SalePrice', sql.Decimal(18, 2), price)
      .input('PurchasePrice', sql.Decimal(18, 2), body.purchasePrice ?? p.PurchasePrice)
      .input('TaxRate', sql.Decimal(9, 4), body.taxRate ?? p.TaxRate)
      .input('MinStockLevel', sql.Decimal(18, 3), body.minStockLevel ?? p.MinStockLevel)
      .input('PosPriority', sql.Int, body.posPriority ?? p.PosPriority ?? 0)
      .input('HasExpiry', sql.Bit, body.hasExpiry ?? p.HasExpiry)
      .input('TrackSerial', sql.Bit, body.trackSerial ?? p.TrackSerial)
      .input('IsActive', sql.Bit, body.isActive ?? p.IsActive)
      .query(`
        UPDATE dbo.Products
        SET CategoryId = @CategoryId, BrandId = @BrandId, UnitId = @UnitId, Name = @Name, SKU = @SKU, 
            Barcode = @Barcode, QRPayload = @QRPayload, SalePrice = @SalePrice, PurchasePrice = @PurchasePrice, 
            TaxRate = @TaxRate, MinStockLevel = @MinStockLevel, PosPriority = @PosPriority, HasExpiry = @HasExpiry, TrackSerial = @TrackSerial,
            IsActive = @IsActive
        OUTPUT INSERTED.*
        WHERE TenantId = @TenantId AND ProductId = @ProductId
      `);

    if (body.stockQuantity !== undefined) {
      const currentStock = await pool.request()
        .input('TenantId', sql.Int, req.user!.tenantId)
        .input('ProductId', sql.Int, Number(req.params.id))
        .query(`
          SELECT ISNULL(stock.StockOnHand, 0) StockOnHand
          FROM dbo.Products p
          LEFT JOIN (${stockFormula}) stock ON stock.ProductId = p.ProductId
          WHERE p.TenantId = @TenantId AND p.ProductId = @ProductId
        `);
      const adjustment = body.stockQuantity - Number(currentStock.recordset[0]?.StockOnHand ?? 0);
      if (Math.abs(adjustment) > 0.0001) {
        await pool.request()
          .input('TenantId', sql.Int, req.user!.tenantId)
          .input('BranchId', sql.Int, req.user!.branchId ?? 1)
          .input('WarehouseId', sql.Int, 1)
          .input('ProductId', sql.Int, Number(req.params.id))
          .input('BatchId', sql.Int, null)
          .input('MovementType', sql.NVarChar(30), 'Adjustment')
          .input('Quantity', sql.Decimal(18, 3), adjustment)
          .input('ReferenceType', sql.NVarChar(40), 'ProductStockEdit')
          .input('ReferenceId', sql.BigInt, Number(req.params.id))
          .input('CreatedBy', sql.Int, req.user!.userId)
          .input('Notes', sql.NVarChar(500), 'Stock adjusted from product form')
          .execute('dbo.sp_RecordStockMovement');
      }
    }

    await audit(req, 'products.update', 'Products', String(req.params.id), body);
    res.json({ ...result.recordset[0], StockOnHand: body.stockQuantity });
  } catch (error) {
    next(error);
  }
});

productsRouter.delete('/:id', requireAuth, requirePermission('products.delete'), async (req, res, next) => {
  try {
    const pool = await getPool();
    // Check if product has stock or transactions
    const check = await pool.request()
      .input('ProductId', sql.Int, Number(req.params.id))
      .query(`
        SELECT 
          (SELECT COUNT(*) FROM dbo.StockBalances WHERE ProductId = @ProductId AND Quantity <> 0) as StockCount,
          (SELECT COUNT(*) FROM dbo.InvoiceItems WHERE ProductId = @ProductId) as SaleCount
      `);
    
    const { StockCount, SaleCount } = check.recordset[0];
    if (StockCount > 0 || SaleCount > 0) {
      return res.status(400).json({ message: 'Cannot delete product with existing stock or sales history. Deactivate it instead.' });
    }

    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('ProductId', sql.Int, Number(req.params.id))
      .query('DELETE FROM dbo.Products WHERE TenantId = @TenantId AND ProductId = @ProductId');

    if (result.rowsAffected[0] === 0) return res.status(404).json({ message: 'Product not found' });
    
    await audit(req, 'products.delete', 'Products', String(req.params.id));
    res.json({ message: 'Product deleted successfully' });
  } catch (error) {
    next(error);
  }
});

productsRouter.get('/:id/qr', requireAuth, requirePermission('products.read'), async (req, res, next) => {
  try {
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('ProductId', sql.Int, Number(req.params.id))
      .query('SELECT TOP 1 QRPayload FROM dbo.Products WHERE TenantId = @TenantId AND ProductId = @ProductId');
    if (!result.recordset[0]) return res.status(404).json({ message: 'Product not found' });
    const dataUrl = await QRCode.toDataURL(result.recordset[0].QRPayload);
    res.json({ dataUrl });
  } catch (error) {
    next(error);
  }
});
