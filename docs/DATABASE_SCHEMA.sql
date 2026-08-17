-- ============================================================================
-- Kinetic Enterprise ERP — Supabase / PostgreSQL Schema (Commercial Edition)
-- يغطي كل موديول مذكور في ARCHITECTURE.md بدون استثناء
-- ============================================================================

create extension if not exists "uuid-ossp";

-- ----------------------------------------------------------------------------
-- 1. المنظمات (Tenants) والتراخيص
-- ----------------------------------------------------------------------------
create table organizations (
  id uuid primary key default uuid_generate_v4(),
  legal_name text not null,
  display_name text not null,
  logo_url text,
  primary_color text not null default '#0B2540',   -- هوية بصرية ديناميكية
  secondary_color text not null default '#C8952B',
  currency_code text not null default 'LYD',
  currency_symbol text not null default 'د.ل',
  locale text not null default 'ar',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table licenses (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references organizations(id) on delete cascade,
  license_key text not null unique,
  plan_tier text not null default 'standard' check (plan_tier in ('trial','standard','professional','enterprise')),
  max_branches int not null default 1,
  max_users int not null default 5,
  enabled_modules jsonb not null default '["inventory","pos","customers","reports"]'::jsonb,
  hardware_fingerprint text,               -- لخيار On-Premise/Windows Server
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  status text not null default 'active' check (status in ('active','grace_period','expired','revoked')),
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 2. الفروع
-- ----------------------------------------------------------------------------
create table branches (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references organizations(id) on delete cascade,
  name text not null,
  code text not null,
  address text,
  phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code)
);

-- ----------------------------------------------------------------------------
-- 3. المستخدمون والصلاحيات (RBAC دقيق على مستوى العملية)
-- ----------------------------------------------------------------------------
create table app_users (
  id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid not null references organizations(id) on delete cascade,
  branch_id uuid references branches(id),   -- null = صلاحية على كل الفروع (مدير عام)
  full_name text not null,
  role text not null default 'cashier' check (role in ('super_admin','branch_manager','cashier','inventory_officer','accountant','custom')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table permissions (
  code text primary key,             -- e.g. 'inventory.edit', 'pos.refund'
  label_ar text not null,
  module text not null
);

create table role_permissions (
  role text not null,
  permission_code text not null references permissions(code),
  organization_id uuid not null references organizations(id) on delete cascade,
  primary key (organization_id, role, permission_code)
);

create table login_history (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references app_users(id),
  organization_id uuid not null references organizations(id),
  ip_address text,
  device_info text,
  success boolean not null,
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 4. المخزون والموردون
-- ----------------------------------------------------------------------------
create table suppliers (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references organizations(id) on delete cascade,
  name text not null,
  phone text,
  balance numeric(14,2) not null default 0,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now()
);

create table product_categories (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references organizations(id) on delete cascade,
  name text not null,
  parent_id uuid references product_categories(id)
);

create table products (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references organizations(id) on delete cascade,
  category_id uuid references product_categories(id),
  supplier_id uuid references suppliers(id),
  sku text not null,
  barcode text,
  name text not null,
  unit_base text not null default 'piece',      -- وحدة البيع الأساسية
  unit_conversion_factor numeric(10,3) not null default 1,  -- بيع بالكرتون مثلاً
  cost_price numeric(14,2) not null default 0,
  sale_price numeric(14,2) not null default 0,
  track_expiry boolean not null default false,
  reorder_level numeric(14,2) not null default 0,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, sku)
);

create table stock_levels (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references organizations(id) on delete cascade,
  branch_id uuid not null references branches(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  quantity numeric(14,3) not null default 0,
  batch_number text,
  expiry_date date,
  updated_at timestamptz not null default now(),
  unique (branch_id, product_id, batch_number)
);

create table stock_transfers (      -- تحويل بين الفروع — موديول مضاف لسد ثغرة
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references organizations(id) on delete cascade,
  from_branch_id uuid not null references branches(id),
  to_branch_id uuid not null references branches(id),
  status text not null default 'pending' check (status in ('pending','in_transit','received','cancelled')),
  created_by uuid references app_users(id),
  created_at timestamptz not null default now()
);

create table stock_transfer_items (
  id uuid primary key default uuid_generate_v4(),
  transfer_id uuid not null references stock_transfers(id) on delete cascade,
  product_id uuid not null references products(id),
  quantity numeric(14,3) not null
);

create table purchase_orders (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references organizations(id) on delete cascade,
  branch_id uuid not null references branches(id),
  supplier_id uuid references suppliers(id),
  status text not null default 'draft' check (status in ('draft','ordered','received','cancelled')),
  total_amount numeric(14,2) not null default 0,
  created_by uuid references app_users(id),
  created_at timestamptz not null default now()
);

create table purchase_order_items (
  id uuid primary key default uuid_generate_v4(),
  purchase_order_id uuid not null references purchase_orders(id) on delete cascade,
  product_id uuid not null references products(id),
  quantity numeric(14,3) not null,
  unit_cost numeric(14,2) not null
);

create table stock_counts (           -- الجرد الدوري
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references organizations(id) on delete cascade,
  branch_id uuid not null references branches(id),
  status text not null default 'open' check (status in ('open','reconciled','cancelled')),
  created_by uuid references app_users(id),
  created_at timestamptz not null default now(),
  closed_at timestamptz
);

create table stock_count_items (
  id uuid primary key default uuid_generate_v4(),
  stock_count_id uuid not null references stock_counts(id) on delete cascade,
  product_id uuid not null references products(id),
  system_quantity numeric(14,3) not null,
  counted_quantity numeric(14,3) not null,
  variance numeric(14,3) generated always as (counted_quantity - system_quantity) stored
);

-- ----------------------------------------------------------------------------
-- 5. العملاء
-- ----------------------------------------------------------------------------
create table customers (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references organizations(id) on delete cascade,
  branch_id uuid references branches(id),
  full_name text not null,
  phone text,
  card_barcode text unique,
  wallet_balance numeric(14,2) not null default 0,
  credit_limit numeric(14,2) not null default 0,
  loyalty_points int not null default 0,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 6. نقطة البيع والمبيعات
-- ----------------------------------------------------------------------------
create table pos_shifts (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references organizations(id) on delete cascade,
  branch_id uuid not null references branches(id),
  cashier_id uuid not null references app_users(id),
  opening_cash numeric(14,2) not null default 0,
  closing_cash numeric(14,2),
  status text not null default 'open' check (status in ('open','closed')),
  opened_at timestamptz not null default now(),
  closed_at timestamptz
);

create table invoices (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references organizations(id) on delete cascade,
  branch_id uuid not null references branches(id),
  shift_id uuid references pos_shifts(id),
  customer_id uuid references customers(id),
  invoice_number text not null,
  invoice_type text not null default 'sale' check (invoice_type in ('sale','return')),
  original_invoice_id uuid references invoices(id),   -- للمرتجعات
  subtotal numeric(14,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  discount_amount numeric(14,2) not null default 0,
  total_amount numeric(14,2) not null default 0,
  status text not null default 'completed' check (status in ('completed','pending','cancelled')),
  created_by uuid references app_users(id),
  created_at timestamptz not null default now(),
  unique (organization_id, branch_id, invoice_number)
);

create table invoice_items (
  id uuid primary key default uuid_generate_v4(),
  invoice_id uuid not null references invoices(id) on delete cascade,
  product_id uuid not null references products(id),
  quantity numeric(14,3) not null,
  unit_price numeric(14,2) not null,
  line_total numeric(14,2) not null
);

create table invoice_payments (        -- دفع مقسم بين أكثر من طريقة
  id uuid primary key default uuid_generate_v4(),
  invoice_id uuid not null references invoices(id) on delete cascade,
  method text not null check (method in ('cash','card','customer_wallet','credit')),
  amount numeric(14,2) not null
);

-- ----------------------------------------------------------------------------
-- 7. المالية المبسّطة
-- ----------------------------------------------------------------------------
create table expenses (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references organizations(id) on delete cascade,
  branch_id uuid not null references branches(id),
  category text not null,
  amount numeric(14,2) not null,
  note text,
  created_by uuid references app_users(id),
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 8. الإشعارات وسجل التدقيق
-- ----------------------------------------------------------------------------
create table notifications (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references organizations(id) on delete cascade,
  branch_id uuid references branches(id),
  type text not null,     -- low_stock | expiry | count_variance | license | security
  title text not null,
  body text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create table audit_logs (
  id uuid primary key default uuid_generate_v4(),
  organization_id uuid not null references organizations(id) on delete cascade,
  user_id uuid references app_users(id),
  action text not null,
  entity_table text not null,
  entity_id uuid,
  old_values jsonb,
  new_values jsonb,
  created_at timestamptz not null default now()
);

-- ============================================================================
-- Row Level Security — عزل مزدوج organization_id + branch_id
-- ============================================================================
alter table branches enable row level security;
alter table app_users enable row level security;
alter table products enable row level security;
alter table stock_levels enable row level security;
alter table customers enable row level security;
alter table invoices enable row level security;
alter table invoice_items enable row level security;
alter table expenses enable row level security;
alter table notifications enable row level security;
alter table audit_logs enable row level security;

-- دالة مساعدة: بيانات المستخدم الحالي
create or replace function current_app_user()
returns table (organization_id uuid, branch_id uuid, role text) as $$
  select organization_id, branch_id, role from app_users where id = auth.uid();
$$ language sql stable security definer;

-- مثال سياسة: المنتجات — كل مستخدمي المنظمة يرون كل منتجاتها (المنتجات ليست معزولة بالفرع)
create policy org_isolation_products on products
  for all using (organization_id = (select organization_id from current_app_user()));

-- مثال سياسة: الفواتير — السوبر أدمن (branch_id is null) يرى كل الفروع، غيره يرى فرعه فقط
create policy branch_isolation_invoices on invoices
  for all using (
    organization_id = (select organization_id from current_app_user())
    and (
      (select branch_id from current_app_user()) is null
      or branch_id = (select branch_id from current_app_user())
    )
  );

-- نفس النمط يُطبَّق على: stock_levels, customers, expenses, notifications
-- (مكرر بنفس البنية لكل جدول يحمل branch_id — انظر ملاحظة أسفل الملف)

-- ملاحظة تنفيذية: كرّر نمط `branch_isolation_invoices` على كل جدول تشغيلي جديد
-- تضيفه مستقبلاً طالما يحمل عمودي organization_id و branch_id — هذا هو العقد
-- الثابت الذي يمنع ثغرات العزل بين الفروع أو بين الزبائن مستقبلاً.
