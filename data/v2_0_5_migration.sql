-- v2.0.5 Database Migration for SQLite
-- Converted from SQL Server syntax

-- Add column to invoices table
ALTER TABLE invoices ADD COLUMN direct_delivery_id TEXT;

-- Create customer_accounts table
CREATE TABLE customer_accounts (
    id TEXT PRIMARY KEY,
    customer_id TEXT NOT NULL,
    account_ledger_id TEXT,
    account_number TEXT NOT NULL,
    bank_name TEXT NOT NULL,
    iban TEXT NOT NULL,
    balance REAL NOT NULL DEFAULT 0,
    credit_limit REAL NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_active INTEGER NOT NULL DEFAULT 1,
    FOREIGN KEY (customer_id) REFERENCES app_users(id) ON DELETE CASCADE
);

-- Create customer_category_fields table
CREATE TABLE customer_category_fields (
    id TEXT PRIMARY KEY,
    category_id TEXT NOT NULL,
    field_name TEXT NOT NULL,
    field_label TEXT NOT NULL,
    field_type TEXT NOT NULL,
    is_required INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (category_id) REFERENCES customer_categories(id) ON DELETE CASCADE
);

-- Create direct_deliveries table
CREATE TABLE direct_deliveries (
    id TEXT PRIMARY KEY,
    purchase_id TEXT NOT NULL,
    customer_id TEXT,
    supplier_id TEXT,
    amount REAL NOT NULL DEFAULT 0,
    delivery_status TEXT NOT NULL DEFAULT 'pending',
    delivery_date DATETIME NOT NULL,
    received_date DATETIME,
    notes TEXT NOT NULL DEFAULT '',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create purchase_types table
CREATE TABLE purchase_types (
    id TEXT PRIMARY KEY,
    organization_id TEXT NOT NULL,
    type_name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    route TEXT NOT NULL DEFAULT '',
    is_active INTEGER NOT NULL DEFAULT 1,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
);

-- Create system_settings table
CREATE TABLE system_settings (
    id TEXT PRIMARY KEY,
    organization_id TEXT NOT NULL,
    setting_key TEXT NOT NULL,
    setting_value TEXT NOT NULL DEFAULT '',
    setting_type TEXT NOT NULL DEFAULT 'string',
    description TEXT NOT NULL DEFAULT '',
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
    UNIQUE(organization_id, setting_key)
);

-- Create customer_loans table
CREATE TABLE customer_loans (
    id TEXT PRIMARY KEY,
    customer_account_id TEXT NOT NULL,
    loan_amount REAL NOT NULL DEFAULT 0,
    paid_amount REAL NOT NULL DEFAULT 0,
    remaining_amount REAL NOT NULL DEFAULT 0,
    installment_count INTEGER NOT NULL DEFAULT 0,
    paid_installments INTEGER NOT NULL DEFAULT 0,
    monthly_installment REAL NOT NULL DEFAULT 0,
    interest_rate REAL NOT NULL DEFAULT 0,
    loan_date DATETIME NOT NULL,
    due_date DATETIME NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    notes TEXT NOT NULL DEFAULT '',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_account_id) REFERENCES customer_accounts(id) ON DELETE CASCADE
);

-- Create salary_records table
CREATE TABLE salary_records (
    id TEXT PRIMARY KEY,
    customer_account_id TEXT NOT NULL,
    year INTEGER NOT NULL,
    month INTEGER NOT NULL,
    basic_salary REAL NOT NULL DEFAULT 0,
    allowances REAL NOT NULL DEFAULT 0,
    deductions REAL NOT NULL DEFAULT 0,
    net_salary REAL NOT NULL DEFAULT 0,
    paid_amount REAL NOT NULL DEFAULT 0,
    payment_date DATETIME NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    notes TEXT NOT NULL DEFAULT '',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_account_id) REFERENCES customer_accounts(id) ON DELETE CASCADE
);

-- Create loan_payments table
CREATE TABLE loan_payments (
    id TEXT PRIMARY KEY,
    customer_loan_id TEXT NOT NULL,
    amount REAL NOT NULL DEFAULT 0,
    payment_date DATETIME NOT NULL,
    payment_method TEXT NOT NULL DEFAULT 'cash',
    reference TEXT NOT NULL DEFAULT '',
    notes TEXT NOT NULL DEFAULT '',
    FOREIGN KEY (customer_loan_id) REFERENCES customer_loans(id) ON DELETE CASCADE
);

-- Create salary_details table
CREATE TABLE salary_details (
    id TEXT PRIMARY KEY,
    salary_record_id TEXT NOT NULL,
    item_type TEXT NOT NULL,
    item_name TEXT NOT NULL,
    amount REAL NOT NULL DEFAULT 0,
    FOREIGN KEY (salary_record_id) REFERENCES salary_records(id) ON DELETE CASCADE
);

-- Create indexes
CREATE INDEX ix_invoices_direct_delivery_id ON invoices(direct_delivery_id);
CREATE INDEX ix_customer_accounts_account_ledger_id ON customer_accounts(account_ledger_id);
CREATE INDEX ix_customer_accounts_customer_id ON customer_accounts(customer_id);
CREATE INDEX ix_customer_category_fields_category_id ON customer_category_fields(category_id);
CREATE INDEX ix_customer_loans_customer_account_id ON customer_loans(customer_account_id);
CREATE INDEX ix_customer_loans_status ON customer_loans(status);
CREATE INDEX ix_direct_deliveries_customer_id ON direct_deliveries(customer_id);
CREATE INDEX ix_direct_deliveries_delivery_status ON direct_deliveries(delivery_status);
CREATE INDEX ix_direct_deliveries_purchase_id ON direct_deliveries(purchase_id);
CREATE INDEX ix_loan_payments_customer_loan_id ON loan_payments(customer_loan_id);
CREATE INDEX ix_loan_payments_payment_date ON loan_payments(payment_date);
CREATE INDEX ix_purchase_types_organization_id ON purchase_types(organization_id);
CREATE INDEX ix_salary_details_salary_record_id ON salary_details(salary_record_id);
CREATE INDEX ix_salary_records_customer_account_id ON salary_records(customer_account_id);
CREATE INDEX ix_salary_records_year_month ON salary_records(year, month);
CREATE UNIQUE INDEX ix_system_settings_organization_id_setting_key ON system_settings(organization_id, setting_key);

-- Migration applied successfully!
