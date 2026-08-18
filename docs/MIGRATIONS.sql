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

-- ----------------------------------------------------------------------------
--  فهارس الأداء — ملف منفصل لأنه يُنفَّذ ويُعاد بلا خطر
-- ----------------------------------------------------------------------------
PRINT N'لا تنسَ تنفيذ docs\INDEXES.sql على هذه القاعدة أيضاً.';
GO
