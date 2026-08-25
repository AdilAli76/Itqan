-- ============================================================================
--  Kinetic Enterprise — فهارس الأداء
--
--  آمن للتنفيذ على قاعدة بيانات تعمل بالفعل: كل فهرس محمي بـ IF NOT EXISTS،
--  فتنفيذ الملف مرتين لا يسبب خطأ، ولا يُعاد بناء فهرس موجود.
--
--  الأساس الذي بُنيت عليه هذه الفهارس — وليس تخميناً:
--
--  ١. سياسة الأمان (Security.fn_TenantPredicate و fn_OrgOnlyPredicate) تضيف
--     `organization_id = SESSION_CONTEXT(...)` — و`branch_id` للجداول على
--     مستوى الفرع — إلى كل استعلام على الجداول المحمية، حتى لو لم يذكرها كود
--     C# إطلاقاً. لذلك تقود هذه الفهارس بـ organization_id: هو الشرط الأكثر
--     تكراراً في النظام كله ولا يظهر في أي سطر من الكود.
--
--  ٢. SQL Server لا يُنشئ فهرساً للمفاتيح الأجنبية تلقائياً (بخلاف المفتاح
--     الأساسي). في المخطط 66 عمود مفتاح أجنبي، وكان 10 منها فقط مغطى. ومع
--     ON DELETE CASCADE غير المفهرس يصبح حذف صف أب مسحاً كاملاً للجدول الابن.
--
--  ٣. كل فهرس أدناه مربوط بالاستعلام الذي يخدمه، بالملف والسطر.
--
--  التنفيذ:  sqlcmd -S .\SQLEXPRESS -d KineticEnterprise -i docs\INDEXES.sql
-- ============================================================================

-- لا USE هنا عمداً: هذا الملف يُنفَّذ بـ -d (راجع سطر التنفيذ أعلاه)، وسطر
-- USE ثابت كان يتجاوز الاسم المُمرَّر فيكتب الكائنات في KineticEnterprise
-- مهما كانت القاعدة المقصودة — وهو ما كان يُعطّل tool/run_local.ps1 -Database
-- ويجعله يلوّث قاعدة التطوير بدل قاعدة التجربة.

-- إلزامي: كثير من الفهارس أدناه **مفلترة** (WHERE ...)، و SQL Server يرفض
-- إنشاءها إن كان QUOTED_IDENTIFIER مطفأً — برسالة تتحدث عن "indexed views"
-- ولا تذكر السبب الحقيقي. عميل sqlcmd القديم (أدوات 2008) يطفئه افتراضياً،
-- بخلاف SSMS الذي يشغّله. ضبطه هنا يجعل الملف يعمل من أي عميل.
-- الإعدادات على مستوى الاتصال فتسري على كل الدفعات بعد GO.
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

-- ============================================================================
--  ١. مسار تسجيل الدخول — الأهم في الملف
-- ============================================================================
-- AuthController.cs:31 يبحث بـ (email = @x OR username = @x) بلا
-- organization_id — بالضرورة، فالمنظمة مجهولة قبل الدخول. لكن الفهرسين
-- الموجودين على app_users يبدآن بـ organization_id:
--     UQ_app_users_org_email      (organization_id, email)
--     UQ_app_users_org_username   (organization_id, username)
-- عمود القيادة مجهول ⇒ الفهرسان غير قابلين للاستخدام ⇒ مسح كامل لجدول
-- المستخدمين في كل محاولة دخول، لكل عملائك مجتمعين على نفس القاعدة.
--
-- فهرسان منفصلان (لا فهرس مركّب) لأن الشرط OR: المُحسِّن يبحث في كل فهرس
-- ثم يوحّد النتيجتين (Index Union). فهرس واحد على عمودين لا يخدم OR.
-- غير فريدين عمداً: نفس البريد قد يوجد لمنظمتين مختلفتين، والتفرّد يبقى
-- محكوماً بقيد (organization_id, email) القائم.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_app_users_email_login' AND object_id = OBJECT_ID('dbo.app_users'))
CREATE INDEX IX_app_users_email_login ON dbo.app_users (email)
  INCLUDE (is_active, organization_id, branch_id, role, is_platform_admin);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_app_users_username_login' AND object_id = OBJECT_ID('dbo.app_users'))
CREATE INDEX IX_app_users_username_login ON dbo.app_users (username)
  INCLUDE (is_active, organization_id, branch_id, role, is_platform_admin)
  WHERE username IS NOT NULL;
GO

-- LicensesController.cs:45 — CountAsync(u => u.IsActive && u.OrganizationId == orgId)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_app_users_org_active' AND object_id = OBJECT_ID('dbo.app_users'))
CREATE INDEX IX_app_users_org_active ON dbo.app_users (organization_id, is_active);
GO

-- AuthController.cs:42 يكتب سجل دخول عند كل محاولة، وسجل الدخول يُقرأ
-- لكل مستخدم على حدة. login_history بلا سياسة أمان، فالفلترة بالعمود مباشرة.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_login_history_user_created' AND object_id = OBJECT_ID('dbo.login_history'))
CREATE INDEX IX_login_history_user_created ON dbo.login_history (user_id, created_at DESC)
  INCLUDE (success, ip_address);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_login_history_org_created' AND object_id = OBJECT_ID('dbo.login_history'))
CREATE INDEX IX_login_history_org_created ON dbo.login_history (organization_id, created_at DESC);
GO

-- ============================================================================
--  ٢. الجداول الابنة — تُقرأ دائماً عبر مفتاح الأب، وكلها كانت بلا فهرس
-- ============================================================================
-- هذه الخمسة ليست عليها سياسة أمان (تُحمى عبر الأب)، فالفلترة بالمفتاح
-- الأجنبي وحده. وكلها ON DELETE CASCADE: بلا فهرس، حذف أب واحد = مسح كامل.

-- InvoicesController.cs:100 — Include(i => i.Items) عند فتح كل فاتورة
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_invoice_items_invoice' AND object_id = OBJECT_ID('dbo.invoice_items'))
CREATE INDEX IX_invoice_items_invoice ON dbo.invoice_items (invoice_id)
  INCLUDE (product_id, quantity, unit_price, line_total);
GO

-- تقرير حركة صنف: كل أسطر الفواتير التي تحوي منتجاً معيّناً
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_invoice_items_product' AND object_id = OBJECT_ID('dbo.invoice_items'))
CREATE INDEX IX_invoice_items_product ON dbo.invoice_items (product_id)
  INCLUDE (invoice_id, quantity, line_total);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_invoice_payments_invoice' AND object_id = OBJECT_ID('dbo.invoice_payments'))
CREATE INDEX IX_invoice_payments_invoice ON dbo.invoice_payments (invoice_id)
  INCLUDE (method, amount);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_purchase_order_items_order' AND object_id = OBJECT_ID('dbo.purchase_order_items'))
CREATE INDEX IX_purchase_order_items_order ON dbo.purchase_order_items (purchase_order_id)
  INCLUDE (product_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_purchase_order_items_product' AND object_id = OBJECT_ID('dbo.purchase_order_items'))
CREATE INDEX IX_purchase_order_items_product ON dbo.purchase_order_items (product_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stock_transfer_items_transfer' AND object_id = OBJECT_ID('dbo.stock_transfer_items'))
CREATE INDEX IX_stock_transfer_items_transfer ON dbo.stock_transfer_items (transfer_id)
  INCLUDE (product_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stock_transfer_items_product' AND object_id = OBJECT_ID('dbo.stock_transfer_items'))
CREATE INDEX IX_stock_transfer_items_product ON dbo.stock_transfer_items (product_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stock_count_items_count' AND object_id = OBJECT_ID('dbo.stock_count_items'))
CREATE INDEX IX_stock_count_items_count ON dbo.stock_count_items (stock_count_id)
  INCLUDE (product_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stock_count_items_product' AND object_id = OBJECT_ID('dbo.stock_count_items'))
CREATE INDEX IX_stock_count_items_product ON dbo.stock_count_items (product_id);
GO

-- ============================================================================
--  ٣. الفواتير — أكثر جدول ينمو في النظام
-- ============================================================================
-- الفهرس القائم IX_invoices_branch_created يبدأ بـ branch_id، لكن سياسة
-- الأمان تفلتر بـ (organization_id, branch_id) معاً. فهرس يقوده
-- organization_id يخدم مدير المنظمة (branch_id في السياق = NULL ⇒ كل الفروع)
-- والكاشير معاً، بينما الفهرس القائم يخدم الثاني فقط.
-- InvoicesController.cs:65-70 — فلترة status و invoice_type ومدى تاريخي، مع
-- ORDER BY created_at DESC. الأعمدة المُضمَّنة تجعل الاستعلام مغطّى تماماً
-- (لا رجوع إلى الجدول لعرض القائمة).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_invoices_org_branch_created' AND object_id = OBJECT_ID('dbo.invoices'))
CREATE INDEX IX_invoices_org_branch_created ON dbo.invoices (organization_id, branch_id, created_at DESC)
  INCLUDE (status, invoice_type, total_amount, invoice_number, customer_id);
GO

-- كشف حساب عميل — InvoicesController.cs:72 وشاشة بطاقة العميل
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_invoices_org_customer_created' AND object_id = OBJECT_ID('dbo.invoices'))
CREATE INDEX IX_invoices_org_customer_created ON dbo.invoices (organization_id, customer_id, created_at DESC)
  INCLUDE (total_amount, status, invoice_type)
  WHERE customer_id IS NOT NULL;
GO

-- InvoicesController.cs:284 — AnyAsync(i => i.OriginalInvoiceId == id)
-- يُنفَّذ قبل كل مرتجع لمنع إرجاع الفاتورة مرتين. مفلتر لأن الغالبية NULL.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_invoices_original' AND object_id = OBJECT_ID('dbo.invoices'))
CREATE INDEX IX_invoices_original ON dbo.invoices (original_invoice_id)
  WHERE original_invoice_id IS NOT NULL;
GO

-- تقفيل الوردية: مجموع فواتير الوردية
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_invoices_shift' AND object_id = OBJECT_ID('dbo.invoices'))
CREATE INDEX IX_invoices_shift ON dbo.invoices (shift_id)
  INCLUDE (total_amount, status)
  WHERE shift_id IS NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_invoices_created_by' AND object_id = OBJECT_ID('dbo.invoices'))
CREATE INDEX IX_invoices_created_by ON dbo.invoices (created_by) WHERE created_by IS NOT NULL;
GO

-- ============================================================================
--  ٤. المخزون
-- ============================================================================
-- القيد القائم UQ_stock_levels يبدأ بـ branch_id، وسياسة الأمان على
-- stock_levels تفلتر بـ (organization_id, branch_id).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stock_levels_org_branch_product' AND object_id = OBJECT_ID('dbo.stock_levels'))
CREATE INDEX IX_stock_levels_org_branch_product ON dbo.stock_levels (organization_id, branch_id, product_id);
GO

-- InvoicesController.cs:197 و 323 — البحث عن رصيد صنف عند كل بيع ومرتجع.
-- وأيضاً "رصيد هذا الصنف في كل الفروع" لمدير المنظمة.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stock_levels_org_product' AND object_id = OBJECT_ID('dbo.stock_levels'))
CREATE INDEX IX_stock_levels_org_product ON dbo.stock_levels (organization_id, product_id)
  INCLUDE (branch_id);
GO

-- ترتيب الصرف — InvoicesController.cs: قراءة كل دفعات الصنف في الفرع عند كل
-- بيع، ثم ترتيبها بـ strategy_date (وهو تاريخ الانتهاء للصنف المتتبَّع
-- وتاريخ الإدخال لغيره — راجع StockLevel.StrategyDate). تضمين quantity
-- وbatch_number وis_locked يجعل الفهرس مغطّياً فلا يعود الاستعلام إلى الجدول.
--
-- الفهرس القديم على expiry_date يُسقَط: العمود لم يعد أساس الترتيب، وإبقاء
-- فهرس لا يخدم استعلاماً هو كلفة كتابة بلا مقابل قراءة.
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stock_levels_fefo' AND object_id = OBJECT_ID('dbo.stock_levels'))
DROP INDEX IX_stock_levels_fefo ON dbo.stock_levels;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stock_levels_issue_order' AND object_id = OBJECT_ID('dbo.stock_levels'))
CREATE INDEX IX_stock_levels_issue_order ON dbo.stock_levels (branch_id, product_id, strategy_date)
  INCLUDE (quantity, batch_number, expiry_date, is_locked);
GO

-- أعمار الديون (DebtAging.ComputeAsync): كل فاتورة بيع بدفع جزئي. الفهرس
-- مفلتر فيبقى صغيراً مهما كبر جدول الفواتير — البيع النقدي هو الغالب.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_invoices_credit_due' AND object_id = OBJECT_ID('dbo.invoices'))
CREATE INDEX IX_invoices_credit_due ON dbo.invoices (customer_id, due_date)
  INCLUDE (total_amount, paid_amount, created_at)
  WHERE paid_amount IS NOT NULL AND customer_id IS NOT NULL;
GO

-- آخر تذكير لكل عميل — يُقرأ مع كل فتح لتقرير الأعمار.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_debt_reminders_customer' AND object_id = OBJECT_ID('dbo.debt_reminders'))
CREATE INDEX IX_debt_reminders_customer ON dbo.debt_reminders (customer_id, sent_at DESC)
  INCLUDE (stage, amount_at_reminder);
GO

-- دفتر حركة المخزون — أثقل قراءتين فيه:
--
-- ١. اختيار الإدخالات التي يُصرَف منها (StockLedger.IssueAsync) عند **كل
--    بيع**: فرع + صنف + مستودع + ما بقي فيه شيء، مرتّبةً بالصلاحية.
--    الفهرس مفلتر على remaining_quantity > 0 فيبقى صغيراً مهما كبر الدفتر:
--    سطور الصرف وسطور الإدخال المستنفدة خارجه تماماً.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stock_ledger_open_lots' AND object_id = OBJECT_ID('dbo.stock_ledger_entries'))
CREATE INDEX IX_stock_ledger_open_lots
  ON dbo.stock_ledger_entries (branch_id, product_id, warehouse_id, expiry_date, posted_at)
  INCLUDE (batch_number, remaining_quantity, unit_cost)
  WHERE remaining_quantity > 0 AND is_cancelled = 0;
GO

-- ٢. كارت الصنف: كل حركات صنف في فرع بترتيب زمني.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stock_ledger_product_posted' AND object_id = OBJECT_ID('dbo.stock_ledger_entries'))
CREATE INDEX IX_stock_ledger_product_posted
  ON dbo.stock_ledger_entries (organization_id, product_id, posted_at DESC)
  INCLUDE (branch_id, batch_number, quantity_change, balance_after, unit_cost, source_type);
GO

-- التتبّع العكسي: «هذه الدفعة معيبة — من اشتراها؟» يقرأ سطور الصرف بمعرّف
-- إدخالها. بلا فهرس يصبح مسحاً كاملاً للدفتر — وهو أكبر جدول في النظام.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stock_ledger_source_entry' AND object_id = OBJECT_ID('dbo.stock_ledger_entries'))
CREATE INDEX IX_stock_ledger_source_entry ON dbo.stock_ledger_entries (source_entry_id)
  WHERE source_entry_id IS NOT NULL;
GO

-- المستند إلى حركاته: «ماذا حرّكت هذه الفاتورة».
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stock_ledger_source' AND object_id = OBJECT_ID('dbo.stock_ledger_entries'))
CREATE INDEX IX_stock_ledger_source ON dbo.stock_ledger_entries (source_type, source_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_warehouses_branch' AND object_id = OBJECT_ID('dbo.warehouses'))
CREATE INDEX IX_warehouses_branch ON dbo.warehouses (branch_id, kind) INCLUDE (name, is_active);
GO

-- مستند الاستلام: القراءة الغالبة «شحنات هذا الأمر مرتّبةً بتاريخ الوصول»
-- (PurchaseOrdersController.Receipts)، والسطور تُجلب بمعرّف مستندها.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_purchase_receipts_order' AND object_id = OBJECT_ID('dbo.purchase_receipts'))
CREATE INDEX IX_purchase_receipts_order ON dbo.purchase_receipts (purchase_order_id, received_on)
  INCLUDE (supplier_note_number, received_by);
GO

-- مفتاح أجنبي بـ ON DELETE CASCADE بلا فهرس = مسح كامل للجدول الابن عند
-- حذف الأب (راجع §٢ أعلاه).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_purchase_receipt_items_receipt' AND object_id = OBJECT_ID('dbo.purchase_receipt_items'))
CREATE INDEX IX_purchase_receipt_items_receipt ON dbo.purchase_receipt_items (purchase_receipt_id);
GO

-- invoice_item_batches.invoice_item_id — مفتاح أجنبي بـ ON DELETE CASCADE.
-- بلا فهرس يصبح حذف سطر فاتورة مسحاً كاملاً للجدول الابن (راجع §٢ أعلاه).
-- والمرتجع يقرأ تخصيص الدفعات لكل سطر من الفاتورة الأصلية.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_invoice_item_batches_item' AND object_id = OBJECT_ID('dbo.invoice_item_batches'))
CREATE INDEX IX_invoice_item_batches_item ON dbo.invoice_item_batches (invoice_item_id);
GO

-- products: القائم IX_products_org_name يخدم الترتيب بالاسم، وIX_products_barcode
-- يخدم الماسح الضوئي. الناقص: المفتاحان الأجنبيان.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_products_org_category' AND object_id = OBJECT_ID('dbo.products'))
CREATE INDEX IX_products_org_category ON dbo.products (organization_id, category_id)
  WHERE is_deleted = 0;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_products_org_supplier' AND object_id = OBJECT_ID('dbo.products'))
CREATE INDEX IX_products_org_supplier ON dbo.products (organization_id, supplier_id)
  WHERE is_deleted = 0 AND supplier_id IS NOT NULL;
GO

-- ============================================================================
--  ٥. المشتريات والتحويلات والجرد
-- ============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_purchase_orders_org_branch_created' AND object_id = OBJECT_ID('dbo.purchase_orders'))
CREATE INDEX IX_purchase_orders_org_branch_created ON dbo.purchase_orders (organization_id, branch_id, created_at DESC)
  INCLUDE (status, supplier_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_purchase_orders_org_supplier' AND object_id = OBJECT_ID('dbo.purchase_orders'))
CREATE INDEX IX_purchase_orders_org_supplier ON dbo.purchase_orders (organization_id, supplier_id)
  WHERE supplier_id IS NOT NULL;
GO

-- التحويلات تُستعلَم من الطرفين: الفرع المُرسل والفرع المستقبِل. عمودان
-- مختلفان ⇒ فهرسان، لا فهرس واحد.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stock_transfers_org_from' AND object_id = OBJECT_ID('dbo.stock_transfers'))
CREATE INDEX IX_stock_transfers_org_from ON dbo.stock_transfers (organization_id, from_branch_id, created_at DESC)
  INCLUDE (status, to_branch_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stock_transfers_org_to' AND object_id = OBJECT_ID('dbo.stock_transfers'))
CREATE INDEX IX_stock_transfers_org_to ON dbo.stock_transfers (organization_id, to_branch_id, created_at DESC)
  INCLUDE (status, from_branch_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stock_counts_org_branch_created' AND object_id = OBJECT_ID('dbo.stock_counts'))
CREATE INDEX IX_stock_counts_org_branch_created ON dbo.stock_counts (organization_id, branch_id, created_at DESC)
  INCLUDE (status);
GO

-- ============================================================================
--  ٦. الجداول المرجعية — كلها كانت بلا فهرس على organization_id
-- ============================================================================
-- BranchesController.cs:32-33 — Where(IsActive) ثم OrderBy(Name)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_branches_org_active_name' AND object_id = OBJECT_ID('dbo.branches'))
CREATE INDEX IX_branches_org_active_name ON dbo.branches (organization_id, is_active, name);
GO

-- CategoriesController.cs:28 — OrderBy(Name)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_product_categories_org_name' AND object_id = OBJECT_ID('dbo.product_categories'))
CREATE INDEX IX_product_categories_org_name ON dbo.product_categories (organization_id, name);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_product_categories_parent' AND object_id = OBJECT_ID('dbo.product_categories'))
CREATE INDEX IX_product_categories_parent ON dbo.product_categories (parent_id) WHERE parent_id IS NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_suppliers_org_name' AND object_id = OBJECT_ID('dbo.suppliers'))
CREATE INDEX IX_suppliers_org_name ON dbo.suppliers (organization_id, name) WHERE is_deleted = 0;
GO

-- CustomersController.cs:69 — Sponsors.Where(s => sponsorIds.Contains(s.Id))
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_sponsors_org_name' AND object_id = OBJECT_ID('dbo.sponsors'))
CREATE INDEX IX_sponsors_org_name ON dbo.sponsors (organization_id, name);
GO

-- LicensesController.cs:34 — OrderByDescending(IssuedAt).FirstOrDefault()
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_licenses_org_issued' AND object_id = OBJECT_ID('dbo.licenses'))
CREATE INDEX IX_licenses_org_issued ON dbo.licenses (organization_id, issued_at DESC)
  INCLUDE (status, expires_at, plan_tier);
GO

-- ============================================================================
--  ٧. الإشعارات والمصروفات والورديات وسجل التغييرات
-- ============================================================================
-- NotificationsController.cs:35-40 — (branch_id IS NULL OR branch_id = @x)
-- مع is_read و ORDER BY created_at DESC. branch_id مُضمَّن لا مفتاح، لأن
-- شرط OR على NULL لا يُخدَم بالبحث في فهرس.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_notifications_org_created' AND object_id = OBJECT_ID('dbo.notifications'))
CREATE INDEX IX_notifications_org_created ON dbo.notifications (organization_id, created_at DESC)
  INCLUDE (is_read, branch_id, type, title);
GO

-- NotificationsController.cs:57 — عدّاد غير المقروء، يُستدعى مع كل تحديث للواجهة
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_notifications_org_unread' AND object_id = OBJECT_ID('dbo.notifications'))
CREATE INDEX IX_notifications_org_unread ON dbo.notifications (organization_id, branch_id)
  WHERE is_read = 0;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_expenses_org_branch_created' AND object_id = OBJECT_ID('dbo.expenses'))
CREATE INDEX IX_expenses_org_branch_created ON dbo.expenses (organization_id, branch_id, created_at DESC)
  INCLUDE (category, amount);
GO

-- pos_shifts بلا سياسة أمان، فالفلترة بالأعمدة مباشرة.
-- "الوردية المفتوحة لهذا الكاشير الآن" — يُنفَّذ عند كل عملية بيع.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_pos_shifts_branch_status' AND object_id = OBJECT_ID('dbo.pos_shifts'))
CREATE INDEX IX_pos_shifts_branch_status ON dbo.pos_shifts (branch_id, status, opened_at DESC)
  INCLUDE (cashier_id, opening_cash, closing_cash);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_pos_shifts_cashier' AND object_id = OBJECT_ID('dbo.pos_shifts'))
CREATE INDEX IX_pos_shifts_cashier ON dbo.pos_shifts (cashier_id, opened_at DESC);
GO

-- AuditLogsController.cs:79 — فلترة entity_table مع ORDER BY created_at DESC.
-- الفهرس القائم IX_audit_logs_org_created لا يخدم فلترة entity_table.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_audit_logs_org_entity_created' AND object_id = OBJECT_ID('dbo.audit_logs'))
CREATE INDEX IX_audit_logs_org_entity_created ON dbo.audit_logs (organization_id, entity_table, created_at DESC)
  INCLUDE (user_id, entity_id);
GO

-- AuditLogsController.cs:94 — الفلترة بمستخدم معيّن
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_audit_logs_org_user_created' AND object_id = OBJECT_ID('dbo.audit_logs'))
CREATE INDEX IX_audit_logs_org_user_created ON dbo.audit_logs (organization_id, user_id, created_at DESC)
  WHERE user_id IS NOT NULL;
GO

-- ============================================================================
--  ٨. العملاء والمحفظة — استكمال ما هو موجود
-- ============================================================================
-- الموجود يغطي الاسم والباركود والكفيل وانتهاء الاستحقاق. الناقص: branch_id
-- والهاتف (يُبحث به في نقطة البيع).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_customers_org_phone' AND object_id = OBJECT_ID('dbo.customers'))
CREATE INDEX IX_customers_org_phone ON dbo.customers (organization_id, phone)
  WHERE phone IS NOT NULL AND is_deleted = 0;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_customers_org_branch' AND object_id = OBJECT_ID('dbo.customers'))
CREATE INDEX IX_customers_org_branch ON dbo.customers (organization_id, branch_id)
  WHERE branch_id IS NOT NULL AND is_deleted = 0;
GO

-- CustomerPortalController.cs:105 و CustomersController.cs:118 — الفهرس
-- القائم IX_wallet_tx_customer_created يغطيهما. الناقص: الربط بالفاتورة.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_wallet_tx_invoice' AND object_id = OBJECT_ID('dbo.customer_wallet_transactions'))
CREATE INDEX IX_wallet_tx_invoice ON dbo.customer_wallet_transactions (invoice_id)
  WHERE invoice_id IS NOT NULL;
GO

-- customer_card_index.organization_id — بوابة العميل تقرأه قبل الدخول
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_customer_card_index_org' AND object_id = OBJECT_ID('dbo.customer_card_index'))
CREATE INDEX IX_customer_card_index_org ON dbo.customer_card_index (organization_id)
  INCLUDE (customer_id, state, expiry_date);
GO

-- ============================================================================
--  التحقق — نفّذ هذا بعد السكربت لعرض النتيجة
-- ============================================================================
SELECT
    OBJECT_NAME(i.object_id) AS [الجدول],
    i.name                   AS [الفهرس],
    i.type_desc              AS [النوع],
    CASE WHEN i.has_filter = 1 THEN N'مفلتر' ELSE N'' END AS [ملاحظة]
FROM sys.indexes i
WHERE i.object_id IN (SELECT object_id FROM sys.tables WHERE schema_id = SCHEMA_ID('dbo'))
  AND i.type > 0
ORDER BY OBJECT_NAME(i.object_id), i.name;
GO

-- ============================================================================
--  ما لا تحلّه الفهارس — اقرأ هذا
-- ============================================================================
-- ١. البحث بـ Contains: CustomersController.cs:51 و ProductsController
--    و AuditLogsController.cs:90 يترجم إلى LIKE N'%نص%'. البادئة المفتوحة
--    تمنع البحث في الفهرس مهما أضفنا — تبقى قراءة كاملة للفهرس (أخف من
--    قراءة الجدول، لكنها ليست بحثاً). الحل الحقيقي عند نمو البيانات:
--    Full-Text Index على customers.full_name و products.name، وهو ميزة
--    منفصلة تُثبَّت مع SQL Server وتحتاج CREATE FULLTEXT CATALOG. لم أضفها
--    هنا لأنها تغيير في طبيعة البحث لا مجرد فهرس، وتحتاج تعديل الكود
--    (CONTAINS بدل LIKE) وقراراً منك.
--
-- ٢. حجم الكتابة: كل فهرس يُبطئ INSERT/UPDATE قليلاً. الفهارس أعلاه مختارة
--    على أعمدة تُقرأ أكثر بكثير مما تُكتب. جدول invoice_items هو الأكثر
--    كتابة (سطر لكل صنف في كل فاتورة) وله فهرسان فقط، وكلاهما ضروري.
--
-- ٣. الصيانة: أعِد بناء الفهارس دورياً بعد أن تكبر البيانات:
--    ALTER INDEX ALL ON dbo.invoices REBUILD;
--    وحدّث الإحصائيات: EXEC sp_updatestats;
--    اجعلها مهمة شهرية في Task Scheduler مع sqlcmd (SQL Agent غير متوفر
--    في Express).
--
-- ٤. لم أضف فهارس على: permissions و role_permissions و platform_settings
--    و platform_organizations. الأول والثالث جداول ثابتة صغيرة (عشرات
--    الصفوف)، والثاني مفتاحه الأساسي (organization_id, role, permission_code)
--    يخدم كل استعلاماته أصلاً. إضافة فهرس هنا تكلفة بلا فائدة.
-- ============================================================================
