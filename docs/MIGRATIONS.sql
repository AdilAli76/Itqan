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

-- لا USE هنا عمداً: هذا الملف يُنفَّذ بـ -d (راجع سطر التنفيذ أعلاه)، وسطر
-- USE ثابت كان يتجاوز الاسم المُمرَّر فيكتب الكائنات في KineticEnterprise
-- مهما كانت القاعدة المقصودة — وهو ما كان يُعطّل tool/run_local.ps1 -Database
-- ويجعله يلوّث قاعدة التطوير بدل قاعدة التجربة.

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
    ('expenses.manage',        N'تسجيل المصروفات',                           N'expenses'),
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

-- ── دالة الحفيد: سطر الدفعة يصل إلى المنظمة عبر قفزتين ──────────────────
--
-- invoice_item_batches لا يحمل invoice_id ولا organization_id، بل
-- invoice_item_id وحده. فبقي **الجدول الوحيد بلا عزل** بينما أبوه محميّ —
-- وحمايةُ الأب لا تحمي الابن: أي استعلام مباشر على الحفيد يقرأ أرقام دفعات
-- كل المنظمات وكمّياتها. وهو ليس جدولاً هامشياً: منه يُبنى المرتجع، ومنه
-- يُعرف ما بيع من أي شحنة.
IF OBJECT_ID('Security.fn_InvoiceGrandChild', 'IF') IS NULL
EXEC('
CREATE FUNCTION Security.fn_InvoiceGrandChild(@InvoiceItemId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE EXISTS (
    SELECT 1 FROM dbo.invoice_items ii
    JOIN dbo.invoices i ON i.id = ii.invoice_id
    WHERE ii.id = @InvoiceItemId
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
--  تخصيص دفعات سطر الفاتورة — شرط FEFO وصحّة المرتجع
--
--  البيع كان يلتقط دفعة واحدة عشوائياً (FirstOrDefault بلا ORDER BY) بينما
--  UQ_stock_levels يسمح بصفٍّ لكل دفعة، فوقع خطآن: رفض بيع 15 والمتاح 30
--  موزّعة على ثلاث دفعات، وخصمٌ من دفعة بعيدة الانتهاء بينما القريبة تتلف.
--
--  والمرتجع كان يعيد الكمية إلى دفعة عامة ("") لتعذّر معرفة الأصل — فينتفخ
--  رصيد بلا تاريخ صلاحية وتبقى الدفعة الحقيقية ناقصة.
--
--  الفواتير المُنشأة قبل هذا الترحيل بلا صفوف هنا، وتُسترجَع بالسلوك القديم
--  (دفعة عامة) عمداً — راجع ReturnInvoice في InvoicesController.cs.
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'invoice_item_batches')
BEGIN
    CREATE TABLE dbo.invoice_item_batches (
        id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        invoice_item_id UNIQUEIDENTIFIER NOT NULL
            REFERENCES dbo.invoice_items(id) ON DELETE CASCADE,
        batch_number NVARCHAR(60) NOT NULL DEFAULT '',
        quantity DECIMAL(14,3) NOT NULL
    );
    PRINT N'أُنشئ جدول invoice_item_batches';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_invoice_item_batches_item')
BEGIN
    CREATE INDEX IX_invoice_item_batches_item
        ON dbo.invoice_item_batches (invoice_item_id);
    PRINT N'أُنشئ فهرس IX_invoice_item_batches_item';
END
GO

-- عزل صفوف جدول الحفيد — **بعد إنشائه لا قبله**.
--
-- كانت هذه الكتلة بين سياسات الجداول الأبناء أعلاه، أي قبل الترحيل الذي
-- يُنشئ invoice_item_batches بمئتَي سطر. على قاعدة جديدة لا أثر للترتيب
-- (المخطّط الكامل يُنشئ الجدول أولاً)، وعلى **قاعدة قائمة تسبق هذا الجدول**
-- كانت الترقية تتوقّف بـ«Cannot find the object dbo.invoice_item_batches».
--
-- وشرط وجود الجدول مضاف فوق الترتيب: الترتيب وحده يعتمد على ألّا يُعاد
-- تنظيم الملف، والشرط لا يعتمد على شيء.
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'invoice_item_batches')
   AND NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'InvoiceItemBatchesPolicy')
EXEC('
CREATE SECURITY POLICY Security.InvoiceItemBatchesPolicy
  ADD FILTER PREDICATE Security.fn_InvoiceGrandChild(invoice_item_id) ON dbo.invoice_item_batches,
  ADD BLOCK PREDICATE Security.fn_InvoiceGrandChild(invoice_item_id) ON dbo.invoice_item_batches AFTER INSERT
  WITH (STATE = ON);');
GO

PRINT N'تخصيص دفعات الفواتير جاهز';
GO

-- ----------------------------------------------------------------------------
--  نشرة الدواء — إصدار الصيدليات وحده
--
--  الجدول على مستوى المنصّة (بلا organization_id وبلا Security Policy):
--  «باراسيتامول 500 مجم» له نفس موانع الاستعمال في كل صيدلية، وربطه
--  بالمنظمة كان يعني أن كل عميل يبدأ بنشرات فارغة فتُهمَل الميزة.
--
--  يُنشأ في كل قاعدة لكن لا يُقرأ إلا لمن يملك وحدة pharmacy — النظام يُباع
--  لبقالة ومحل قطع غيار أيضاً. راجع Editions.ModulesOf في Entities.cs
--  و RequireModule("pharmacy") على MedicineReferenceController.
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'medicine_reference')
BEGIN
    CREATE TABLE dbo.medicine_reference (
        id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        name NVARCHAR(200) NOT NULL,
        active_ingredient NVARCHAR(200) NOT NULL,
        strength NVARCHAR(60) NULL,
        form NVARCHAR(60) NULL,
        indications NVARCHAR(1000) NULL,
        contraindications NVARCHAR(1000) NULL,
        cautions NVARCHAR(1000) NULL,
        side_effects NVARCHAR(1000) NULL,
        requires_prescription BIT NOT NULL DEFAULT 0,
        is_deleted BIT NOT NULL DEFAULT 0,
        created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        updated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
    PRINT N'أُنشئ جدول medicine_reference';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.products') AND name = 'medicine_ref_id')
BEGIN
    -- NULL دائماً مسموح: الصيدلية نفسها تبيع مستحضرات تجميل وحفاضات وأدوات.
    ALTER TABLE dbo.products ADD medicine_ref_id UNIQUEIDENTIFIER NULL
        CONSTRAINT FK_products_medicine_ref REFERENCES dbo.medicine_reference(id);
    PRINT N'أُضيف عمود products.medicine_ref_id';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_medicine_reference_ingredient')
BEGIN
    -- البحث بالمادة الفعّالة هو مدخل الصيدلي الطبيعي (بديل، تكرار مادة).
    CREATE INDEX IX_medicine_reference_ingredient
        ON dbo.medicine_reference (active_ingredient) WHERE is_deleted = 0;
    PRINT N'أُنشئ فهرس IX_medicine_reference_ingredient';
END
GO

PRINT N'نشرة الدواء جاهزة';
GO

-- ----------------------------------------------------------------------------
--  دفتر الوصفات — إصدار الصيدليات
--
--  سجلٌّ لكل صرف دواء مقيَّد بوصفة. بيانات منظمة لا معرفة عامة (بخلاف
--  medicine_reference)، فيحمل organization_id وbranch_id وتُطبَّق عليه سياسة
--  العزل. مرتبط بالفاتورة لأن الوصفة تُقدَّم لحظة الصرف — وربطها بما صُرِف
--  فعلاً هو ما يجعل الدفتر قابلاً للمراجعة.
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'prescriptions')
BEGIN
    CREATE TABLE dbo.prescriptions (
        id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        organization_id UNIQUEIDENTIFIER NOT NULL
            REFERENCES dbo.organizations(id) ON DELETE CASCADE,
        branch_id UNIQUEIDENTIFIER NOT NULL
            REFERENCES dbo.branches(id) ON DELETE NO ACTION,
        invoice_id UNIQUEIDENTIFIER NULL
            REFERENCES dbo.invoices(id) ON DELETE NO ACTION,
        prescription_number NVARCHAR(60) NULL,
        doctor_name NVARCHAR(150) NOT NULL,
        doctor_license NVARCHAR(60) NULL,
        patient_name NVARCHAR(150) NOT NULL,
        patient_phone NVARCHAR(30) NULL,
        issued_on DATE NULL,
        notes NVARCHAR(500) NULL,
        created_by UNIQUEIDENTIFIER NULL REFERENCES dbo.app_users(id),
        created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
    PRINT N'أُنشئ جدول prescriptions';
END
GO

-- سياسة العزل تُنشأ منفصلة عن الجدول: قد يكون الجدول موجوداً من ترحيل سابق
-- بلا سياسة، وتركه بلا عزل يعني أن صيدلية تقرأ وصفات صيدلية أخرى.
IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'PrescriptionsPolicy')
   AND EXISTS (SELECT 1 FROM sys.tables WHERE name = 'prescriptions')
BEGIN
    EXEC(N'CREATE SECURITY POLICY Security.PrescriptionsPolicy
        ADD FILTER PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.prescriptions,
        ADD BLOCK PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.prescriptions AFTER INSERT
        WITH (STATE = ON);');
    PRINT N'أُنشئت سياسة العزل PrescriptionsPolicy';
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.permissions WHERE code = 'prescriptions.dispense')
BEGIN
    INSERT INTO dbo.permissions (code, label_ar, module)
    VALUES ('prescriptions.dispense', N'صرف الأدوية المقيَّدة بوصفة وتسجيلها', N'pharmacy');
    PRINT N'أُضيفت صلاحية prescriptions.dispense';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_prescriptions_org_branch_date')
BEGIN
    -- الدفتر يُراجَع بالتاريخ (تفتيش، مراجعة شهرية) لا بالمعرّف.
    CREATE INDEX IX_prescriptions_org_branch_date
        ON dbo.prescriptions (organization_id, branch_id, created_at DESC);
    PRINT N'أُنشئ فهرس IX_prescriptions_org_branch_date';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_prescriptions_invoice')
BEGIN
    CREATE INDEX IX_prescriptions_invoice ON dbo.prescriptions (invoice_id)
        WHERE invoice_id IS NOT NULL;
    PRINT N'أُنشئ فهرس IX_prescriptions_invoice';
END
GO

PRINT N'دفتر الوصفات جاهز';
GO

-- ----------------------------------------------------------------------------
--  البيع بالوحدة الجزئية — الصيدلية تشتري شريطاً وتبيع حبّة
--
--  المخزون يُعدّ بالوحدة الأساسية دائماً، والبيع الجزئي يخصم كسراً منها
--  (stock_levels.quantity من نوع DECIMAL(14,3) فيتّسع للكسر أصلاً).
--
--  وسعر الوحدة الجزئية مستقلٌّ لا يُشتقّ بالقسمة: الصيدلية تربح على التجزئة،
--  فحبّة من شريط بثمانية دنانير تُباع بدينار لا بـ0.80. اشتقاقه بالقسمة كان
--  يعني بيعاً بالتكلفة بلا أن ينتبه أحد.
--
--  ليست مقصورة على إصدار الصيدليات: بقالة تبيع البيضة من الطبق، ومحل قطع
--  غيار يبيع البرغي من العلبة. فلا RequireModule عليها.
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.products') AND name = 'sub_unit_name')
BEGIN
    ALTER TABLE dbo.products ADD
        sub_unit_name NVARCHAR(30) NULL,
        sub_units_per_base DECIMAL(10,3) NOT NULL
            CONSTRAINT df_products_sub_units_per_base DEFAULT 0,
        sub_unit_price DECIMAL(14,2) NOT NULL
            CONSTRAINT df_products_sub_unit_price DEFAULT 0;
    PRINT N'أُضيفت أعمدة البيع بالوحدة الجزئية إلى products';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.invoice_items') AND name = 'sold_as_sub_unit')
BEGIN
    -- الكمية والسعر يُحفَظان كما بيعا فعلاً؛ هذان العمودان يوثّقان بأي وحدة
    -- كان البيع، وبأي معامل تحويل وقتها — فيعيد المرتجع ما خرج فعلاً.
    ALTER TABLE dbo.invoice_items ADD
        sold_as_sub_unit BIT NOT NULL
            CONSTRAINT df_invoice_items_sold_as_sub_unit DEFAULT 0,
        sub_units_per_base DECIMAL(10,3) NOT NULL
            CONSTRAINT df_invoice_items_sub_units_per_base DEFAULT 0;
    PRINT N'أُضيفت أعمدة الوحدة الجزئية إلى invoice_items';
END
GO

PRINT N'البيع بالوحدة الجزئية جاهز';
GO

-- ----------------------------------------------------------------------------
--  مهلة التوريد — نصف معادلة إعادة الطلب
--
--  حدّ إعادة الطلب رقم يُدخله المستخدم يدوياً ويُنسى، فيبقى على قيمته الأولى
--  بينما يتغيّر الاستهلاك. المشتقّ منه = متوسط الاستهلاك اليومي × مهلة
--  التوريد، ولا يمكن اشتقاقه بلا معرفة المهلة.
--
--  ولا يُكتب المشتقّ فوق اليدوي: اقتراحٌ يُعرض في التقرير ويطبّقه المدير إن
--  اقتنع. الكتابة الصامتة فوق قرار إداري تُفقد الثقة بالنظام كلّه.
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.products') AND name = 'lead_time_days')
BEGIN
    ALTER TABLE dbo.products ADD lead_time_days INT NOT NULL
        CONSTRAINT df_products_lead_time_days DEFAULT 7;
    PRINT N'أُضيف عمود products.lead_time_days';
END
GO

PRINT N'مهلة التوريد جاهزة';
GO

-- ----------------------------------------------------------------------------
--  قفل المخزون — إيقاف دفعة عن الصرف مع بقائها في مكانها
--
--  الحالة: تصل دفعة بشبهة عيب، أو ينتظر صنف نتيجة فحص، أو تُرتجع بضاعة يجب
--  ألّا تُباع قبل معاينتها. الحلول الثلاثة المتاحة قبل هذه الأعمدة كانت كلها
--  معطوبة: حذف الصفّ يفقد الكمية ويكسر التدقيق، وتركه يعني أن يبيعها
--  الكاشير، ونقلها إلى فرع وهمي يشوّه كل تقارير الفروع.
--
--  الموقوف يخرج من: البيع (FEFO في InvoicesController)، وحساب إعادة الطلب،
--  والتحويل بين الفروع. ويبقى في: الجرد، وقيمة المخزون، وتقرير الصلاحية —
--  فهو مالٌ مملوك فعلاً وموجود على الرفّ.
--
--  الافتراضي 0 على كل الصفوف القائمة، فلا أثر على أي بيانات موجودة.
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.stock_levels') AND name = 'is_locked')
BEGIN
    ALTER TABLE dbo.stock_levels ADD
        is_locked BIT NOT NULL CONSTRAINT df_stock_levels_is_locked DEFAULT 0,
        lock_reason NVARCHAR(300) NULL,
        locked_by UNIQUEIDENTIFIER NULL,
        locked_at DATETIME2 NULL;
    PRINT N'أُضيفت أعمدة قفل المخزون إلى stock_levels';
END
GO

-- المفتاح الأجنبي في دفعة منفصلة: ALTER TABLE ADD أعلاه لا يرى الأعمدة التي
-- أنشأها هو نفسه في الدفعة ذاتها.
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'fk_stock_levels_locked_by')
   AND EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.stock_levels') AND name = 'locked_by')
BEGIN
    ALTER TABLE dbo.stock_levels ADD CONSTRAINT fk_stock_levels_locked_by
        FOREIGN KEY (locked_by) REFERENCES dbo.app_users(id);
    PRINT N'أُضيف قيد stock_levels.locked_by';
END
GO

PRINT N'قفل المخزون جاهز';
GO

-- ----------------------------------------------------------------------------
--  تاريخ الاستراتيجية — ترتيب الصرف بحقل واحد يوحّد FEFO وFIFO
--
--  الصيدلية يجب أن تصرف الأقرب انتهاءً، والبقالة تكفيها الأقدم دخولاً. فبدل
--  قاعدتَي ترتيب منفصلتين، تاريخٌ واحد يُملأ بحسب طبيعة الصنف:
--
--      صنف بصلاحية   → تاريخ الانتهاء  ⇒ FEFO
--      صنف بلا صلاحية → تاريخ الإدخال   ⇒ FIFO
--
--  العطب الذي يصلحه: ترتيب الصرف كان `ORDER BY expiry_date, batch_number`.
--  والصنف بلا صلاحية كل دفعاته expiry_date = NULL، فيسقط الترتيب كلّه على
--  رقم الدفعة أبجدياً — أي عشوائياً فعلياً. النتيجة دفعة قديمة تبقى على
--  الرفّ إلى ما لا نهاية لأن رقمها يبدأ بحرف متأخّر.
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.stock_levels') AND name = 'strategy_date')
BEGIN
    ALTER TABLE dbo.stock_levels ADD strategy_date DATETIME2 NULL;
    PRINT N'أُضيف عمود stock_levels.strategy_date';
END
GO

-- التعبئة الرجعية للصفوف القائمة، بنفس قاعدة StockLevel.StampStrategyDate:
--
--   ذات صلاحية                    → تاريخ الانتهاء.
--   صنف لا يتتبّع الصلاحية أصلاً    → updated_at، أقرب تقريب متاح لتاريخ
--                                    الإدخال (لا يوجد created_at على الجدول).
--   صنف يتتبّع الصلاحية بلا تاريخ   → يُترك NULL فيُؤخَّر في الصرف — وهو
--                                    السلوك القائم اليوم حرفياً، فلا تتغيّر
--                                    نتيجة أي صرف بسبب هذا الترحيل.
-- ⚠ stock_levels محمي بسياسة عزل: التعبئة بلا SESSION_CONTEXT تُطبَّق على
-- صفر صفوف بصمت (راجع تحذير رأس الملف). فيُدار على المنظمات كما في ترحيل
-- role_permissions أعلاه.
DECLARE @sdOrg UNIQUEIDENTIFIER;
DECLARE @sdFilled INT = 0;
DECLARE sd_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT organization_id FROM dbo.app_users;
OPEN sd_cursor;
FETCH NEXT FROM sd_cursor INTO @sdOrg;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sp_set_session_context @key = N'organization_id', @value = @sdOrg;

    UPDATE sl
    SET strategy_date = COALESCE(
            CAST(sl.expiry_date AS DATETIME2),
            CASE WHEN p.track_expiry = 0 THEN sl.updated_at END)
    FROM dbo.stock_levels sl
    JOIN dbo.products p ON p.id = sl.product_id
    WHERE sl.strategy_date IS NULL;
    SET @sdFilled = @sdFilled + @@ROWCOUNT;

    FETCH NEXT FROM sd_cursor INTO @sdOrg;
END
CLOSE sd_cursor;
DEALLOCATE sd_cursor;
EXEC sp_set_session_context @key = N'organization_id', @value = NULL;
PRINT N'تاريخ الاستراتيجية: عُبِّئ ' + CAST(@sdFilled AS NVARCHAR) + N' صفّاً';
GO

PRINT N'تاريخ الاستراتيجية جاهز';
GO

-- ----------------------------------------------------------------------------
--  خطوة اعتماد فروقات الجرد
--
--  كان الجرد ينتقل من open إلى reconciled بضغطة واحدة، فيُطبَّق فرقٌ ناتج عن
--  خطأ عدّ على المخزون بلا أن يراه أحد. والفرق ليس رقماً محايداً: زيادة
--  تُخفي سرقة، ونقصٌ يشطب بضاعة موجودة على الرفّ.
--
--  الحالة الجديدة pending_review تفرض قراراً بشرياً بخيارين لا ثالث لهما:
--  اقبل الفرق، أو أعد العدّ. وجردٌ بلا فرق واحد لا يمرّ بها — إجبار المستخدم
--  على تأكيد «لا شيء تغيّر» يُعلّمه أن يضغط بلا قراءة، وهو نقيض الغرض.
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.stock_counts') AND name = 'submitted_by')
BEGIN
    ALTER TABLE dbo.stock_counts ADD
        submitted_by UNIQUEIDENTIFIER NULL,
        submitted_at DATETIME2 NULL,
        reviewed_by UNIQUEIDENTIFIER NULL,
        reviewed_at DATETIME2 NULL,
        recount_reason NVARCHAR(300) NULL,
        recount_rounds INT NOT NULL CONSTRAINT df_stock_counts_recount_rounds DEFAULT 0;
    PRINT N'أُضيفت أعمدة اعتماد فروقات الجرد';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'fk_stock_counts_submitted_by')
   AND EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.stock_counts') AND name = 'submitted_by')
BEGIN
    ALTER TABLE dbo.stock_counts ADD
        CONSTRAINT fk_stock_counts_submitted_by FOREIGN KEY (submitted_by) REFERENCES dbo.app_users(id),
        CONSTRAINT fk_stock_counts_reviewed_by  FOREIGN KEY (reviewed_by)  REFERENCES dbo.app_users(id);
    PRINT N'أُضيفت قيود stock_counts.submitted_by/reviewed_by';
END
GO

-- توسيع قيد الحالة ليقبل pending_review.
--
-- القيد القديم مكتوب داخل تعريف العمود، فاسمه مولَّد بلاحقة هاش تختلف بين
-- القواعد (CK__stock_cou__statu__32AB8735) — فيُبحَث عنه بالجدول والعمود لا
-- بالاسم. والجديد **مسمّى صراحةً**: بلا اسم ثابت لا يمكن ربط رسالة عربية به
-- في DbConstraintMessageMiddleware، ولا توسيعه لاحقاً بأمان.
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_stock_counts_status')
BEGIN
    DECLARE @old SYSNAME = (
        SELECT TOP 1 cc.name
        FROM sys.check_constraints cc
        JOIN sys.columns c ON c.object_id = cc.parent_object_id AND c.column_id = cc.parent_column_id
        WHERE cc.parent_object_id = OBJECT_ID('dbo.stock_counts') AND c.name = 'status');

    IF @old IS NOT NULL
        EXEC('ALTER TABLE dbo.stock_counts DROP CONSTRAINT [' + @old + ']');

    ALTER TABLE dbo.stock_counts ADD CONSTRAINT CK_stock_counts_status
        CHECK (status IN ('open','pending_review','reconciled','cancelled'));
    PRINT N'وُسِّع قيد stock_counts.status ليقبل pending_review';
END
GO

PRINT N'خطوة اعتماد فروقات الجرد جاهزة';
GO

-- ----------------------------------------------------------------------------
--  مستند الاستلام — شحنة واحدة من أمر شراء
--
--  received_quantity رقم تراكمي يبتلع ثلاث شحنات في واحدة. فتضيع تواريخ
--  الوصول (ومعها قياس مهلة التوريد الحقيقية بدل lead_time_days المُدخَل
--  بالظنّ)، ورقم إشعار المورّد وهو المرجع الوحيد عند الخلاف، وأي شحنة تخصّ
--  أي فاتورة مورّد حين تُبنى المطابقة.
--
--  شرط مسبق لدفتر حركة المخزون: سطر الإدخال يشير إلى مستند وصول حقيقي.
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'purchase_receipts')
BEGIN
    CREATE TABLE dbo.purchase_receipts (
        id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.organizations(id) ON DELETE CASCADE,
        branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.branches(id) ON DELETE NO ACTION,
        purchase_order_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.purchase_orders(id) ON DELETE NO ACTION,
        supplier_note_number NVARCHAR(60) NULL,
        received_on DATETIME2 NOT NULL,
        received_by UNIQUEIDENTIFIER NULL REFERENCES dbo.app_users(id),
        notes NVARCHAR(300) NULL,
        created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
    PRINT N'أُنشئ جدول purchase_receipts';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'purchase_receipt_items')
BEGIN
    CREATE TABLE dbo.purchase_receipt_items (
        id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        purchase_receipt_id UNIQUEIDENTIFIER NOT NULL
            REFERENCES dbo.purchase_receipts(id) ON DELETE CASCADE,
        purchase_order_item_id UNIQUEIDENTIFIER NOT NULL
            REFERENCES dbo.purchase_order_items(id) ON DELETE NO ACTION,
        product_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.products(id),
        quantity DECIMAL(14,3) NOT NULL,
        batch_number NVARCHAR(60) NOT NULL DEFAULT '',
        expiry_date DATE NULL,
        unit_cost DECIMAL(14,2) NOT NULL DEFAULT 0
    );
    PRINT N'أُنشئ جدول purchase_receipt_items';
END
GO

-- العزل بعد إنشاء الجدول — وبشرط وجوده، لا بترتيب السطور وحده. (الترتيب
-- وحده هو ما أوقف ترقية 2026-08-24 على قاعدة إنتاج تسبق invoice_item_batches.)
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'purchase_receipts')
   AND NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'PurchaseReceiptsPolicy')
EXEC('
CREATE SECURITY POLICY Security.PurchaseReceiptsPolicy
  ADD FILTER PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.purchase_receipts,
  ADD BLOCK PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.purchase_receipts AFTER INSERT
  WITH (STATE = ON);');
GO

-- سطور المستند تصل إلى المنظمة عبر أبيها، كبقية جداول الأبناء.
IF OBJECT_ID('Security.fn_PurchaseReceiptChild', 'IF') IS NULL
   AND EXISTS (SELECT 1 FROM sys.tables WHERE name = 'purchase_receipts')
EXEC('
CREATE FUNCTION Security.fn_PurchaseReceiptChild(@ReceiptId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE EXISTS (
    SELECT 1 FROM dbo.purchase_receipts r
    WHERE r.id = @ReceiptId
      AND r.organization_id = CAST(SESSION_CONTEXT(N''organization_id'') AS UNIQUEIDENTIFIER)
);');
GO

IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'purchase_receipt_items')
   AND NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'PurchaseReceiptItemsPolicy')
EXEC('
CREATE SECURITY POLICY Security.PurchaseReceiptItemsPolicy
  ADD FILTER PREDICATE Security.fn_PurchaseReceiptChild(purchase_receipt_id) ON dbo.purchase_receipt_items,
  ADD BLOCK PREDICATE Security.fn_PurchaseReceiptChild(purchase_receipt_id) ON dbo.purchase_receipt_items AFTER INSERT
  WITH (STATE = ON);');
GO

PRINT N'مستند الاستلام جاهز';
GO

-- ----------------------------------------------------------------------------
--  الديون: تاريخ استحقاق، وسلّم تذكير، وأعمار
--
--  البيع الآجل كان يقيّد الفرق دَيناً على محفظة العميل — وهو تصميم سليم
--  محاسبياً — لكنه دَينٌ **بلا موعد**: لا يُقال عنه «متأخّر»، فلا تقرير
--  أعمار ولا تذكير ولا أولوية تحصيل.
--
--  والتذكير يُسجَّل عند الإرسال لا عند حلول الموعد: صفٌّ آلي يجعل النظام
--  يدّعي مطالبةً لم تقع، فتُترك المطالبة الحقيقية.
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.customers') AND name = 'credit_days')
BEGIN
    ALTER TABLE dbo.customers ADD credit_days INT NOT NULL
        CONSTRAINT df_customers_credit_days DEFAULT 0;
    PRINT N'أُضيف عمود customers.credit_days';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.invoices') AND name = 'due_date')
BEGIN
    ALTER TABLE dbo.invoices ADD due_date DATETIME2 NULL;
    PRINT N'أُضيف عمود invoices.due_date';
END
GO

-- الفواتير الآجلة السابقة لهذا الترحيل تُملأ بتاريخ إصدارها: افتراض
-- «مستحقّ يوم البيع» أصدق من تركها فارغة، لأن الفراغ يُخفي ديناً قديماً في
-- خانة «لم يحن أجله بعد». (وDebtAging يعامل NULL بالمنطق نفسه احتياطاً.)
-- invoices محميّ بسياسة عزل — التعبئة بلا سياق تُطبَّق على صفر صفوف بصمت.
DECLARE @ddOrg UNIQUEIDENTIFIER;
DECLARE @ddFilled INT = 0;
DECLARE dd_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT organization_id FROM dbo.app_users;
OPEN dd_cursor;
FETCH NEXT FROM dd_cursor INTO @ddOrg;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sp_set_session_context @key = N'organization_id', @value = @ddOrg;

    UPDATE dbo.invoices
    SET due_date = created_at
    WHERE due_date IS NULL
      AND invoice_type = 'sale'
      AND paid_amount IS NOT NULL
      AND paid_amount < total_amount;
    SET @ddFilled = @ddFilled + @@ROWCOUNT;

    FETCH NEXT FROM dd_cursor INTO @ddOrg;
END
CLOSE dd_cursor;
DEALLOCATE dd_cursor;
EXEC sp_set_session_context @key = N'organization_id', @value = NULL;
PRINT N'تاريخ الاستحقاق: عُبِّئ ' + CAST(@ddFilled AS NVARCHAR) + N' فاتورة';
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'debt_reminders')
BEGIN
    CREATE TABLE dbo.debt_reminders (
        id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.organizations(id) ON DELETE CASCADE,
        customer_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.customers(id) ON DELETE NO ACTION,
        stage INT NOT NULL CONSTRAINT CK_debt_reminders_stage CHECK (stage BETWEEN 1 AND 3),
        due_on DATETIME2 NOT NULL,
        sent_at DATETIME2 NOT NULL CONSTRAINT df_debt_reminders_sent_at DEFAULT SYSUTCDATETIME(),
        sent_by UNIQUEIDENTIFIER NULL REFERENCES dbo.app_users(id),
        amount_at_reminder DECIMAL(14,2) NOT NULL CONSTRAINT df_debt_reminders_amount DEFAULT 0,
        note NVARCHAR(300) NULL
    );
    PRINT N'أُنشئ جدول debt_reminders';
END
GO

IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'debt_reminders')
   AND NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'DebtRemindersPolicy')
EXEC('
CREATE SECURITY POLICY Security.DebtRemindersPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.debt_reminders,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.debt_reminders AFTER INSERT
  WITH (STATE = ON);');
GO

PRINT N'الديون والتذكير والأعمار جاهزة';
GO

-- ----------------------------------------------------------------------------
--  الجرد الموزَّع، والجرد الابتدائي، والكمية المتوقَّعة
--
--  ثلاثة أعمدة تُكمل ثلاثة عيوب:
--
--  products.last_counted_at   الجرد كان كلّه أو لا شيء — إغلاق المحل يوماً
--                             كاملاً. بهذا العمود يُعدّ ما لم يُعدّ منذ مدّة.
--  stock_counts.kind          كل زبون جديد كان يُدخل مخزونه الأول صنفاً صنفاً
--                             من شاشة تعديل الكمية، بلا مستند ولا مراجعة.
--  purchase_orders.is_auto    الأمر المولَّد آلياً لا يُميَّز عن اليدوي، فلا
--                             تُراجَع المعادلة التي ولّدته.
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.products') AND name = 'last_counted_at')
BEGIN
    ALTER TABLE dbo.products ADD last_counted_at DATETIME2 NULL;
    PRINT N'أُضيف عمود products.last_counted_at';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.purchase_orders') AND name = 'is_auto')
BEGIN
    ALTER TABLE dbo.purchase_orders ADD is_auto BIT NOT NULL
        CONSTRAINT df_purchase_orders_is_auto DEFAULT 0;
    PRINT N'أُضيف عمود purchase_orders.is_auto';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.stock_counts') AND name = 'kind')
BEGIN
    ALTER TABLE dbo.stock_counts ADD kind NVARCHAR(20) NOT NULL
        CONSTRAINT df_stock_counts_kind DEFAULT 'periodic';
    PRINT N'أُضيف عمود stock_counts.kind';
END
GO

-- قيد مسمّى صراحةً — راجع القاعدة في ARCHITECTURE.md §2.16: القيد المكتوب
-- داخل تعريف العمود يولّد اسماً بلاحقة هاش تختلف بين القواعد.
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_stock_counts_kind')
   AND EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.stock_counts') AND name = 'kind')
BEGIN
    ALTER TABLE dbo.stock_counts ADD CONSTRAINT CK_stock_counts_kind
        CHECK (kind IN ('periodic','initial'));
    PRINT N'أُضيف قيد CK_stock_counts_kind';
END
GO

-- تعبئة رجعية لآخر عدّ: الجرود المعتمَدة السابقة تُثبت أن أصنافها عُدّت
-- يومها. بدونها يظهر كل صنف في أول جرد موزَّع وكأنه لم يُعدّ قطّ.
-- products وstock_counts محميّان بسياسة عزل — نفس السبب أعلاه.
DECLARE @lcOrg UNIQUEIDENTIFIER;
DECLARE @lcFilled INT = 0;
DECLARE lc_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT organization_id FROM dbo.app_users;
OPEN lc_cursor;
FETCH NEXT FROM lc_cursor INTO @lcOrg;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sp_set_session_context @key = N'organization_id', @value = @lcOrg;

    UPDATE p
    SET last_counted_at = x.closed_at
    FROM dbo.products p
    JOIN (
        SELECT sci.product_id, MAX(sc.closed_at) AS closed_at
        FROM dbo.stock_count_items sci
        JOIN dbo.stock_counts sc ON sc.id = sci.stock_count_id
        WHERE sc.status = 'reconciled' AND sc.closed_at IS NOT NULL
        GROUP BY sci.product_id
    ) x ON x.product_id = p.id
    WHERE p.last_counted_at IS NULL;
    SET @lcFilled = @lcFilled + @@ROWCOUNT;

    FETCH NEXT FROM lc_cursor INTO @lcOrg;
END
CLOSE lc_cursor;
DEALLOCATE lc_cursor;
EXEC sp_set_session_context @key = N'organization_id', @value = NULL;
PRINT N'آخر عدّ: عُبِّئ ' + CAST(@lcFilled AS NVARCHAR) + N' صنفاً';
GO

PRINT N'الجرد الموزَّع والابتدائي والكمية المتوقَّعة جاهزة';
GO

-- ============================================================================
--  المرحلة الثانية: دفتر حركة المخزون والمستودعات
--
--  الرصيد كان يُعدَّل في مكانه فلا تاريخ له ولا تكلفة. الدفتر يصبح مصدر
--  الحقيقة، وstock_levels ذاكرة مشتقّة تُكتب معه في المعاملة نفسها عبر
--  StockLedger وحده (Data/StockLedger.cs).
-- ============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'warehouses')
BEGIN
    CREATE TABLE dbo.warehouses (
        id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.organizations(id) ON DELETE CASCADE,
        branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.branches(id) ON DELETE NO ACTION,
        parent_warehouse_id UNIQUEIDENTIFIER NULL REFERENCES dbo.warehouses(id),
        name NVARCHAR(120) NOT NULL,
        code NVARCHAR(40) NOT NULL DEFAULT '',
        kind NVARCHAR(20) NOT NULL DEFAULT 'main',
        CONSTRAINT CK_warehouses_kind
            CHECK (kind IN ('main','transit','damaged','returns','quarantine')),
        is_group BIT NOT NULL DEFAULT 0,
        is_active BIT NOT NULL DEFAULT 1,
        created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
    PRINT N'أُنشئ جدول warehouses';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'stock_ledger_entries')
BEGIN
    CREATE TABLE dbo.stock_ledger_entries (
        id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.organizations(id) ON DELETE CASCADE,
        branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.branches(id) ON DELETE NO ACTION,
        warehouse_id UNIQUEIDENTIFIER NULL REFERENCES dbo.warehouses(id),
        product_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.products(id),
        batch_number NVARCHAR(60) NOT NULL DEFAULT '',
        expiry_date DATETIME2 NULL,
        posted_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        quantity_change DECIMAL(14,3) NOT NULL,
        balance_after DECIMAL(14,3) NOT NULL,
        unit_cost DECIMAL(14,2) NOT NULL DEFAULT 0,
        value_after DECIMAL(18,2) NOT NULL DEFAULT 0,
        value_change DECIMAL(18,2) NOT NULL DEFAULT 0,
        source_type NVARCHAR(30) NOT NULL,
        source_id UNIQUEIDENTIFIER NULL,
        source_entry_id UNIQUEIDENTIFIER NULL REFERENCES dbo.stock_ledger_entries(id),
        remaining_quantity DECIMAL(14,3) NOT NULL DEFAULT 0,
        created_by UNIQUEIDENTIFIER NULL REFERENCES dbo.app_users(id),
        created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        is_cancelled BIT NOT NULL DEFAULT 0,
        cancel_reason NVARCHAR(300) NULL
    );
    PRINT N'أُنشئ جدول stock_ledger_entries';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.stock_levels') AND name = 'warehouse_id')
BEGIN
    ALTER TABLE dbo.stock_levels ADD warehouse_id UNIQUEIDENTIFIER NULL
        CONSTRAINT fk_stock_levels_warehouse REFERENCES dbo.warehouses(id);
    PRINT N'أُضيف عمود stock_levels.warehouse_id';
END
GO

IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'warehouses')
   AND NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'WarehousesPolicy')
EXEC('
CREATE SECURITY POLICY Security.WarehousesPolicy
  ADD FILTER PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.warehouses,
  ADD BLOCK PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.warehouses AFTER INSERT
  WITH (STATE = ON);');
GO

IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'stock_ledger_entries')
   AND NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'StockLedgerEntriesPolicy')
EXEC('
CREATE SECURITY POLICY Security.StockLedgerEntriesPolicy
  ADD FILTER PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.stock_ledger_entries,
  ADD BLOCK PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.stock_ledger_entries AFTER INSERT
  WITH (STATE = ON);');
GO

-- ----------------------------------------------------------------------------
--  الحركة الافتتاحية — الخطوة التي بدونها يتوقّف البيع
--
--  الدفتر يصرف من **سطور الإدخال**، فقاعدة قائمة بلا سطر افتتاحي واحد تعني
--  أن كل بيع يفشل بـ«الكمية المتاحة صفر» بينما الرفّ ممتلئ.
--
--  ولذلك سطرٌ واحد لكل رصيد قائم بنوع opening: يقول إن هذه البضاعة كانت
--  موجودة قبل الدفتر، لا أنها ظهرت من العدم. تكلفتها من سعر تكلفة الصنف —
--  وهو أدقّ ما هو متاح، فلا تاريخ شراء لها يُقرأ منه أفضل.
--
--  ⚠ يدور على المنظمات: stock_levels محميّ بسياسة عزل، والإدراج بلا سياق
--  يرفضه مسند BLOCK صراحةً بخلاف التحديث الذي يمرّ صامتاً على صفر صفوف.
-- ----------------------------------------------------------------------------
-- ⚠ حارس التكرار **داخل** الحلقة لا قبلها: فحصٌ قبل ضبط السياق يقرأ عبر
-- سياسة العزل فيرى صفر صفوف دائماً — فيُعيد الإدراج في كل تنفيذ ويضاعف
-- الدفتر. وهو أيضاً الأصحّ منطقياً: منظمة تُضاف لاحقاً تستحقّ حركتها
-- الافتتاحية ولو كانت لغيرها حركات.
DECLARE @opOrg UNIQUEIDENTIFIER;
DECLARE @opRows INT = 0;

DECLARE op_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT organization_id FROM dbo.app_users;

OPEN op_cursor;
FETCH NEXT FROM op_cursor INTO @opOrg;

WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sp_set_session_context @key = N'organization_id', @value = @opOrg;

    IF NOT EXISTS (SELECT 1 FROM dbo.stock_ledger_entries WHERE source_type = 'opening')
    BEGIN
        INSERT INTO dbo.stock_ledger_entries (
            organization_id, branch_id, warehouse_id, product_id,
            batch_number, expiry_date, posted_at,
            quantity_change, balance_after, unit_cost, value_after, value_change,
            source_type, source_id, remaining_quantity)
        SELECT
            sl.organization_id, sl.branch_id, sl.warehouse_id, sl.product_id,
            sl.batch_number, CAST(sl.expiry_date AS DATETIME2),
            -- updated_at لا strategy_date: الأخير للصنف المتتبَّع هو تاريخ
            -- **الانتهاء**، ووضعه هنا يجعل الدفتر يقول إن البضاعة أُدخلت في
            -- 2027 — فينهار سؤال «كم كان الرصيد يوم كذا»، وهو غاية الدفتر.
            -- وترتيب الصرف لا يتأثّر: يقرأ expiry_date أوّلاً (المنسوخ أدناه)
            -- ثم posted_at.
            COALESCE(sl.updated_at, SYSUTCDATETIME()),
            sl.quantity, sl.quantity,
            p.cost_price, sl.quantity * p.cost_price, sl.quantity * p.cost_price,
            'opening', NULL, sl.quantity
        FROM dbo.stock_levels sl
        JOIN dbo.products p ON p.id = sl.product_id
        WHERE sl.quantity > 0;

        SET @opRows = @opRows + @@ROWCOUNT;
    END

    FETCH NEXT FROM op_cursor INTO @opOrg;
END

CLOSE op_cursor;
DEALLOCATE op_cursor;
EXEC sp_set_session_context @key = N'organization_id', @value = NULL;

PRINT N'الحركة الافتتاحية: أُنشئ ' + CAST(@opRows AS NVARCHAR) + N' سطر دفتر';
GO

PRINT N'دفتر حركة المخزون والمستودعات جاهزان';
GO

-- ----------------------------------------------------------------------------
--  مزامنة وحدات الترخيص مع الإصدار — شرط تفعيل فرض الوحدات
--
--  enabled_modules كان يُكتب عند إنشاء المنظمة ولا يقرأه أحد: التقييد كان
--  على الإصدار وحده. وقد صار يُفرَض الآن (LicenseLimits.EffectiveModules)،
--  فقائمة متخلّفة عن الإصدار تعني حجب وحدة يستعملها العميل اليوم — عقوبةً
--  على ترقية لا ذنب له فيها.
--
--  فتُزامَن مرّة: كل ترخيص يأخذ وحدات إصدار منظمته. وبعدها يُحدِّثها
--  PlatformController عند كل تغيير إصدار.
-- ----------------------------------------------------------------------------
DECLARE @lmOrg UNIQUEIDENTIFIER;
DECLARE @lmEdition NVARCHAR(20);
DECLARE @lmModules NVARCHAR(MAX);
DECLARE @lmCount INT = 0;

DECLARE lm_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT organization_id FROM dbo.app_users;

OPEN lm_cursor;
FETCH NEXT FROM lm_cursor INTO @lmOrg;

WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sp_set_session_context @key = N'organization_id', @value = @lmOrg;

    SELECT @lmEdition = edition FROM dbo.organizations;

    -- القوائم مطابقة لـEditions.ModulesOf في Entities.cs. تكرارها هنا مقصود
    -- ومحدود بترحيل يُنفَّذ مرّة: البديل — قراءتها من التطبيق — يجعل الترحيل
    -- يعتمد على تشغيل الخادم، وهو ما لا يحدث أثناء الترقية.
    SET @lmModules =
        CASE @lmEdition
            WHEN 'wallet'     THEN N'["pos","customers","reports"]'
            WHEN 'pharmacy'   THEN N'["inventory","pos","customers","reports","pharmacy"]'
            WHEN 'enterprise' THEN N'["inventory","pos","customers","reports","warehouses","valuation","procurement"]'
            ELSE                   N'["inventory","pos","customers","reports"]'
        END;

    UPDATE dbo.licenses
    SET enabled_modules = @lmModules
    WHERE organization_id = @lmOrg AND enabled_modules <> @lmModules;
    SET @lmCount = @lmCount + @@ROWCOUNT;

    FETCH NEXT FROM lm_cursor INTO @lmOrg;
END

CLOSE lm_cursor;
DEALLOCATE lm_cursor;
EXEC sp_set_session_context @key = N'organization_id', @value = NULL;

PRINT N'وحدات الترخيص: زُومنت ' + CAST(@lmCount AS NVARCHAR) + N' رخصة';
GO

PRINT N'فرض حدود الترخيص جاهز';
GO

-- ----------------------------------------------------------------------------
--  حالة الاشتراك ووضع القراءة فقط
--
--  حالات الترخيص الأربع كانت معرَّفة في المخطّط منذ اليوم الأول ولا يقرأها
--  سطر واحد: ترخيصٌ انتهى أو أُلغي كان يعمل كالجديد تماماً.
--
--  is_read_only عمود واحد يخدم ثلاث حاجات: نسخة عرض تُرى ولا تُعدَّل، وعميل
--  متأخّر يُجمَّد بلا فقد بياناته، ومهلة ما بعد الانتهاء التي يذكرها
--  ARCHITECTURE.md §2.2 — «قراءة فقط بدل توقّف مفاجئ يفقد ثقة الزبون».
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.licenses') AND name = 'is_read_only')
BEGIN
    ALTER TABLE dbo.licenses ADD
        is_read_only BIT NOT NULL CONSTRAINT df_licenses_is_read_only DEFAULT 0,
        status_reason NVARCHAR(300) NULL,
        status_changed_at DATETIME2 NULL;
    PRINT N'أُضيفت أعمدة حالة الاشتراك';
END
GO

PRINT N'حالة الاشتراك ووضع القراءة فقط جاهزان';
GO

-- ----------------------------------------------------------------------------
--  لوح خلفية الفرع
--
--  يميّز المكان لا الشخص: تفضيل السطوع شخصيّ يُحفَظ على الجهاز، واللوح يقول
--  لموظفٍ ينتقل بين فرعين أين هو الآن — فيمنع إدخال بيانات في الفرع الخطأ.
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.branches') AND name = 'theme_palette')
BEGIN
    ALTER TABLE dbo.branches ADD theme_palette NVARCHAR(20) NOT NULL
        CONSTRAINT df_branches_theme_palette DEFAULT 'default';
    PRINT N'أُضيف عمود branches.theme_palette';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_branches_theme_palette')
   AND EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.branches') AND name = 'theme_palette')
BEGIN
    ALTER TABLE dbo.branches ADD CONSTRAINT CK_branches_theme_palette
        CHECK (theme_palette IN ('default','warm','cool','green','slate'));
    PRINT N'أُضيف قيد CK_branches_theme_palette';
END
GO

PRINT N'لوح خلفية الفرع جاهز';
GO

-- ----------------------------------------------------------------------------
--  أنماط بطاقة المحفظة
--
--  العطب: الرقم السرّي كان **إلزامياً دائماً بلا بديل**. والرقم وسيلةُ إثبات
--  يعرفها طرفان: الزبون يُدخله على جهاز الكاشير، فيراه أو يلتقطه أو يحفظه، ثم
--  يسحب بعد انصرافه بالبحث عن اسمه. الإلزام بلا بديل هو ما يخلق الثغرة — لا
--  ضعف الرقم.
--
--  والقسمة: المنظمة تضع المظروف (المسموح والسقف والافتراضي)، والزبون يختار
--  داخله، **والكاشير لا يغيّر شيئاً** — من يستطيع خفض الحماية لحظة الصرف لا
--  تحميه حمايةٌ.
--
--  ولا حاجة لأي تعبئة رجعية هنا: كل الافتراضات تُبقي السلوك القائم كما هو
--  (الرقم السرّي)، فترقيةٌ لا تُرخي حراسة أحدٍ بلا علمه.
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.organizations') AND name = 'card_modes_allowed')
BEGIN
    ALTER TABLE dbo.organizations ADD card_modes_allowed NVARCHAR(100) NOT NULL
        CONSTRAINT df_organizations_card_modes_allowed DEFAULT 'card,pin';
    PRINT N'أُضيف عمود organizations.card_modes_allowed';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.organizations') AND name = 'card_mode_default')
BEGIN
    -- الافتراضي 'pin' لا 'card': الترقية لا تُنقص حماية حسابٍ قائم.
    ALTER TABLE dbo.organizations ADD card_mode_default NVARCHAR(20) NOT NULL
        CONSTRAINT df_organizations_card_mode_default DEFAULT 'pin';
    PRINT N'أُضيف عمود organizations.card_mode_default';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.organizations') AND name = 'card_open_mode_daily_cap')
BEGIN
    ALTER TABLE dbo.organizations ADD card_open_mode_daily_cap DECIMAL(18,2) NOT NULL
        CONSTRAINT df_organizations_card_open_cap DEFAULT 50;
    PRINT N'أُضيف عمود organizations.card_open_mode_daily_cap';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.customers') AND name = 'card_mode')
BEGIN
    -- NULL = اتبع افتراضي المنظمة. عمودٌ بقيمة صريحة لكل زبون كان سيُجمّد
    -- اختيارهم على ما كان يوم الترقية، ولا يسري تغيير المدير على أحد.
    ALTER TABLE dbo.customers ADD card_mode NVARCHAR(20) NULL;
    PRINT N'أُضيف عمود customers.card_mode';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.customers') AND name = 'daily_cap')
BEGIN
    ALTER TABLE dbo.customers ADD daily_cap DECIMAL(18,2) NOT NULL
        CONSTRAINT df_customers_daily_cap DEFAULT 0;
    PRINT N'أُضيف عمود customers.daily_cap';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_customers_card_mode')
   AND EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.customers') AND name = 'card_mode')
BEGIN
    -- 'phone' مسموح في القيد ولو لم يُعرَض بعد في الواجهة: القيد يحرس ما
    -- يُكتَب، والنمط سيُفعَّل يوم تُبنى قناة الإرسال بلا ترحيل ثانٍ.
    ALTER TABLE dbo.customers ADD CONSTRAINT CK_customers_card_mode
        CHECK (card_mode IS NULL OR card_mode IN ('card','pin','phone'));
    PRINT N'أُضيف قيد CK_customers_card_mode';
END
GO

PRINT N'أنماط بطاقة المحفظة جاهزة';
GO

-- ----------------------------------------------------------------------------
--  الجرد الميداني: تمييز «عُدَّ» من «لم يُمَسّ»
--
--  العطب: الجرد الدوري يبدأ بـ counted_quantity = system_quantity، ولا حقل
--  يميّز السطر الذي عُدَّ وطابق من السطر الذي لم يره أحد. فعاملٌ مسح أربعين
--  صنفاً من ثلاثمئة ثم أرسل، يقول له النظام «صفر فروقات» — لأن مئتين وستين
--  وافقت نفسها. والفرق بين «طابق» و«لم يُنظَر إليه» هو الجرد كلّه.
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.stock_count_items') AND name = 'counted_at')
BEGIN
    ALTER TABLE dbo.stock_count_items ADD counted_at DATETIME2 NULL;
    PRINT N'أُضيف عمود stock_count_items.counted_at';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.stock_count_items') AND name = 'added_during_count')
BEGIN
    ALTER TABLE dbo.stock_count_items ADD added_during_count BIT NOT NULL
        CONSTRAINT df_stock_count_items_added DEFAULT 0;
    PRINT N'أُضيف عمود stock_count_items.added_during_count';
END
GO

-- تعبئة رجعية: سطور الجرود **المغلقة** وحدها تُختَم بتاريخ إغلاقها.
--
--   • المغلقة اعتُمدت فعلاً بقرار بشري، فتركها NULL يجعل كل جرد تاريخي
--     يُقرأ لاحقاً كأنه «لم يُعدّ منه شيء» — وهو أكذب من ختمها.
--   • **والمفتوحة تُترك NULL عمداً**: لا نعرف أيّ سطر منها رآه العامل فعلاً،
--     وختمها كلّها يعني تثبيت الكذبة التي جاء هذا العمود ليكشفها. وNULL
--     تدفع إلى إعادة المسح — وهو الاتجاه الآمن. الكميات المُدخلة محفوظة كما
--     هي، فلا يضيع عمل أحد.
--
-- والتحديث عبر مؤشّر لكل منظمة: RLS تحجب صفوف المنظمات الأخرى، فتحديثٌ
-- واحد بلا سياق يُصيب صفر صفوف صامتاً (راجع رأس هذا الملف).
IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID('dbo.stock_count_items') AND name = 'counted_at')
BEGIN
    DECLARE @orgId UNIQUEIDENTIFIER;
    -- **من app_users لا من organizations**: الأخير محمي بسياسة العزل، ويُقرأ
    -- هنا قبل ضبط أي سياق فيُرجع صفر صفوف — فيدور المؤشّر على لا شيء ولا
    -- يُنفَّذ التحديث أبداً، صامتاً. (وقع فعلاً في أول كتابة لهذه الكتلة.)
    DECLARE org_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT DISTINCT organization_id FROM dbo.app_users;
    OPEN org_cursor;
    FETCH NEXT FROM org_cursor INTO @orgId;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC sp_set_session_context @key = N'organization_id', @value = @orgId;

        UPDATE i
        SET i.counted_at = c.closed_at
        FROM dbo.stock_count_items i
        JOIN dbo.stock_counts c ON c.id = i.stock_count_id
        WHERE i.counted_at IS NULL
          AND c.closed_at IS NOT NULL;

        FETCH NEXT FROM org_cursor INTO @orgId;
    END
    CLOSE org_cursor;
    DEALLOCATE org_cursor;
    EXEC sp_set_session_context @key = N'organization_id', @value = NULL;
END
GO

PRINT N'الجرد الميداني: تمييز العدّ جاهز';
GO

-- ----------------------------------------------------------------------------
--  المحاسبة: دليل الحسابات والقيود  (وحدة accounting)
--
--  على الدليل المحاسبي الموحّد: 1 الأصول · 2 الالتزامات وحقوق الملكية ·
--  3 الاستخدامات · 4 الإيرادات.
--
--  ولا بذر هنا: الدليل يُبذَر من التطبيق عند تفعيل الوحدة
--  (POST /api/accounting/accounts/seed) لا من ترحيل. البذر من SQL يعني
--  إنشاء شجرة لكل منظمة في القاعدة — بما فيها من لم يشترِ الوحدة أصلاً.
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.accounts', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.accounts (
      id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
      organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.organizations(id) ON DELETE CASCADE,
      code NVARCHAR(20) NOT NULL,
      name NVARCHAR(200) NOT NULL,
      -- بلا ON DELETE: حذف أبٍ له أبناء يُرفض لا يتتالى.
      parent_id UNIQUEIDENTIFIER NULL REFERENCES dbo.accounts(id),
      type NVARCHAR(20) NOT NULL
        CONSTRAINT CK_accounts_type CHECK (type IN ('asset','liability','equity','expense','revenue')),
      is_postable BIT NOT NULL DEFAULT 1,
      is_system BIT NOT NULL DEFAULT 0,
      is_active BIT NOT NULL DEFAULT 1,
      created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
      CONSTRAINT UQ_accounts_org_code UNIQUE (organization_id, code)
    );
    PRINT N'أُنشئ جدول accounts';
END
GO

IF OBJECT_ID('dbo.journal_entries', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.journal_entries (
      id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
      organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.organizations(id) ON DELETE CASCADE,
      branch_id UNIQUEIDENTIFIER NULL REFERENCES dbo.branches(id),
      -- تسلسل بلا فجوات: يُولَّد بقفل داخل المعاملة لا بـIDENTITY. فجوةٌ في
      -- دفتر اليومية سؤالٌ يطرحه كل مراجع.
      number BIGINT NOT NULL,
      entry_date DATETIME2 NOT NULL,
      source NVARCHAR(30) NOT NULL,
      source_id UNIQUEIDENTIFIER NULL,
      description NVARCHAR(400) NOT NULL DEFAULT N'',
      reverses_entry_id UNIQUEIDENTIFIER NULL REFERENCES dbo.journal_entries(id),
      created_by UNIQUEIDENTIFIER NULL REFERENCES dbo.app_users(id),
      created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
      CONSTRAINT UQ_journal_entries_number UNIQUE (organization_id, number)
    );
    PRINT N'أُنشئ جدول journal_entries';
END
GO

IF OBJECT_ID('dbo.journal_entry_lines', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.journal_entry_lines (
      id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
      journal_entry_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.journal_entries(id) ON DELETE CASCADE,
      account_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.accounts(id),
      debit DECIMAL(18,2) NOT NULL DEFAULT 0,
      credit DECIMAL(18,2) NOT NULL DEFAULT 0,
      note NVARCHAR(300) NULL,
      -- سطرٌ بمدين ودائن معاً، أو بصفرَين، أو بسالب: بلا معنى محاسبي.
      -- القيد في القاعدة لا في الكود: الكود يُنسى في مسار جديد.
      CONSTRAINT CK_journal_lines_side CHECK (
        debit >= 0 AND credit >= 0 AND (
          (debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0)
        )
      )
    );
    PRINT N'أُنشئ جدول journal_entry_lines';
END
GO

IF OBJECT_ID('dbo.account_mappings', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.account_mappings (
      organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.organizations(id) ON DELETE CASCADE,
      role NVARCHAR(40) NOT NULL,
      account_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.accounts(id),
      PRIMARY KEY (organization_id, role)
    );
    PRINT N'أُنشئ جدول account_mappings';
END
GO

-- ── سياسات العزل ────────────────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'AccountsPolicy')
EXEC('
CREATE SECURITY POLICY Security.AccountsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.accounts,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.accounts AFTER INSERT
  WITH (STATE = ON);');
GO

IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'JournalEntriesPolicy')
EXEC('
CREATE SECURITY POLICY Security.JournalEntriesPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.journal_entries,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.journal_entries AFTER INSERT
  WITH (STATE = ON);');
GO

IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'AccountMappingsPolicy')
EXEC('
CREATE SECURITY POLICY Security.AccountMappingsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.account_mappings,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.account_mappings AFTER INSERT
  WITH (STATE = ON);');
GO

-- سطر القيد يصل إلى المنظمة عبر رأس القيد — نفس نمط invoice_items.
IF OBJECT_ID('Security.fn_JournalChild', 'IF') IS NULL
EXEC('
CREATE FUNCTION Security.fn_JournalChild(@EntryId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE EXISTS (
    SELECT 1 FROM dbo.journal_entries e
    WHERE e.id = @EntryId
      AND e.organization_id = CAST(SESSION_CONTEXT(N''organization_id'') AS UNIQUEIDENTIFIER)
);');
GO

IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'JournalEntryLinesPolicy')
EXEC('
CREATE SECURITY POLICY Security.JournalEntryLinesPolicy
  ADD FILTER PREDICATE Security.fn_JournalChild(journal_entry_id) ON dbo.journal_entry_lines,
  ADD BLOCK PREDICATE Security.fn_JournalChild(journal_entry_id) ON dbo.journal_entry_lines AFTER INSERT
  WITH (STATE = ON);');
GO

PRINT N'المحاسبة: دليل الحسابات والقيود جاهز';
GO

-- ----------------------------------------------------------------------------
--  المصروفات: حساب المصروف
--
--  جدول expenses كان موجوداً في المخطّط منذ اليوم الأول ولا يقرؤه سطر واحد —
--  لا كيان ولا وحدة تحكّم ولا شاشة. يُبنى الآن، ويُربَط بدليل الحسابات.
--
--  ⚠ يجب أن يلي كتلة المحاسبة أعلاه: المفتاح الخارجي يشير إلى accounts.
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.expenses') AND name = 'account_id')
   AND OBJECT_ID('dbo.accounts', 'U') IS NOT NULL
BEGIN
    ALTER TABLE dbo.expenses ADD account_id UNIQUEIDENTIFIER NULL
        CONSTRAINT FK_expenses_account REFERENCES dbo.accounts(id);
    PRINT N'أُضيف عمود expenses.account_id';
END
GO

PRINT N'المصروفات جاهزة';
GO

-- ----------------------------------------------------------------------------
--  منح وحدة accounting لتراخيص المؤسسات القائمة
--
--  ⚠ **قاعدة عامّة، لا حالة واحدة:** الوحدات الفعّالة = وحدات الإصدار ∩
--  قائمة الترخيص (راجع LicenseLimits.EffectiveModules). والقائمة تُكتب في
--  الترخيص لحظة إصداره وتُجمَّد. فأيّ وحدة تُضاف إلى إصدارٍ بعد ذلك
--  **تختفي صامتةً عن كل عميل قائم** — لا رسالة ولا أثر، فقط شاشة لا تظهر
--  وترحيلٌ لا يقع.
--
--  وهذا أخطر ما يكون في المحاسبة تحديداً: مالك المنصّة يتجاوز فحص الوحدات
--  بحكم التصميم، فيرى الشاشة تعمل عنده بينما لا قيد يُكتب عند العميل.
--
--  فكل إضافة وحدة إلى إصدار تستلزم كتلةً كهذه.
-- ----------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID('dbo.licenses') AND name = 'enabled_modules')
BEGIN
    DECLARE @orgId UNIQUEIDENTIFIER;
    DECLARE @granted INT = 0;

    -- من app_users لنفس السبب أعلاه. والإصدار يُفحَص **داخل** الحلقة بعد
    -- ضبط السياق، إذ لا يمكن قراءته من خارجها.
    DECLARE org_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT DISTINCT organization_id FROM dbo.app_users;
    OPEN org_cursor;
    FETCH NEXT FROM org_cursor INTO @orgId;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- RLS تحجب صفوف المنظمات الأخرى، فتحديثٌ بلا سياق يُصيب صفر صفوف
        -- صامتاً (راجع رأس هذا الملف).
        EXEC sp_set_session_context @key = N'organization_id', @value = @orgId;

        -- تُضاف فقط لمن لا يملكها، ولا تُمسّ قائمة قُيّدت عمداً بغير ذلك:
        -- الشرط أن تكون القائمة تحوي وحدات المؤسسات الأخرى — أي أنها
        -- «كل ما يمنحه الإصدار» وقت إصدارها، لا اشتراكاً مقيَّداً.
        UPDATE dbo.licenses
        SET enabled_modules = JSON_MODIFY(enabled_modules, 'append $', 'accounting')
        WHERE EXISTS (SELECT 1 FROM dbo.organizations o WHERE o.edition = 'enterprise')
          AND ISJSON(enabled_modules) = 1
          AND enabled_modules NOT LIKE '%accounting%'
          AND enabled_modules LIKE '%warehouses%'
          AND enabled_modules LIKE '%valuation%'
          AND enabled_modules LIKE '%procurement%';

        SET @granted = @granted + @@ROWCOUNT;
        FETCH NEXT FROM org_cursor INTO @orgId;
    END
    CLOSE org_cursor;
    DEALLOCATE org_cursor;
    EXEC sp_set_session_context @key = N'organization_id', @value = NULL;

    PRINT N'مُنحت وحدة accounting لـ ' + CAST(@granted AS NVARCHAR(10)) + N' ترخيص مؤسسات';
END
GO

-- ----------------------------------------------------------------------------
--  سداد الموردين
--
--  حساب «الموردون» كان يتراكم بلا طرف مقابل: كل استلام يزيد الدَّين ولا شيء
--  يُنقصه.
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.supplier_payments', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.supplier_payments (
      id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
      organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.organizations(id) ON DELETE CASCADE,
      branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.branches(id),
      supplier_id UNIQUEIDENTIFIER NOT NULL REFERENCES dbo.suppliers(id),
      amount DECIMAL(18,3) NOT NULL,
      method NVARCHAR(20) NOT NULL
        CONSTRAINT CK_supplier_payments_method CHECK (method IN ('cash','bank')),
      reference NVARCHAR(80) NULL,
      note NVARCHAR(300) NULL,
      paid_on DATETIME2 NOT NULL,
      created_by UNIQUEIDENTIFIER NULL REFERENCES dbo.app_users(id),
      created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
      CONSTRAINT CK_supplier_payments_amount CHECK (amount > 0)
    );
    CREATE INDEX ix_supplier_payments_supplier
        ON dbo.supplier_payments (organization_id, supplier_id, paid_on);
    PRINT N'أُنشئ جدول supplier_payments';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'SupplierPaymentsPolicy')
EXEC('
CREATE SECURITY POLICY Security.SupplierPaymentsPolicy
  ADD FILTER PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.supplier_payments,
  ADD BLOCK PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.supplier_payments AFTER INSERT
  WITH (STATE = ON);');
GO

PRINT N'سداد الموردين جاهز';
GO

-- ----------------------------------------------------------------------------
--  فهارس الأداء — ملف منفصل لأنه يُنفَّذ ويُعاد بلا خطر
-- ----------------------------------------------------------------------------
PRINT N'لا تنسَ تنفيذ docs\INDEXES.sql على هذه القاعدة أيضاً.';
GO
