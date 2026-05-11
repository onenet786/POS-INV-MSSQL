import http from 'node:http';
import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import swaggerUi from 'swagger-ui-express';
import { Server } from 'socket.io';
import { env } from './config/env.js';
import { closePool, getPool } from './config/db.js';
import { authRouter } from './routes/auth.js';
import { dashboardRouter } from './routes/dashboard.js';
import { inventoryRouter } from './routes/inventory.js';
import { invoicesRouter } from './routes/invoices.js';
import { productsRouter } from './routes/products.js';
import { customersRouter } from './routes/customers.js';
import { suppliersRouter } from './routes/suppliers.js';
import { purchasesRouter } from './routes/purchases.js';
import { expensesRouter } from './routes/expenses.js';
import { usersRouter } from './routes/users.js';
import { referenceRouter } from './routes/reference.js';
import { reportsRouter } from './routes/reports.js';
import { openApiSpec } from './openapi.js';

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: env.CORS_ORIGIN } });

app.use(helmet());
app.use(cors({ origin: env.CORS_ORIGIN === '*' ? true : env.CORS_ORIGIN }));
app.use(express.json({ limit: '10mb' }));

app.get('/health', (_req, res) => res.json({ status: 'ok', service: 'pos-inv-mssql-api' }));
app.use('/docs', swaggerUi.serve, swaggerUi.setup(openApiSpec));
app.use('/api/auth', authRouter);
app.use('/api/dashboard', dashboardRouter);
app.use('/api/products', productsRouter);
app.use('/api/customers', customersRouter);
app.use('/api/suppliers', suppliersRouter);
app.use('/api/purchases', purchasesRouter);
app.use('/api/expenses', expensesRouter);
app.use('/api/users', usersRouter);
app.use('/api/inventory', inventoryRouter);
app.use('/api/invoices', invoicesRouter);
app.use('/api/reports', reportsRouter);
app.use('/api/reference', referenceRouter);

io.on('connection', (socket) => {
  socket.emit('connected', { message: 'Realtime inventory channel ready' });
});

app.use((error: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  const message = error instanceof Error ? error.message : 'Unexpected server error';
  res.status(500).json({ message });
});

await getPool();
server.listen(env.PORT, () => {
  console.log(`API running on http://localhost:${env.PORT}`);
  console.log(`Swagger running on http://localhost:${env.PORT}/docs`);
});

let shuttingDown = false;

async function shutdown(signal: NodeJS.Signals) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`\n${signal} received. Closing API server...`);
  io.close();
  server.close(async () => {
    try {
      await closePool();
      console.log('API server stopped.');
      process.exit(0);
    } catch (error) {
      console.error('API shutdown failed:', error);
      process.exit(1);
    }
  });
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
