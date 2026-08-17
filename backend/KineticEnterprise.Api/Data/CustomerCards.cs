using System.Security.Cryptography;
using System.Text.RegularExpressions;

namespace KineticEnterprise.Api.Data;

/// <summary>
/// قواعد بطاقة العميل ورقمها السري — منقولة حرفياً عن نموذج التوطين الليبي
/// (libyan_logic.py: generate_card_code / validate_pin وثوابت القفل).
/// </summary>
public static class CustomerCards
{
    // الرمز يُطبَع على بطاقة ويُكتب باليد، فالحروف الملتبسة مستبعَدة:
    // لا 0/O ولا 1/I — هذا سبب استبعادها من الأبجدية وليس اختصاراً.
    private const string CodeAlphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
    private const int CodeLength = 12;

    public const int PinMaxAttempts = 5;
    public const int PinLockoutMinutes = 15;

    public static string GenerateCardCode()
    {
        var chars = new char[CodeLength];
        for (var i = 0; i < CodeLength; i++)
        {
            chars[i] = CodeAlphabet[RandomNumberGenerator.GetInt32(CodeAlphabet.Length)];
        }
        return new string(chars);
    }

    /// <summary>
    /// يرفض الأرقام السرية سهلة التخمين. يُرجع رسالة الخطأ أو null إن كان سليماً.
    /// </summary>
    public static string? ValidatePin(string? pin)
    {
        if (pin is null || !Regex.IsMatch(pin, @"^\d{4,6}$"))
        {
            return "الرقم السري يجب أن يكون من 4 إلى 6 أرقام";
        }
        if (pin.Distinct().Count() == 1)
        {
            return "الرقم السري يجب ألا يكون رقماً واحداً مكرراً";
        }

        // تسلسل صاعد أو نازل كامل (1234 / 4321) — مرفوض كذلك.
        var steps = new HashSet<int>();
        for (var i = 1; i < pin.Length; i++)
        {
            steps.Add(pin[i] - pin[i - 1]);
        }
        if (steps.Count == 1 && (steps.Contains(1) || steps.Contains(-1)))
        {
            return "الرقم السري يجب ألا يكون أرقاماً متسلسلة";
        }

        return null;
    }
}
