export const openApiSpec = {
  openapi: '3.0.3',
  info: {
    title: 'POS Inventory MSSQL API',
    version: '1.0.0',
    description: 'REST API for enterprise inventory, POS, invoices, barcode/QR, reporting, and multi-branch workflows.',
  },
  servers: [{ url: 'http://localhost:4100/api' }],
  security: [{ bearerAuth: [] }],
  components: {
    securitySchemes: {
      bearerAuth: { type: 'http', scheme: 'bearer', bearerFormat: 'JWT' },
    },
  },
  paths: {
    '/auth/login': { post: { summary: 'Login and receive JWT' } },
    '/dashboard': { get: { summary: 'Dashboard summary, monthly sales, top products' } },
    '/products': { 
      get: { summary: 'Search products' }, 
      post: { summary: 'Create product' } 
    },
    '/products/{id}': {
      get: { summary: 'Get product details' },
      put: { summary: 'Update product' },
      delete: { summary: 'Delete product' }
    },
    '/products/{id}/qr': { get: { summary: 'Generate product QR code data URL' } },
    '/customers': {
      get: { summary: 'List customers' },
      post: { summary: 'Create customer' }
    },
    '/customers/{id}': {
      put: { summary: 'Update customer' },
      delete: { summary: 'Delete customer' }
    },
    '/suppliers': {
      get: { summary: 'List suppliers' },
      post: { summary: 'Create supplier' }
    },
    '/inventory/stock': { get: { summary: 'Warehouse stock balances' } },
    '/inventory/movement': { post: { summary: 'Record stock in/out/adjustment/damaged/return movement' } },
    '/invoices': { 
      get: { summary: 'List invoices' },
      post: { summary: 'Create sales invoice' } 
    },
    '/invoices/{id}': { get: { summary: 'Get invoice details' } },
    '/invoices/{id}/void': { post: { summary: 'Void an invoice and reverse stock' } },
    '/purchases': {
      get: { summary: 'List purchase orders' },
      post: { summary: 'Create purchase order' }
    },
    '/expenses': {
      get: { summary: 'List expenses' },
      post: { summary: 'Create expense' }
    },
    '/users': {
      get: { summary: 'List users' },
      post: { summary: 'Create user' }
    },
    '/users/{id}': { put: { summary: 'Update user' } },
    '/reports/sales': { get: { summary: 'Sales report' } },
    '/reports/inventory-valuation': { get: { summary: 'Inventory valuation report' } },
    '/reports/low-stock': { get: { summary: 'Low stock report' } },
    '/reference': { get: { summary: 'Branches, warehouses, categories, brands, units' } },
    '/reference/categories': { post: { summary: 'Create category' } },
    '/reference/brands': { post: { summary: 'Create brand' } },
    '/reference/units': { post: { summary: 'Create unit' } },
  },
};

