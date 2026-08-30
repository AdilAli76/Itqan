using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Data;

/// <summary>
/// «اليوم» بتوقيت المنظمة لا بتوقيت غرينتش.
///
/// <para><b>العطب الذي يصلحه:</b> كل تاريخ في النظام يُقاس بـUTC، و«اليوم»
/// كان <c>DateTime.UtcNow.Date</c>. ومحلٌّ في طرابلس يُنهي يومه الساعة
/// الثانية عشرة ليلاً بتوقيته — أي العاشرة مساءً بتوقيت غرينتش. فبين
/// العاشرة ومنتصف الليل:</para>
///
/// <list type="bullet">
/// <item>مصروفٌ يُسجَّل «اليوم» يقع في **يوم أمس** محاسبياً.</item>
/// <item>ومحاولةُ إقفال «أمس» تُرفض لأن UTC ما زال فيه.</item>
/// <item>وتقرير «هذا الشهر» في أول ساعتين من اليوم الأول يعرض الشهر السابق.
/// </item>
/// </list>
///
/// <para><b>ولماذا التخزين يبقى UTC:</b> تحويل التخزين إلى التوقيت المحلّي
/// يجعل صفّاً واحداً يُقرأ بمعنيين حين تنتقل المنظمة أو يتغيّر التوقيت
/// الصيفي. فيبقى ما يُخزَّن UTC، ويُحوَّل ما **يُقارَن باليوم** أو يُعرَض.
/// </para>
/// </summary>
public static class OrgClock
{
    /// <summary>
    /// التوقيت الافتراضي — ليبيا. لا توقيت صيفي فيها منذ 2013، فالإزاحة
    /// ثابتة (+2) وهو أبسط ما يمكن.
    /// </summary>
    public const string DefaultTimeZone = "Libya";

    /// <summary>
    /// منطقة المنظمة، أو UTC إن كان المعرّف مجهولاً.
    ///
    /// <para><b>الفشل مفتوح عمداً:</b> معرّفٌ لا يعرفه النظام (نسخة ويندوز
    /// بلا ICU، أو معرّف كُتب خطأً) يجب ألّا يُوقف البيع. ويُسجَّل ليُصحَّح.
    /// </para>
    /// </summary>
    public static TimeZoneInfo Zone(Organization? org)
    {
        var id = string.IsNullOrWhiteSpace(org?.TimeZoneId) ? DefaultTimeZone : org!.TimeZoneId;
        try
        {
            return TimeZoneInfo.FindSystemTimeZoneById(id);
        }
        catch (Exception)
        {
            // TimeZoneNotFoundException وInvalidTimeZoneException كلاهما وارد،
            // ومنصّات مختلفة ترمي أنواعاً مختلفة.
            return TimeZoneInfo.Utc;
        }
    }

    /// <summary>«اليوم» كما يراه من في المحلّ.</summary>
    public static DateTime Today(Organization? org) =>
        TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, Zone(org)).Date;

    /// <summary>لحظة «الآن» بتوقيت المنظمة — للعرض لا للتخزين.</summary>
    public static DateTime Now(Organization? org) =>
        TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, Zone(org));

    /// <summary>أول يوم في السنة الجارية بتوقيت المنظمة.</summary>
    public static DateTime StartOfYear(Organization? org)
    {
        var today = Today(org);
        return new DateTime(today.Year, 1, 1);
    }
}
