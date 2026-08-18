using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Data;

/// <summary>
/// إنشاء أول حساب — مالك المنصة — على قاعدة بيانات فارغة.
///
/// لماذا أمر سطر أوامر ولا نقطة نهاية HTTP: النظام مقفل بإحكام وهذا مقصود.
/// PlatformController يتطلّب ادّعاء is_platform_admin، و UsersController
/// يتطلّب توكناً صالحاً، و AuthController فيه login وحده بلا تسجيل ذاتي.
/// أي نقطة نهاية عامة لإنشاء أول مالك تبقى بابًا مفتوحاً على السيرفر بعد
/// استخدامها — ينساها أحدهم فتصبح ثغرة استيلاء كامل على المنصة. أمر يُنفَّذ
/// من على السيرفر نفسه لا يحمل هذا الخطر: من يملك تنفيذ أوامر على السيرفر
/// يملك قاعدة البيانات أصلاً.
///
/// كلمة المرور تُقرأ تفاعلياً ولا تُمرَّر كوسيط سطر أوامر: الوسائط تُسجَّل في
/// تاريخ الأوامر وفي قائمة العمليات، وكلمة مرور مالك المنصة تُفتح بها كل
/// منظمات كل عملائك.
///
/// التشغيل من مجلد المشروع:
///     dotnet run -- create-platform-owner
/// </summary>
public static class PlatformOwnerBootstrap
{
    public const string CommandName = "create-platform-owner";
    public const string ResetCommandName = "reset-user-password";
    public const string CreateUserCommandName = "create-user";

    /// <summary>
    /// إنشاء مستخدم داخل منظمة قائمة — كاشير أو مدير فرع أو غيرهما.
    ///
    /// موجود لأن اختبار الصلاحيات يحتاج حساباً بدور حقيقي: مالك المنصة
    /// و super_admin يتجاوزان كل فحوص الصلاحيات بحكم التصميم، فلا يمكن بهما
    /// إثبات أن المنع يعمل. الكاشير هو الحساب الذي يُثبت ذلك.
    ///
    /// كلمة المرور تُقرأ تفاعلياً كبقية أوامر هذا الملف — لا تُمرَّر كوسيط
    /// ولا تُكتب في أي ملف.
    /// </summary>
    public static async Task<int> CreateUserAsync(IConfiguration config)
    {
        Console.OutputEncoding = System.Text.Encoding.UTF8;
        Console.WriteLine();
        Console.WriteLine("=== إنشاء مستخدم في منظمة قائمة ===");
        Console.WriteLine();

        var connectionString = config.GetConnectionString("Default");
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            Console.Error.WriteLine("خطأ: سلسلة الاتصال ConnectionStrings:Default فارغة.");
            return 1;
        }

        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(connectionString)
            .UseSnakeCaseNamingConvention()
            .Options;

        await using var db = new AppDbContext(options);
        var connection = db.Database.GetDbConnection();
        await connection.OpenAsync();

        // المنظمة تُختار عبر حساب قائم فيها: organizations محمي بسياسة أمان
        // تحجب كل الصفوف قبل ضبط SESSION_CONTEXT، وapp_users غير محمي.
        var ownerEmail = Prompt("بريد مستخدم قائم في المنظمة المقصودة (لتحديدها)");
        if (ownerEmail is null) return 1;

        var reference = await db.AppUsers.FirstOrDefaultAsync(u => u.Email == ownerEmail);
        if (reference is null)
        {
            Console.Error.WriteLine("لا مستخدم بهذا البريد.");
            return 1;
        }

        var orgId = reference.OrganizationId;
        await using (var cmd = connection.CreateCommand())
        {
            cmd.CommandText = "EXEC sp_set_session_context @key=N'organization_id', @value=@orgId;";
            cmd.Parameters.Add(new SqlParameter("@orgId", orgId));
            await cmd.ExecuteNonQueryAsync();
        }

        var branches = await db.Branches.Where(b => b.IsActive).OrderBy(b => b.Name).ToListAsync();
        if (branches.Count == 0)
        {
            Console.Error.WriteLine("لا فرع نشط في هذه المنظمة — أنشئ فرعاً أولاً من شاشة الفروع.");
            Console.Error.WriteLine("الكاشير بلا فرع لا يستطيع فتح نقطة البيع.");
            return 1;
        }

        Console.WriteLine();
        Console.WriteLine("الفروع المتاحة:");
        for (var i = 0; i < branches.Count; i++)
        {
            Console.WriteLine($"  [{i + 1}] {branches[i].Name} ({branches[i].Code})");
        }
        var branchPick = Prompt($"اختر رقم الفرع (1-{branches.Count})");
        if (branchPick is null) return 1;
        if (!int.TryParse(branchPick, out var branchIndex) || branchIndex < 1 || branchIndex > branches.Count)
        {
            Console.Error.WriteLine("اختيار غير صالح.");
            return 1;
        }
        var branch = branches[branchIndex - 1];

        var roles = new[] { "cashier", "branch_manager", "inventory_officer", "accountant" };
        Console.WriteLine();
        Console.WriteLine("الأدوار المتاحة:");
        for (var i = 0; i < roles.Length; i++)
        {
            Console.WriteLine($"  [{i + 1}] {roles[i]}");
        }
        var rolePick = Prompt($"اختر رقم الدور (1-{roles.Length})", defaultValue: "1");
        if (rolePick is null) return 1;
        if (!int.TryParse(rolePick, out var roleIndex) || roleIndex < 1 || roleIndex > roles.Length)
        {
            Console.Error.WriteLine("اختيار غير صالح.");
            return 1;
        }
        var role = roles[roleIndex - 1];

        var fullName = Prompt("الاسم الكامل");
        if (fullName is null) return 1;

        var email = Prompt("البريد الإلكتروني");
        if (email is null) return 1;

        // تفرّد عالمي بين الحسابات النشطة — نفس قاعدة UsersController، وإلا
        // صار الدخول بهذا البريد غير محدَّد النتيجة بين منظمتين.
        if (await db.AppUsers.AnyAsync(u => u.IsActive && u.Email == email))
        {
            Console.Error.WriteLine("هذا البريد مستخدَم بالفعل على حساب نشط.");
            return 1;
        }

        Console.WriteLine();
        Console.WriteLine("كلمة المرور — 8 أحرف على الأقل، لا تظهر أثناء الكتابة.");
        var password = ReadHidden("كلمة المرور");
        if (password is null) return 1;
        if (password.Length < 8)
        {
            Console.Error.WriteLine("كلمة المرور أقصر من 8 أحرف.");
            return 1;
        }
        var confirm = ReadHidden("تأكيد كلمة المرور");
        if (confirm != password)
        {
            Console.Error.WriteLine("كلمتا المرور غير متطابقتين.");
            return 1;
        }

        db.AppUsers.Add(new AppUser
        {
            OrganizationId = orgId,
            BranchId = branch.Id,
            FullName = fullName,
            Email = email,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(password),
            Role = role,
            IsPlatformAdmin = false,
            IsActive = true,
        });
        await db.SaveChangesAsync();

        Console.WriteLine();
        Console.WriteLine($"أُنشئ الحساب: {fullName} <{email}>");
        Console.WriteLine($"  الدور  : {role}");
        Console.WriteLine($"  الفرع  : {branch.Name}");
        Console.WriteLine();
        Console.WriteLine("ملاحظة: صلاحيات هذا الدور تُقرأ من جدول role_permissions لهذه المنظمة.");
        Console.WriteLine("إن كانت المنظمة أُنشئت يدوياً فقد لا تحوي صفوف صلاحيات افتراضية،");
        Console.WriteLine("فتُضبط من شاشة «مصفوفة الصلاحيات».");
        return 0;
    }

    /// <summary>
    /// إعادة تعيين كلمة مرور مستخدم من على السيرفر — الطريق الوحيد لاستعادة
    /// حساب مالك المنصة، إذ لا يوجد من هو أعلى منه ليعيد تعيينها له.
    ///
    /// يتعامل مع تكرار البريد بين منظمتين: قيد التفرّد هو
    /// (organization_id, email) لا البريد وحده، فقد يوجد نفس البريد في أكثر
    /// من منظمة ويجب اختيار الصف المقصود صراحةً.
    /// </summary>
    public static async Task<int> ResetPasswordAsync(IConfiguration config)
    {
        Console.OutputEncoding = System.Text.Encoding.UTF8;
        Console.WriteLine();
        Console.WriteLine("=== إعادة تعيين كلمة مرور مستخدم ===");
        Console.WriteLine();

        var connectionString = config.GetConnectionString("Default");
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            Console.Error.WriteLine("خطأ: سلسلة الاتصال ConnectionStrings:Default فارغة.");
            return 1;
        }

        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(connectionString)
            .UseSnakeCaseNamingConvention()
            .Options;

        await using var db = new AppDbContext(options);

        var email = Prompt("بريد المستخدم أو اسم مستخدمه");
        if (email is null) return 1;

        var matches = await db.AppUsers
            .Where(u => u.Email == email || u.Username == email)
            .OrderBy(u => u.CreatedAt)
            .ToListAsync();

        if (matches.Count == 0)
        {
            Console.Error.WriteLine("لا مستخدم بهذا البريد أو اسم المستخدم.");
            return 1;
        }

        AppUser target;
        if (matches.Count == 1)
        {
            target = matches[0];
        }
        else
        {
            Console.WriteLine();
            Console.WriteLine($"تحذير: {matches.Count} مستخدمين بنفس البريد في منظمات مختلفة.");
            Console.WriteLine("هذا يجعل تسجيل الدخول بهذا البريد غامضاً — راجع الملاحظة في نهاية هذا الأمر.");
            Console.WriteLine();
            for (var i = 0; i < matches.Count; i++)
            {
                var u = matches[i];
                Console.WriteLine($"  [{i + 1}] {u.FullName} | منظمة {u.OrganizationId} | " +
                                  $"دور {u.Role} | مالك منصة: {(u.IsPlatformAdmin ? "نعم" : "لا")} | " +
                                  $"أُنشئ {u.CreatedAt:yyyy-MM-dd}");
            }
            Console.WriteLine();
            var pick = Prompt($"اختر رقماً (1-{matches.Count})");
            if (pick is null) return 1;
            if (!int.TryParse(pick, out var index) || index < 1 || index > matches.Count)
            {
                Console.Error.WriteLine("اختيار غير صالح.");
                return 1;
            }
            target = matches[index - 1];
        }

        Console.WriteLine();
        Console.WriteLine($"المستخدم المحدَّد: {target.FullName} ({target.Email})");
        var minLength = target.IsPlatformAdmin ? 12 : 8;
        Console.WriteLine($"كلمة المرور الجديدة — {minLength} حرفاً على الأقل، لا تظهر أثناء الكتابة.");

        var password = ReadHidden("كلمة المرور الجديدة");
        if (password is null) return 1;
        if (password.Length < minLength)
        {
            Console.Error.WriteLine($"كلمة المرور أقصر من {minLength} حرفاً.");
            return 1;
        }
        var confirm = ReadHidden("تأكيد كلمة المرور");
        if (confirm != password)
        {
            Console.Error.WriteLine("كلمتا المرور غير متطابقتين.");
            return 1;
        }

        target.PasswordHash = BCrypt.Net.BCrypt.HashPassword(password);
        await db.SaveChangesAsync();

        Console.WriteLine();
        Console.WriteLine($"تم تحديث كلمة مرور {target.Email}.");
        if (matches.Count > 1)
        {
            Console.WriteLine();
            Console.WriteLine("ملاحظة مهمة: بريد مكرَّر بين منظمتين يجعل تسجيل الدخول به غير محدَّد —");
            Console.WriteLine("AuthController يبحث بالبريد بلا منظمة (لا سبيل لمعرفتها قبل الدخول)");
            Console.WriteLine("ويأخذ أول صف يرجعه SQL Server. عالِج التكرار بتغيير أحد البريدين،");
            Console.WriteLine("أو بتعطيل الحساب غير المستخدم (is_active = 0).");
        }
        return 0;
    }

    public static async Task<int> RunAsync(string[] args, IConfiguration config)
    {
        Console.OutputEncoding = System.Text.Encoding.UTF8;
        Console.WriteLine();
        Console.WriteLine("=== إنشاء حساب مالك المنصة ===");
        Console.WriteLine();

        var connectionString = config.GetConnectionString("Default");
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            Console.Error.WriteLine("خطأ: سلسلة الاتصال ConnectionStrings:Default فارغة.");
            Console.Error.WriteLine("املأها في appsettings.Production.json أو في متغيّرات البيئة أولاً.");
            return 1;
        }

        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(connectionString)
            .UseSnakeCaseNamingConvention()
            .Options;

        await using var db = new AppDbContext(options);

        try
        {
            await db.Database.OpenConnectionAsync();
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"تعذّر الاتصال بقاعدة البيانات: {ex.Message}");
            Console.Error.WriteLine("تحقّق أن SQL Server يعمل وأن قاعدة KineticEnterprise مُنشأة من sql.sql.");
            return 1;
        }

        // app_users بلا Security Policy، فهذا العدّ حقيقي لا مفلتر بمنظمة.
        var existingAdmins = await db.AppUsers.CountAsync(u => u.IsPlatformAdmin);
        if (existingAdmins > 0)
        {
            Console.WriteLine($"يوجد بالفعل {existingAdmins} حساب مالك منصة على هذه القاعدة.");
            Console.Write("إنشاء حساب إضافي؟ (اكتب نعم للمتابعة): ");
            if (Console.ReadLine()?.Trim() != "نعم")
            {
                Console.WriteLine("أُلغي.");
                return 0;
            }
        }

        var fullName = Prompt("الاسم الكامل");
        if (fullName is null) return 1;

        var email = Prompt("البريد الإلكتروني (يُستخدم للدخول)");
        if (email is null) return 1;

        var username = Prompt("اسم مستخدم للدخول (اختياري — اتركه فارغاً للتخطي)", allowEmpty: true);

        var duplicate = await db.AppUsers.AnyAsync(u => u.Email == email);
        if (duplicate)
        {
            Console.Error.WriteLine("هذا البريد مستخدم بالفعل على هذه القاعدة.");
            return 1;
        }

        var minLength = 12;
        Console.WriteLine();
        Console.WriteLine($"كلمة المرور — {minLength} حرفاً على الأقل. لا تظهر على الشاشة أثناء الكتابة.");
        var password = ReadHidden("كلمة المرور");
        if (password is null) return 1;
        if (password.Length < minLength)
        {
            Console.Error.WriteLine($"كلمة المرور أقصر من {minLength} حرفاً. هذا الحساب يفتح كل منظمات كل عملائك.");
            return 1;
        }
        var confirm = ReadHidden("تأكيد كلمة المرور");
        if (confirm != password)
        {
            Console.Error.WriteLine("كلمتا المرور غير متطابقتين.");
            return 1;
        }

        var orgName = Prompt("اسم منظمة الإدارة (منظمة تشغيلية لك، لا لعميل)", defaultValue: "إدارة المنصة");
        if (orgName is null) return 1;

        // مالك المنصة يحتاج منظمة: app_users.organization_id عمود NOT NULL
        // بمفتاح أجنبي. هذه منظمة إدارية لك لا لعميل، ولا تُنشأ لها فروع ولا
        // ترخيص — التراخيص تخصّ منظمات العملاء وحدها.
        var orgId = Guid.NewGuid();

        var connection = db.Database.GetDbConnection();
        await using (var cmd = connection.CreateCommand())
        {
            // organizations عليها BLOCK PREDICATE عند الإدراج تشترط تطابق id
            // مع SESSION_CONTEXT — فيُضبط السياق على المعرّف الجديد قبل الإدراج،
            // وإلا رُفض الصف بلا رسالة مفهومة.
            cmd.CommandText = "EXEC sp_set_session_context @key=N'organization_id', @value=@orgId;";
            cmd.Parameters.Add(new SqlParameter("@orgId", orgId));
            await cmd.ExecuteNonQueryAsync();
        }

        await using var transaction = await db.Database.BeginTransactionAsync();
        try
        {
            // صف المنظمة في SaveChanges منفصلة: لا Navigation properties بين
            // الجداول في AppDbContext، فـ EF لا يعرف ترتيب الاعتماد ويُدرج
            // المستخدم قبل منظمته فترفضه قيود FOREIGN KEY. نفس السبب المشروح
            // في PlatformController.Create.
            db.Organizations.Add(new Organization
            {
                Id = orgId,
                LegalName = orgName,
                DisplayName = orgName,
            });
            await db.SaveChangesAsync();

            db.AppUsers.Add(new AppUser
            {
                OrganizationId = orgId,
                BranchId = null,
                FullName = fullName,
                Email = email,
                Username = string.IsNullOrWhiteSpace(username) ? null : username,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(password),
                Role = "super_admin",
                IsPlatformAdmin = true,
                IsActive = true,
            });
            await db.SaveChangesAsync();

            await transaction.CommitAsync();
        }
        catch (Exception ex)
        {
            await transaction.RollbackAsync();
            Console.Error.WriteLine($"تعذّر إنشاء الحساب: {ex.Message}");
            return 1;
        }

        Console.WriteLine();
        Console.WriteLine("تم إنشاء حساب مالك المنصة.");
        Console.WriteLine($"  الاسم         : {fullName}");
        Console.WriteLine($"  الدخول بالبريد: {email}");
        if (!string.IsNullOrWhiteSpace(username)) Console.WriteLine($"  أو باسم المستخدم: {username}");
        Console.WriteLine($"  المنظمة       : {orgName}");
        Console.WriteLine();
        Console.WriteLine("الخطوة التالية: شغّل السيرفر (dotnet run)، سجّل الدخول من التطبيق،");
        Console.WriteLine("ثم النظام ← إنشاء منظمة جديدة لإضافة أول عميل.");
        Console.WriteLine();
        Console.WriteLine("كلمة المرور غير محفوظة في أي ملف — لا يمكن استرجاعها، فقط تغييرها.");
        return 0;
    }

    static string? Prompt(string label, bool allowEmpty = false, string? defaultValue = null)
    {
        while (true)
        {
            Console.Write(defaultValue is null ? $"{label}: " : $"{label} [{defaultValue}]: ");
            var value = Console.ReadLine();
            if (value is null)
            {
                // stdin مغلق (تشغيل غير تفاعلي) — لا سبيل لإكمال الأمر.
                Console.Error.WriteLine();
                Console.Error.WriteLine("هذا الأمر تفاعلي ويجب تشغيله من نافذة أوامر حقيقية.");
                return null;
            }
            value = value.Trim();
            if (value.Length > 0) return value;
            if (defaultValue is not null) return defaultValue;
            if (allowEmpty) return "";
            Console.WriteLine("القيمة مطلوبة.");
        }
    }

    /// <summary>
    /// قراءة بلا إظهار على الشاشة. Console.ReadKey(intercept: true) لا يطبع
    /// الحرف، ولا نطبع نجوماً بعدد الأحرف — عدد الأحرف نفسه معلومة لمن ينظر.
    /// </summary>
    static string? ReadHidden(string label)
    {
        Console.Write($"{label}: ");
        var buffer = new System.Text.StringBuilder();

        try
        {
            while (true)
            {
                var key = Console.ReadKey(intercept: true);
                if (key.Key == ConsoleKey.Enter)
                {
                    Console.WriteLine();
                    return buffer.ToString();
                }
                if (key.Key == ConsoleKey.Backspace)
                {
                    if (buffer.Length > 0) buffer.Length--;
                    continue;
                }
                if (key.Key == ConsoleKey.Escape)
                {
                    Console.WriteLine();
                    Console.Error.WriteLine("أُلغي.");
                    return null;
                }
                if (!char.IsControl(key.KeyChar)) buffer.Append(key.KeyChar);
            }
        }
        catch (InvalidOperationException)
        {
            // لا طرفية حقيقية (stdin مُعاد توجيهه) — الإخفاء غير ممكن، ولا
            // نقرأ كلمة المرور ظاهرةً بدلاً من ذلك.
            Console.Error.WriteLine();
            Console.Error.WriteLine("تعذّر إخفاء الكتابة — شغّل الأمر من نافذة أوامر حقيقية لا عبر إعادة توجيه.");
            return null;
        }
    }
}
