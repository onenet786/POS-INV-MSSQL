import dotenv from 'dotenv';
import { z } from 'zod';

dotenv.config();

const schema = z.object({
  NODE_ENV: z.string().default('development'),
  PORT: z.coerce.number().default(4100),
  HOST: z.string().default('0.0.0.0'),
  PUBLIC_API_URL: z.string().optional(),
  SQL_SERVER: z.string().default('localhost'),
  SQL_PORT: z.coerce.number().default(1433),
  SQL_DATABASE: z.string().default('PosInvMssql'),
  SQL_USER: z.string().default('sa'),
  SQL_PASSWORD: z.string(),
  JWT_SECRET: z.string().min(24),
  JWT_EXPIRES_IN: z.string().default('8h'),
  CORS_ORIGIN: z.string().default('*'),
});

export const env = schema.parse(process.env);
