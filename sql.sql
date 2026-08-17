-- ============================================================================
-- Kinetic Enterprise ERP — SQL Server Schema (نسخة .NET Backend)
-- تحويل كامل من DATABASE_SCHEMA.sql (Postgres) — نفس التغطية بدون نقصان
--
-- ⚠ الحد الأدنى المطلوب: SQL Server 2016 (13.x) فما فوق.
-- الموصى به فعلياً: SQL Server 2019 أو 2022 Express (مجاني، ومدعوم أمنياً
-- من مايكروسوفت حتى 2025/2028 على التوالي، بخلاف 2008 المتوقف دعمه منذ 2019).
-- السبب: SESSION_CONTEXT وCREATE SECURITY POLICY (المستخدَمان في نظام
-- العزل بين الفروع والزبائن أسفل هذا الملف) وISJSON غير متوفرة قبل 2016.
-- ============================================================================

CREATE DATABASE KineticEnterprise;
GO
USE KineticEnterprise;
GO

-- ضبط صريح لمستوى التوافق (150 = محرك 2019، 160 = محرك 2022) — غير
-- إلزامي لعمل SESSION_CONTEXT/Security Policy (يعتمدان على إصدار المحرك
-- نفسه لا على مستوى التوافق)، لكنه ممارسة سليمة لضمان استخدام أحدث
-- سلوك لمُحسِّن الاستعلامات المتاح فعلياً على السيرفر المُثبَّت.
-- عدّل الرقم إلى 160 إذا كان المحرك المثبَّت 2022.
ALTER DATABASE KineticEnterprise SET COMPATIBILITY_LEVEL = 150;
GO

-- ----------------------------------------------------------------------------
-- 1. المنظمات (Tenants) والتراخيص
-- ----------------------------------------------------------------------------
CREATE TABLE organizations (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  legal_name NVARCHAR(200) NOT NULL,
  display_name NVARCHAR(200) NOT NULL,
  logo_url NVARCHAR(400) NULL,
  primary_color CHAR(7) NOT NULL DEFAULT '#0B2540',
  secondary_color CHAR(7) NOT NULL DEFAULT '#C8952B',
  currency_code CHAR(3) NOT NULL DEFAULT 'LYD',
  currency_symbol NVARCHAR(10) NOT NULL DEFAULT N'د.ل',
  locale NVARCHAR(5) NOT NULL DEFAULT 'ar',
  tax_rate DECIMAL(5,2) NOT NULL DEFAULT 0,
  password_min_length INT NOT NULL DEFAULT 6,
  barcode_template NVARCHAR(MAX) NOT NULL
    DEFAULT N'{"widthMm":40,"heightMm":25,"showName":true,"showPrice":true,"showSku":false}',
  receipt_width_mm DECIMAL(5,2) NOT NULL DEFAULT 80,
  nav_layout NVARCHAR(20) NOT NULL DEFAULT 'sidebar'
    CHECK (nav_layout IN ('sidebar','navbar')),
  is_active BIT NOT NULL DEFAULT 1,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  updated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE licenses (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  license_key NVARCHAR(100) NOT NULL UNIQUE,
  plan_tier NVARCHAR(20) NOT NULL DEFAULT 'standard'
    CHECK (plan_tier IN ('trial','standard','professional','enterprise')),
  max_branches INT NOT NULL DEFAULT 1,
  max_users INT NOT NULL DEFAULT 5,
  enabled_modules NVARCHAR(MAX) NOT NULL DEFAULT N'["inventory","pos","customers","reports"]', -- JSON
  hardware_fingerprint NVARCHAR(200) NULL,
  issued_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  expires_at DATETIME2 NOT NULL,
  status NVARCHAR(20) NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','grace_period','expired','revoked')),
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT CK_licenses_modules_json CHECK (ISJSON(enabled_modules) = 1)
);
GO

CREATE TABLE platform_settings (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  company_name NVARCHAR(200) NOT NULL DEFAULT N'',
  owner_name NVARCHAR(150) NOT NULL DEFAULT N'',
  phone NVARCHAR(30) NULL,
  whatsapp NVARCHAR(30) NULL,
  email NVARCHAR(200) NULL,
  address NVARCHAR(300) NULL,
  updated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- ----------------------------------------------------------------------------
-- 2. الفروع
-- ----------------------------------------------------------------------------
CREATE TABLE branches (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name NVARCHAR(150) NOT NULL,
  code NVARCHAR(20) NOT NULL,
  address NVARCHAR(300) NULL,
  phone NVARCHAR(30) NULL,
  is_active BIT NOT NULL DEFAULT 1,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  updated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT UQ_branches_org_code UNIQUE (organization_id, code)
);
GO

-- ----------------------------------------------------------------------------
-- 3. المستخدمون والصلاحيات
-- ----------------------------------------------------------------------------
CREATE TABLE app_users (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),      -- يقابل AspNetUsers.Id
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NULL REFERENCES branches(id),  -- NULL = صلاحية على كل الفروع
  full_name NVARCHAR(150) NOT NULL,
  email NVARCHAR(200) NOT NULL,
  username NVARCHAR(50) NULL,
  password_hash NVARCHAR(400) NOT NULL,   -- أو FK إلى AspNetUsers إذا استُخدم Identity كاملاً
  role NVARCHAR(30) NOT NULL DEFAULT 'cashier'
    CHECK (role IN ('super_admin','branch_manager','cashier','inventory_officer','accountant','custom')),
  is_active BIT NOT NULL DEFAULT 1,
  is_platform_admin BIT NOT NULL DEFAULT 0,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT UQ_app_users_org_email UNIQUE (organization_id, email)
);
GO

CREATE UNIQUE INDEX UQ_app_users_org_username ON app_users (organization_id, username)
  WHERE username IS NOT NULL;
GO

CREATE TABLE platform_organizations (
  id UNIQUEIDENTIFIER PRIMARY KEY,
  legal_name NVARCHAR(200) NOT NULL,
  display_name NVARCHAR(200) NOT NULL,
  is_active BIT NOT NULL DEFAULT 1,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE permissions (
  code NVARCHAR(60) PRIMARY KEY,
  label_ar NVARCHAR(150) NOT NULL,
  module NVARCHAR(60) NOT NULL
);
GO

CREATE TABLE role_permissions (
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  role NVARCHAR(30) NOT NULL,
  permission_code NVARCHAR(60) NOT NULL REFERENCES permissions(code),
  CONSTRAINT PK_role_permissions PRIMARY KEY (organization_id, role, permission_code)
);
GO

CREATE TABLE login_history (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  user_id UNIQUEIDENTIFIER NOT NULL REFERENCES app_users(id),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id),
  ip_address NVARCHAR(50) NULL,
  device_info NVARCHAR(300) NULL,
  success BIT NOT NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- ----------------------------------------------------------------------------
-- 4. المخزون والموردون
-- ----------------------------------------------------------------------------
CREATE TABLE suppliers (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name NVARCHAR(150) NOT NULL,
  phone NVARCHAR(30) NULL,
  balance DECIMAL(14,2) NOT NULL DEFAULT 0,
  is_deleted BIT NOT NULL DEFAULT 0,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE product_categories (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name NVARCHAR(150) NOT NULL,
  parent_id UNIQUEIDENTIFIER NULL REFERENCES product_categories(id)
);
GO

CREATE TABLE products (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  category_id UNIQUEIDENTIFIER NULL REFERENCES product_categories(id),
  supplier_id UNIQUEIDENTIFIER NULL REFERENCES suppliers(id),
  sku NVARCHAR(60) NOT NULL,
  barcode NVARCHAR(60) NULL,
  name NVARCHAR(200) NOT NULL,
  unit_base NVARCHAR(30) NOT NULL DEFAULT 'piece',
  unit_conversion_factor DECIMAL(10,3) NOT NULL DEFAULT 1,
  cost_price DECIMAL(14,2) NOT NULL DEFAULT 0,
  sale_price DECIMAL(14,2) NOT NULL DEFAULT 0,
  track_expiry BIT NOT NULL DEFAULT 0,
  tracks_stock BIT NOT NULL DEFAULT 1,
  reorder_level DECIMAL(14,2) NOT NULL DEFAULT 0,
  is_deleted BIT NOT NULL DEFAULT 0,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  updated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT UQ_products_org_sku UNIQUE (organization_id, sku)
);
GO

CREATE TABLE stock_levels (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  -- branch_id وproduct_id بدون CASCADE عمداً: كلاهما يصل لجدول organizations
  -- عبر مسار آخر (branches->organizations وproducts->organizations)،
  -- فلو أضفنا CASCADE هنا أيضاً سيصبح لدى SQL Server أكثر من مسار حذف
  -- متتالٍ لنفس الجدول الجذري، وهذا مرفوض دائماً بغض النظر عن الإصدار.
  -- عملياً هذا متوافق مع مبدأ "لا حذف فعلي" أصلاً (راجع DATABASE_TABLES_GUIDE.md §1.4).
  branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id) ON DELETE NO ACTION,
  product_id UNIQUEIDENTIFIER NOT NULL REFERENCES products(id) ON DELETE NO ACTION,
  quantity DECIMAL(14,3) NOT NULL DEFAULT 0,
  batch_number NVARCHAR(60) NOT NULL DEFAULT '',
  expiry_date DATE NULL,
  updated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT UQ_stock_levels UNIQUE (branch_id, product_id, batch_number)
);
GO

CREATE TABLE stock_transfers (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  from_branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id),
  to_branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id),
  status NVARCHAR(20) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','in_transit','received','cancelled')),
  created_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE stock_transfer_items (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  transfer_id UNIQUEIDENTIFIER NOT NULL REFERENCES stock_transfers(id) ON DELETE CASCADE,
  product_id UNIQUEIDENTIFIER NOT NULL REFERENCES products(id),
  quantity DECIMAL(14,3) NOT NULL
);
GO

CREATE TABLE purchase_orders (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id),
  supplier_id UNIQUEIDENTIFIER NULL REFERENCES suppliers(id),
  status NVARCHAR(20) NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','ordered','received','cancelled')),
  total_amount DECIMAL(14,2) NOT NULL DEFAULT 0,
  created_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE purchase_order_items (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  purchase_order_id UNIQUEIDENTIFIER NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
  product_id UNIQUEIDENTIFIER NOT NULL REFERENCES products(id),
  quantity DECIMAL(14,3) NOT NULL,
  unit_cost DECIMAL(14,2) NOT NULL,
  sale_price DECIMAL(14,2) NULL
);
GO

CREATE TABLE stock_counts (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id),
  status NVARCHAR(20) NOT NULL DEFAULT 'open'
    CHECK (status IN ('open','reconciled','cancelled')),
  created_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  closed_at DATETIME2 NULL
);
GO

CREATE TABLE stock_count_items (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  stock_count_id UNIQUEIDENTIFIER NOT NULL REFERENCES stock_counts(id) ON DELETE CASCADE,
  product_id UNIQUEIDENTIFIER NOT NULL REFERENCES products(id),
  system_quantity DECIMAL(14,3) NOT NULL,
  counted_quantity DECIMAL(14,3) NOT NULL,
  variance AS (counted_quantity - system_quantity) PERSISTED
);
GO

-- ----------------------------------------------------------------------------
-- 5. العملاء
-- ----------------------------------------------------------------------------
-- ----------------------------------------------------------------------------
-- الجهات الممولة لأرصدة العملاء (شركة لموظفيها، جمعية، مدرسة) — الطرف الذي
-- تُحاسبه المنشأة في نموذج الاستحقاق الممنوح، لا المستفيد نفسه.
-- لا تحمل branch_id: الجهة تتعامل مع المنظمة ككل، بنفس مبرر suppliers.
-- ----------------------------------------------------------------------------
CREATE TABLE sponsors (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name NVARCHAR(150) NOT NULL,
  phone NVARCHAR(30) NULL,
  notes NVARCHAR(500) NULL,
  is_deleted BIT NOT NULL DEFAULT 0,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE customers (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NULL REFERENCES branches(id),
  full_name NVARCHAR(150) NOT NULL,
  phone NVARCHAR(30) NULL,
  email NVARCHAR(200) NULL,
  notes NVARCHAR(500) NULL,
  card_barcode NVARCHAR(60) NULL,
  credit_limit DECIMAL(14,2) NOT NULL DEFAULT 0,
  -- ---- نموذج الحساب ----
  -- prepaid: رصيد دفعه العميل من ماله — لا يسقط ولا سقف له (إسقاط مال دفعه
  --          صاحبه مصادرة له).
  -- entitlement: استحقاق منحته جهة ثالثة بسقف وفترة — ما لا يُصرف يسقط،
  --          والمحاسبة مع الجهة الممولة. راجع AccountModels في Entities.cs.
  account_model NVARCHAR(20) NOT NULL DEFAULT 'prepaid'
    CHECK (account_model IN ('prepaid','entitlement')),
  sponsor_id UNIQUEIDENTIFIER NULL REFERENCES sponsors(id),
  entitlement_ceiling DECIMAL(18,3) NOT NULL DEFAULT 0,
  entitlement_expires_on DATE NULL,

  loyalty_points INT NOT NULL DEFAULT 0,
  is_deleted BIT NOT NULL DEFAULT 0,
  pin_hash NVARCHAR(400) NULL,
  pin_locked_until DATETIME2 NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- فهرس بطاقات العملاء — معفى من RLS (الدخول يسبق وجود SESSION_CONTEXT).
CREATE TABLE customer_card_index (
  card_code NVARCHAR(12) NOT NULL PRIMARY KEY,
  customer_id UNIQUEIDENTIFIER NOT NULL REFERENCES customers(id),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  issued_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  state NVARCHAR(20) NOT NULL DEFAULT 'active'
    CHECK (state IN ('active','blocked','expired')),
  expiry_date DATE NULL,
  issued_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  blocked_reason NVARCHAR(200) NULL,
  holder_name NVARCHAR(150) NULL
);
GO

CREATE UNIQUE INDEX UQ_customer_card_index_customer ON customer_card_index (customer_id);
GO

CREATE TABLE customer_pin_attempts (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  customer_id UNIQUEIDENTIFIER NOT NULL REFERENCES customers(id),
  success BIT NOT NULL,
  ip_address NVARCHAR(60) NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE INDEX IX_customer_pin_attempts_customer ON customer_pin_attempts (customer_id, created_at);
GO

-- ----------------------------------------------------------------------------
-- 6. نقطة البيع والمبيعات
-- ----------------------------------------------------------------------------
CREATE TABLE pos_shifts (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id),
  cashier_id UNIQUEIDENTIFIER NOT NULL REFERENCES app_users(id),
  opening_cash DECIMAL(14,2) NOT NULL DEFAULT 0,
  closing_cash DECIMAL(14,2) NULL,
  status NVARCHAR(10) NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed')),
  opened_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  closed_at DATETIME2 NULL
);
GO

CREATE TABLE invoices (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id),
  shift_id UNIQUEIDENTIFIER NULL REFERENCES pos_shifts(id),
  customer_id UNIQUEIDENTIFIER NULL REFERENCES customers(id),
  invoice_number NVARCHAR(40) NOT NULL,
  invoice_type NVARCHAR(10) NOT NULL DEFAULT 'sale' CHECK (invoice_type IN ('sale','return')),
  original_invoice_id UNIQUEIDENTIFIER NULL REFERENCES invoices(id),
  subtotal DECIMAL(14,2) NOT NULL DEFAULT 0,
  tax_amount DECIMAL(14,2) NOT NULL DEFAULT 0,
  discount_amount DECIMAL(14,2) NOT NULL DEFAULT 0,
  total_amount DECIMAL(14,2) NOT NULL DEFAULT 0,
  status NVARCHAR(15) NOT NULL DEFAULT 'completed' CHECK (status IN ('completed','pending','cancelled','refunded')),
  created_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT UQ_invoices_number UNIQUE (organization_id, branch_id, invoice_number)
);
GO

CREATE TABLE invoice_items (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  invoice_id UNIQUEIDENTIFIER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  product_id UNIQUEIDENTIFIER NOT NULL REFERENCES products(id),
  quantity DECIMAL(14,3) NOT NULL,
  unit_price DECIMAL(14,2) NOT NULL,
  line_total DECIMAL(14,2) NOT NULL
);
GO

CREATE TABLE invoice_payments (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  invoice_id UNIQUEIDENTIFIER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  method NVARCHAR(20) NOT NULL CHECK (method IN ('cash','card','customer_wallet','credit')),
  amount DECIMAL(14,2) NOT NULL
);
GO

-- دفتر حركات محفظة العميل — الرصيد مجموعه، ولا يوجد عمود رصيد قابل للكتابة.
CREATE TABLE customer_wallet_transactions (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  customer_id UNIQUEIDENTIFIER NOT NULL REFERENCES customers(id),
  invoice_id UNIQUEIDENTIFIER NULL REFERENCES invoices(id),
  kind NVARCHAR(20) NOT NULL
    CHECK (kind IN ('topup','spend','invoice_refund','adjustment_in','adjustment_out',
                    'entitlement_grant','entitlement_expiry')),
  amount DECIMAL(18,3) NOT NULL CHECK (amount > 0),
  note NVARCHAR(300) NULL,
  created_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE INDEX IX_customer_wallet_transactions_customer
  ON customer_wallet_transactions (customer_id) INCLUDE (kind, amount);
GO

-- ----------------------------------------------------------------------------
-- 7. المالية المبسّطة
-- ----------------------------------------------------------------------------
CREATE TABLE expenses (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id),
  category NVARCHAR(80) NOT NULL,
  amount DECIMAL(14,2) NOT NULL,
  note NVARCHAR(300) NULL,
  created_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- ----------------------------------------------------------------------------
-- 8. الإشعارات وسجل التدقيق
-- ----------------------------------------------------------------------------
CREATE TABLE notifications (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NULL REFERENCES branches(id),
  type NVARCHAR(30) NOT NULL,   -- low_stock | expiry | count_variance | license | security
  title NVARCHAR(200) NOT NULL,
  body NVARCHAR(500) NULL,
  is_read BIT NOT NULL DEFAULT 0,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE audit_logs (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  action NVARCHAR(80) NOT NULL,
  entity_table NVARCHAR(80) NOT NULL,
  entity_id UNIQUEIDENTIFIER NULL,
  old_values NVARCHAR(MAX) NULL,   -- JSON
  new_values NVARCHAR(MAX) NULL,   -- JSON
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- ============================================================================
-- Row-Level Security — بديل SQL Server لعزل organization_id + branch_id
-- يعتمد على SESSION_CONTEXT الذي يضبطه الـ .NET Backend في بداية كل اتصال
-- (انظر Middleware/TenantContextMiddleware.cs في مشروع الـ Backend)
-- ============================================================================

CREATE SCHEMA Security;
GO

-- دالة الحماية العامة: تقارن organization_id دائماً، وbranch_id فقط إن لم
-- يكن المستخدم مديراً عاماً (branch_id = NULL في السياق يعني "كل الفروع").
CREATE FUNCTION Security.fn_TenantPredicate(@OrgId UNIQUEIDENTIFIER, @BranchId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE @OrgId = CAST(SESSION_CONTEXT(N'organization_id') AS UNIQUEIDENTIFIER)
  AND (
    SESSION_CONTEXT(N'branch_id') IS NULL
    OR @BranchId = CAST(SESSION_CONTEXT(N'branch_id') AS UNIQUEIDENTIFIER)
  );
GO

-- تطبَّق على كل جدول يحمل organization_id + branch_id.
-- (الجداول التي على مستوى المنظمة فقط، مثل organizations وproducts، تُفلتر
-- بدالة أبسط تعتمد على organization_id فقط — انظر fn_OrgOnlyPredicate أسفله)

CREATE SECURITY POLICY Security.InvoicesPolicy
  ADD FILTER PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.invoices,
  ADD BLOCK PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.invoices AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.StockLevelsPolicy
  ADD FILTER PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.stock_levels,
  ADD BLOCK PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.stock_levels AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.ExpensesPolicy
  ADD FILTER PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.expenses,
  ADD BLOCK PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.expenses AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.StockCountsPolicy
  ADD FILTER PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.stock_counts,
  ADD BLOCK PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.stock_counts AFTER INSERT
  WITH (STATE = ON);
GO

-- جداول على مستوى المنظمة فقط (لا branch_id) — عزل بـ organization_id فقط
CREATE FUNCTION Security.fn_OrgOnlyPredicate(@OrgId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE @OrgId = CAST(SESSION_CONTEXT(N'organization_id') AS UNIQUEIDENTIFIER);
GO

CREATE SECURITY POLICY Security.ProductsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.products,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.products AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.CustomersPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.customers,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.customers AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.CustomerWalletTransactionsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.customer_wallet_transactions,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.customer_wallet_transactions AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.SuppliersPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.suppliers,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.suppliers AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.ProductCategoriesPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.product_categories,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.product_categories AFTER INSERT
  WITH (STATE = ON);
GO

-- notifications.branch_id وصفي فقط (NULL = تنبيه على مستوى المنظمة كلها)
-- وليس عزلاً أمنياً — نفس معاملة customers.branch_id، فالفلترة حسب الفرع
-- تتم في NotificationsController نفسه وليس عبر fn_TenantPredicate.
CREATE SECURITY POLICY Security.NotificationsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.notifications,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.notifications AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.AuditLogsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.audit_logs,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.audit_logs AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.BranchesPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.branches,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.branches AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.OrganizationsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(id) ON dbo.organizations,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(id) ON dbo.organizations AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.LicensesPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.licenses,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.licenses AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.StockTransfersPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.stock_transfers,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.stock_transfers AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.RolePermissionsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.role_permissions,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.role_permissions AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.PurchaseOrdersPolicy
  ADD FILTER PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.purchase_orders,
  ADD BLOCK PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.purchase_orders AFTER INSERT
  WITH (STATE = ON);
GO

-- ملاحظة تنفيذية ثابتة: أي جدول تشغيلي جديد يُضاف مستقبلاً يجب أن يُنشأ له
-- Security Policy بنفس النمط أعلاه (fn_TenantPredicate إن كان يحمل branch_id،
-- أو fn_OrgOnlyPredicate إن كان على مستوى المنظمة فقط) — هذا هو العقد
-- الثابت الذي يمنع ثغرة عزل بيانات بين الفروع أو بين الزبائن مستقبلاً.

-- ============================================================================
-- سياسة عزل الجهات الممولة — نفس نمط suppliers (المنظمة ككل لا الفرع)
-- ============================================================================
CREATE SECURITY POLICY Security.SponsorsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.sponsors,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.sponsors AFTER INSERT
  WITH (STATE = ON);
GO

-- ============================================================================
-- الفهارس
--
-- كل فهرس هنا يقابل استعلاماً فعلياً في الكود لا تخميناً: فهرس زائد يبطئ
-- الكتابة ويستهلك مساحة بلا مقابل. النسخة الكاملة مع تعليق كل فهرس واستعلامه
-- في backend/KineticEnterprise.Api/migrate_entitlement.sql.
--
-- SET إلزامي: sqlcmd يعمل افتراضياً بـ QUOTED_IDENTIFIER OFF والفهارس
-- المُصفّاة ترفض ذلك.
-- ============================================================================
SET QUOTED_IDENTIFIER ON;
GO

-- بديل قيد UNIQUE العادي: يسمح بعملاء كثيرين بلا بطاقة، ويمنع تكرار الرمز.
CREATE UNIQUE INDEX UX_customers_card_barcode ON customers (card_barcode) WHERE card_barcode IS NOT NULL;
CREATE INDEX IX_customers_org_name ON customers (organization_id, full_name) WHERE is_deleted = 0;
CREATE INDEX IX_customers_card_barcode ON customers (card_barcode) WHERE card_barcode IS NOT NULL;
CREATE INDEX IX_customers_sponsor ON customers (sponsor_id) WHERE sponsor_id IS NOT NULL;
CREATE INDEX IX_customers_entitlement_expiry ON customers (entitlement_expires_on) WHERE entitlement_expires_on IS NOT NULL;
CREATE INDEX IX_wallet_tx_customer_created ON customer_wallet_transactions (customer_id, created_at) INCLUDE (kind, amount);
CREATE INDEX IX_pin_attempts_customer_created ON customer_pin_attempts (customer_id, created_at) INCLUDE (success);
CREATE INDEX IX_products_org_name ON products (organization_id, name) WHERE is_deleted = 0;
CREATE INDEX IX_products_barcode ON products (barcode) WHERE barcode IS NOT NULL;
CREATE INDEX IX_invoices_branch_created ON invoices (branch_id, created_at);
CREATE INDEX IX_stock_levels_branch_product ON stock_levels (branch_id, product_id);
CREATE INDEX IX_audit_logs_org_created ON audit_logs (organization_id, created_at DESC);
GO
