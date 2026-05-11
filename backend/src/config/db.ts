import sql from 'mssql';
import { env } from './env.js';

const config: sql.config = {
  server: env.SQL_SERVER,
  port: env.SQL_PORT,
  database: env.SQL_DATABASE,
  user: env.SQL_USER,
  password: env.SQL_PASSWORD,
  options: {
    encrypt: true,
    trustServerCertificate: env.NODE_ENV !== 'production',
  },
  pool: {
    max: 25,
    min: 0,
    idleTimeoutMillis: 30000,
  },
};

let pool: sql.ConnectionPool | null = null;

export async function getPool() {
  if (pool?.connected) return pool;
  pool = await sql.connect(config);
  return pool;
}

export async function closePool() {
  if (!pool) return;
  await pool.close();
  pool = null;
}

export { sql };
