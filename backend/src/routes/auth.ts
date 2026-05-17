import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { getPool, sql } from '../config/db.js';
import { signToken } from '../middleware/auth.js';

export const authRouter = Router();

authRouter.post('/login', async (req, res, next) => {
  try {
    const body = z.object({
      email: z.string().email(),
      password: z.string().min(1),
    }).parse(req.body);

    const pool = await getPool();
    const result = await pool.request()
      .input('Email', sql.NVarChar(180), body.email)
      .query(`
        SELECT TOP 1 u.UserId, u.TenantId, u.BranchId, u.FullName, u.Email, u.PasswordHash, r.Name RoleName, r.Permissions,
          b.Name BranchName, b.Code BranchCode, bt.Name BranchTypeName
        FROM dbo.Users u
        INNER JOIN dbo.Roles r ON r.RoleId = u.RoleId
        LEFT JOIN dbo.Branches b ON b.BranchId = u.BranchId
        LEFT JOIN dbo.BranchTypes bt ON bt.BranchTypeId = b.BranchTypeId
        WHERE u.Email = @Email AND u.IsActive = 1
      `);

    const user = result.recordset[0];
    if (!user || !(await bcrypt.compare(body.password, user.PasswordHash))) {
      return res.status(401).json({ message: 'Invalid email or password' });
    }

    await pool.request()
      .input('UserId', sql.Int, user.UserId)
      .query('UPDATE dbo.Users SET LastLoginAt = SYSUTCDATETIME() WHERE UserId = @UserId');

    const token = signToken({
      userId: user.UserId,
      tenantId: user.TenantId,
      branchId: user.BranchId,
      role: user.RoleName,
      permissions: JSON.parse(user.Permissions),
    });

    return res.json({
      token,
      user: { id: user.UserId, name: user.FullName, email: user.Email, role: user.RoleName, branchId: user.BranchId, branchName: user.BranchName, branchCode: user.BranchCode, branchType: user.BranchTypeName ?? 'Retail' },
    });
  } catch (error) {
    next(error);
  }
});

authRouter.post('/bootstrap-admin', async (req, res, next) => {
  try {
    const body = z.object({
      email: z.string().email(),
      password: z.string().min(10),
    }).parse(req.body);
    const hash = await bcrypt.hash(body.password, 12);
    const pool = await getPool();
    await pool.request()
      .input('Email', sql.NVarChar(180), body.email)
      .input('PasswordHash', sql.NVarChar(255), hash)
      .query('UPDATE dbo.Users SET PasswordHash = @PasswordHash WHERE Email = @Email');
    return res.json({ message: 'Admin password updated' });
  } catch (error) {
    next(error);
  }
});
