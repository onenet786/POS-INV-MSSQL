import { Router } from 'express';
import { z } from 'zod';
import { getPool, sql } from '../config/db.js';
import { requireAuth, requirePermission } from '../middleware/auth.js';
import { audit } from '../services/audit.js';

export const referenceRouter = Router();

referenceRouter.get('/', requireAuth, async (req, res, next) => {
  try {
    const pool = await getPool();
    const request = pool.request().input('TenantId', sql.Int, req.user!.tenantId);
    const [branches, branchTypes, warehouses, categories, brands, units] = await Promise.all([
      request.query(`
        SELECT b.BranchId, b.Name, b.Code, b.BranchTypeId, bt.Name BranchTypeName
        FROM dbo.Branches b
        LEFT JOIN dbo.BranchTypes bt ON bt.BranchTypeId = b.BranchTypeId
        WHERE b.TenantId = @TenantId AND b.IsActive = 1
      `),
      pool.request().input('TenantId', sql.Int, req.user!.tenantId).query('SELECT BranchTypeId, Name, Code FROM dbo.BranchTypes WHERE TenantId = @TenantId AND IsActive = 1 ORDER BY Name'),
      pool.request().input('TenantId', sql.Int, req.user!.tenantId).query('SELECT WarehouseId, BranchId, Name, Code FROM dbo.Warehouses WHERE TenantId = @TenantId AND IsActive = 1'),
      pool.request().input('TenantId', sql.Int, req.user!.tenantId).query('SELECT CategoryId, ParentCategoryId, Name FROM dbo.Categories WHERE TenantId = @TenantId'),
      pool.request().input('TenantId', sql.Int, req.user!.tenantId).query('SELECT BrandId, Name FROM dbo.Brands WHERE TenantId = @TenantId'),
      pool.request().input('TenantId', sql.Int, req.user!.tenantId).query('SELECT UnitId, Name, Symbol FROM dbo.Units WHERE TenantId = @TenantId'),
    ]);
    res.json({
      branches: branches.recordset,
      branchTypes: branchTypes.recordset,
      warehouses: warehouses.recordset,
      categories: categories.recordset,
      brands: brands.recordset,
      units: units.recordset,
    });
  } catch (error) {
    next(error);
  }
});

// Categories CRUD
referenceRouter.post('/categories', requireAuth, requirePermission('settings.manage'), async (req, res, next) => {
  try {
    const body = z.object({ name: z.string().min(2), parentCategoryId: z.number().nullable().optional() }).parse(req.body);
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('Name', sql.NVarChar(140), body.name)
      .input('ParentCategoryId', sql.Int, body.parentCategoryId ?? null)
      .query('INSERT INTO dbo.Categories (TenantId, Name, ParentCategoryId) OUTPUT INSERTED.* VALUES (@TenantId, @Name, @ParentCategoryId)');
    await audit(req, 'categories.create', 'Categories', String(result.recordset[0].CategoryId), body);
    res.status(201).json(result.recordset[0]);
  } catch (error) {
    next(error);
  }
});

referenceRouter.put('/categories/:id', requireAuth, requirePermission('settings.manage'), async (req, res, next) => {
  try {
    const body = z.object({ name: z.string().min(2), parentCategoryId: z.number().nullable().optional() }).parse(req.body);
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('CategoryId', sql.Int, req.params.id)
      .input('Name', sql.NVarChar(140), body.name)
      .input('ParentCategoryId', sql.Int, body.parentCategoryId ?? null)
      .query('UPDATE dbo.Categories SET Name = @Name, ParentCategoryId = @ParentCategoryId OUTPUT INSERTED.* WHERE TenantId = @TenantId AND CategoryId = @CategoryId');
    await audit(req, 'categories.update', 'Categories', String(req.params.id), body);
    res.json(result.recordset[0]);
  } catch (error) {
    next(error);
  }
});

// Brands CRUD
referenceRouter.post('/brands', requireAuth, requirePermission('settings.manage'), async (req, res, next) => {
  try {
    const body = z.object({ name: z.string().min(2) }).parse(req.body);
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('Name', sql.NVarChar(140), body.name)
      .query('INSERT INTO dbo.Brands (TenantId, Name) OUTPUT INSERTED.* VALUES (@TenantId, @Name)');
    await audit(req, 'brands.create', 'Brands', String(result.recordset[0].BrandId), body);
    res.status(201).json(result.recordset[0]);
  } catch (error) {
    next(error);
  }
});

// Units CRUD
referenceRouter.post('/units', requireAuth, requirePermission('settings.manage'), async (req, res, next) => {
  try {
    const body = z.object({ name: z.string().min(2), symbol: z.string().min(1) }).parse(req.body);
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('Name', sql.NVarChar(40), body.name)
      .input('Symbol', sql.NVarChar(20), body.symbol)
      .query('INSERT INTO dbo.Units (TenantId, Name, Symbol) OUTPUT INSERTED.* VALUES (@TenantId, @Name, @Symbol)');
    await audit(req, 'units.create', 'Units', String(result.recordset[0].UnitId), body);
    res.status(201).json(result.recordset[0]);
  } catch (error) {
    next(error);
  }
});

// Branches CRUD
referenceRouter.post('/branches', requireAuth, requirePermission('settings.manage'), async (req, res, next) => {
  try {
    const body = z.object({ name: z.string().min(2), code: z.string().min(2), branchTypeId: z.number().optional(), address: z.string().optional() }).parse(req.body);
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('Name', sql.NVarChar(160), body.name)
      .input('Code', sql.NVarChar(32), body.code)
      .input('BranchTypeId', sql.Int, body.branchTypeId ?? null)
      .input('Address', sql.NVarChar(500), body.address ?? null)
      .query('INSERT INTO dbo.Branches (TenantId, BranchTypeId, Name, Code, Address) OUTPUT INSERTED.* VALUES (@TenantId, @BranchTypeId, @Name, @Code, @Address)');
    await audit(req, 'branches.create', 'Branches', String(result.recordset[0].BranchId), body);
    res.status(201).json(result.recordset[0]);
  } catch (error) {
    next(error);
  }
});

referenceRouter.put('/branches/:id/type', requireAuth, requirePermission('settings.manage'), async (req, res, next) => {
  try {
    const body = z.object({ branchTypeCode: z.enum(['RETAIL', 'RESTAURANT']) }).parse(req.body);
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('BranchId', sql.Int, Number(req.params.id))
      .input('BranchTypeCode', sql.NVarChar(32), body.branchTypeCode)
      .query(`
        UPDATE b
        SET BranchTypeId = bt.BranchTypeId
        OUTPUT INSERTED.*
        FROM dbo.Branches b
        INNER JOIN dbo.BranchTypes bt ON bt.TenantId = b.TenantId AND bt.Code = @BranchTypeCode
        WHERE b.TenantId = @TenantId AND b.BranchId = @BranchId
      `);
    if (!result.recordset[0]) return res.status(404).json({ message: 'Branch or branch type not found' });
    await audit(req, 'branches.updateType', 'Branches', String(req.params.id), body);
    res.json(result.recordset[0]);
  } catch (error) {
    next(error);
  }
});

// Warehouses CRUD
referenceRouter.post('/warehouses', requireAuth, requirePermission('settings.manage'), async (req, res, next) => {
  try {
    const body = z.object({ branchId: z.number(), name: z.string().min(2), code: z.string().min(2) }).parse(req.body);
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('BranchId', sql.Int, body.branchId)
      .input('Name', sql.NVarChar(160), body.name)
      .input('Code', sql.NVarChar(32), body.code)
      .query('INSERT INTO dbo.Warehouses (TenantId, BranchId, Name, Code) OUTPUT INSERTED.* VALUES (@TenantId, @BranchId, @Name, @Code)');
    await audit(req, 'warehouses.create', 'Warehouses', String(result.recordset[0].WarehouseId), body);
    res.status(201).json(result.recordset[0]);
  } catch (error) {
    next(error);
  }
});
