-- ============================================================================
--  ترقيات المخطط للقواعد القائمة
--
--  sql.sql هو المخطط الكامل لقاعدة بيانات **جديدة**. أي قاعدة تعمل بالفعل
--  (على جهازك أو على سيرفر عميل) لا يمكن إعادة تنفيذه عليها — هذا الملف هو
--  طريق الترقية.
--
--  كل ترقية محمية بـ IF NOT EXISTS، فتنفيذ الملف كاملاً أكثر من مرة آمن.
--  نفّذ الترقيات بالترتيب، ولا تحذف واحدة منتهية — السيرفرات تُرقّى في
--  أوقات مختلفة.
--
--  التنفيذ:
--      sqlcmd -S .\SQLEXPRESS -d KineticEnterprise -E -I -f 65001 -i docs\MIGRATIONS.sql
--
--  المعاملان -I و -f 65001 ليسا تزييناً:
--    -I       QUOTED_IDENTIFIER مطلوب للكتابة على الجداول ذات الفهارس
--             المفلترة (app_users). بدونه تُرفض كل عبارة تعديل عليها.
--    -f 65001 ترميز UTF-8. بدونه تُخزَّن النصوص العربية تالفة بلا أي خطأ —
--             وهو ما أصاب 14 صفاً في جدول permissions من قبل.
--
--  ⚠ الجداول المحمية بسياسات أمان (role_permissions، organizations، …):
--  أي تعديل عليها بلا SESSION_CONTEXT مضبوط يُطبَّق على صفر صفوف **بصمت**.
--  الترحيلات أدناه تدور على المنظمات وتضبط السياق لكل واحدة.
-- ============================================================================

USE KineticEnterprise;
GO

-- ----------------------------------------------------------------------------
--  2026-08-17 — نقطة البيع: السماح بالأصناف مفتوحة القيمة (إعداد المنظمة)
-- ----------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.organizations') AND name = 'pos_allow_open_product'
)
BEGIN
    ALTER TABLE dbo.organizations
        ADD pos_allow_open_product BIT NOT NULL
            CONSTRAINT DF_organizations_pos_allow_open_product DEFAULT 0;

    PRINT N'أُضيف العمود organizations.pos_allow_open_product (مطفأ افتراضياً)';
END
ELSE
BEGIN
    PRINT N'organizations.pos_allow_open_product موجود — لا تغيير';
END
GO

-- ----------------------------------------------------------------------------
--  2026-08-17 — منع تكرار البريد بين المنظمات
--
--  المشكلة: قيد التفرّد الأصلي هو (organization_id, email)، فنفس البريد
--  مسموح في منظمتين. لكن AuthController يبحث بالبريد **بلا منظمة** — لا
--  سبيل لمعرفتها قبل الدخول — ويأخذ أول صف يرجعه SQL Server بلا ترتيب
--  محدَّد. النتيجة: الدخول ببريد مكرَّر غير محدَّد النتيجة، وقد يدخل
--  المستخدم إلى منظمة ليست منظمته. في نظام يعزل بيانات عملاء مختلفين هذا
--  تسريب لا إزعاج.
--
--  الحل: تفرّد عالمي على البريد **بين الحسابات النشطة فقط**. مفلتر عمداً:
--  الحسابات المعطَّلة تاريخ يجب أن يبقى (سجل تغييرات وفواتير تشير إليها)،
--  ومنعها كان سيمنع تعطيل حساب وإعادة استخدام بريده لاحقاً.
--
--  ملاحظة تشغيلية: فهرس مفلتر يعني أن أي عميل يكتب في app_users يجب أن
--  يكون QUOTED_IDENTIFIER لديه ON. عملاء .NET (SqlClient) وSSMS يضبطونه
--  تلقائياً؛ أما sqlcmd القديم فيحتاج المعامل -I صراحةً.
-- ----------------------------------------------------------------------------
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF EXISTS (
    SELECT email FROM dbo.app_users WHERE is_active = 1
    GROUP BY email HAVING COUNT(*) > 1
)
BEGIN
    PRINT N'تحذير: يوجد بريد مكرَّر بين حسابات نشطة — عطّل الزائد ثم أعِد التنفيذ.';
    SELECT email AS [بريد مكرَّر], COUNT(*) AS [عدد الحسابات النشطة]
    FROM dbo.app_users WHERE is_active = 1
    GROUP BY email HAVING COUNT(*) > 1;
END
ELSE IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_app_users_email_active')
BEGIN
    CREATE UNIQUE INDEX UQ_app_users_email_active
        ON dbo.app_users (email)
        WHERE is_active = 1;
    PRINT N'أُنشئ UQ_app_users_email_active — لا بريدان نشطان متطابقان بعد الآن';
END
ELSE
BEGIN
    PRINT N'UQ_app_users_email_active موجود — لا تغيير';
END
GO

-- اسم المستخدم كذلك: نفس الاستعلام في تسجيل الدخول يقارنه بلا منظمة.
IF NOT EXISTS (
    SELECT username FROM dbo.app_users WHERE is_active = 1 AND username IS NOT NULL
    GROUP BY username HAVING COUNT(*) > 1
)
AND NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_app_users_username_active')
BEGIN
    CREATE UNIQUE INDEX UQ_app_users_username_active
        ON dbo.app_users (username)
        WHERE is_active = 1 AND username IS NOT NULL;
    PRINT N'أُنشئ UQ_app_users_username_active';
END
GO

-- ----------------------------------------------------------------------------
--  2026-08-17 — كتالوج الصلاحيات: تعبئته وتصحيح تلف النصوص العربية
--
--  مشكلتان اكتُشفتا معاً:
--
--  ١) جدول permissions لم يكن يُملأ في أي مكان في المستودع — لا في المخطط
--     ولا في كود التهيئة. و role_permissions.permission_code يحمل مفتاحاً
--     أجنبياً عليه، وPlatformController.Create يُدرج صفوف الأدوار الافتراضية
--     عند إنشاء كل منظمة. أي أن **أول إنشاء منظمة على قاعدة جديدة كان
--     سيفشل** بخرق مفتاح أجنبي. القاعدة الحالية تعمل فقط لأن الصفوف
--     أُدخلت يدوياً فيها من قبل.
--
--  ٢) أربعة عشر صفاً من الخمسة عشر القائمة تحمل نصاً عربياً **تالفاً**
--     مخزَّناً في القاعدة (بايتات UTF-8 مقروءة كـ Windows-1256)، لأنها
--     أُدخلت بلا بادئة N. فشاشة مصفوفة الصلاحيات تعرض رموزاً لا عربية.
--     MERGE أدناه يصحّحها ويُكمل الناقص في آن.
--
--  التنفيذ يجب أن يكون بترميز صريح وإلا تكرّر التلف نفسه:
--      sqlcmd ... -I -f 65001 -i docs\MIGRATIONS.sql
-- ----------------------------------------------------------------------------
MERGE dbo.permissions AS target
USING (VALUES
    ('inventory.manage',        N'إدارة المنتجات (إضافة/تعديل/تسوية مخزون)', N'inventory'),
    ('inventory.delete',        N'حذف المنتجات',                              N'inventory'),
    ('categories.manage',       N'إدارة تصنيفات المنتجات',                    N'inventory'),
    ('suppliers.manage',        N'إدارة الموردين',                            N'suppliers'),
    ('suppliers.delete',        N'حذف الموردين',                              N'suppliers'),
    ('purchasing.manage',       N'إدارة أوامر الشراء',                        N'purchasing'),
    ('stock_transfer.manage',   N'تحويل المخزون بين الفروع',                  N'stock_transfer'),
    ('stock_count.manage',      N'الجرد الدوري',                              N'stock_count'),
    ('customers.manage',        N'إدارة بيانات العملاء',                      N'customers'),
    ('customers.delete',        N'حذف العملاء',                               N'customers'),
    ('customers.wallet_adjust', N'تعديل رصيد محفظة العميل',                   N'customers'),
    ('invoices.refund',         N'استرجاع الفواتير',                          N'invoices'),
    ('pos.price_override',      N'البيع بسعر مخالف لسعر الكتالوج',            N'pos'),
    ('reports.view',            N'عرض التقارير',                              N'reports'),
    ('audit_log.view',          N'عرض سجل التدقيق',                           N'audit_log'),
    ('license.view',            N'عرض الترخيص والاشتراك',                     N'license')
) AS source (code, label_ar, module)
ON target.code = source.code
WHEN MATCHED AND (target.label_ar <> source.label_ar OR target.module <> source.module)
    THEN UPDATE SET label_ar = source.label_ar, module = source.module
WHEN NOT MATCHED BY TARGET
    THEN INSERT (code, label_ar, module) VALUES (source.code, source.label_ar, source.module);

PRINT N'كتالوج الصلاحيات محدَّث (16 صلاحية، منها pos.price_override الجديدة)';
GO

-- ----------------------------------------------------------------------------
--  2026-08-18 — فصل صلاحية إصدار البطاقات، وسحب شحن المحفظة من الكاشير
--
--  الثغرة: إصدار البطاقة وحظرها و**إعادة تعيين رقمها السري** كانت كلها
--  محروسة بـ customers.manage، وشحن الرصيد بـ customers.wallet_adjust —
--  والكاشير يملك الاثنتين بالتعيين الافتراضي. أي أن كاشيراً واحداً يستطيع:
--  إنشاء عميل وهمي ← إصدار بطاقة ← شحنها بمبلغ لم يدخل الصندوق ← ضبط رقمها
--  السري ← إنفاقها على بضاعة حقيقية. هذا خلق نقود لا تجاوز صلاحية، ولا
--  يكشفه إلا جرد يقارن البضاعة بالإيراد.
--
--  وأخطر جزء: إعادة تعيين الرقم السري بنفس صلاحية تعديل بيانات العميل —
--  الرقم السري هو الحماية الوحيدة على أرصدة **كل** العملاء.
--
--  ما يفعله هذا الترحيل على المنظمات القائمة:
--    1. يضيف صلاحية cards.issue إلى الكتالوج.
--    2. يمنحها لـ branch_manager في كل منظمة (كان يملكها ضمناً عبر
--       customers.manage، فهذا إبقاء لوضعه لا توسيع).
--    3. **يسحب** customers.wallet_adjust من الكاشير في كل منظمة.
--
--  البند 3 يغيّر صلاحيات قائمة عمداً — هو الإصلاح نفسه. من أراد إبقاءها
--  لكاشير بعينه يعيد منحها من شاشة «مصفوفة الصلاحيات» بقرار صريح.
--
--  البيع من محفظة العميل لا يتأثر: حركة الخصم تُكتب داخل InvoicesController
--  بعد التحقق من الرقم السري، لا عبر نقطة wallet-adjustments.
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.permissions WHERE code = 'cards.issue')
BEGIN
    INSERT INTO dbo.permissions (code, label_ar, module)
    VALUES ('cards.issue', N'إصدار بطاقات العملاء وضبط أرقامها السرية', N'customers');
    PRINT N'أُضيفت صلاحية cards.issue';
END
ELSE
BEGIN
    -- تصحيح النصّ لا مجرّد تخطّي الإدراج.
    --
    -- من نفّذ هذا الملف بـ sqlcmd بلا العلم -f 65001 خُزّن عنده النصّ
    -- العربي تالفاً (بايتات UTF-8 مقروءة بترميز غربي: «Ø¥ØµØ¯Ø§Ø±»).
    -- وإعادة التنفيذ لم تكن تُصلحه: الصف موجود فيتخطّاه IF NOT EXISTS،
    -- فيبقى التلف ظاهراً للمستخدم في شاشة الصلاحيات إلى الأبد.
    UPDATE dbo.permissions
    SET label_ar = N'إصدار بطاقات العملاء وضبط أرقامها السرية',
        module   = N'customers'
    WHERE code = 'cards.issue'
      AND (label_ar <> N'إصدار بطاقات العملاء وضبط أرقامها السرية' OR module <> N'customers');
    IF @@ROWCOUNT > 0 PRINT N'صُحّح نصّ صلاحية cards.issue';
END
GO

-- ⚠ role_permissions محمي بسياسة أمان (Security.RolePermissionsPolicy).
--
-- أي INSERT/UPDATE/DELETE عليه بلا SESSION_CONTEXT مضبوط يُطبَّق على **صفر
-- صفوف** ولا يرفع أي خطأ — العبارة تنجح والترحيل يعلن نجاحه وهو لم يغيّر
-- شيئاً. هذا بالضبط ما حدث في أول تنفيذ لهذا الملف.
--
-- لذلك: دوران على كل منظمة، وضبط السياق قبل كل عملية. معرّفات المنظمات
-- تُقرأ من app_users لأنه الجدول الوحيد غير المحمي الذي يحملها (جدول
-- organizations نفسه محمي بنفس الطريقة).
DECLARE @org UNIQUEIDENTIFIER;
DECLARE @granted INT = 0, @revoked INT = 0;

DECLARE org_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT organization_id FROM dbo.app_users;

OPEN org_cursor;
FETCH NEXT FROM org_cursor INTO @org;

WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sp_set_session_context @key = N'organization_id', @value = @org;

    -- منح cards.issue لمدير الفرع: كان يملكها ضمناً عبر customers.manage،
    -- فهذا إبقاء لوضعه القائم لا توسيع له.
    IF NOT EXISTS (
        SELECT 1 FROM dbo.role_permissions
        WHERE organization_id = @org AND role = 'branch_manager' AND permission_code = 'cards.issue'
    )
    BEGIN
        INSERT INTO dbo.role_permissions (organization_id, role, permission_code)
        VALUES (@org, 'branch_manager', 'cards.issue');
        SET @granted = @granted + 1;
    END

    -- سحب شحن المحفظة من الكاشير — هذا هو الإصلاح نفسه
    DELETE FROM dbo.role_permissions
    WHERE organization_id = @org AND role = 'cashier' AND permission_code = 'customers.wallet_adjust';
    SET @revoked = @revoked + @@ROWCOUNT;

    FETCH NEXT FROM org_cursor INTO @org;
END

CLOSE org_cursor;
DEALLOCATE org_cursor;

PRINT N'مُنحت cards.issue لمديري الفروع في ' + CAST(@granted AS NVARCHAR(10)) + N' منظمة';
PRINT N'سُحبت customers.wallet_adjust من الكاشير: ' + CAST(@revoked AS NVARCHAR(10)) + N' صف';
GO


-- ============================================================================
--  عمود مفتاح عملية العميل + فهرسه الفريد
--
--  يخدم البيع دون اتصال في نقطة البيع: جهاز الكاشير يولّد مفتاحاً لكل عملية
--  ويعيد إرساله مع كل محاولة مزامنة، فتُنشأ الفاتورة مرّة واحدة مهما تكرّر
--  الإرسال. الفهرس الفريد هو الضمانة النهائية ضد الازدواج عند التزامن.
--
--  الاسم snake_case إلزاماً لا اختياراً: AppDbContext يستعمل
--  UseSnakeCaseNamingConvention، فالخاصية ClientRequestId في الكيان تُترجَم
--  إلى client_request_id. إنشاء العمود بصيغة PascalCase يجعل EF يبحث عن
--  اسم غير موجود، فيفشل *كل* استعلام يمسّ جدول الفواتير — لا استعلام
--  البيع دون اتصال وحده. أي أن خطأ حرف واحد هنا يُعطّل لوحة التحكم
--  والفواتير والتقارير والبحث عن الأصناف معاً.
-- ============================================================================
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.invoices') AND name = 'client_request_id')
BEGIN
    -- ترقية من نسخة سابقة أنشأت العمود بالصيغة الخاطئة
    IF EXISTS (
        SELECT 1 FROM sys.columns
        WHERE object_id = OBJECT_ID('dbo.invoices') AND name = 'ClientRequestId')
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_invoices_ClientRequestId')
            DROP INDEX UX_invoices_ClientRequestId ON dbo.invoices;
        EXEC sp_rename 'dbo.invoices.ClientRequestId', 'client_request_id', 'COLUMN';
        PRINT N'أُعيد تسمية ClientRequestId إلى client_request_id';
    END
    ELSE
    BEGIN
        ALTER TABLE dbo.invoices ADD client_request_id NVARCHAR(64) NULL;
        PRINT N'أُضيف عمود client_request_id إلى invoices';
    END
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.invoices') AND name = 'UX_invoices_client_request_id')
BEGIN
    CREATE UNIQUE INDEX UX_invoices_client_request_id
        ON dbo.invoices (client_request_id)
        WHERE client_request_id IS NOT NULL;
    PRINT N'أُنشئ الفهرس الفريد UX_invoices_client_request_id';
END
GO

-- ============================================================================
--  سياسات العزل الناقصة
--
--  الجداول المعفاة عمداً — لا تُضاف لها سياسة أبداً:
--
--    app_users            : AuthController يبحث بالبريد *قبل* معرفة المنظمة.
--                           لا سبيل لضبط السياق قبل تحديد المستخدم، وأي
--                           FILTER هنا يجعل تسجيل الدخول مستحيلاً.
--    customer_card_index  : بوابة العميل تحدّد المنظمة من رمز البطاقة نفسه
--                           قبل وجود أي سياق (راجع تعليق الجدول في المخطط).
--
--  الجداول المضافة هنا وسببها:
--
--    customer_pin_attempts: آمن للحماية لأن كل مسار يلمسه يضبط السياق أولاً —
--                           InvoicesController عبر التوكن، وبوابة العميل
--                           تضبطه يدوياً فور إيجاد البطاقة وقبل فحص الرقم
--                           السري (CustomerPortalController).
--    pos_shifts           : غير مستعمل في الكود بعد؛ حمايته الآن مجانية
--                           وتمنع ثغرة عند أول استعمال.
--    login_history        : FILTER فقط بلا BLOCK — الإدراج يقع أثناء تسجيل
--                           الدخول قبل وجود السياق، وBLOCK AFTER INSERT كان
--                           سيرفضه فيمنع الدخول كلياً. وFILTER لا يمسّ
--                           الإدراج، فيحمي القراءة وحدها وهو المطلوب.
--
--  والجداول الأبناء (بنود الفواتير وأوامر الشراء والجرد والتحويلات): لا
--  تحمل organization_id، فتُعزَل عبر جدولها الأب. كان اعتمادها على أن كل
--  استعلام يمرّ بالأب — حماية بالمصادفة لا بالتصميم، وأول استعلام مباشر
--  يكسرها. القياس أثبت ذلك: purchase_order_items كان يُظهر الصفوف الخمسة
--  نفسها من سياق كل منظمة.
-- ============================================================================

-- ── دالة الأبناء: تتحقّق عبر الأب ───────────────────────────────────────
IF OBJECT_ID('Security.fn_InvoiceChild', 'IF') IS NULL
EXEC('
CREATE FUNCTION Security.fn_InvoiceChild(@InvoiceId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE EXISTS (
    SELECT 1 FROM dbo.invoices i
    WHERE i.id = @InvoiceId
      AND i.organization_id = CAST(SESSION_CONTEXT(N''organization_id'') AS UNIQUEIDENTIFIER)
);');
GO

IF OBJECT_ID('Security.fn_PurchaseOrderChild', 'IF') IS NULL
EXEC('
CREATE FUNCTION Security.fn_PurchaseOrderChild(@PurchaseOrderId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE EXISTS (
    SELECT 1 FROM dbo.purchase_orders p
    WHERE p.id = @PurchaseOrderId
      AND p.organization_id = CAST(SESSION_CONTEXT(N''organization_id'') AS UNIQUEIDENTIFIER)
);');
GO

IF OBJECT_ID('Security.fn_StockCountChild', 'IF') IS NULL
EXEC('
CREATE FUNCTION Security.fn_StockCountChild(@StockCountId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE EXISTS (
    SELECT 1 FROM dbo.stock_counts s
    WHERE s.id = @StockCountId
      AND s.organization_id = CAST(SESSION_CONTEXT(N''organization_id'') AS UNIQUEIDENTIFIER)
);');
GO

IF OBJECT_ID('Security.fn_StockTransferChild', 'IF') IS NULL
EXEC('
CREATE FUNCTION Security.fn_StockTransferChild(@TransferId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE EXISTS (
    SELECT 1 FROM dbo.stock_transfers t
    WHERE t.id = @TransferId
      AND t.organization_id = CAST(SESSION_CONTEXT(N''organization_id'') AS UNIQUEIDENTIFIER)
);');
GO

-- ── سياسات الجداول ذات organization_id ──────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'CustomerPinAttemptsPolicy')
EXEC('
CREATE SECURITY POLICY Security.CustomerPinAttemptsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.customer_pin_attempts,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.customer_pin_attempts AFTER INSERT
  WITH (STATE = ON);');
GO

IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'PosShiftsPolicy')
EXEC('
CREATE SECURITY POLICY Security.PosShiftsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.pos_shifts,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.pos_shifts AFTER INSERT
  WITH (STATE = ON);');
GO

-- FILTER بلا BLOCK — راجع السبب أعلى الملف.
IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'LoginHistoryPolicy')
EXEC('
CREATE SECURITY POLICY Security.LoginHistoryPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.login_history
  WITH (STATE = ON);');
GO

-- ── سياسات الجداول الأبناء ──────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'InvoiceItemsPolicy')
EXEC('
CREATE SECURITY POLICY Security.InvoiceItemsPolicy
  ADD FILTER PREDICATE Security.fn_InvoiceChild(invoice_id) ON dbo.invoice_items,
  ADD BLOCK PREDICATE Security.fn_InvoiceChild(invoice_id) ON dbo.invoice_items AFTER INSERT
  WITH (STATE = ON);');
GO

IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'InvoicePaymentsPolicy')
EXEC('
CREATE SECURITY POLICY Security.InvoicePaymentsPolicy
  ADD FILTER PREDICATE Security.fn_InvoiceChild(invoice_id) ON dbo.invoice_payments,
  ADD BLOCK PREDICATE Security.fn_InvoiceChild(invoice_id) ON dbo.invoice_payments AFTER INSERT
  WITH (STATE = ON);');
GO

IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'PurchaseOrderItemsPolicy')
EXEC('
CREATE SECURITY POLICY Security.PurchaseOrderItemsPolicy
  ADD FILTER PREDICATE Security.fn_PurchaseOrderChild(purchase_order_id) ON dbo.purchase_order_items,
  ADD BLOCK PREDICATE Security.fn_PurchaseOrderChild(purchase_order_id) ON dbo.purchase_order_items AFTER INSERT
  WITH (STATE = ON);');
GO

IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'StockCountItemsPolicy')
EXEC('
CREATE SECURITY POLICY Security.StockCountItemsPolicy
  ADD FILTER PREDICATE Security.fn_StockCountChild(stock_count_id) ON dbo.stock_count_items,
  ADD BLOCK PREDICATE Security.fn_StockCountChild(stock_count_id) ON dbo.stock_count_items AFTER INSERT
  WITH (STATE = ON);');
GO

IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'StockTransferItemsPolicy')
EXEC('
CREATE SECURITY POLICY Security.StockTransferItemsPolicy
  ADD FILTER PREDICATE Security.fn_StockTransferChild(transfer_id) ON dbo.stock_transfer_items,
  ADD BLOCK PREDICATE Security.fn_StockTransferChild(transfer_id) ON dbo.stock_transfer_items AFTER INSERT
  WITH (STATE = ON);');
GO

PRINT N'سياسات العزل الناقصة مُطبَّقة';
GO

-- ----------------------------------------------------------------------------
--  2026-08-19 — جدول المرفقات: شعار المنظمة وفواتير الموردين
--
--  الملف نفسه يُخزَّن على قرص السيرفر لا في القاعدة: صور الشعارات وصور
--  فواتير الموردين تُقاس بالميغابايتات، ووضعها في VARBINARY يُضخّم كل نسخة
--  احتياطية بلا مقابل ويُبطئ استرجاعها. الجدول يحفظ الوصف والمسار، والقرص
--  يحفظ البايتات.
--
--  ومسار التخزين خارج مجلد النشر بقصد (Storage:Path في appsettings): كل
--  ترقية تستبدل مجلد backend كاملاً، فملفات مرفوعة بداخله تُمحى مع أول
--  تحديث — وفاتورة مورّد ممحوّة لا تُسترجع.
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'attachments')
BEGIN
    CREATE TABLE dbo.attachments (
        id               UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
        organization_id  UNIQUEIDENTIFIER NOT NULL,
        -- الكيان المرتبط: 'organization_logo' أو 'purchase_order' …
        entity_type      NVARCHAR(40)  NOT NULL,
        entity_id        UNIQUEIDENTIFIER NULL,
        file_name        NVARCHAR(260) NOT NULL,
        content_type     NVARCHAR(120) NOT NULL,
        size_bytes       BIGINT        NOT NULL,
        -- اسم الملف على القرص فقط، لا مسار كامل: نقل مجلد التخزين أو تغيير
        -- حرف القرص لا يُبطل الصفوف.
        stored_name      NVARCHAR(120) NOT NULL,
        uploaded_by      UNIQUEIDENTIFIER NULL,
        created_at       DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
    );
    CREATE INDEX ix_attachments_entity ON dbo.attachments (organization_id, entity_type, entity_id);
    PRINT N'أُنشئ جدول attachments';
END
GO

-- عزل على مستوى المنظمة: مرفقات منظمة لا تُقرأ من منظمة أخرى ولو عُرف
-- معرّفها. فاتورة مورّد تكشف أسعار الشراء — وهي أكثر ما يهمّ منافساً.
IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'AttachmentsPolicy')
EXEC('
CREATE SECURITY POLICY Security.AttachmentsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.attachments,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.attachments AFTER INSERT
  WITH (STATE = ON);');
GO

PRINT N'جدول المرفقات وسياسة عزله جاهزان';
GO

-- ----------------------------------------------------------------------------
--  2026-08-19 — إصدار المنظمة
--
--  الإصدار يحدّد **شكل** النظام لا حجمه: أي وحدات تعمل، وكيف تتصرّف نقطة
--  البيع. وهو غير plan_tier في licenses الذي يحدّد الحدود (فروع، مستخدمون،
--  مدّة). منظمة على إصدار المحفظة قد تكون كبيرة، وأخرى قياسية قد تكون
--  تجريبية.
--
--    standard : متجر كامل — أصناف ومخزون ومشتريات ونقطة بيع
--    wallet   : بطاقات وأرصدة بلا أي بضاعة. الكاشير يُدخل مبلغاً فيُخصم من
--               بطاقة العامل أو يُسجَّل بيعاً نقدياً للفرع. للجهة التي تصرف
--               على منتسبيها لا التي تبيع بضاعة.
--    trial    : قياسي بمدّة محدودة
--    enterprise : قياسي بحدود أوسع
--
--  عمود واحد بقيمة نصية لا جدول: القيمة تُقرأ في كل طلب تقريباً (لبناء
--  التنقّل وسلوك نقطة البيع)، وربطها بجدول يعني وصلة في كل استعلام مقابل
--  لا شيء — فهي لا تحمل خصائص أخرى تُخزَّن.
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.organizations') AND name = 'edition')
BEGIN
    ALTER TABLE dbo.organizations
        ADD edition NVARCHAR(20) NOT NULL CONSTRAINT df_organizations_edition DEFAULT 'standard';
    PRINT N'أُضيف عمود organizations.edition';
END
GO

PRINT N'إصدار المنظمة جاهز';
GO

-- ----------------------------------------------------------------------------
--  2026-08-19 — الدفاتر: الدفع الجزئي، النقد المستلَم، الاستلام الجزئي
-- ----------------------------------------------------------------------------

-- النقد المستلَم والباقي.
--
-- كانت حاسبة النقد في نقطة البيع تحسبهما وتعرضهما ثم تنساهما: لا يُطبعان
-- على الإيصال ولا يُراجَعان في تسوية الدرج آخر اليوم. ورقم لا يُحفَظ لا
-- يُدقَّق — والدرج الناقص حينها لا يُعرف أهو خطأ صرف أم سرقة.
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.invoices') AND name = 'tendered_amount')
BEGIN
    ALTER TABLE dbo.invoices ADD tendered_amount DECIMAL(18,3) NULL;
    PRINT N'أُضيف عمود invoices.tendered_amount';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.invoices') AND name = 'change_due')
BEGIN
    ALTER TABLE dbo.invoices ADD change_due DECIMAL(18,3) NULL;
    PRINT N'أُضيف عمود invoices.change_due';
END
GO

-- المدفوع فعلاً من إجمالي الفاتورة.
--
-- NULL أو مساوٍ للإجمالي = مدفوعة بالكامل، وهو حال كل الفواتير السابقة.
-- وأقلّ منه = دفع جزئي، والفرق دَينٌ مقيَّد على محفظة العميل بحركة مدينة.
-- لا جدول ديون منفصل: دفتر المحفظة هو دفتر العميل، ورصيده السالب هو دَينه
-- — فيظهر في كشف حسابه ويُسدَّد بشحنة كأي رصيد.
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.invoices') AND name = 'paid_amount')
BEGIN
    ALTER TABLE dbo.invoices ADD paid_amount DECIMAL(18,3) NULL;
    PRINT N'أُضيف عمود invoices.paid_amount';
END
GO

-- الكمية المستلَمة فعلياً من كل سطر أمر شراء.
--
-- كان الاستلام كلّه-أو-لا-شيء: ReceiveLineRequest بلا حقل كمية أصلاً، فأي
-- توريد ناقص من المورّد لا يمكن تسجيله كما وقع — إمّا يُستلَم الأمر كاملاً
-- (فيدخل المخزون بضاعة لم تصل) أو يبقى معلَّقاً (فلا تدخل بضاعة وصلت).
-- كلاهما رصيد خاطئ في الدفتر.
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.purchase_order_items') AND name = 'received_quantity')
BEGIN
    ALTER TABLE dbo.purchase_order_items
        ADD received_quantity DECIMAL(18,3) NOT NULL
            CONSTRAINT df_po_items_received DEFAULT 0;
    PRINT N'أُضيف عمود purchase_order_items.received_quantity';
END
GO

-- تعبئة الماضي في دفعة منفصلة — والفصل إلزامي لا تنظيمي.
--
-- SQL Server يترجم الدفعة كاملةً قبل تنفيذ أي سطر منها، فعمودٌ يُضاف
-- بـALTER في نفس الدفعة لا يعرفه المترجم بعد: تفشل الدفعة كلها بـ«Invalid
-- column name» ولا يُنفَّذ حتى الـALTER نفسه. GO بينهما هو ما يجعل الأولى
-- تكتمل قبل ترجمة الثانية.
--
-- والأوامر المستلَمة سابقاً استُلمت بالكامل بحكم آلية ذلك الوقت، فتُضبط
-- كميتها المستلَمة على المطلوبة — وإلا ظهرت كلها «ناقصة» بعد الترحيل.
-- والشرط received_quantity = 0 يجعلها آمنة للإعادة: لا تدهس استلاماً
-- جزئياً سُجّل بعد الترحيل.
IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID('dbo.purchase_order_items') AND name = 'received_quantity')
BEGIN
    UPDATE i SET i.received_quantity = i.quantity
    FROM dbo.purchase_order_items i
    JOIN dbo.purchase_orders o ON o.id = i.purchase_order_id
    WHERE o.status = 'received' AND i.received_quantity = 0;

    IF @@ROWCOUNT > 0 PRINT N'ضُبطت الكميات المستلَمة للأوامر المكتملة سابقاً';
END
GO

PRINT N'أعمدة الدفاتر جاهزة';
GO

-- ----------------------------------------------------------------------------
--  2026-08-19 — شروط العقد المالية على الترخيص
--
--  تُحفَظ لا تُطبَع وتُنسى: العقد يُعاد طبعه بعد شهور عند خلاف أو تجديد،
--  وقيمةٌ أُدخلت مرّة في نافذة ثم ضاعت تجعل النسخة الثانية مختلفة عن
--  الأولى — وعقدان بمبلغين مختلفين أسوأ من غياب العقد.
--
--  على licenses لا على organizations: هي شروط الاشتراك لا هوية الشركة،
--  وتتغيّر مع كل تجديد بينما الهوية ثابتة.
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.licenses') AND name = 'monthly_fee')
BEGIN
    ALTER TABLE dbo.licenses ADD monthly_fee DECIMAL(18,3) NOT NULL
        CONSTRAINT df_licenses_monthly_fee DEFAULT 0;
    PRINT N'أُضيف عمود licenses.monthly_fee';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.licenses') AND name = 'storage_fee')
BEGIN
    ALTER TABLE dbo.licenses ADD storage_fee DECIMAL(18,3) NOT NULL
        CONSTRAINT df_licenses_storage_fee DEFAULT 0;
    PRINT N'أُضيف عمود licenses.storage_fee';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.licenses') AND name = 'maintenance_rate')
BEGIN
    ALTER TABLE dbo.licenses ADD maintenance_rate DECIMAL(9,3) NOT NULL
        CONSTRAINT df_licenses_maintenance_rate DEFAULT 0;
    PRINT N'أُضيف عمود licenses.maintenance_rate';
END
GO

PRINT N'شروط العقد المالية جاهزة';
GO

-- ----------------------------------------------------------------------------
--  فهارس الأداء — ملف منفصل لأنه يُنفَّذ ويُعاد بلا خطر
-- ----------------------------------------------------------------------------
PRINT N'لا تنسَ تنفيذ docs\INDEXES.sql على هذه القاعدة أيضاً.';
GO
