import { Router } from 'express';
import { z } from 'zod';
import { getPool, sql } from '../config/db.js';
import { requireAuth, requirePermission } from '../middleware/auth.js';
import { audit } from '../services/audit.js';

export const suppliersRouter = Router();

const supplierSchema = z.object({
  name: z.string().min(2),
  phone: z.string().optional().nullable(),
  email: z.string().email().optional().nullable(),
  taxNumber: z.string().optional().nullable(),
});

suppliersRouter.get('/', requireAuth, requirePermission('suppliers.read'), async (req, res, next) => {
  try {
    const search = String(req.query.search ?? '');
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('Search', sql.NVarChar(180), `%${search}%`)
      .query(`
        SELECT * FROM dbo.Suppliers 
        WHERE TenantId = @TenantId AND (Name LIKE @Search OR Phone LIKE @Search OR Email LIKE @Search)
        ORDER BY Name
      `);
    res.json(result.recordset);
  } catch (error) {
    next(error);
  }
});

suppliersRouter.get('/:id', requireAuth, requirePermission('suppliers.read'), async (req, res, next) => {
  try {
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('SupplierId', sql.Int, Number(req.params.id))
      .query('SELECT * FROM dbo.Suppliers WHERE TenantId = @TenantId AND SupplierId = @SupplierId');
    if (!result.recordset[0]) return res.status(404).json({ message: 'Supplier not found' });
    res.json(result.recordset[0]);
  } catch (error) {
    next(error);
  }
});

suppliersRouter.post('/', requireAuth, requirePermission('suppliers.create'), async (req, res, next) => {
  try {
    const body = supplierSchema.parse(req.body);
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('Name', sql.NVarChar(180), body.name)
      .input('Phone', sql.NVarChar(50), body.phone ?? null)
      .input('Email', sql.NVarChar(180), body.email ?? null)
      .input('TaxNumber', sql.NVarChar(80), body.taxNumber ?? null)
      .query(`
        INSERT INTO dbo.Suppliers (TenantId, Name, Phone, Email, TaxNumber)
        OUTPUT INSERTED.*
        VALUES (@TenantId, @Name, @Phone, @Email, @TaxNumber)
      `);
    await audit(req, 'suppliers.create', 'Suppliers', String(result.recordset[0].SupplierId), body);
    res.status(201).json(result.recordset[0]);
  } catch (error) {
    next(error);
  }
});

suppliersRouter.put('/:id', requireAuth, requirePermission('suppliers.update'), async (req, res, next) => {
  try {
    const body = supplierSchema.partial().parse(req.body);
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('SupplierId', sql.Int, Number(req.params.id))
      .input('Name', sql.NVarChar(180), body.name)
      .input('Phone', sql.NVarChar(50), body.phone === undefined ? undefined : body.phone)
      .input('Email', sql.NVarChar(180), body.email === undefined ? undefined : body.email)
      .input('TaxNumber', sql.NVarChar(80), body.taxNumber === undefined ? undefined : body.taxNumber)
      .query(`
        UPDATE dbo.Suppliers
        SET Name = ISNULL(@Name, Name),
            Phone = CASE WHEN @Phone IS NULL THEN Phone ELSE @Phone END,
            Email = CASE WHEN @Email IS NULL THEN Email ELSE @Email END,
            TaxNumber = CASE WHEN @TaxNumber IS NULL THEN TaxNumber ELSE @TaxNumber END
        OUTPUT INSERTED.*
        WHERE TenantId = @TenantId AND SupplierId = @SupplierId
      `);
    if (result.rowsAffected[0] === 0) return res.status(404).json({ message: 'Supplier not found' });
    await audit(req, 'suppliers.update', 'Suppliers', String(req.params.id), body);
    res.json(result.recordset[0]);
  } catch (error) {
    next(error);
  }
});

suppliersRouter.delete('/:id', requireAuth, requirePermission('suppliers.delete'), async (req, res, next) => {
  try {
    const pool = await getPool();
    const check = await pool.request()
      .input('SupplierId', sql.Int, Number(req.params.id))
      .query('SELECT COUNT(*) as POCount FROM dbo.PurchaseOrders WHERE SupplierId = @SupplierId');
    
    if (check.recordset[0].POCount > 0) {
      return res.status(400).json({ message: 'Cannot delete supplier with transaction history.' });
    }

    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('SupplierId', sql.Int, Number(req.params.id))
      .query('DELETE FROM dbo.Suppliers WHERE TenantId = @TenantId AND SupplierId = @SupplierId');

    if (result.rowsAffected[0] === 0) return res.status(404).json({ message: 'Supplier not found' });
    await audit(req, 'suppliers.delete', 'Suppliers', String(req.params.id));
    res.json({ message: 'Supplier deleted successfully' });
  } catch (error) {
    next(error);
  }
});
