import { Router } from 'express';
import { z } from 'zod';
import { getPool, sql } from '../config/db.js';
import { requireAuth, requirePermission } from '../middleware/auth.js';
import { audit } from '../services/audit.js';

export const expensesRouter = Router();

expensesRouter.get('/', requireAuth, requirePermission('expenses.read'), async (req, res, next) => {
  try {
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .query(`
        SELECT e.*, b.Name BranchName
        FROM dbo.Expenses e
        INNER JOIN dbo.Branches b ON b.BranchId = e.BranchId
        WHERE e.TenantId = @TenantId
        ORDER BY e.ExpenseDate DESC
      `);
    res.json(result.recordset);
  } catch (error) {
    next(error);
  }
});

expensesRouter.post('/', requireAuth, requirePermission('expenses.create'), async (req, res, next) => {
  try {
    const body = z.object({
      branchId: z.number(),
      category: z.string().min(2),
      amount: z.number().positive(),
      notes: z.string().optional(),
      expenseDate: z.string(),
    }).parse(req.body);

    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('BranchId', sql.Int, body.branchId)
      .input('Category', sql.NVarChar(100), body.category)
      .input('Amount', sql.Decimal(18, 2), body.amount)
      .input('Notes', sql.NVarChar(500), body.notes ?? null)
      .input('ExpenseDate', sql.Date, body.expenseDate)
      .query(`
        INSERT INTO dbo.Expenses (TenantId, BranchId, Category, Amount, Notes, ExpenseDate)
        OUTPUT INSERTED.*
        VALUES (@TenantId, @BranchId, @Category, @Amount, @Notes, @ExpenseDate)
      `);
    await audit(req, 'expenses.create', 'Expenses', String(result.recordset[0].ExpenseId), body);
    res.status(201).json(result.recordset[0]);
  } catch (error) {
    next(error);
  }
});
