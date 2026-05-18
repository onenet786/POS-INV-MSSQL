import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { getPool, sql } from '../config/db.js';
import { requireAuth, requirePermission } from '../middleware/auth.js';
import { audit } from '../services/audit.js';

export const usersRouter = Router();

usersRouter.get('/', requireAuth, requirePermission('users.read'), async (req, res, next) => {
  try {
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .query(`
        SELECT u.UserId, u.FullName, u.Email, u.BranchId, u.IsActive, u.LastLoginAt,
          r.Name RoleName, b.Name BranchName, COALESCE(ubt.Name, bt.Name) BranchTypeName
        FROM dbo.Users u
        INNER JOIN dbo.Roles r ON r.RoleId = u.RoleId
        LEFT JOIN dbo.Branches b ON b.BranchId = u.BranchId
        LEFT JOIN dbo.BranchTypes bt ON bt.BranchTypeId = b.BranchTypeId
        LEFT JOIN dbo.BranchTypes ubt ON ubt.BranchTypeId = u.BranchTypeId
        WHERE u.TenantId = @TenantId
        ORDER BY u.FullName
      `);
    res.json(result.recordset);
  } catch (error) {
    next(error);
  }
});

usersRouter.post('/', requireAuth, requirePermission('users.create'), async (req, res, next) => {
  try {
    const body = z.object({
      fullName: z.string().min(2),
      email: z.string().email(),
      password: z.string().min(6),
      roleId: z.number(),
      branchId: z.number().nullable().optional(),
      branchTypeCode: z.enum(['RETAIL', 'RESTAURANT', 'HOTEL']).optional(),
    }).parse(req.body);

    const pool = await getPool();
    const hash = await bcrypt.hash(body.password, 12);
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('BranchId', sql.Int, body.branchId ?? null)
      .input('BranchTypeCode', sql.NVarChar(32), body.branchTypeCode ?? null)
      .input('RoleId', sql.Int, body.roleId)
      .input('FullName', sql.NVarChar(160), body.fullName)
      .input('Email', sql.NVarChar(180), body.email)
      .input('PasswordHash', sql.NVarChar(255), hash)
      .query(`
        DECLARE @BranchTypeId INT = (
          SELECT TOP 1 BranchTypeId
          FROM dbo.BranchTypes
          WHERE TenantId = @TenantId AND Code = @BranchTypeCode
        );

        INSERT INTO dbo.Users (TenantId, BranchId, BranchTypeId, RoleId, FullName, Email, PasswordHash)
        OUTPUT INSERTED.UserId, INSERTED.FullName, INSERTED.Email
        VALUES (@TenantId, @BranchId, @BranchTypeId, @RoleId, @FullName, @Email, @PasswordHash)
      `);
    await audit(req, 'users.create', 'Users', String(result.recordset[0].UserId), { email: body.email, fullName: body.fullName });
    res.json(result.recordset[0]);
  } catch (error) {
    next(error);
  }
});

usersRouter.put('/me/password', requireAuth, async (req, res, next) => {
  try {
    const body = z.object({
      currentPassword: z.string().min(1),
      newPassword: z.string().min(6),
    }).parse(req.body);

    const pool = await getPool();
    const current = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('UserId', sql.Int, req.user!.userId)
      .query('SELECT PasswordHash FROM dbo.Users WHERE TenantId = @TenantId AND UserId = @UserId AND IsActive = 1');

    const user = current.recordset[0];
    if (!user || !(await bcrypt.compare(body.currentPassword, user.PasswordHash))) {
      return res.status(400).json({ message: 'Current password is incorrect' });
    }

    const hash = await bcrypt.hash(body.newPassword, 12);
    await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('UserId', sql.Int, req.user!.userId)
      .input('PasswordHash', sql.NVarChar(255), hash)
      .query('UPDATE dbo.Users SET PasswordHash = @PasswordHash WHERE TenantId = @TenantId AND UserId = @UserId');

    await audit(req, 'users.password.change', 'Users', String(req.user!.userId));
    res.json({ message: 'Password changed successfully' });
  } catch (error) {
    next(error);
  }
});

usersRouter.put('/:id', requireAuth, requirePermission('users.update'), async (req, res, next) => {
  try {
    const body = z.object({
      fullName: z.string().min(2).optional(),
      roleId: z.number().optional(),
      branchId: z.number().nullable().optional(),
      branchTypeCode: z.enum(['RETAIL', 'RESTAURANT', 'HOTEL']).optional(),
      isActive: z.boolean().optional(),
    }).parse(req.body);

    const pool = await getPool();
    const existing = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('UserId', sql.Int, req.params.id)
      .query('SELECT BranchId FROM dbo.Users WHERE TenantId = @TenantId AND UserId = @UserId');
    if (!existing.recordset[0]) return res.status(404).json({ message: 'User not found' });
    const targetBranchId = body.branchId === undefined ? existing.recordset[0].BranchId : body.branchId;
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('UserId', sql.Int, req.params.id)
      .input('FullName', sql.NVarChar(160), body.fullName ?? null)
      .input('RoleId', sql.Int, body.roleId ?? null)
      .input('BranchId', sql.Int, targetBranchId ?? null)
      .input('BranchTypeCode', sql.NVarChar(32), body.branchTypeCode ?? null)
      .input('IsActive', sql.Bit, body.isActive ?? null)
      .query(`
        DECLARE @BranchTypeId INT = (
          SELECT TOP 1 BranchTypeId
          FROM dbo.BranchTypes
          WHERE TenantId = @TenantId AND Code = @BranchTypeCode
        );

        UPDATE dbo.Users
        SET FullName = ISNULL(@FullName, FullName),
            RoleId = ISNULL(@RoleId, RoleId),
            BranchId = @BranchId,
            BranchTypeId = ISNULL(@BranchTypeId, BranchTypeId),
            IsActive = ISNULL(@IsActive, IsActive)
        OUTPUT INSERTED.UserId, INSERTED.FullName, INSERTED.Email, INSERTED.IsActive
        WHERE TenantId = @TenantId AND UserId = @UserId
      `);
    if (result.rowsAffected[0] === 0) return res.status(404).json({ message: 'User not found' });
    await audit(req, 'users.update', 'Users', String(req.params.id), body);
    res.json(result.recordset[0]);
  } catch (error) {
    next(error);
  }
});

usersRouter.put('/:id/password', requireAuth, requirePermission('users.update'), async (req, res, next) => {
  try {
    const body = z.object({
      password: z.string().min(6),
    }).parse(req.body);

    const hash = await bcrypt.hash(body.password, 12);
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .input('UserId', sql.Int, req.params.id)
      .input('PasswordHash', sql.NVarChar(255), hash)
      .query('UPDATE dbo.Users SET PasswordHash = @PasswordHash WHERE TenantId = @TenantId AND UserId = @UserId');

    if (result.rowsAffected[0] === 0) return res.status(404).json({ message: 'User not found' });
    await audit(req, 'users.password.reset', 'Users', String(req.params.id));
    res.json({ message: 'Password reset successfully' });
  } catch (error) {
    next(error);
  }
});

usersRouter.get('/roles', requireAuth, async (req, res, next) => {
  try {
    const pool = await getPool();
    const result = await pool.request()
      .input('TenantId', sql.Int, req.user!.tenantId)
      .query('SELECT RoleId, Name, Permissions FROM dbo.Roles WHERE TenantId = @TenantId');
    res.json(result.recordset);
  } catch (error) {
    next(error);
  }
});
