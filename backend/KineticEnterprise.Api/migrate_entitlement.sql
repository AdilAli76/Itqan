-- ============================================================================
-- نموذج الاستحقاق الممنوح + فهارس الأداء
--
-- فواصل GO إلزامية لا تجميلية: SQL Server يترجم الدفعة كاملة قبل تنفيذها،
-- فأي فهرس على عمود أُضيف في نفس الدفعة يفشل بـ "Invalid column name".
-- ============================================================================
--
-- ملاحظة تشغيلية: sqlcmd يعمل افتراضياً بـ QUOTED_IDENTIFIER OFF، والفهارس
-- المُصفّاة (WHERE ...) ترفض ذلك. الضبط مكتوب داخل كل دفعة فهرس أدناه حتى
-- يعمل الملف كما هو على سيرفر الإنتاج دون تذكّر خيار -I.

-- ---- 1. الجهات الممولة ----
IF OBJECT_ID('dbo.sponsors', 'U') IS NULL
BEGIN
    CREATE TABLE sponsors (
      id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
      organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
      name NVARCHAR(150) NOT NULL,
      phone NVARCHAR(30) NULL,
      notes NVARCHAR(500) NULL,
      is_deleted BIT NOT NULL DEFAULT 0,
      created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
    PRINT 'created sponsors';
END
GO

-- العزل بنفس نمط suppliers بالضبط: الجهة تخص المنظمة ككل لا فرعاً منها.
IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'SponsorsPolicy')
BEGIN
    EXEC('CREATE SECURITY POLICY Security.SponsorsPolicy
      ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.sponsors,
      ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.sponsors AFTER INSERT
      WITH (STATE = ON);');
    PRINT 'created SponsorsPolicy';
END
GO

-- ---- 2. أعمدة نموذج الحساب على العملاء ----
IF COL_LENGTH('dbo.customers','account_model') IS NULL
BEGIN
    ALTER TABLE customers ADD
      account_model NVARCHAR(20) NOT NULL
        CONSTRAINT DF_customers_account_model DEFAULT 'prepaid'
        CONSTRAINT CK_customers_account_model CHECK (account_model IN ('prepaid','entitlement')),
      sponsor_id UNIQUEIDENTIFIER NULL REFERENCES sponsors(id),
      entitlement_ceiling DECIMAL(18,3) NOT NULL
        CONSTRAINT DF_customers_entitlement_ceiling DEFAULT 0,
      entitlement_expires_on DATE NULL;
    PRINT 'added entitlement columns to customers';
END
GO

-- ---- 3. توسيع أنواع حركات الدفتر ----
-- القيد القديم يمنع إدراج المنح والإسقاط، فيفشل كل الموديول بصمت بدونه.
IF EXISTS (SELECT 1 FROM sys.check_constraints
           WHERE parent_object_id = OBJECT_ID('dbo.customer_wallet_transactions')
             AND definition LIKE '%adjustment_out%'
             AND definition NOT LIKE '%entitlement_grant%')
BEGIN
    DECLARE @ck SYSNAME = (
        SELECT TOP 1 name FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID('dbo.customer_wallet_transactions')
          AND definition LIKE '%adjustment_out%');
    EXEC('ALTER TABLE customer_wallet_transactions DROP CONSTRAINT ' + @ck);
    EXEC('ALTER TABLE customer_wallet_transactions ADD CONSTRAINT CK_wallet_tx_kind
      CHECK (kind IN (''topup'',''spend'',''invoice_refund'',''adjustment_in'',''adjustment_out'',
                      ''entitlement_grant'',''entitlement_expiry''))');
    PRINT 'widened wallet kind constraint';
END
GO

-- ---- 4. فهارس الأداء ----
-- كل فهرس أدناه يقابل استعلاماً فعلياً في الكود، لا تخميناً: فهرس زائد يبطئ
-- الكتابة ويستهلك مساحة دون فائدة.

-- WalletBalances.ComputeAsync/ComputeManyAsync: تجميع بـ customer_id.
-- الأعمدة المُضمَّنة تجعله فهرساً مغطّياً، فلا يعود المحرّك للجدول الأصلي.
SET QUOTED_IDENTIFIER ON;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_wallet_tx_customer_created')
    CREATE INDEX IX_wallet_tx_customer_created
      ON customer_wallet_transactions (customer_id, created_at)
      INCLUDE (kind, amount);
GO

-- SponsorsController.GetStatement: مستفيدو جهة ممولة.
SET QUOTED_IDENTIFIER ON;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_customers_sponsor')
    CREATE INDEX IX_customers_sponsor ON customers (sponsor_id) WHERE sponsor_id IS NOT NULL;
GO

-- EntitlementSweeper: العملاء المنتهية استحقاقاتهم. الفهرس المُصفّى يغطي
-- حسابات الاستحقاق وحدها — وهي أقلية في أي منظمة عادية.
SET QUOTED_IDENTIFIER ON;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_customers_entitlement_expiry')
    CREATE INDEX IX_customers_entitlement_expiry
      ON customers (entitlement_expires_on)
      WHERE entitlement_expires_on IS NOT NULL;
GO

-- CustomersController.GetAll: الفرز الافتراضي بالاسم داخل المنظمة.
SET QUOTED_IDENTIFIER ON;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_customers_org_name')
    CREATE INDEX IX_customers_org_name ON customers (organization_id, full_name) WHERE is_deleted = 0;
GO

-- CustomersController.GetByCard: مسح البطاقة في نقطة البيع (مطابقة تامة).
SET QUOTED_IDENTIFIER ON;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_customers_card_barcode')
    CREATE INDEX IX_customers_card_barcode ON customers (card_barcode) WHERE card_barcode IS NOT NULL;
GO

-- CustomerPinGate: عدّ الإخفاقات داخل نافذة القفل — يُنفَّذ عند كل محاولة دفع.
SET QUOTED_IDENTIFIER ON;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_pin_attempts_customer_created')
    CREATE INDEX IX_pin_attempts_customer_created
      ON customer_pin_attempts (customer_id, created_at) INCLUDE (success);
GO

-- ProductsController.GetInventory: البحث والفرز بالاسم، والمسح بالباركود.
SET QUOTED_IDENTIFIER ON;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_products_org_name')
    CREATE INDEX IX_products_org_name ON products (organization_id, name) WHERE is_deleted = 0;
GO
SET QUOTED_IDENTIFIER ON;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_products_barcode')
    CREATE INDEX IX_products_barcode ON products (barcode) WHERE barcode IS NOT NULL;
GO

-- InvoicesController: قوائم الفواتير وتقاريرها مفرزة بالتاريخ داخل الفرع.
SET QUOTED_IDENTIFIER ON;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_invoices_branch_created')
    CREATE INDEX IX_invoices_branch_created ON invoices (branch_id, created_at);
GO

-- StockLevels: البحث بالفرع + الصنف في كل عملية بيع.
SET QUOTED_IDENTIFIER ON;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_stock_levels_branch_product')
    CREATE INDEX IX_stock_levels_branch_product ON stock_levels (branch_id, product_id);
GO

-- AuditLogs: الشاشة تعرضها مفرزة بالتاريخ تنازلياً دائماً.
SET QUOTED_IDENTIFIER ON;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_audit_logs_org_created')
    CREATE INDEX IX_audit_logs_org_created ON audit_logs (organization_id, created_at DESC);
GO

PRINT 'migration complete';
GO
