/// جداول قاعدة البيانات المحلية - SQLite Schema
///
/// البنية:
/// - Core Entities: Products, Customers, Branches, Users
/// - Transactions: Invoices, PurchaseOrders, Expenses, StockTransfers
/// - Support: SyncMetadata, PendingChanges, ConflictLog
/// - Licensing: LicenseStatus
library;

const String createProductsTable = '''
CREATE TABLE IF NOT EXISTS products (
  id TEXT PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  category TEXT,
  unit TEXT,
  purchase_price REAL DEFAULT 0,
  selling_price REAL DEFAULT 0,
  quantity INTEGER DEFAULT 0,
  reorder_level INTEGER DEFAULT 10,
  supplier_id TEXT,
  is_active INTEGER DEFAULT 1,
  created_at TEXT,
  updated_at TEXT,
  synced INTEGER DEFAULT 0
);
''';

const String createCustomersTable = '''
CREATE TABLE IF NOT EXISTS customers (
  id TEXT PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  address TEXT,
  city TEXT,
  country TEXT,
  credit_limit REAL DEFAULT 0,
  credit_used REAL DEFAULT 0,
  tax_id TEXT,
  customer_type TEXT,
  is_active INTEGER DEFAULT 1,
  created_at TEXT,
  updated_at TEXT,
  synced INTEGER DEFAULT 0
);
''';

const String createBranchesTable = '''
CREATE TABLE IF NOT EXISTS branches (
  id TEXT PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  address TEXT,
  city TEXT,
  country TEXT,
  phone TEXT,
  email TEXT,
  manager_id TEXT,
  currency TEXT DEFAULT 'SAR',
  is_active INTEGER DEFAULT 1,
  created_at TEXT,
  updated_at TEXT
);
''';

const String createUsersTable = '''
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  email TEXT UNIQUE NOT NULL,
  full_name TEXT NOT NULL,
  role TEXT NOT NULL,
  branch_id TEXT,
  is_active INTEGER DEFAULT 1,
  last_login TEXT,
  created_at TEXT,
  updated_at TEXT
);
''';

const String createInvoicesTable = '''
CREATE TABLE IF NOT EXISTS invoices (
  id TEXT PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  customer_id TEXT NOT NULL,
  branch_id TEXT NOT NULL,
  invoice_date TEXT NOT NULL,
  due_date TEXT,
  total_amount REAL DEFAULT 0,
  discount_amount REAL DEFAULT 0,
  tax_amount REAL DEFAULT 0,
  net_amount REAL DEFAULT 0,
  payment_status TEXT DEFAULT 'PENDING',
  invoice_status TEXT DEFAULT 'DRAFT',
  notes TEXT,
  created_by TEXT,
  created_at TEXT,
  updated_at TEXT,
  synced INTEGER DEFAULT 0,
  FOREIGN KEY (customer_id) REFERENCES customers(id),
  FOREIGN KEY (branch_id) REFERENCES branches(id)
);
''';

const String createInvoiceItemsTable = '''
CREATE TABLE IF NOT EXISTS invoice_items (
  id TEXT PRIMARY KEY,
  invoice_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  quantity REAL NOT NULL,
  unit_price REAL NOT NULL,
  discount_percent REAL DEFAULT 0,
  line_total REAL DEFAULT 0,
  created_at TEXT,
  FOREIGN KEY (invoice_id) REFERENCES invoices(id),
  FOREIGN KEY (product_id) REFERENCES products(id)
);
''';

const String createPurchaseOrdersTable = '''
CREATE TABLE IF NOT EXISTS purchase_orders (
  id TEXT PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  supplier_id TEXT NOT NULL,
  branch_id TEXT NOT NULL,
  order_date TEXT NOT NULL,
  expected_date TEXT,
  total_amount REAL DEFAULT 0,
  tax_amount REAL DEFAULT 0,
  net_amount REAL DEFAULT 0,
  status TEXT DEFAULT 'DRAFT',
  notes TEXT,
  created_by TEXT,
  created_at TEXT,
  updated_at TEXT,
  synced INTEGER DEFAULT 0,
  FOREIGN KEY (supplier_id) REFERENCES customers(id),
  FOREIGN KEY (branch_id) REFERENCES branches(id)
);
''';

const String createPurchaseOrderItemsTable = '''
CREATE TABLE IF NOT EXISTS purchase_order_items (
  id TEXT PRIMARY KEY,
  po_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  quantity REAL NOT NULL,
  unit_price REAL NOT NULL,
  line_total REAL DEFAULT 0,
  received_qty REAL DEFAULT 0,
  created_at TEXT,
  FOREIGN KEY (po_id) REFERENCES purchase_orders(id),
  FOREIGN KEY (product_id) REFERENCES products(id)
);
''';

const String createExpensesTable = '''
CREATE TABLE IF NOT EXISTS expenses (
  id TEXT PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  branch_id TEXT NOT NULL,
  category TEXT NOT NULL,
  amount REAL NOT NULL,
  currency TEXT DEFAULT 'SAR',
  expense_date TEXT NOT NULL,
  payment_method TEXT,
  description TEXT,
  attachment_url TEXT,
  status TEXT DEFAULT 'PENDING',
  approved_by TEXT,
  created_by TEXT,
  created_at TEXT,
  updated_at TEXT,
  synced INTEGER DEFAULT 0,
  FOREIGN KEY (branch_id) REFERENCES branches(id)
);
''';

const String createStockTransfersTable = '''
CREATE TABLE IF NOT EXISTS stock_transfers (
  id TEXT PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  from_branch_id TEXT NOT NULL,
  to_branch_id TEXT NOT NULL,
  transfer_date TEXT NOT NULL,
  status TEXT DEFAULT 'PENDING',
  notes TEXT,
  created_by TEXT,
  created_at TEXT,
  updated_at TEXT,
  synced INTEGER DEFAULT 0,
  FOREIGN KEY (from_branch_id) REFERENCES branches(id),
  FOREIGN KEY (to_branch_id) REFERENCES branches(id)
);
''';

const String createStockTransferItemsTable = '''
CREATE TABLE IF NOT EXISTS stock_transfer_items (
  id TEXT PRIMARY KEY,
  transfer_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  quantity REAL NOT NULL,
  received_qty REAL DEFAULT 0,
  created_at TEXT,
  FOREIGN KEY (transfer_id) REFERENCES stock_transfers(id),
  FOREIGN KEY (product_id) REFERENCES products(id)
);
''';

// =============== Sync Tables ===============

const String createSyncMetadataTable = '''
CREATE TABLE IF NOT EXISTS sync_metadata (
  entity_type TEXT PRIMARY KEY,
  last_pull_time TEXT,
  last_push_time TEXT,
  pull_version INTEGER DEFAULT 0,
  push_version INTEGER DEFAULT 0,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
''';

const String createPendingChangesTable = '''
CREATE TABLE IF NOT EXISTS pending_changes (
  id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL,
  data TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  status TEXT DEFAULT 'PENDING',
  retry_count INTEGER DEFAULT 0,
  UNIQUE(entity_type, entity_id, operation)
);
''';

const String createConflictLogTable = '''
CREATE TABLE IF NOT EXISTS conflict_log (
  id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  local_version INTEGER,
  remote_version INTEGER,
  local_data TEXT,
  remote_data TEXT,
  resolution TEXT DEFAULT 'PENDING',
  strategy TEXT,
  resolved_data TEXT,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
''';

const String createLicenseStatusTable = '''
CREATE TABLE IF NOT EXISTS license_status (
  id TEXT PRIMARY KEY,
  license_key TEXT UNIQUE NOT NULL,
  status TEXT DEFAULT 'ACTIVE',
  expiry_date TEXT,
  modules TEXT,
  device_id TEXT,
  activated_at TEXT,
  last_check TEXT,
  created_at TEXT,
  updated_at TEXT
);
''';

/// جميع جداول الإنشاء
const List<String> allTables = [
  // Core Entities
  createBranchesTable,
  createUsersTable,
  createProductsTable,
  createCustomersTable,

  // Transactions
  createInvoicesTable,
  createInvoiceItemsTable,
  createPurchaseOrdersTable,
  createPurchaseOrderItemsTable,
  createExpensesTable,
  createStockTransfersTable,
  createStockTransferItemsTable,

  // Sync & Licensing
  createSyncMetadataTable,
  createPendingChangesTable,
  createConflictLogTable,
  createLicenseStatusTable,
];

/// الفهارس (Indexes) لتحسين الأداء
const List<String> createIndexes = [
  // Products
  'CREATE INDEX IF NOT EXISTS idx_products_code ON products(code);',
  'CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);',
  'CREATE INDEX IF NOT EXISTS idx_products_active ON products(is_active);',

  // Customers
  'CREATE INDEX IF NOT EXISTS idx_customers_code ON customers(code);',
  'CREATE INDEX IF NOT EXISTS idx_customers_email ON customers(email);',
  'CREATE INDEX IF NOT EXISTS idx_customers_active ON customers(is_active);',

  // Invoices
  'CREATE INDEX IF NOT EXISTS idx_invoices_code ON invoices(code);',
  'CREATE INDEX IF NOT EXISTS idx_invoices_customer ON invoices(customer_id);',
  'CREATE INDEX IF NOT EXISTS idx_invoices_date ON invoices(invoice_date);',
  'CREATE INDEX IF NOT EXISTS idx_invoices_status ON invoices(invoice_status);',

  // Invoice Items
  'CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice ON invoice_items(invoice_id);',
  'CREATE INDEX IF NOT EXISTS idx_invoice_items_product ON invoice_items(product_id);',

  // Purchase Orders
  'CREATE INDEX IF NOT EXISTS idx_po_code ON purchase_orders(code);',
  'CREATE INDEX IF NOT EXISTS idx_po_supplier ON purchase_orders(supplier_id);',
  'CREATE INDEX IF NOT EXISTS idx_po_date ON purchase_orders(order_date);',

  // Expenses
  'CREATE INDEX IF NOT EXISTS idx_expenses_branch ON expenses(branch_id);',
  'CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses(category);',
  'CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(expense_date);',

  // Sync
  'CREATE INDEX IF NOT EXISTS idx_pending_changes_entity ON pending_changes(entity_type, entity_id);',
  'CREATE INDEX IF NOT EXISTS idx_pending_changes_status ON pending_changes(status);',
  'CREATE INDEX IF NOT EXISTS idx_conflict_log_entity ON conflict_log(entity_type, entity_id);',
];
