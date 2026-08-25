using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace KineticEnterprise.Api.Middleware;

/// <summary>
/// يترجم انتهاك قيد في قاعدة البيانات إلى رسالة عربية مفهومة.
///
/// <para><b>لماذا هنا لا في كل Controller:</b> البديل الشائع — فحص «هل يوجد
/// صنف بهذا الـSKU؟» قبل كل كتابة — يُضاعف الاستعلامات على كل مسار كتابة،
/// ويظلّ مع ذلك **عرضة لسباق التزامن**: طلبان متزامنان بنفس الباركود يمرّان
/// معاً من الفحص قبل أن يُحفظ أيّهما، فيقع الانتهاك على أي حال. القيد في
/// قاعدة البيانات هو الضمانة الوحيدة التي لا تُخترق، وهذه الطبقة تجعل
/// رسالته صالحة للعرض.</para>
///
/// <para>وما كان يراه الكاشير قبلها: نصّ SQL Server خاماً بالإنجليزية
/// («Violation of UNIQUE KEY constraint 'UQ_products_org_sku'…») أو خطأ
/// خادم 500 بلا أي تفسير — أسوأ تجربة ممكنة لمستخدم عربي أمام زبون منتظر.
/// </para>
///
/// <para><b>عند إضافة قيد جديد إلى المخطّط، يُضاف اسمه إلى
/// <see cref="Messages"/>.</b> ونسيانه ليس عطباً صامتاً: الرسالة العامة
/// المناسبة لنوع الخطأ تُعرض بدلاً منه، ويُسجَّل اسم القيد غير المعروف في
/// السجلّ تحذيراً.</para>
/// </summary>
public class DbConstraintMessageMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<DbConstraintMessageMiddleware> _logger;

    public DbConstraintMessageMiddleware(RequestDelegate next, ILogger<DbConstraintMessageMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    /// <summary>
    /// اسم القيد → الرسالة. الأسماء مطابقة لـ`DATABASE_SCHEMA_SQLSERVER.sql`.
    ///
    /// الرسالة تقول **ما الذي تكرّر أو تعذّر ولماذا**، لا «حدث خطأ»: المستخدم
    /// يحتاج أن يعرف أي حقل يصحّح، وإلا أعاد المحاولة بنفس القيمة.
    /// </summary>
    private static readonly Dictionary<string, string> Messages = new(StringComparer.OrdinalIgnoreCase)
    {
        // ── تفرّد ────────────────────────────────────────────────────────
        ["UQ_products_org_sku"] = "رمز الصنف (SKU) مستعمل في صنف آخر — اختر رمزاً غيره.",
        ["UQ_branches_org_code"] = "رمز الفرع مستعمل في فرع آخر — اختر رمزاً غيره.",
        // أربعة قيود على app_users لا اثنان: الفهرسان العامّان
        // (UQ_app_users_org_*) والفهرسان على النشطين وحدهم (…_active) من
        // MIGRATIONS.sql. تمييزها هو الفائدة الأصلية لهذه الطبقة: الرسالة
        // القديمة كانت «البريد أو اسم المستخدم مستخدَم» — تخمينٌ يترك
        // المستخدم يصحّح الحقل الخطأ.
        ["UQ_app_users_org_email"] = "البريد الإلكتروني مسجَّل لمستخدم آخر.",
        ["UQ_app_users_email_active"] = "البريد الإلكتروني مسجَّل لمستخدم نشط آخر.",
        ["UQ_app_users_org_username"] = "اسم الدخول مستعمل لمستخدم آخر.",
        ["UQ_app_users_username_active"] = "اسم الدخول مستعمل لمستخدم نشط آخر.",
        ["UQ_invoices_number"] = "رقم الفاتورة مستعمل — أعد المحاولة.",
        ["UQ_stock_levels"] = "توجد دفعة بهذا الرقم لنفس الصنف في هذا الفرع.",
        ["UQ_customer_card_index_customer"] = "لهذا العميل بطاقة مسجَّلة بالفعل.",
        ["UX_customers_card_barcode"] = "باركود البطاقة مستعمل لعميل آخر.",
        // الحارس النهائي ضد ازدواج الفاتورة عند إعادة إرسال عملية بيع بعد
        // انقطاع الشبكة. وقوعه ليس خطأ مستخدم بل **نجاح الحماية**، فالرسالة
        // تطمئن ولا تُنذر.
        ["UX_invoices_client_request_id"] = "هذه العملية مسجَّلة بالفعل — لا حاجة لإعادة إرسالها.",

        // ── تحقّق (CHECK) ────────────────────────────────────────────────
        //
        // المسمّاة صراحةً في المخطّط فقط. أما القيود المكتوبة داخل تعريف
        // العمود (`status NVARCHAR(20) ... CHECK (...)`) فيولّد SQL Server
        // لها اسماً بلاحقة هاش **تختلف من قاعدة إلى أخرى**
        // (CK__stock_tra__statu__160F4887) — فلا يصحّ ربط رسالة به، ويتكفّل
        // بها النصّ العام للرمز 547. وهو سبب كافٍ لتسمية أي CHECK جديد
        // صراحةً في المخطّط.
        ["CK_licenses_modules_json"] = "قائمة الوحدات المفعّلة بصيغة غير صحيحة.",
        ["CK_invoices_status"] = "حالة الفاتورة غير مقبولة.",
        ["CK_customers_account_model"] = "نوع حساب العميل غير مقبول.",
        ["CK_customer_card_index_state"] = "حالة البطاقة غير مقبولة.",
        ["CK_wallet_tx_kind"] = "نوع حركة المحفظة غير مقبول.",
        ["CK_organizations_nav_layout"] = "شكل التنقّل غير مقبول — اختر شريطاً جانبياً أو علوياً.",
    };

    /// <summary>
    /// رسائل عامة لكل رمز خطأ حين لا يُعرف اسم القيد — أو حين لا يذكره
    /// SQL Server أصلاً (كما في تجاوز طول النصّ).
    /// </summary>
    private static (int Status, string Message) Fallback(int number) => number switch
    {
        2627 or 2601 => (StatusCodes.Status409Conflict, "القيمة المُدخَلة مستعملة في سجلّ آخر."),
        // 547 يشمل انتهاك مفتاح أجنبي وانتهاك CHECK معاً. والحذف المرفوض هو
        // الحالة الغالبة عملياً: محاولة حذف فئة أو مورّد مرتبط بأصناف.
        547 => (StatusCodes.Status400BadRequest,
                "لا يمكن إتمام العملية: السجلّ مرتبط بسجلّات أخرى، أو إحدى القيم غير مقبولة."),
        515 => (StatusCodes.Status400BadRequest, "حقل إلزامي تُرك فارغاً."),
        2628 or 8152 => (StatusCodes.Status400BadRequest, "إحدى القيم أطول من المسموح."),
        _ => (0, ""),
    };

    /// <summary>
    /// اسم القيد يأتي بين علامتَي اقتباس مفردتين في نصّ الخطأ، وهو **أوّل**
    /// نصّ مقتبس فيه: «Violation of UNIQUE KEY constraint 'UQ_x'. Cannot
    /// insert duplicate key in object 'dbo.products'». الاقتباس الثاني اسم
    /// الجدول لا القيد، فالاكتفاء بالأول مقصود.
    /// </summary>
    private static readonly Regex ConstraintName = new("'([^']+)'", RegexOptions.Compiled);

    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await _next(context);
        }
        catch (Exception ex) when (Extract(ex) is { } sql)
        {
            var name = ConstraintName.Match(sql.Message) is { Success: true } m ? m.Groups[1].Value : null;
            var (fallbackStatus, fallbackMessage) = Fallback(sql.Number);

            // رمز خطأ غير معروف أصلاً: ليس انتهاك قيد بل عطب حقيقي (انقطاع
            // اتصال، مهلة، جمود). يُترك للسلوك الافتراضي بلا تجميل — إخفاؤه
            // خلف رسالة لطيفة يجعل تشخيصه مستحيلاً.
            if (fallbackStatus == 0) throw;

            string message;
            if (name is not null && Messages.TryGetValue(name, out var mapped))
            {
                message = mapped;
            }
            else
            {
                message = fallbackMessage;
                if (name is not null)
                {
                    _logger.LogWarning(
                        "قيد بلا رسالة معرَّفة: {Constraint} (رمز {Number}) — أضفه إلى DbConstraintMessageMiddleware.Messages",
                        name, sql.Number);
                }
            }

            // النصّ الأصلي إلى السجلّ لا إلى الرد: الرد يذهب إلى متصفّح
            // المستخدم، وأسماء الجداول والقيود فيه معلومة بنيوية لا داعي
            // لنشرها. والمطوّر يجدها كاملة في السجلّ.
            _logger.LogError(ex, "انتهاك قيد على {Path}", context.Request.Path);

            // بعد بدء الإرسال لا يمكن تغيير الحالة ولا الجسم — رميُ الاستثناء
            // حينها هو التصرّف الصحيح الوحيد (يقطع الاتصال بدل إرسال ردّ
            // نصفه نجاح ونصفه خطأ).
            if (context.Response.HasStarted) throw;

            context.Response.Clear();
            context.Response.StatusCode = name is not null && Messages.ContainsKey(name)
                ? (sql.Number is 2627 or 2601 ? StatusCodes.Status409Conflict : StatusCodes.Status400BadRequest)
                : fallbackStatus;
            context.Response.ContentType = "application/json; charset=utf-8";
            await context.Response.WriteAsync(JsonSerializer.Serialize(new { message }));
        }
    }

    /// <summary>
    /// EF Core يغلّف خطأ الخادم في <see cref="DbUpdateException"/>، وقد يصل
    /// <see cref="SqlException"/> مباشرةً من استعلام خام. البحث في سلسلة
    /// الأسباب يغطّي الحالتين بلا افتراض عن العمق.
    /// </summary>
    private static SqlException? Extract(Exception ex)
    {
        for (Exception? e = ex; e is not null; e = e.InnerException)
        {
            if (e is SqlException sql) return sql;
        }
        return null;
    }
}
