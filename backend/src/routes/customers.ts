import { Router } from 'express';
import { z } from 'zod';
import { getPool, sql } from '../config/db.js';
import { requireAuth, requirePermission } from '../middleware/auth.js';
import { audit } from '../services/audit.js';

export const customersRouter = Router();

const customerSchema = z.object({
  name: z.string().min(2),
  phone: z.string().optional().nullable(),
  email: z.string().email().optional().nullable(),
  creditLimit: z.number().nonnegative().default(0),
});

customersRouter.get('/', requireAuth, requirePermission('customers.read'), async (req, res, next) => {
  try {
    const search = String(req.query.search ?? '');
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('Search', sql.NVarChar(180), `%${search}%`)
      .query(`
        SELECT * FROM dbo.Customers 
        WHERE TenantId = @TenantId AND (Name LIKE @Search OR Phone LIKE @Search OR Email LIKE @Search)
        ORDER BY Name
      `);
    res.json(result.recordset);
  } catch (error) {
    next(error);
  }
});

customersRouter.get('/:id', requireAuth, requirePermission('customers.read'), async (req, res, next) => {
  try {
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('CustomerId', sql.Int, Number(req.params.id))
      .query('SELECT * FROM dbo.Customers WHERE TenantId = @TenantId AND CustomerId = @CustomerId');
    if (!result.recordset[0]) return res.status(404).json({ message: 'Customer not found' });
    res.json(result.recordset[0]);
  } catch (error) {
    next(error);
  }
});

customersRouter.post('/', requireAuth, requirePermission('customers.create'), async (req, res, next) => {
  try {
    const body = customerSchema.parse(req.body);
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('Name', sql.NVarChar(180), body.name)
      .input('Phone', sql.NVarChar(50), body.phone ?? null)
      .input('Email', sql.NVarChar(180), body.email ?? null)
      .input('CreditLimit', sql.Decimal(18, 2), body.creditLimit)
      .query(`
        INSERT INTO dbo.Customers (TenantId, Name, Phone, Email, CreditLimit)
        OUTPUT INSERTED.*
        VALUES (@TenantId, @Name, @Phone, @Email, @CreditLimit)
      `);
    await audit(req, 'customers.create', 'Customers', String(result.recordset[0].CustomerId), body);
    res.status(201).json(result.recordset[0]);
  } catch (error) {
    next(error);
  }
});

customersRouter.put('/:id', requireAuth, requirePermission('customers.update'), async (req, res, next) => {
  try {
    const body = customerSchema.partial().parse(req.body);
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('CustomerId', sql.Int, Number(req.params.id))
      .input('Name', sql.NVarChar(180), body.name)
      .input('Phone', sql.NVarChar(50), body.phone === undefined ? undefined : body.phone)
      .input('Email', sql.NVarChar(180), body.email === undefined ? undefined : body.email)
      .input('CreditLimit', sql.Decimal(18, 2), body.creditLimit)
      .query(`
        UPDATE dbo.Customers
        SET Name = ISNULL(@Name, Name),
            Phone = CASE WHEN @Phone IS NULL THEN Phone ELSE @Phone END,
            Email = CASE WHEN @Email IS NULL THEN Email ELSE @Email END,
            CreditLimit = ISNULL(@CreditLimit, CreditLimit)
        OUTPUT INSERTED.*
        WHERE TenantId = @TenantId AND CustomerId = @CustomerId
      `);
    if (result.rowsAffected[0] === 0) return res.status(404).json({ message: 'Customer not found' });
    await audit(req, 'customers.update', 'Customers', String(req.params.id), body);
    res.json(result.recordset[0]);
  } catch (error) {
    next(error);
  }
});

customersRouter.delete('/:id', requireAuth, requirePermission('customers.delete'), async (req, res, next) => {
  try {
    const pool = await getPool();
    const check = await pool.request()
      .input('CustomerId', sql.Int, Number(req.params.id))
      .query('SELECT COUNT(*) as InvoiceCount FROM dbo.Invoices WHERE CustomerId = @CustomerId');
    
    if (check.recordset[0].InvoiceCount > 0) {
      return res.status(400).json({ message: 'Cannot delete customer with transaction history.' });
    }

    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('CustomerId', sql.Int, Number(req.params.id))
      .query('DELETE FROM dbo.Customers WHERE TenantId = @TenantId AND CustomerId = @CustomerId');

    if (result.rowsAffected[0] === 0) return res.status(404).json({ message: 'Customer not found' });
    await audit(req, 'customers.delete', 'Customers', String(req.params.id));
    res.json({ message: 'Customer deleted successfully' });
  } catch (error) {
    next(error);
  }
});
