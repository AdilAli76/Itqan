-- ============================================================================
--  حذف بيانات اختبار الـ API
--
--  كل تشغيل لـ tool\api_test.ps1 يُنشئ صنفاً بوسم TEST-<طابع زمني> وفواتير
--  عليه. هذا الملف يحذفها كلها ولا يمسّ أي بيانات حقيقية.
--
--  التنفيذ (المعامل -I إلزامي — الفهارس المفلترة على app_users تمنع الكتابة
--  من عميل بـ QUOTED_IDENTIFIER مطفأ):
--
--      sqlcmd -S "localhost\SQLEXPRESS01" -d KineticEnterprise -E -I -f 65001 ^
--             -v OwnerEmail="adiledris76@gmail.com" -i tool\clean_test_data.sql
--
--  ملاحظة مقصودة: **سجلات التدقيق لا تُحذف**. سجل التدقيق أثر لا بيانات
--  عمل، وأول ما يُدقَّق عليه في نظام مالي هو ما إذا كانت صفوفه قابلة للحذف
--  انتقائياً. تبقى سجلات تجاوز السعر الناتجة عن الاختبار شاهدةً على أن
--  التسجيل يعمل.
-- ============================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- المنظمة تُشتق من بريد مستخدم فيها: الجداول محمية بسياسات أمان تعتمد على
-- SESSION_CONTEXT، وبدون ضبطه ترجع الاستعلامات صفر صفوف بلا أي خطأ.
DECLARE @org UNIQUEIDENTIFIER = (
    SELECT TOP 1 organization_id FROM dbo.app_users WHERE email = '$(OwnerEmail)'
);

IF @org IS NULL
BEGIN
    RAISERROR(N'لا مستخدم بهذا البريد — مرّر -v OwnerEmail=<بريد مستخدم في المنظمة>', 16, 1);
    RETURN;
END

EXEC sp_set_session_context @key = N'organization_id', @value = @org;

BEGIN TRANSACTION;

DECLARE @prods TABLE (id UNIQUEIDENTIFIER PRIMARY KEY);
INSERT INTO @prods SELECT id FROM dbo.products WHERE sku LIKE 'TEST-%';

DECLARE @invs TABLE (id UNIQUEIDENTIFIER PRIMARY KEY);
INSERT INTO @invs
    SELECT DISTINCT invoice_id FROM dbo.invoice_items WHERE product_id IN (SELECT id FROM @prods);

DELETE FROM dbo.invoice_payments WHERE invoice_id IN (SELECT id FROM @invs);
DELETE FROM dbo.invoice_items    WHERE invoice_id IN (SELECT id FROM @invs);

-- المرتجعات قبل فواتير البيع: original_invoice_id مفتاح أجنبي على نفس
-- الجدول، والعكس يفشل بخرق القيد.
DELETE FROM dbo.invoices WHERE id IN (SELECT id FROM @invs) AND invoice_type = 'return';
DELETE FROM dbo.invoices WHERE id IN (SELECT id FROM @invs);

DELETE FROM dbo.customer_wallet_transactions WHERE invoice_id IN (SELECT id FROM @invs);
DELETE FROM dbo.stock_levels WHERE product_id IN (SELECT id FROM @prods);
DELETE FROM dbo.products     WHERE id         IN (SELECT id FROM @prods);
DELETE FROM dbo.notifications WHERE title LIKE N'%صنف اختبار%';

COMMIT;
GO

DECLARE @org2 UNIQUEIDENTIFIER = (
    SELECT TOP 1 organization_id FROM dbo.app_users WHERE email = '$(OwnerEmail)'
);
EXEC sp_set_session_context @key = N'organization_id', @value = @org2;

SELECT
    (SELECT COUNT(*) FROM dbo.products WHERE sku LIKE 'TEST-%')            AS [بقايا اختبار],
    (SELECT COUNT(*) FROM dbo.products)                                    AS [أصناف باقية],
    (SELECT COUNT(*) FROM dbo.invoices)                                    AS [فواتير باقية],
    (SELECT COUNT(*) FROM dbo.invoice_items ii
      WHERE NOT EXISTS (SELECT 1 FROM dbo.invoices i WHERE i.id = ii.invoice_id)) AS [أسطر يتيمة],
    (SELECT COUNT(*) FROM dbo.audit_logs)                                  AS [سجلات تدقيق (محفوظة)];
GO
