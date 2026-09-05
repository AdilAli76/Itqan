using System.Data.Common;
using System.IO.Compression;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;

namespace KineticEnterprise.Api.Data;

/// <summary>جدولٌ يدخل النسخة، وكيف تُقصَر قراءته على صاحبها.</summary>
public record BackupTable(string Name, bool FilterByOrg);

/// <summary>خطّة النسخة: ما يدخلها، وما غاب عن القاعدة، وما استُبعد.</summary>
public record BackupPlan(List<BackupTable> Include, List<string> Missing, List<string> Skipped);

/// <summary>هوية المنظمة كما تُكتب في المانيفست.</summary>
public record BackupOrg(Guid Id, string DisplayName, string LegalName, string Edition);

/// <summary>
/// بناء ملف النسخة الاحتياطية — منطقٌ واحد يخدم التنزيل اليدوي والرفع
/// التلقائي.
///
/// <para><b>ولماذا صُنِّف هنا لا في الكنترولر:</b> المهمّة الليلية لا طلبَ
/// HTTP لها ولا <c>Response</c> تكتب فيه. ونسخُ منطق البناء إليها كان يعني
/// نسختين تفترقان: تُصلَح ثغرةُ عزلٍ في إحداهما وتبقى في الأخرى — وهي التي
/// تعمل بلا أحد ينظر.</para>
/// </summary>
public static class BackupArchive
{
    /// <summary>صيغة الملف — يُقرأ من المانيفست عند الاسترجاع مستقبلاً.</summary>
    public const int FormatVersion = 1;

    /// <summary>
    /// جداولٌ لا معرّف منظمة فيها ولا سياسة عزل عليها، ومحتواها **قائمةٌ
    /// ثابتة** يشترك فيها الجميع — تدخل النسخة كما هي.
    ///
    /// <para>وقائمةٌ صريحة لا استنتاج: الأصل في جدولٍ لا يُعرَف صاحبه أن
    /// **يُستبعَد**، لأن الخطأ في الاتجاه الآخر يُسرّب بيانات عميلٍ إلى
    /// ملف عميلٍ آخر. فما يدخل هنا يدخل بقرارٍ مكتوب.</para>
    /// </summary>
    static readonly HashSet<string> GlobalCatalogTables =
        new(StringComparer.OrdinalIgnoreCase) { "permissions" };

    /// <summary>
    /// أسماء جداول المنظمة كما يعرفها نموذج EF.
    ///
    /// <para>مشتقّة من النموذج لا مكتوبة يدوياً: جدولٌ يُضاف بعد سنة ولا
    /// يُضاف إلى قائمةٍ يدوية يغيب عن كل نسخةٍ بعده صامتاً — ولا يُكتشف
    /// غيابه إلا يوم الاسترجاع.</para>
    /// </summary>
    static List<string> ModelTables(AppDbContext db) => db.Model.GetEntityTypes()
        .Select(t => t.GetTableName())
        .Where(t => !string.IsNullOrEmpty(t))
        .Select(t => t!)
        .Distinct()
        .OrderBy(t => t, StringComparer.Ordinal)
        .ToList();

    /// <summary>
    /// خطّة النسخة: ما يدخلها، وما غاب عن القاعدة، وما استُبعد ولماذا.
    ///
    /// <para><b>العطب الأول الذي تمنعه:</b> قاعدةٌ متأخّرة عن النموذج —
    /// خادمٌ لم تُطبَّق عليه آخر الترقيات — تجعل <c>SELECT</c> على جدولٍ
    /// غير موجود يرمي استثناءً **بعد** أن بدأ البثّ. والاستجابة حينها لا
    /// يمكن تغييرها: يصل المستخدم ملف ZIP مقطوع يظنّه نسخته، ولا يكتشف
    /// أنه خرابٌ إلا يوم يحتاجه.</para>
    ///
    /// <para><b>والعطب الثاني أخطر:</b> ليست كل الجداول تحت سياسة عزل.
    /// <c>app_users</c> مثلاً تُرشَّح في الكود لا بالسياسة (راجع
    /// [UsersController])، و<c>platform_organizations</c> سجلُّ مالك
    /// المنصّة بكل عملائه. و<c>SELECT *</c> عليها كان يضع **مستخدمي كل
    /// المنظمات ببصمات كلمات مرورهم** في ملفٍ يُسلَّم لعميل واحد. فما فيه
    /// <c>organization_id</c> يُرشَّح صراحةً، وما لا سياسة عليه ولا عمود
    /// يُستبعَد ويُذكَر استبعاده.</para>
    /// </summary>
    public static async Task<BackupPlan> PlanAsync(AppDbContext db, DbConnection connection)
    {
        var model = ModelTables(db);

        var hasOrgColumn = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var hasPolicy = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var existing = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        await using (var command = connection.CreateCommand())
        {
            command.CommandText = """
                SELECT t.name,
                       CASE WHEN EXISTS (SELECT 1 FROM sys.columns c
                                         WHERE c.object_id = t.object_id AND c.name = 'organization_id')
                            THEN 1 ELSE 0 END AS has_org,
                       CASE WHEN EXISTS (SELECT 1 FROM sys.security_predicates p
                                         WHERE p.target_object_id = t.object_id)
                            THEN 1 ELSE 0 END AS has_policy
                FROM sys.tables t
                WHERE t.is_ms_shipped = 0
                """;
            await using var reader = await command.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                var name = reader.GetString(0);
                existing.Add(name);
                if (reader.GetInt32(1) == 1) hasOrgColumn.Add(name);
                if (reader.GetInt32(2) == 1) hasPolicy.Add(name);
            }
        }

        var include = new List<BackupTable>();
        var missing = new List<string>();
        var skipped = new List<string>();

        foreach (var table in model)
        {
            if (!existing.Contains(table)) { missing.Add(table); continue; }

            if (hasOrgColumn.Contains(table)) include.Add(new BackupTable(table, FilterByOrg: true));
            else if (hasPolicy.Contains(table)) include.Add(new BackupTable(table, FilterByOrg: false));
            else if (GlobalCatalogTables.Contains(table)) include.Add(new BackupTable(table, FilterByOrg: false));
            else skipped.Add(table);
        }

        return new BackupPlan(include, missing, skipped);
    }

    /// <summary>
    /// يكتب ملف ZIP كاملاً على <paramref name="output"/>: مانيفست وملف JSON
    /// لكل جدول.
    ///
    /// <para>ZIP لا JSON واحد: ملفٌ واحد بعشرات الميغابايتات لا يفتحه محرّر
    /// نصوص، وتقسيمه بالجداول يجعل استخراج «العملاء» وحدهم ممكناً بلا أداة
    /// خاصة. والضغط يردّ الحجم إلى عُشره تقريباً — والفرق بين 80 و8
    /// ميغابايت هو الفرق بين نسخةٍ تُرفع على شبكة ضعيفة ونسخةٍ تُترك.</para>
    ///
    /// <para>ويُبَثّ صفّاً صفّاً ولا يُجمَع في الذاكرة: منظمةٌ بسنتين من
    /// الفواتير كانت تُسقط الخادم لو بُني الملف في مصفوفة بايتات أولاً.</para>
    /// </summary>
    public static async Task WriteAsync(
        DbConnection connection, BackupOrg org, BackupPlan plan, Stream output)
    {
        using var archive = new ZipArchive(output, ZipArchiveMode.Create, leaveOpen: true);

        foreach (var table in plan.Include)
        {
            var entry = archive.CreateEntry($"data/{table.Name}.json", CompressionLevel.Optimal);
            await using var entryStream = entry.Open();
            await using var writer = new Utf8JsonWriter(entryStream, new JsonWriterOptions { Indented = false });

            writer.WriteStartArray();

            await using (var command = connection.CreateCommand())
            {
                command.CommandText = Select("*", table);
                AddOrgParameter(command, table, org.Id);
                await using var reader = await command.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    writer.WriteStartObject();
                    for (var i = 0; i < reader.FieldCount; i++)
                    {
                        writer.WritePropertyName(reader.GetName(i));
                        WriteValue(writer, reader, i);
                    }
                    writer.WriteEndObject();
                }
            }

            writer.WriteEndArray();
            await writer.FlushAsync();
        }

        var manifest = archive.CreateEntry("manifest.json", CompressionLevel.Optimal);
        await using var manifestStream = manifest.Open();
        await JsonSerializer.SerializeAsync(manifestStream, new
        {
            formatVersion = FormatVersion,
            generatedAt = DateTime.UtcNow,
            organizationId = org.Id,
            organization = org.DisplayName,
            legalName = org.LegalName,
            edition = org.Edition,
            tables = plan.Include.Select(t => t.Name).ToList(),
            missingTables = plan.Missing,
            skippedTables = plan.Skipped,
            // تحذيرٌ في الملف نفسه لا في الشاشة وحدها: الملف يُنسَخ ويُرسَل
            // بعد أن تُنسى الشاشة التي نزّلته.
            notice = "يحوي هذا الملف كل بيانات المنظمة — احفظه في مكان موثوق ولا تشاركه.",
        }, new JsonSerializerOptions { WriteIndented = true });
    }

    /// <summary>
    /// استعلام الجدول مقصوراً على صاحبه.
    ///
    /// <para>اسم الجدول يأتي من نموذج EF ومن <c>sys.tables</c> — لا من
    /// المستخدم — فلا مدخل لحقنٍ منه. أمّا معرّف المنظمة فيُمرَّر
    /// **معامِلاً** لا نصّاً مدموجاً: قاعدةٌ في هذا الموضع تُقرأ بكاملها،
    /// وتنسيقُ معرّفٍ داخل الجملة عادةٌ تنتقل إلى موضعٍ يأتي فيه المعرّف
    /// من الخارج.</para>
    /// </summary>
    public static string Select(string projection, BackupTable table) =>
        table.FilterByOrg
            ? $"SELECT {projection} FROM [{table.Name}] WHERE organization_id = @org"
            : $"SELECT {projection} FROM [{table.Name}]";

    public static void AddOrgParameter(DbCommand command, BackupTable table, Guid orgId)
    {
        if (!table.FilterByOrg) return;
        var parameter = command.CreateParameter();
        parameter.ParameterName = "@org";
        parameter.Value = orgId;
        command.Parameters.Add(parameter);
    }

    static void WriteValue(Utf8JsonWriter writer, DbDataReader reader, int i)
    {
        if (reader.IsDBNull(i)) { writer.WriteNullValue(); return; }

        var value = reader.GetValue(i);
        switch (value)
        {
            case bool b: writer.WriteBooleanValue(b); break;
            case byte or short or int or long: writer.WriteNumberValue(Convert.ToInt64(value)); break;
            case decimal d: writer.WriteNumberValue(d); break;
            case double or float: writer.WriteNumberValue(Convert.ToDouble(value)); break;
            // ISO 8601 لا تنسيق محلّي: ملفٌ يُقرأ على جهازٍ إعداده العربي
            // كان يُنتج تواريخ لا تُحلَّل.
            case DateTime dt: writer.WriteStringValue(dt.ToString("O")); break;
            case DateTimeOffset dto: writer.WriteStringValue(dto.ToString("O")); break;
            case Guid g: writer.WriteStringValue(g); break;
            case byte[] bytes: writer.WriteBase64StringValue(bytes); break;
            default: writer.WriteStringValue(value.ToString()); break;
        }
    }
}
