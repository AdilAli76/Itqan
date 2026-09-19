namespace KineticEnterprise.Api.Models;

/// <summary>
/// إصدارات النظام. المصدر الوحيد لأسمائها، فلا تتفرّق نصوصاً حرّة في
/// الوحدات والواجهة.
/// </summary>
public static class Editions
{
    public const string Standard = "standard";
    public const string Trial = "trial";
    public const string Enterprise = "enterprise";

    /// <summary>
    /// بطاقات وأرصدة بلا بضاعة: الكاشير يُدخل مبلغاً فيُخصم من بطاقة صاحبها
    /// أو يُسجَّل بيعاً نقدياً للفرع. للجهة التي تصرف على منتسبيها لا التي
    /// تبيع بضاعة — فلا كتالوج ولا مخزون ولا مشتريات.
    /// </summary>
    public const string Wallet = "wallet";

    /// <summary>
    /// المحفظة ومعها دفتر محاسبي كامل.
    ///
    /// <para><b>لماذا إصدارٌ مستقلّ لا ترقية إلى «المؤسسات»:</b> جهةٌ تصرف
    /// على منتسبيها تريد ميزاناً ودفتراً — ورصيد البطاقة عندها **التزام**
    /// لا إيراد (راجع [AccountRoles.CustomerWallet]). لكنها لا بضاعة لها،
    /// فترقيتُها إلى المؤسسات تُغرق قائمتها بمخزونٍ ومستودعاتٍ ومشترياتٍ لا
    /// معنى لها عندها — وهو نفس ما نتجنّبه حين نُخفي المحاسبة عن
    /// البقّالة.</para>
    ///
    /// <para>وهو محفظةٌ في كل سلوكه — راجع [IsWalletShaped].</para>
    /// </summary>
    public const string WalletPlus = "wallet_plus";

    /// <summary>
    /// الإصدار القياسي زائد المعرفة الدوائية: نشرة الدواء المرتبطة بالصنف
    /// (المادة الفعّالة، التركيز، دواعي الاستعمال، موانعه، التحذيرات،
    /// الأعراض الجانبية) تُعرض للكاشير لحظة الصرف.
    ///
    /// <para><b>لماذا إصدار لا ميزة دائمة:</b> النظام يُباع لبقالة ومحل
    /// قطع غيار ومخزن مواد بناء أيضاً. حقول «موانع الاستعمال» و«الجرعة» في
    /// شاشة أصناف محل ملابس ليست ميزة زائدة بل ضوضاء تُربك المستخدم وتُطيل
    /// نموذج الإدخال بلا مقابل. فتُقيَّد بوحدة <c>pharmacy</c> التي لا
    /// يملكها إلا من اشتراها.</para>
    /// </summary>
    public const string Pharmacy = "pharmacy";

    public static readonly string[] All = { Standard, Wallet, WalletPlus, Pharmacy, Trial, Enterprise };

    /// <summary>الوحدات المفعَّلة لكل إصدار — منها يُبنى التنقّل وتُقيَّد النقاط.</summary>
    public static string[] ModulesOf(string edition) => edition switch
    {
        Wallet => new[] { "pos", "customers", "reports" },
        // المحفظة ومعها المحاسبة — ولا مخزون: لا بضاعة تُقاس ولا مستودع
        // يُدار. والمصروفات تأتي مع accounting لا وحدةً مستقلّة.
        WalletPlus => new[] { "pos", "customers", "reports", "accounting", "wallet" },
        // وحدة pharmacy فوق وحدات الإصدار القياسي لا بدلاً منها: الصيدلية
        // متجر تجزئة كامل قبل أن تكون صيدلية — لها مخزون ومشتريات وموردون.
        Pharmacy => new[] { "inventory", "pos", "customers", "reports", "pharmacy" },
        // إصدار المؤسسات: المخزون يُقاس بالدينار لا بالقطعة، ويُثبَت بدفتر،
        // وله مكان معلوم. الوحدات الثلاث هي ما يفصله عن القياسي فعلياً بعد
        // أن كان يسقط على الافتراضي فيطابقه حرفياً — أي إصداراً بالاسم فقط.
        Enterprise => new[]
        {
            "inventory", "pos", "customers", "reports",
            "warehouses", "valuation", "procurement",
            // دليل الحسابات والقيود. لإصدار المؤسسات وحده: بقّالة بفرع واحد
            // لا تحتاج ميزان مراجعة، وشجرة حسابات في شاشتها ضوضاء تُربك ولا
            // تُفيد — نفس مبرر تقييد نشرة الدواء بوحدة pharmacy.
            "accounting",
        },
        _ => new[] { "inventory", "pos", "customers", "reports" },
    };

    /// <summary>
    /// كل الوحدات القابلة للبيع — المصدر الوحيد لأسمائها.
    ///
    /// <para><b>لماذا قائمة مستقلّة عن [ModulesOf]:</b> صارت الوحدات تُباع
    /// فوق الإصدار لا داخله وحده (راجع [LicenseLimits.EffectiveModules])،
    /// فمالك المنصّة يحتاج ما يعرضه ليختار منه، والخادم يحتاج ما يرفض به
    /// اسماً مكتوباً بخطأ. واشتقاقها من اتّحاد ما تُرجعه ModulesOf كان
    /// يعني أن وحدةً لا يحملها أي إصدار افتراضاً — وهي عين ما يُباع
    /// منفرداً — تصير غير قابلة للبيع.</para>
    ///
    /// <para>والترتيب مقصود: وحدات الأساس أوّلاً ثم ما يُباع فوقها، فتُعرض
    /// على مالك المنصّة بترتيبٍ يُقرأ لا بترتيب أبجدي.</para>
    /// </summary>
    public static readonly string[] AllModules =
    {
        "pos", "customers", "reports", "inventory",
        // «wallet» — بطاقاتٌ جماعية ومرتَّباتٌ للمنتسبين.
        //
        // <para><b>سبب فصلها عن الإصدار:</b> كان الإصدار الجماعي محصوراً في
        // «المحفظة بالمحاسبة»، وهو إصدارٌ **بلا بضاعة**. فجهةٌ لها بضاعة
        // ومنتسبون معاً — محلٌّ عسكري بفروعه الغذائية، جمعيةٌ تصرف على
        // أعضائها، شركةٌ لموظّفيها — تقع على الجانب الخطأ من الخطّ: تشتري
        // النسخة الكاملة فتستطيع كل شيء إلا إصدار ألف بطاقة دفعةً واحدة،
        // فتُصدرها فرادى ألف مرّة.</para>
        //
        // <para>ووحدةً تُباع فوق أي إصدار: هي نفسها ما تحتاجه تلك الجهات
        // كلّها، ولا معنى لإصدارٍ رابع يجمع المحفظة والبضاعة ثم خامسٍ
        // يجمعها بالصيدلية.</para>
        "wallet",
        "warehouses", "valuation", "procurement", "accounting", "pharmacy",
    };

    /// <summary>
    /// أهذا إصدارٌ على شكل المحفظة — بطاقات وأرصدة بلا بضاعة؟
    ///
    /// <para><b>ولماذا دالّة لا مقارنة مكرّرة:</b> سلوك المحفظة يُفحَص في
    /// ستّة مواضع بين الخادم والواجهة (شاشة البيع، إخفاء المخزون، بذر صنف
    /// القيمة، البيع بالقيمة الحرّة…). وإضافةُ إصدارٍ جديد على شكلها بـ
    /// <c>== Wallet</c> مكرّرة تعني تحديث خمسةٍ ونسيان السادس — والسادس هو
    /// الذي يُكتشف عند العميل.</para>
    /// </summary>
    public static bool IsWalletShaped(string edition) =>
        edition == Wallet || edition == WalletPlus;

    /// <summary>إصدارات المحفظة تبيع بالقيمة الحرّة حصراً — لا أصناف تُختار.</summary>
    public static bool AllowsOpenProduct(string edition) => IsWalletShaped(edition);
}

public class Organization
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string LegalName { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public string? LogoUrl { get; set; }

    /// <summary>
    /// شكل النظام لا حجمه — انظر [Editions]. غير PlanTier في الترخيص الذي
    /// يحدّد الحدود (فروع، مستخدمون، مدّة).
    /// </summary>
    public string Edition { get; set; } = Editions.Standard;
    public string PrimaryColor { get; set; } = "#0B2540";
    public string SecondaryColor { get; set; } = "#C8952B";
    public string CurrencyCode { get; set; } = "LYD";
    public string CurrencySymbol { get; set; } = "د.ل";
    public string Locale { get; set; } = "ar";
    // إعدادات عامة (ARCHITECTURE.md §2.14) — لم تكن موجودة في المخطط
    // الأصلي، أُضيفت كأعمدة جديدة على organizations لأنها إعداد على مستوى
    // المنظمة كلها، لا يستحق جدولاً منفصلاً بحجمه الحالي.
    public decimal TaxRate { get; set; }
    public int PasswordMinLength { get; set; } = 6;
    // إعداد ملصق الباركود (ARCHITECTURE.md §2.12) — JSON حرة بدل أعمدة
    // منفصلة لكل خاصية تصميم (نفس أسلوب licenses.enabled_modules)، لأنها
    // قيم عرض بحتة لا تحتاج استعلاماً أو فهرسة مباشرة.
    public string BarcodeTemplateJson { get; set; } = "{\"widthMm\":40,\"heightMm\":25,\"showName\":true,\"showPrice\":true,\"showSku\":false}";
    // عرض لفة الطابعة الحرارية (ملم) — 58 أو 80 هما القياسان الشائعان في
    // الطابعات الحديثة (تكامل الأجهزة §2.12). الطباعة نفسها عبر تعريف
    // Windows القياسي للطابعة، لا بروتوكول ESC/POS مباشر لموديل بعينه.
    public double ReceiptWidthMm { get; set; } = 80;

    /// <summary>
    /// الرقم الضريبي — كما تطلبه الفاتورة الرسمية.
    ///
    /// <para>لم يكن له موضع، فيكتبه التاجر بخطّ اليد على الورقة المطبوعة أو
    /// لا يكتبه.</para>
    /// </summary>
    public string? TaxNumber { get; set; }

    /// <summary>رقم السجلّ التجاري.</summary>
    public string? CommercialRegistry { get; set; }

    /// <summary>
    /// قالب الإيصال — JSON واحد لا عمودٌ لكل خيار.
    ///
    /// <para><b>الفجوة التي يسدّه:</b> الإيصال كان يطبع اسم المنظمة نصّاً
    /// وحسب: لا شعار ولا رقم ضريبي ولا سجلّ تجاري ولا شروط تذييل ولا رمز
    /// استجابة سريعة. والتاجر يريد شعاره على الورقة — وهو أوّل ما يسأل عنه
    /// بعد الشراء.</para>
    ///
    /// <para><b>ولماذا JSON لا أعمدة:</b> نفس نهج
    /// <see cref="BarcodeTemplateJson"/>. كل خيار عمودٌ يعني هجرةً لكل خيار
    /// جديد — وهو الطريق الذي انتهى بجدولٍ ذي ١٦٥ عموداً في نظامٍ آخر
    /// دُرس (راجع ENTERPRISE_HARVEST.md §32.2).</para>
    ///
    /// <para><c>paper</c> أحد: <c>roll80</c>، <c>roll58</c>، <c>a4</c>،
    /// <c>a5</c>.</para>
    /// </summary>
    public string ReceiptTemplateJson { get; set; } =
        "{\"paper\":\"roll80\",\"showLogo\":true,\"showTaxNumber\":true,"
        + "\"showCommercialRegistry\":false,\"showQr\":false,"
        + "\"headerText\":null,\"footerText\":\"شكراً لتعاملكم معنا\"}";
    // شريط جانبي أو شريط علوي — تفضيل عرض بحت لا يغيّر أي وظيفة.
    public string NavLayout { get; set; } = "sidebar";
    // السماح ببيع الأصناف مفتوحة القيمة في نقطة البيع. مطفأ افتراضياً:
    // قيمة يكتبها الكاشير بنفسه لا تقابلها بضاعة في المخزون، فهي أوسع باب
    // لسحب نقدية بلا أثر. تفعيله قرار مدير المنظمة (super_admin) وحده،
    // ولا يُضبط من إعدادات جهاز الكاشير.
    public bool PosAllowOpenProduct { get; set; }

    /// <summary>
    /// منطقة المنظمة الزمنية — راجع [OrgClock].
    ///
    /// <para>«اليوم» كان يُقاس بـUTC، فمحلٌّ في طرابلس بين العاشرة مساءً
    /// ومنتصف الليل يُسجّل مصروف اليوم في يوم أمس، ولا يستطيع إقفال أمس.
    /// </para>
    /// </summary>
    // النصّ لا OrgClock.DefaultTimeZone: الكيانات لا تعتمد على طبقة
    // البيانات. والقيمتان متطابقتان وتُفحصان في الاختبار.
    public string TimeZoneId { get; set; } = "Libya";

    // ── أنماط بطاقة المحفظة (راجع [CardModes]) ──────────────────────────

    /// <summary>
    /// الأنماط المسموحة في هذه المنظمة، مفصولة بفاصلة. المدير يحدّد
    /// **المظروف** لا اختيار كل زبون: محلٌّ بلا إنترنت مستقرّ لا يفعّل
    /// التأكيد بالهاتف، ومحلٌّ يخدم كباراً قد يُلغي الرقم السرّي كلّه.
    /// </summary>
    public string CardModesAllowed { get; set; } = $"{CardModes.Card},{CardModes.Pin}";

    /// <summary>نمط الحساب الجديد — كل حساب يبدأ من مكان معلوم.</summary>
    public string CardModeDefault { get; set; } = CardModes.Pin;

    /// <summary>
    /// السقف اليومي لنمط «بطاقة فقط». صفر = النمط معطَّل فعلياً.
    ///
    /// <para>هو ما يجعل النمط المكشوف مقبولاً: خطرُه محصور برقم يقرّره
    /// المدير، لا بكامل رصيد الزبون.</para>
    /// </summary>
    public decimal CardOpenModeDailyCap { get; set; } = 50;

    // ── النسخة الاحتياطية التلقائية ─────────────────────────────────────
    //
    // النسخة اليدوية تعتمد على أن يتذكّرها إنسان، والإنسان يتذكّرها شهراً
    // ثم ينساها — ولا يكتشف نسيانه إلا يوم يحتاجها. فالتلقائية هي التي
    // تحمي فعلاً، واليدوية تبقى لمن يريد نسخةً الآن.

    /// <summary>هل تُؤخذ نسخة ليلية وتُرفع إلى درايف المنظمة؟</summary>
    public bool AutoBackupEnabled { get; set; }

    /// <summary>
    /// ساعة الرفع **بتوقيت المنظمة** لا بـUTC — راجع [OrgClock].
    ///
    /// <para>«الثالثة فجراً» عند صاحب المحلّ تعني الثالثة عنده. وضبطها
    /// بـUTC كان يجعل النسخة تُؤخذ الواحدة صباحاً في ليبيا والسابعة مساءً
    /// في مكانٍ آخر — أي في ذروة البيع.</para>
    /// </summary>
    public int AutoBackupHour { get; set; } = 3;

    /// <summary>
    /// رمز التحديث من قوقل — به يُصدر الخادم رمز وصولٍ عند كل رفع.
    ///
    /// <para><b>ولا يخرج في أي استجابة أبداً:</b> من يملكه يكتب في درايف
    /// صاحبه بلا كلمة مرور ولا تحقّق ثانٍ. فالنقاط تُرجع البريد المرتبط
    /// وحده — راجع [BackupController].</para>
    /// </summary>
    public string? GoogleRefreshToken { get; set; }

    /// <summary>بريد الحساب المرتبط — ليعرف المالك أين تذهب نسخه.</summary>
    public string? GoogleAccountEmail { get; set; }

    /// <summary>مجلّد الدرايف الذي تُرفع إليه النسخ — يُنشأ عند أول رفع.</summary>
    public string? GoogleFolderId { get; set; }

    public DateTime? LastAutoBackupAt { get; set; }

    /// <summary>ok أو failed — وسببُ الفشل في [LastAutoBackupError].</summary>
    public string? LastAutoBackupStatus { get; set; }

    /// <summary>
    /// آخر سبب فشل، مقروءاً.
    ///
    /// <para><b>ولماذا يُخزَّن ويُعرَض:</b> رفعٌ يفشل ليلة بعد ليلة بلا أثر
    /// في الشاشة هو أسوأ من ألّا يكون هناك رفع: المالك يظنّ نفسه محميّاً.
    /// </para>
    /// </summary>
    public string? LastAutoBackupError { get; set; }

    /// <summary>
    /// حقولٌ إضافية يعرّفها مالك المنظمة لحسابات الدليل — JSON.
    ///
    /// <para><b>سبب وجودها:</b> ما يحتاجه الحساب يختلف بالنشاط: مقاولاتٌ
    /// تريد «مركز التكلفة» على كل حساب، وجهةٌ متعدّدة العملات تريد «عملة
    /// الحساب»، ومكتبٌ يريد «رقم الحساب في النظام القديم» ليطابق. وإضافةُ
    /// عمودٍ لكل واحدة تعني هجرةً لكل عميل — وهو الطريق الذي انتهى بجدولٍ
    /// ذي ١٦٥ عموداً في نظامٍ آخر دُرس.</para>
    ///
    /// <para><b>ولماذا التعريف على المنظمة والقيمة على الحساب:</b> التعريف
    /// يُكتب مرّةً ويُقرأ في كل نموذج، والقيمة تخصّ صفّاً واحداً. وخلطُهما
    /// يعني تكرار اسم الحقل ونوعه في كل حساب — فيُعاد تسميته في مئة موضع.
    /// </para>
    ///
    /// <para>الشكل: <c>[{"key":"f1","label":"مركز التكلفة","type":"text",
    /// "required":false,"options":[]}]</c></para>
    /// </summary>
    public string AccountFieldDefsJson { get; set; } = "[]";

    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// صف واحد عالمي — بيانات تواصل مالك المنصة، تُعرض لكل العملاء كجهة دعم
/// فني موحّدة. راجع PlatformSettingsController.cs.
/// </summary>
public class PlatformSettings
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string CompanyName { get; set; } = "";
    public string OwnerName { get; set; } = "";
    public string? Phone { get; set; }
    public string? Whatsapp { get; set; }
    public string? Email { get; set; }
    public string? Address { get; set; }
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// فهرس عالمي (لا RLS) لكل منظمة زوَّدها مالك المنصة — راجع
/// PlatformController.cs. منفصل عمداً عن Organization المحمية بـ RLS.
/// </summary>
public class PlatformOrganizationRecord
{
    public Guid Id { get; set; }
    public string LegalName { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public bool IsActive { get; set; } = true;

    /// <summary>
    /// حساب المنصّة الذي باع هذه المنظمة — من أنشأها يملكها.
    ///
    /// <para><b>وهو مدار العزل بين المهندسين:</b> مهندسٌ يرى ما نُسب إليه
    /// وحده، ومالك المنصّة يرى الكلّ. والحقل هنا على **الفهرس العالمي** لا
    /// على جدول المنظمات: الفهرس هو ما يُقرأ بلا عزل صفوف، وهو الوحيد الذي
    /// يستطيع مالك المنصّة قراءته كلّه أصلاً.</para>
    ///
    /// <para>و<c>null</c> = بلا نسبة — منظمات أُنشئت قبل وجود المهندسين.
    /// يراها المالك ولا يراها أي مهندس، وهو الصواب: لا أحد باعها غيره.</para>
    /// </summary>
    public Guid? OwnerUserId { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public class License
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public string LicenseKey { get; set; } = "";
    public string PlanTier { get; set; } = "standard"; // trial | standard | professional | enterprise
    public int MaxBranches { get; set; } = 1;
    public int MaxUsers { get; set; } = 5;
    /// <summary>
    /// الوحدات الفعّالة كما تُعرَض — **مشتقّة لا مصدر**.
    ///
    /// <para>تُعاد كتابتها من [LicenseLimits.EffectiveModules] عند كل تغيير
    /// في الإصدار أو في الفوارق. لا يقرأها فارضٌ واحد في النظام: قراءتها
    /// للفرض تعني مصدرَي حقيقة للوحدات يفترقان أوّل مرّة يُعدَّل أحدهما من
    /// خارج المسار — وهو عين ما تمنعه قاعدة «مخنقٌ واحد لكل فعل».</para>
    ///
    /// <para>وتبقى موجودة لأنها ما يقرؤه العميل في شاشة ترخيصه وما يُطبع في
    /// عقده.</para>
    /// </summary>
    public string EnabledModulesJson { get; set; } = "[\"inventory\",\"pos\",\"customers\",\"reports\"]";

    /// <summary>
    /// وحدات اشتُريت **فوق** الإصدار — الإصدار قالبٌ ابتدائي لا سقف.
    ///
    /// <para><b>العطب الذي يصلحه:</b> كانت الوحدات الفعّالة تقاطعاً بين
    /// وحدات الإصدار ووحدات الترخيص، فيمكن سحب وحدة من إصدارٍ ولا يمكن
    /// إضافة وحدة ليست فيه أبداً. فبيع نشرة الدواء لعميلٍ قياسي — وهو بيعٌ
    /// حقيقي يُطلب — كان يستلزم نقله إلى إصدار الصيدليات بكامله.</para>
    ///
    /// <para><b>ولماذا فارقٌ لا قائمةٌ كاملة:</b> الفارق يبقى صحيحاً عبر
    /// تغيير الإصدار. عميلٌ اشترى pharmacy ثم رُقّي إلى إصدار المؤسسات
    /// يحتفظ بها تلقائياً — بينما القائمة الكاملة كانت تُعاد حسابتها من
    /// الإصدار الجديد فتضيع كل صفقةٍ بيعت منفردة، بلا أثرٍ يدلّ عليها.</para>
    /// </summary>
    public string GrantedModulesJson { get; set; } = "[]";

    /// <summary>
    /// وحدات سُحبت من الإصدار — عميلٌ لا يريدها أو لم يدفع ثمنها.
    ///
    /// <para>السحب يغلب المنح عند اجتماعهما على وحدة واحدة: صفٌّ متناقض
    /// يجب أن يُغلق لا أن يُفتح، فحالة الفرض الخاطئة الوحيدة المقبولة هي
    /// أن يشتكي عميل من وحدة ناقصة — لا أن يعمل بوحدة لم تُبَع.</para>
    /// </summary>
    public string RevokedModulesJson { get; set; } = "[]";
    /// <summary>الاشتراك الشهري المتفَّق عليه — يُطبَع في العقد.</summary>
    public decimal MonthlyFee { get; set; }

    /// <summary>رسوم التخزين السحابي الشهرية.</summary>
    public decimal StorageFee { get; set; }

    /// <summary>نسبة الصيانة المئوية. صفر يعني التفاهم عليها مع الدعم.</summary>
    public decimal MaintenanceRate { get; set; }

    public string? HardwareFingerprint { get; set; }
    public DateTime IssuedAt { get; set; } = DateTime.UtcNow;
    public DateTime ExpiresAt { get; set; }

    /// <summary>
    /// active (عامل) · grace_period (مهلة — قراءة فقط) · expired (منتهٍ) ·
    /// revoked (أُنهيت الخدمة).
    ///
    /// <para>كانت هذه القيم معرَّفة في المخطّط منذ البداية **ولا يقرأها
    /// أحد** — أي أن ترخيصاً منتهياً أو ملغى كان يعمل كالجديد تماماً.</para>
    /// </summary>
    public string Status { get; set; } = "active";

    /// <summary>
    /// قراءة فقط: كل ما ليس <c>GET</c> يُرفض.
    ///
    /// <para><b>عمود واحد يخدم ثلاث حاجات</b> بدل ثلاث آليات:
    /// نسخة العرض التي تُرى ولا تُعدَّل، والعميل المتأخّر في السداد يُجمَّد
    /// بلا أن يفقد بياناته، ومهلة ما بعد الانتهاء التي يذكرها
    /// <c>ARCHITECTURE.md</c> §2.2 — «قراءة فقط بدل توقّف مفاجئ يفقد ثقة
    /// الزبون».</para>
    ///
    /// <para><b>ولماذا على الترخيص لا على الإصدار:</b> ربطه بإصدار
    /// <c>trial</c> كان يمنع وجود تجربة حقيقية يُدخِل فيها العميل بياناته،
    /// ويمنع تجميد عميل قياسي متأخّر. الحاجة صفةُ عقد لا شكلُ منتج.</para>
    /// </summary>
    public bool IsReadOnly { get; set; }

    /// <summary>سبب التجميد أو الإنهاء — يُعرض للعميل نفسه لا لنا وحدنا.</summary>
    public string? StatusReason { get; set; }

    /// <summary>متى تغيّرت الحالة آخر مرّة — أساس أي نزاع لاحق.</summary>
    public DateTime? StatusChangedAt { get; set; }
}

public class Branch
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public string Name { get; set; } = "";
    public string Code { get; set; } = "";
    public string? Address { get; set; }
    public string? Phone { get; set; }

    /// <summary>
    /// لوح خلفية الفرع: default | warm | cool | green | slate.
    ///
    /// <para><b>يميّز المكان لا الشخص:</b> تفضيل السطوع (نهاري/ليلي) شخصيّ
    /// يُحفَظ على الجهاز، أمّا اللوح فيقول لموظفٍ ينتقل بين فرعين **أين هو
    /// الآن** — وهو ما يمنع إدخال بيانات في الفرع الخطأ، أشيع أخطاء
    /// الأنظمة متعدّدة الفروع.</para>
    ///
    /// <para>ولا يمسّ ألوان العلامة التجارية: يُزيح الأسطح والحدود وحدها،
    /// فتبقى هوية الشركة واحدة في كل فروعها (ARCHITECTURE.md §2.1).</para>
    /// </summary>
    public string ThemePalette { get; set; } = "default";

    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// BranchId = null يعني صلاحية على كل فروع المنظمة (مدير عام) — نفس المنطق
/// المستخدم في fn_TenantPredicate على مستوى قاعدة البيانات.
/// </summary>
public class AppUser
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid? BranchId { get; set; }
    public string FullName { get; set; } = "";
    public string Email { get; set; } = "";
    // اسم دخول مختصر اختياري بديل عن البريد الكامل — أسهل للعمال (كاشير،
    // أمين مخزن) من كتابة بريد إلكتروني كامل في كل مناوبة. فريد داخل
    // المنظمة فقط (نفس نطاق تفرّد Email)، وليس إلزامياً.
    public string? Username { get; set; }
    public string PasswordHash { get; set; } = "";
    public string Role { get; set; } = "cashier";
    public bool IsActive { get; set; } = true;
    // مالك المنصة (أنت، مشغّل النظام) فقط — يمنح صلاحية تزويد منظمات
    // (عملاء) جدد عبر PlatformController، منفصلة تماماً عن super_admin
    // العادي الذي يبقى محصوراً داخل منظمته وحدها. راجع PlatformController.cs.
    public bool IsPlatformAdmin { get; set; }

    /// <summary>
    /// دور هذا الحساب على مستوى المنصّة: <c>owner</c> أو <c>engineer</c>،
    /// و<c>null</c> لمن ليس حساب منصّة أصلاً.
    ///
    /// <para><b>لماذا حقلٌ ثانٍ بجوار [IsPlatformAdmin] لا استبدالٌ له:</b>
    /// العلم القديم يعني «يدخل شاشات المنصّة»، وهو صحيح للاثنين. وتحويله
    /// إلى نصّ كان سيمسّ كل فحصٍ في الخادم والواجهة والتوكن دفعةً واحدة —
    /// وواحدٌ منها يُنسى فيصير المهندس مالكاً أو المالك عاجزاً. فالعلم يبقى
    /// بوّابة الدخول، وهذا يقول ما حدوده بعدها.</para>
    ///
    /// <para>و<c>null</c> مع علمٍ مرفوع = مالك: حسابات المنصّة القائمة قبل
    /// هذا الترحيل أُنشئت كلّها مالكةً، وتفسير غيابها بـ«مهندس» كان يسلبها
    /// صلاحياتها لحظة الترقية.</para>
    /// </summary>
    public string? PlatformRole { get; set; }

    /// <summary>
    /// رقم ترخيص مهندس البيع — يولّده النظام ويُطبع في عقد كل عميل باعه.
    ///
    /// <para>فيُعرَف من باع لمن من الورقة وحدها، بعد سنوات وبلا فتح
    /// النظام. ولمالك المنصّة أيضاً رقم — فهو يبيع كذلك.</para>
    /// </summary>
    public string? ResellerLicense { get; set; }

    /// <summary>
    /// كلمةُ مرورٍ مؤقّتة تنتظر التغيير — يُرفع عند كل إعادة تعيين من غير
    /// صاحب الحساب، ويُخفض حين يغيّرها هو.
    ///
    /// <para><b>العطب الذي يصلحه:</b> إعادة التعيين تُولّد كلمةً تُملى
    /// هاتفياً وتُسلَّم للعميل «ليغيّرها» — ولا شيء كان يُلزمه. فتبقى الكلمة
    /// التي أملاها مشغّل النظام هي كلمة الحساب الدائمة، ويعرفها اثنان.</para>
    ///
    /// <para>والفرض على الخادم لا في الشاشة: شاشةٌ تُلحّ تُتجاوز بفتح مسارٍ
    /// آخر، والتوكن يبقى صالحاً ثماني ساعات. راجع
    /// [MustChangePasswordFilter].</para>
    /// </summary>
    public bool MustChangePassword { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>أدوار المنصّة — المصدر الوحيد لأسمائها.</summary>
public static class PlatformRoles
{
    public const string Owner = "owner";
    public const string Engineer = "engineer";

    /// <summary>
    /// أمالكٌ هذا؟ — الغياب يعني مالكاً لا مهندساً.
    ///
    /// <para><b>الفشل المغلق هنا كان سيكون خطأ:</b> كل حساب منصّة أُنشئ قبل
    /// هذا الترحيل يحمل <c>null</c>، وتفسيره «مهندس» كان يسلب مالك المنصّة
    /// حذفَ المنظمات وإنشاءَ المهندسين لحظة الترقية — بلا أن يعرف السبب.
    /// </para>
    /// </summary>
    public static bool IsOwner(string? platformRole) => platformRole != Engineer;
}

/// <summary>
/// راجع ARCHITECTURE.md §2.3 ("سجل تسجيل الدخول"). يُكتب من AuthController
/// فقط عندما يتطابق البريد مع مستخدم موجود فعلاً (نجاحاً أو كلمة مرور
/// خاطئة) — محاولة ببريد غير موجود أصلاً لا تنتمي لأي منظمة فيُستحيل عزوها.
/// </summary>
public class LoginHistory
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public Guid OrganizationId { get; set; }
    public string? IpAddress { get; set; }
    public string? DeviceInfo { get; set; }
    public bool Success { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public partial class Product
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid? CategoryId { get; set; }
    public Guid? SupplierId { get; set; }
    public string Sku { get; set; } = "";
    public string? Barcode { get; set; }
    public string Name { get; set; } = "";
    public string UnitBase { get; set; } = "piece";
    public decimal UnitConversionFactor { get; set; } = 1;

    // ── البيع بالوحدة الجزئية ──────────────────────────────────────────
    //
    // الصيدلية تشتري شريطاً وتبيع حبّة، والبقالة تبيع البيضة من الطبق.
    // المخزون يُعدّ بالوحدة الأساسية دائماً، والبيع الجزئي يخصم كسراً منها.

    /// <summary>اسم الوحدة الجزئية: حبّة، قرص، مل. NULL = لا بيع جزئي.</summary>
    public string? SubUnitName { get; set; }

    /// <summary>كم وحدة جزئية في الوحدة الأساسية. صفر أو واحد = لا بيع جزئي.</summary>
    public decimal SubUnitsPerBase { get; set; }

    /// <summary>
    /// سعر الوحدة الجزئية — مستقلٌّ لا يُشتقّ بالقسمة: الصيدلية تربح على
    /// التجزئة، فحبّة من شريط بثمانية دنانير تُباع بدينار لا بـ0.80.
    /// </summary>
    public decimal SubUnitPrice { get; set; }

    /// <summary>هل يقبل هذا الصنف بيعاً جزئياً فعلياً.</summary>
    public bool AllowsSubUnitSale => SubUnitsPerBase > 1 && SubUnitPrice > 0;
    public decimal CostPrice { get; set; }
    public decimal SalePrice { get; set; }

    /// <summary>
    /// الحدّ الأدنى لسعر البيع. صفر = بلا حدّ.
    ///
    /// <para><b>العطب الذي يسدّه:</b> صلاحية <c>pos.price_override</c> تسمح
    /// بتغيير السعر، ولا شيء كان يمنع البيع **تحت التكلفة**. كاشيرٌ يخطئ في
    /// رقم، أو يجامل قريباً، فتخرج البضاعة بخسارة ولا يظهر ذلك إلا في تقرير
    /// الشهر — إن ظهر. والصلاحية لا تحمي: مدير المنظمة يملكها دائماً.</para>
    ///
    /// <para><b>وهو حدٌّ مطلق لا يتجاوزه أحد</b> — ولا حتى حامل صلاحية
    /// تعديل السعر. حدٌّ له استثناء ليس حدّاً: من يريد بيعاً أرخص يُنزل
    /// الحدّ صراحةً على بطاقة الصنف، فيبقى القرار مسجَّلاً في مكانٍ واحد بدل
    /// أن يتكرّر صامتاً في كل فاتورة.</para>
    ///
    /// <para>وبالوحدة الأساسية دائماً: البيع الجزئي يقيسه بالنسبة (راجع
    /// [SubUnitsPerBase])، فحدٌّ ثانٍ للوحدة الجزئية كان سيفترق عن الأوّل
    /// أوّل مرّة يُعدَّل أحدهما.</para>
    public decimal MinSalePrice { get; set; }
    /// <summary>
    /// نشرة الدواء المرتبطة بهذا الصنف — راجع [MedicineReference].
    ///
    /// اختياري دائماً وليس فقط في غير إصدار الصيدلية: الصيدلية نفسها تبيع
    /// مستحضرات تجميل وحفاضات وأدوات، وإلزامه كان يمنع إدخالها.
    /// </summary>
    public Guid? MedicineRefId { get; set; }

    public bool TrackExpiry { get; set; }
    public decimal ReorderLevel { get; set; }

    /// <summary>
    /// مهلة التوريد بالأيام — كم يوماً بين إرسال أمر الشراء ووصول البضاعة.
    /// نصف معادلة إعادة الطلب (الاستهلاك اليومي × المهلة).
    /// </summary>
    public int LeadTimeDays { get; set; } = 7;

    /// <summary>
    /// صنف غير متتبَّع مخزنياً (خدمة، أو بضاعة مفتوحة القيمة تُكتب قيمتها
    /// يدوياً عند البيع).
    ///
    /// وُجد لمشتري النظام الذي يستخدمه لتعبئة أرصدة عملائه والخصم منها دون
    /// إدارة مخزون أصلاً. البديل — خصم من المحفظة بلا فاتورة — كان يقطع سلسلة
    /// التدقيق: لا يُعرف *ماذا* أخذ العميل، ولا يمكن عمل مرتجع، ولا يظهر البيع
    /// في تقارير المبيعات. فالبيع يبقى فاتورة نظامية كاملة، ويُتخطّى قيد
    /// المخزون وحده (راجع InvoicesController.Create).
    /// </summary>
    public bool TracksStock { get; set; } = true;

    /// <summary>
    /// آخر مرّة عُدّ فيها هذا الصنف فعلياً (اعتُمد جرد يشمله).
    ///
    /// <para>هو ما يجعل **الجرد الدوري الموزَّع** ممكناً: بدل إغلاق المحل
    /// يوماً كاملاً لعدّ كل شيء، يُعدّ ما لم يُعدّ منذ مدّة. والحقل بلا
    /// معنى قبل أن يوجد معيار يقرأه — ولهذا يُضاف معه لا قبله.</para>
    /// </summary>
    public DateTime? LastCountedAt { get; set; }

    public bool IsDeleted { get; set; }
}

/// <summary>
/// لا يحمل branch_id عمداً — المورّد يتعامل مع المنظمة ككل
/// (راجع DATABASE_TABLES_GUIDE.md §5.1)، وليس فرعاً واحداً.
/// </summary>
public class Supplier
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public string Name { get; set; } = "";
    public string? Phone { get; set; }
    public decimal Balance { get; set; }
    public bool IsDeleted { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// شجرة فئات عبر ParentId (Self-Referencing) — راجع
/// DATABASE_TABLES_GUIDE.md §5.2.
/// </summary>
public class ProductCategory
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public string Name { get; set; } = "";
    public Guid? ParentId { get; set; }
}

/// <summary>
/// مرفق مخزَّن على قرص السيرفر — شعار منظمة، أو صورة فاتورة مورّد.
///
/// الصفّ يصف الملف ولا يحمله: البايتات على القرص تحت مجلد التخزين
/// (Storage:Path)، و[StoredName] اسمه هناك. حفظ الملفات في القاعدة كان
/// سيُضخّم كل نسخة احتياطية بصور لا تتغيّر أبداً بعد رفعها.
/// </summary>
public class Attachment
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    /// organization_logo | purchase_order
    public string EntityType { get; set; } = "";
    public Guid? EntityId { get; set; }
    public string FileName { get; set; } = "";
    public string ContentType { get; set; } = "";
    public long SizeBytes { get; set; }
    /// اسم الملف على القرص فقط لا مسار كامل — نقل المجلد لا يُبطل الصف.
    public string StoredName { get; set; } = "";
    public Guid? UploadedBy { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public class StockLevel
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid BranchId { get; set; }
    public Guid ProductId { get; set; }
    public decimal Quantity { get; set; }
    public string BatchNumber { get; set; } = "";
    public DateTime? ExpiryDate { get; set; }

    /// <summary>
    /// موضع التخزين داخل الفرع. NULL = مستودع الفرع الافتراضي — راجع
    /// [Warehouse]. قابليته للـ NULL هي ما يجعل الشجرة تُضاف بلا ترحيل
    /// بيانات ولا كسر لإصدار قائم.
    /// </summary>
    public Guid? WarehouseId { get; set; }

    // ── القفل: إيقاف بضاعة في مكانها ────────────────────────────────────
    //
    // تصل دفعة بشبهة عيب، أو ينتظر صنف نتيجة فحص، أو تُرتجع بضاعة يجب ألّا
    // تُباع قبل معاينتها. الحلول الثلاثة المتاحة قبل هذا الحقل كانت كلها
    // معطوبة: حذف الصفّ يفقد الكمية ويكسر التدقيق، وتركه يعني أن يبيعها
    // الكاشير، ونقلها إلى فرع وهمي يشوّه كل تقارير الفروع.
    //
    // فالقفل هو الجواب الرابع: البضاعة تبقى في مكانها وبكمّيتها، وتظهر في
    // الجرد وفي قيمة المخزون (فهي مالٌ مملوك فعلاً)، وتخرج وحدها من:
    // المتاح للبيع، وحساب إعادة الطلب، والتحويل بين الفروع.

    /// <summary>موقوفة عن الصرف — راجع تعليق القفل أعلاه.</summary>
    public bool IsLocked { get; set; }

    /// <summary>
    /// سبب الإيقاف. إلزامي عند القفل لا اختياري: قفلٌ بلا سبب يصبح بعد
    /// أسبوعين كمية مجمَّدة لا يعرف أحد لماذا جُمِّدت ولا متى تُفرَج.
    /// </summary>
    public string? LockReason { get; set; }

    public Guid? LockedBy { get; set; }
    public DateTime? LockedAt { get; set; }

    // ── تاريخ الاستراتيجية: ترتيب الصرف بحقل واحد ────────────────────────
    //
    // الصيدلية يجب أن تصرف الأقرب انتهاءً (FEFO)، والبقالة تكفيها الأقدم
    // دخولاً (FIFO). فبدل قاعدتَي ترتيب منفصلتين، تاريخٌ واحد يُملأ بحسب
    // طبيعة الصنف ويُرتَّب عليه في كل مكان:
    //
    //   صنف بصلاحية  → تاريخ الانتهاء     ⇒ FEFO
    //   صنف بلا صلاحية → تاريخ الإدخال     ⇒ FIFO
    //
    // العطب الذي يصلحه: الأصناف بلا صلاحية كانت تُرتَّب برقم الدفعة أبجدياً
    // — أي عشوائياً فعلياً — فتبقى الدفعة القديمة على الرفّ إلى ما لا نهاية
    // لأن رقمها يبدأ بحرف متأخّر.

    /// <summary>
    /// أساس ترتيب الصرف. NULL = صنف يتتبّع الصلاحية ووصلت دفعته بلا تاريخ
    /// (بيانات قديمة أو إدخال ناقص) — ويُؤخَّر في الترتيب عمداً: المعلوم
    /// أولى بالتصريف من المجهول.
    /// </summary>
    public DateTime? StrategyDate { get; set; }

    /// <summary>
    /// يُستدعى عند **إنشاء** الصفّ أو تغيير تاريخ صلاحيته — لا عند مجرّد
    /// زيادة الكمية على دفعة قائمة: إعادة ختمه حينها تُقفز الدفعة القديمة
    /// إلى آخر الطابور كلما وصلها توريد جديد، وهو نقيض FIFO.
    /// </summary>
    public void StampStrategyDate(bool trackExpiry) =>
        StrategyDate = ExpiryDate ?? (trackExpiry ? null : DateTime.UtcNow);
}

/// <summary>
/// تسلسل status (راجع DATABASE_TABLES_GUIDE.md §5.5): pending (أُنشئ، بلا
/// أثر مخزوني بعد) ← in_transit (خُصمت الكمية من الفرع المصدر فعلياً) ←
/// received (أُضيفت للفرع الهدف) — يمنع ازدواج الكمية أو فقدانها أثناء
/// النقل. لا مسار رجوع من in_transit إلى cancelled عمداً؛ البضاعة تكون قد
/// غادرت الفرع المصدر فعلياً، فالتصحيح بعد هذه النقطة تعديل مخزون يدوي.
/// </summary>
/// <summary>أنواع المستندات التي تُحرّك المخزون — مصدر السطر في الدفتر.</summary>
public static class StockSourceTypes
{
    public const string PurchaseReceipt = "purchase_receipt";
    public const string Invoice = "invoice";
    public const string InvoiceReturn = "invoice_return";
    public const string TransferOut = "transfer_out";
    public const string TransferIn = "transfer_in";
    public const string StockCount = "stock_count";
    /// <summary>بضاعة أُعيدت إلى المورّد — إخراجٌ من المخزون.</summary>
    public const string PurchaseReturn = "purchase_return";

    public const string ManualAdjustment = "manual_adjustment";
    public const string Opening = "opening";
}

/// <summary>
/// دفتر حركة المخزون — **مصدر الحقيقة**، وstock_levels ذاكرة مشتقّة منه.
///
/// <para><b>العطب الذي يصلحه:</b> كان الرصيد يُعدَّل في مكانه، فلا جواب عن
/// «كم كان الرصيد يوم كذا»، ولا تكلفة حقيقية (سعر تكلفة واحد ثابت للصنف مهما
/// اختلفت أسعار الشراء)، ولا أثر يُجمَع حسابياً لمن غيّر ماذا.</para>
///
/// <para><b>يُلحَق به ولا يُعدَّل:</b> التصحيح بسطرٍ عكسي لا بمحو الماضي —
/// نفس حرمة القيد في دفتر المحفظة. و<see cref="IsCancelled"/> إلغاء منطقي
/// لا حذف.</para>
///
/// <para><b>الكتابة داخل المعاملة نفسها</b> التي تُعدّل الرصيد، عبر
/// [StockLedger] وحده — لا مسار يستثنيه.</para>
/// </summary>
public class StockLedgerEntry
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid BranchId { get; set; }

    /// <summary>NULL = مستودع الفرع الافتراضي — راجع [Warehouse].</summary>
    public Guid? WarehouseId { get; set; }

    public Guid ProductId { get; set; }
    public string BatchNumber { get; set; } = "";
    public DateTime? ExpiryDate { get; set; }

    /// <summary>
    /// وقت الحركة. datetime لا date: ترتيب حركات اليوم الواحد يحدّد الرصيد
    /// بعد كلٍّ منها، وتاريخٌ بلا وقت يجعل ترتيب البيع والاستلام في اليوم
    /// نفسه اعتباطياً.
    /// </summary>
    public DateTime PostedAt { get; set; } = DateTime.UtcNow;

    /// <summary>الفرق موجباً أو سالباً — لا رصيداً.</summary>
    public decimal QuantityChange { get; set; }

    /// <summary>الرصيد بعد هذه الحركة، لهذه الدفعة في هذا الموضع.</summary>
    public decimal BalanceAfter { get; set; }

    /// <summary>تكلفة الوحدة الداخلة أو الخارجة.</summary>
    public decimal UnitCost { get; set; }

    /// <summary>قيمة المخزون بعد الحركة = BalanceAfter × متوسط التكلفة.</summary>
    public decimal ValueAfter { get; set; }

    /// <summary>ما يُرحَّل محاسبياً — أساس تقرير قيمة المخزون.</summary>
    public decimal ValueChange { get; set; }

    /// <summary>راجع [StockSourceTypes].</summary>
    public string SourceType { get; set; } = "";
    public Guid? SourceId { get; set; }

    /// <summary>
    /// سطر الإدخال الذي استُهلك منه — في سطور الصرف وحدها.
    ///
    /// <para>هذا ما يميّز الدفتر عن دفتر عادي: الأخير يقول «خرجت خمس قطع»،
    /// وهذا يقول «خرجت خمس قطع **من الشحنة التي وصلت يوم كذا بتكلفة كذا**».
    /// منه تُقرأ التكلفة الدقيقة بلا طابور FIFO يُخزَّن ويُصان، ومنه يُجاب
    /// سؤال التتبّع العكسي: «هذه الدفعة معيبة — من اشتراها؟» باستعلام
    /// واحد — وهو مطلب تنظيمي في الأدوية والغذاء لا رفاهية.</para>
    /// </summary>
    public Guid? SourceEntryId { get; set; }

    /// <summary>
    /// المتبقّي من هذا الإدخال لم يُستهلَك بعد — في سطور الإدخال وحدها.
    /// هو ما يجعل اختيار «من أي إدخال نصرف» استعلاماً لا حساباً تراكمياً.
    /// </summary>
    public decimal RemainingQuantity { get; set; }

    public Guid? CreatedBy { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public bool IsCancelled { get; set; }
    public string? CancelReason { get; set; }
}

/// <summary>أنواع المستودعات — راجع [Warehouse].</summary>
public static class WarehouseKinds
{
    public const string Main = "main";
    /// <summary>بضاعة غادرت فرعاً ولم تصل الآخر بعد.</summary>
    public const string Transit = "transit";
    public const string Damaged = "damaged";
    public const string Returns = "returns";
    public const string Quarantine = "quarantine";
}

/// <summary>
/// مستودع **تحت** الفرع لا بدلاً منه.
///
/// <para><b>لماذا NULL مسموح في كل مكان يشير إليه:</b> NULL يعني «مستودع
/// الفرع الافتراضي». فتبقى البقالة والصيدلية تعملان بلا سطر إعداد واحد ولا
/// ترحيل بيانات، ويستفيد إصدار المؤسسات وحده من الشجرة.</para>
///
/// <para><b>مستودع العبور يصلح عطباً قائماً:</b> تحويل في حالة
/// <c>in_transit</c> يُخصم من المصدر ولا يُضاف للهدف — فتختفي البضاعة من كل
/// تقرير طوال الترحيل. بمستودع عبور تبقى مرئية، لها مكان ومسؤول.</para>
/// </summary>
public partial class Warehouse
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid BranchId { get; set; }

    /// <summary>عقدة أعلى في الشجرة. NULL = جذر تحت الفرع.</summary>
    public Guid? ParentWarehouseId { get; set; }

    public string Name { get; set; } = "";
    public string Code { get; set; } = "";
    public string Kind { get; set; } = WarehouseKinds.Main;

    /// <summary>
    /// عقدة تجميعية لا تُخزَّن فيها بضاعة — تُجمع أرصدة أبنائها وحسب.
    /// السماح بالتخزين فيها يجعل المجموع يعدّ الأب والابن معاً.
    /// </summary>
    public bool IsGroup { get; set; }

    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public class StockTransfer
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid FromBranchId { get; set; }
    public Guid ToBranchId { get; set; }
    public string Status { get; set; } = "pending"; // pending | in_transit | received | cancelled
    public Guid? CreatedBy { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public List<StockTransferItem> Items { get; set; } = new();
}

public class StockTransferItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid TransferId { get; set; }
    public Guid ProductId { get; set; }
    public decimal Quantity { get; set; }
}

/// <summary>
/// راجع DATABASE_TABLES_GUIDE.md §5.7. status: open (قيد العد) ← reconciled
/// (اعتُمد، وطُبِّق الفرق فعلياً على stock_levels) أو cancelled (أُلغي بلا أثر).
/// </summary>
public class StockCount
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid BranchId { get; set; }

    /// <summary>
    /// open (قيد العد) ← pending_review (انتهى العدّ وفيه فروقات تنتظر قراراً)
    /// ← reconciled (اعتُمدت الفروقات وطُبِّقت على stock_levels) أو عودة إلى
    /// open (طُلبت إعادة عدّ). و cancelled يُلغي بلا أثر.
    ///
    /// <para><b>لماذا حالة وسيطة:</b> كان الجرد ينتقل من open إلى reconciled
    /// بضغطة واحدة، فيُطبَّق فرقٌ ناتج عن خطأ عدّ على المخزون بلا أن يراه
    /// أحد. والفرق ليس رقماً محايداً: زيادة تُخفي سرقة، ونقصٌ يُشطب بضاعة
    /// موجودة. فالقرار بشري بخيارين لا ثالث لهما — اقبل الفرق، أو أعد العدّ.
    /// </para>
    ///
    /// <para>وجردٌ بلا فرق واحد لا يمرّ بها: لا قرار يُتخذ حين لا يوجد ما
    /// يُقرَّر فيه، وإجبار المستخدم على ضغطتين لتأكيد «لا شيء تغيّر» يُعلّمه
    /// أن يضغط بلا قراءة — وهو ما تُوجد هذه الخطوة لمنعه.</para>
    /// </summary>
    public string Status { get; set; } = "open";

    /// <summary>
    /// <c>periodic</c> جرد دوري على مخزون قائم، أو <c>initial</c> جرد
    /// ابتدائي لإدخال مخزون موجود إلى نظام جديد.
    ///
    /// <para><b>الفرق ليس تسميةً:</b> الدوري يبدأ بالكمية النظامية مملوءة
    /// فيصحّح الموظف الاستثناءات وحدها. والابتدائي يبدأ **بأصفار** لأنه لا
    /// كمية نظامية أصلاً — وملؤه بالنظامي كان يجعل «قبول الافتراضي» يُثبّت
    /// صفراً لكل صنف على الرفّ.</para>
    ///
    /// <para>وبلا هذا المسار كان كل زبون جديد يُدخل مخزونه الأول صنفاً صنفاً
    /// من شاشة تعديل الكمية — بلا مستند ولا مراجعة ولا أثر واحد يجمعها.</para>
    /// </summary>
    public string Kind { get; set; } = StockCountKinds.Periodic;

    public Guid? CreatedBy { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? ClosedAt { get; set; }

    /// <summary>من أنهى العدّ ومتى — الطرف الأول في القرار.</summary>
    public Guid? SubmittedBy { get; set; }
    public DateTime? SubmittedAt { get; set; }

    /// <summary>
    /// من بتّ في الفروقات ومتى (قبولاً أو إعادةَ عدّ).
    ///
    /// <para>لا يمنع النظام أن يكون هو نفسه من عدّ: المحل الذي يديره صاحبه
    /// وحده لا يملك شخصاً ثانياً، ومنعُه يجعل الجرد مستحيلاً فيه. لكنّ
    /// الحقلين منفصلان فيظهر تطابقهما في سجلّ التدقيق لمن يبحث عنه.</para>
    /// </summary>
    public Guid? ReviewedBy { get; set; }
    public DateTime? ReviewedAt { get; set; }

    /// <summary>سبب آخر طلب إعادة عدّ — إلزامي عند الطلب.</summary>
    public string? RecountReason { get; set; }

    /// <summary>
    /// كم مرّة أُعيد العدّ. جردٌ أُعيد ثلاث مرّات ليس جرداً دقيقاً بل مؤشّر
    /// على مشكلة في العدّ نفسه أو في المخزون — والرقم هو ما يجعلها مرئية.
    /// </summary>
    public int RecountRounds { get; set; }

    public List<StockCountItem> Items { get; set; } = new();
}

/// <summary>
/// Variance عمود محسوب (PERSISTED) في قاعدة البيانات نفسها — لا يُكتَب من
/// EF Core إطلاقاً (راجع AppDbContext.OnModelCreating)، فقط يُقرأ بعد الحفظ.
/// </summary>
public static class StockCountKinds
{
    public const string Periodic = "periodic";
    public const string Initial = "initial";
}

public class StockCountItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid StockCountId { get; set; }
    public Guid ProductId { get; set; }
    public decimal SystemQuantity { get; set; }
    public decimal CountedQuantity { get; set; }
    public decimal Variance { get; set; }

    /// <summary>
    /// متى عُدَّ هذا السطر فعلاً. NULL = **لم يُمَسّ بعد**.
    ///
    /// <para><b>العطب الذي يصلحه:</b> الجرد الدوري يبدأ بـ
    /// <c>CountedQuantity = SystemQuantity</c>، فسطرٌ لم يره أحد يبدو
    /// «عُدَّ وطابق». عاملٌ مسح أربعين صنفاً من ثلاثمئة ثم أرسل، يقول له
    /// النظام **صفر فروقات** — لأن مئتين وستين وافقت نفسها. الكمية وحدها
    /// لا تفرّق بين «طابق» و«لم يُنظَر إليه»، والفرق بينهما هو الجرد كلّه.
    /// </para>
    ///
    /// <para>وهو ما يجعل الشاشة الميدانية ممكنة أصلاً: سؤالها الدائم «كم
    /// بقي» لا جواب له بلا هذا الحقل.</para>
    /// </summary>
    public DateTime? CountedAt { get; set; }

    /// <summary>
    /// أُضيف أثناء العدّ لأنه وُجد على الرفّ ولم يكن في القائمة.
    ///
    /// <para>الحالة التي يسمّيها myWMS <c>ConfirmUnexpectedUnitLoad</c>،
    /// وتقع عندنا في الجرد الموزَّع: <c>NotCountedSince</c> يستبعد ما عُدَّ
    /// حديثاً، فيقف العامل أمام صنف موجود لا يجده في قائمته. بلا زرٍّ يقول
    /// «وجدتُ ما ليس في القائمة» يخرج من النظام ويكتب على ورقة — وتنتهي
    /// صلاحية النظام كلّه.</para>
    /// </summary>
    public bool AddedDuringCount { get; set; }
}

/// <summary>
/// تسلسل status: draft (مسودة، بلا أثر) ← ordered (أُرسل للمورّد، بلا أثر
/// مخزوني بعد) ← received (وصلت البضاعة فعلياً — هنا فقط تُضاف الكمية
/// لـ stock_levels) — أو cancelled قبل الاستلام فقط. نفس فلسفة
/// StockTransfer.Status تماماً.
/// </summary>
public class PurchaseOrder
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid BranchId { get; set; }
    public Guid? SupplierId { get; set; }
    public string Status { get; set; } = "draft"; // draft | ordered | received | cancelled
    public decimal TotalAmount { get; set; }

    /// <summary>
    /// أمرٌ ولّده اقتراح إعادة الطلب لا يدُ مستخدم.
    ///
    /// <para>يجعل الأتمتة **قابلة للمراجعة**: مدير يرى عشرين أمراً لا يعرف
    /// أيّها قراره وأيّها قرار معادلة، فلا يستطيع الحكم على المعادلة أصلاً.
    /// وصندوقٌ أسود لا يُراجَع يُوقَف بعد أول خطأ.</para>
    /// </summary>
    public bool IsAuto { get; set; }
    public Guid? CreatedBy { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public List<PurchaseOrderItem> Items { get; set; } = new();
}

public class PurchaseOrderItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid PurchaseOrderId { get; set; }
    public Guid ProductId { get; set; }
    public decimal Quantity { get; set; }
    public decimal UnitCost { get; set; }
    // اختياري — NULL يعني الإبقاء على سعر بيع الصنف الحالي عند الاستلام.
    public decimal? SalePrice { get; set; }

    /// <summary>
    /// المستلَم فعلياً من [Quantity]. أقلّ منها يعني توريداً ناقصاً والأمر
    /// يبقى مفتوحاً حتى يكتمل.
    /// </summary>
    public decimal ReceivedQuantity { get; set; }

    /// <summary>ما لم يصل بعد — الأساس الذي يُبنى عليه أي استلام تالٍ.</summary>
    public decimal RemainingQuantity => Quantity - ReceivedQuantity;
}

/// <summary>
/// لا يحمل WalletBalance عمداً — الرصيد مجموع دفتر
/// [CustomerWalletTransaction] ولا يُخزَّن كعمود قابل للكتابة إطلاقاً
/// (راجع libyan_models/ACCOUNTING_RULES.md §3: عمود رصيد قابل للكتابة هو
/// أسرع طريق إلى بطاقة رصيدها لا يطابق محاسبتها).
/// </summary>
/// <summary>
/// مستند استلام: شحنة واحدة وصلت فعلياً من أمر شراء.
///
/// <para><b>لماذا مستند لا رقم تراكمي:</b> كان الاستلام يزيد
/// <see cref="PurchaseOrderItem.ReceivedQuantity"/> فقط. فثلاث شحنات جزئية
/// تُبتلع في رقم واحد، ويضيع معها ثلاثة أشياء لا تُستعاد: **متى** وصلت كل
/// شحنة (فلا تُقاس مهلة التوريد الحقيقية ويبقى <c>LeadTimeDays</c> رقماً
/// مُدخَلاً بالظنّ)، و**رقم إشعار المورّد** وهو المرجع الوحيد عند الخلاف،
/// و**أي شحنة تخصّ أي فاتورة مورّد** حين تُبنى المطابقة لاحقاً.</para>
///
/// <para>وهو **شرط مسبق لدفتر حركة المخزون** (راجع ARCHITECTURE.md §2.15):
/// سطر الإدخال في الدفتر يجب أن يشير إلى مستند وصول حقيقي، لا إلى أمر شراء
/// قد يصل على دفعات.</para>
/// </summary>
public class PurchaseReceipt
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid BranchId { get; set; }
    public Guid PurchaseOrderId { get; set; }

    /// <summary>
    /// رقم إشعار التسليم كما كتبه المورّد على ورقته. اختياري لا إلزامي:
    /// كثير من الموردين المحليين يسلّمون بلا إشعار مرقَّم، وإلزامه كان
    /// يدفع المستخدم إلى كتابة أي شيء ليمرّ — وحقلٌ مملوء بالقمامة أسوأ من
    /// حقل فارغ، لأن الأول يُصدَّق.
    /// </summary>
    public string? SupplierNoteNumber { get; set; }

    /// <summary>
    /// تاريخ وصول البضاعة فعلاً — منفصل عن <see cref="CreatedAt"/> عمداً:
    /// الشحنة تصل الخميس ويُدخلها أمين المخزن الأحد. قياس مهلة التوريد
    /// بتاريخ الإدخال يضيف إليها يومين وهميين في كل مرّة.
    /// </summary>
    public DateTime ReceivedOn { get; set; }

    public Guid? ReceivedBy { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public string? Notes { get; set; }

    public List<PurchaseReceiptItem> Items { get; set; } = new();
}

public class PurchaseReceiptItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid PurchaseReceiptId { get; set; }

    /// <summary>
    /// سطر أمر الشراء المقابل. يُحفَظ إلى جانب ProductId لا بدلاً منه:
    /// الأمر قد يحمل سطرين لنفس الصنف بتكلفتين، والربط بالصنف وحده يجعل
    /// نسبة الشحنة إلى سطرها تخميناً.
    /// </summary>
    public Guid PurchaseOrderItemId { get; set; }

    public Guid ProductId { get; set; }
    public decimal Quantity { get; set; }
    public string BatchNumber { get; set; } = "";
    public DateTime? ExpiryDate { get; set; }

    /// <summary>
    /// لقطة التكلفة وقت الوصول — **محمَّلةً** بنصيب الوحدة من مصاريف
    /// الشحنة (راجع [KineticEnterprise.Api.Data.LandedCost]). وهي التي تدخل
    /// الدفعة وتُحسب منها تكلفة البضاعة المباعة.
    /// </summary>
    public decimal UnitCost { get; set; }

    /// <summary>
    /// سعر المورّد وحده كما وصل — بلا نصيب المصاريف.
    ///
    /// <para><b>ولماذا يُحفظ الاثنان:</b> مطابقة فاتورة المورّد تقارن بما
    /// طالب **هو** به، والفرق بينه وبين المحمَّل هو ما رُسمل من شحنٍ يطالب
    /// به غيره. وبعمودٍ واحد يستحيل التمييز بعد الحفظ: أهذا سعرٌ ارتفع أم
    /// شحنٌ أُضيف؟</para>
    ///
    /// <para>وصفرٌ في مستندات ما قبل هذه الميزة يعني «لا فرق» — فالمحمَّل
    /// عندها هو سعر المورّد نفسه.</para>
    /// </summary>
    public decimal SupplierUnitCost { get; set; }
}

public class Customer
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid? BranchId { get; set; }
    public string FullName { get; set; } = "";
    public string? Phone { get; set; }
    public string? Email { get; set; }
    public string? Notes { get; set; }
    public string? CardBarcode { get; set; }
    public decimal CreditLimit { get; set; }

    /// <summary>
    /// مهلة سداد الآجل بالأيام. صفر = مستحقّ يوم البيع.
    ///
    /// <para><b>لماذا على العميل لا على المنظمة:</b> تاجر الجملة يمنح
    /// مستشفى ثلاثين يوماً وبقّالاً سبعة. ومهلة واحدة للجميع تعني إمّا
    /// مطاردة من له مهلة، أو تركَ من لا مهلة له.</para>
    ///
    /// <para>منه يُشتقّ <see cref="Invoice.DueDate"/> لحظة البيع، ولقطةً
    /// لا مرجعاً: تغيير المهلة لاحقاً لا يحرّك استحقاق فواتير مضت.</para>
    /// </summary>
    public int CreditDays { get; set; }

    public int LoyaltyPoints { get; set; }
    public bool IsDeleted { get; set; }
    // الرقم السري مُجزَّأ بـ BCrypt كأي كلمة مرور، ورمز البطاقة نفسه يعيش
    // في customer_card_index وحده (راجع تعليقه).
    //
    // القفل واحد لكل مداخل الرقم السري (بوابة العميل + نقطة البيع) لا لكل
    // مدخل على حدة — راجع [CustomerPinGate] لسبب كون ذلك شرطاً أمنياً.
    public string? PinHash { get; set; }
    public DateTime? PinLockedUntil { get; set; }

    /// <summary>
    /// نمط التحقّق لهذا الحساب — راجع [CardModes]. NULL = افتراضي المنظمة.
    ///
    /// <para>يختاره **صاحب الحساب** لا الكاشير: ماله هو. والتشديد حقٌّ بلا
    /// إذن، أمّا التخفيف فلا يقع إلا بحضوره.</para>
    /// </summary>
    public string? CardMode { get; set; }

    /// <summary>
    /// سقف يومي أشدّ يختاره الزبون لنفسه. صفر = سقف المنظمة.
    ///
    /// <para>يُقبل الأقلّ فقط: سقفٌ أعلى من سقف المنظمة تجاوزٌ لحدّ وضعه
    /// صاحب المحل لمخاطرته هو.</para>
    /// </summary>
    public decimal DailyCap { get; set; }

    // ---- نموذج الحساب ----
    // راجع [AccountModels] لسبب الفصل بين النموذجين.
    public string AccountModel { get; set; } = AccountModels.Prepaid;

    /// <summary>الجهة الممولة — للاستحقاق الممنوح وحده.</summary>
    public Guid? SponsorId { get; set; }

    /// <summary>سقف ما يُمنَح خلال الفترة الواحدة. صفر = بلا سقف.</summary>
    public decimal EntitlementCeiling { get; set; }

    /// <summary>فئة العميل — منها يُؤخذ مبلغ المرتَّب. NULL = بلا فئة.</summary>
    public Guid? CategoryId { get; set; }

    /// <summary>
    /// صورة صاحب البطاقة — مسارُ مرفقٍ لا الصورة نفسها.
    ///
    /// <para><b>لماذا تُطبع على البطاقة:</b> بطاقةٌ بلا رقم سرّي يحميها شيءٌ
    /// واحد — أن يعرف الكاشير أن حاملها صاحبها. وبطاقةٌ بلا صورة في نمط
    /// «بطاقة فقط» يستعملها من وجدها في الشارع.</para>
    ///
    /// <para>ومسارٌ لا بايتات: صورةٌ في عمود تُحمَّل مع كل قراءة عميل، وقائمةٌ
    /// بألف منتسب كانت ستنقل عشرات الميغابايتات في كل فتح شاشة.</para>
    /// </summary>
    public string? PhotoUrl { get; set; }

    /// <summary>
    /// مبلغٌ يخصّ هذا العميل وحده، يَجُبّ مبلغ فئته. NULL = اتبع الفئة.
    ///
    /// <para><b>ولماذا NULL لا صفر:</b> الصفر قرارٌ صريح — «هذا العميل
    /// موقوف المرتَّب هذه الدورة». وجعلُه يعني «اتبع الفئة» يُلغي القدرة على
    /// إيقاف مرتَّب شخصٍ بعينه، وهي حاجةٌ حقيقية.</para>
    /// </summary>
    public decimal? EntitlementOverride { get; set; }

    /// <summary>
    /// نهاية فترة الاستحقاق الحالية. ما تبقّى بعدها يسقط بحركة إسقاط صريحة
    /// (راجع [EntitlementSweeper]) — ولا يُطبَّق هذا على الرصيد المدفوع مسبقاً أبداً.
    /// </summary>
    public DateOnly? EntitlementExpiresOn { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// نموذجا حساب العميل — مفصولان لأن حكمهما القانوني مختلف لا لأن حقولهما مختلفة.
///
/// <para><b>prepaid</b> — رصيد دفعه العميل من ماله. هو دَين على المنشأة له،
/// ولا يسقط بمرور الوقت: إسقاط مال دفعه صاحبه مصادرة له. لا سقف ولا انتهاء.</para>
///
/// <para><b>entitlement</b> — استحقاق منحته جهة ثالثة (شركة لموظفيها، جمعية،
/// مدرسة) بسقف وفترة. المال ليس مال المستفيد، وغير المستخدَم يسقط بانتهاء
/// الفترة، والمنشأة تحاسب الجهة الممولة لا المستفيد.</para>
///
/// الخلط بينهما في عمود واحد كان سيؤدي يوماً ما إلى إسقاط رصيد عميل حقيقي
/// دفعه من جيبه — وتلك مشكلة مع عميل، لا خطأ برمجي يُصلَح بتحديث.
/// </summary>
public static class AccountModels
{
    public const string Prepaid = "prepaid";
    public const string Entitlement = "entitlement";

    public static bool IsValid(string? value) => value is Prepaid or Entitlement;
}

/// <summary>
/// جهة تموّل أرصدة مجموعة من العملاء (شركة، جمعية، مدرسة).
///
/// لا يحمل branch_id — الجهة تتعامل مع المنظمة ككل، بنفس مبرر [Supplier].
/// </summary>
/// <summary>
/// فئة عملاء — اسمٌ ومبلغُ مرتَّبٍ دوري.
///
/// <para><b>الفجوة التي تسدّها:</b> سقف الاستحقاق كان
/// <see cref="Customer.EntitlementCeiling"/> — رقماً **على كل عميل على
/// حدة**. وجهةٌ تصرف على ألف منتسب مقسَّمين إلى ثلاث فئات كانت ترفع مرتب
/// الفئة بتعديل ألف صفّ يدوياً؛ وأوّل صفٍّ يُنسى يُنتج منتسباً يقبض أقلّ
/// من زملائه ولا يعرف أحدٌ لماذا.</para>
///
/// <para>والفئة **مبلغٌ واسم فقط** — لا سقفٌ يومي ولا نمط بطاقة ولا مدّة.
/// تلك تبقى على العميل حيث كانت: خلطُها هنا يجعل تغيير المرتب يغيّر معه
/// إعداداتٍ لم يقصد أحدٌ تغييرها.</para>
/// </summary>
public class CustomerCategory
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }

    /// <summary>اسمها كما تسمّيها الإدارة — «أ» أو «موظفون» أو غيرهما.</summary>
    public string Name { get; set; } = "";

    /// <summary>المرتَّب الذي يُودَع لكل عميل فيها كل دورة صرف.</summary>
    public decimal PeriodAmount { get; set; }

    /// <summary>
    /// أيسقط ما لم يُصرَف من مرتَّب الدورة عند صرف الدورة التالية؟
    ///
    /// <para><b>قرارُ إدارةٍ لا قاعدةٌ ثابتة:</b> جهةٌ تريد الرصيد «استعمله
    /// أو تفقده» فلا يتراكم عندها التزام، وأخرى تريده يتراكم لمن لم يصرف.
    /// وفرضُ أحدهما على الاثنتين يجعل النظام غير صالح لإحداهما.</para>
    ///
    /// <para>وتنفيذُه لا يحتاج شيئاً جديداً: <see cref="EntitlementSweeper"/>
    /// لا يمسّ إلا من له <c>EntitlementExpiresOn</c> غير فارغ. فالرصيد الذي
    /// لا يسقط يُودَع بتاريخ انتهاءٍ فارغ — فلا تراه المكنسة أصلاً.</para>
    /// </summary>
    public bool UnspentExpires { get; set; } = true;

    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public class Sponsor
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public string Name { get; set; } = "";
    public string? Phone { get; set; }
    public string? Notes { get; set; }
    public bool IsDeleted { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// فهرس بطاقات العملاء — معفى من RLS عمداً وبنفس مبرر app_users بالضبط:
/// دخول العميل للبوابة يحدث *قبل* وجود أي SESSION_CONTEXT، فأي FILTER
/// PREDICATE هنا كان سيمنع كل عمليات الدخول. رمز البطاقة فريد عالمياً وهو
/// ما يحدّد منظمة العميل قبل ضبط السياق.
///
/// رمز البطاقة يعيش هنا وحده (لا نسخة منه على customers) حتى لا يوجد
/// مصدرا حقيقة يمكن أن يتفارقا.
/// </summary>
public class CustomerCardIndex
{
    public string CardCode { get; set; } = "";
    public Guid CustomerId { get; set; }
    public Guid OrganizationId { get; set; }
    public DateTime IssuedAt { get; set; } = DateTime.UtcNow;
    public string State { get; set; } = CardStates.Active;
    public DateOnly? ExpiryDate { get; set; }
    public Guid? IssuedBy { get; set; }
    public string? BlockedReason { get; set; }
    /// <summary>
    /// الاسم المطبوع على البطاقة — قد يختلف عن اسم العميل المسجَّل (بطاقة
    /// شركة يحملها موظف، أو اسم مختصر يناسب مساحة البطاقة). فارغ = يُطبع
    /// اسم العميل نفسه.
    /// </summary>
    public string? HolderName { get; set; }

    /// <summary>
    /// بطاقة منتهية الصلاحية تُعامَل كمحظورة فعلياً حتى لو بقيت حالتها
    /// 'active' في قاعدة البيانات — لا وظيفة مجدوَلة تُغيّر الحالة تلقائياً،
    /// فالتحقق يتم وقت الاستخدام لا بانتظار مهمة دورية قد لا تعمل.
    /// </summary>
    public bool IsUsable(DateOnly today) =>
        State == CardStates.Active && (ExpiryDate is null || ExpiryDate >= today);
}

public static class CardStates
{
    public const string Active = "active";
    public const string Blocked = "blocked";
    public const string Expired = "expired";
}

/// <summary>
/// سجل محاولات الرقم السري — أساس القفل بعد تكرار الفشل، ودليل تدقيق على
/// أي محاولة اختراق لبطاقة عميل.
/// </summary>
public class CustomerPinAttempt
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid CustomerId { get; set; }
    public bool Success { get; set; }
    public string? IpAddress { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// دفتر حركات المحفظة — يُضاف إليه فقط، ولا يُعدَّل ولا يُحذف منه صف أبداً
/// (نفس حرمة القيد المحاسبي؛ التصحيح بحركة معاكسة لا بتعديل الماضي).
/// amount موجب دائماً والإشارة تُشتق من Kind عبر [WalletKinds.SignOf] وحدها.
/// </summary>
/// <summary>
/// سلفة على منتسب — مالٌ يُقرَض ويُستردّ من مرتَّبه.
///
/// <para><b>ولماذا كيانٌ لا حركةُ محفظةٍ وحدها:</b> الحركة تقول كم دخل
/// البطاقة؛ والسلفة تحتاج ما لا تحمله الحركة: كم القسط، ومتى بدأت، وكم
/// بقي منها. والمتبقّي <b>محسوبٌ لا مخزَّن</b> — مجموعُ أقساطها مطروحاً من
/// أصلها، بنفس مبدأ رصيد المحفظة وحساب المورّد.</para>
///
/// <para><b>والاسترداد تلقائي</b> عند صرف مرتَّب الدورة: يُخصم القسط، وما
/// لا يتّسع له المرتَّب يُرحَّل. فلا يهبط رصيد المنتسب تحت الصفر بسبب قسط،
/// ولا يبقى دَينٌ لا يُسدَّد.</para>
/// </summary>
public class CustomerAdvance
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid CustomerId { get; set; }

    /// <summary>أصل السلفة كما صُرفت.</summary>
    public decimal Amount { get; set; }

    /// <summary>
    /// ما يُخصم من كل مرتَّب. صفر = كامل المتبقّي دفعةً واحدة.
    ///
    /// <para>وتحديدُه للإدارة لا حدَّ أدنى له — منتسبٌ يستلف مئتين ويسدّد
    /// عشرين شهرياً أمرٌ تقرّره هي لا النظام.</para>
    /// </summary>
    public decimal InstallmentAmount { get; set; }

    public DateOnly IssuedOn { get; set; }
    public string? Note { get; set; }

    /// <summary>
    /// مُلغاة — لا محذوفة. أقساطها المخصومة حركاتٌ في الدفتر تشير إليها،
    /// وحذفُها يترك خصماً بلا سببٍ ظاهر في كشف المنتسب.
    /// </summary>
    public bool IsCancelled { get; set; }

    public Guid? CreatedBy { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public class CustomerWalletTransaction
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid CustomerId { get; set; }
    public Guid? InvoiceId { get; set; }

    /// <summary>
    /// السلفة التي تخصّها هذه الحركة — صرفاً أو سداداً.
    ///
    /// <para>بدونه يستحيل معرفة كم بقي من سلفةٍ بعينها حين يكون على المنتسب
    /// أكثر من واحدة.</para>
    /// </summary>
    public Guid? AdvanceId { get; set; }

    public string Kind { get; set; } = "";
    public decimal Amount { get; set; }
    public string? Note { get; set; }
    public Guid? CreatedBy { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// المصدر الوحيد لإشارة كل نوع حركة — أي حساب للرصيد في النظام يمرّ من هنا،
/// فلا يمكن أن يحسب موضعان الرصيد بإشارتين مختلفتين.
/// </summary>
/// <summary>
/// أنماط التحقّق عند الصرف من بطاقة المحفظة.
///
/// <para><b>المشكلة التي تحلّها:</b> الرقم السري كان **إلزامياً دائماً**
/// بلا بديل. والرقم وسيلةُ إثبات يعرفها طرفان: الزبون يُدخله على جهاز
/// الكاشير، فيراه أو يلتقطه أو يحفظه — ثم يسحب بعد انصراف الزبون بالبحث
/// عن اسمه. إلزامٌ بلا بديل هو ما يخلق الثغرة، لا ضعف الرقم.</para>
///
/// <para><b>وقاعدة الحوكمة:</b> التشديد على النفس حقٌّ لا يحتاج إذناً،
/// والتخفيف لا يقع إلا برضا صاحب المال. **والكاشير لا يغيّر النمط
/// إطلاقاً** — من يستطيع خفض الحماية لحظة الصرف لا تحميه حمايةٌ.</para>
/// </summary>
public static class CardModes
{
    /// <summary>
    /// مسح البطاقة وحده، **بسقف يومي**.
    ///
    /// <para>لمن لا يملك هاتفاً ولا يحفظ رقماً. والرقم السري هنا **يختفي
    /// تماماً** فلا شيء يُحفَظ أصلاً — الثغرة تُغلق بحذف الوسيلة لا
    /// بحراستها، وهذا أقوى من أي ضبط.</para>
    /// </summary>
    public const string Card = "card";

    /// <summary>بطاقة + رقم سرّي — السلوك القائم، ويبقى خياراً.</summary>
    public const string Pin = "pin";

    /// <summary>
    /// بطاقة + تأكيد من هاتف الزبون.
    ///
    /// <para><b>معرَّف ولا يُعرَض بعد:</b> لا قناة إرسال في النظام، وإتاحة
    /// نمطٍ يفشل صامتاً أسوأ من غيابه. يُضاف إلى [Selectable] يوم تُبنى
    /// القناة.</para>
    /// </summary>
    public const string Phone = "phone";

    /// <summary>ما يجوز اختياره فعلياً اليوم.</summary>
    public static readonly string[] Selectable = { Card, Pin };

    public static bool IsSelectable(string? mode) =>
        mode is not null && Selectable.Contains(mode);

    /// <summary>
    /// هل الأول أشدّ من الثاني — أساس قاعدة «التشديد بلا إذن».
    /// </summary>
    public static bool IsStricter(string mode, string than) =>
        Rank(mode) > Rank(than);

    private static int Rank(string mode) => mode switch
    {
        Card => 0,
        Phone => 1,
        Pin => 2,
        _ => 0,
    };
}

public static class WalletKinds
{
    public const string TopUp = "topup";
    public const string Spend = "spend";
    public const string InvoiceRefund = "invoice_refund";
    public const string AdjustmentIn = "adjustment_in";
    public const string AdjustmentOut = "adjustment_out";

    /// <summary>منحة استحقاق من جهة ممولة — تقابل TopUp في نموذج الدفع المسبق.</summary>
    public const string EntitlementGrant = "entitlement_grant";

    /// <summary>
    /// إسقاط ما تبقّى من استحقاق بانتهاء فترته. حركة خصم *جديدة* لا حذف
    /// للمنحة الأصلية — حرمة القيد: التصحيح بعكسه لا بمحو الماضي.
    /// </summary>
    public const string EntitlementExpiry = "entitlement_expiry";

    /// <summary>
    /// سلفة صُرفت على البطاقة — مالٌ يُقرَض لا يُعطى.
    ///
    /// <para><b>ولماذا نوعٌ مستقلّ عن <see cref="TopUp"/>:</b> السلفة ترفع
    /// الرصيد كالشحن، لكنها **تبقى ديناً على المنتسب** حتى تُستردّ. وخلطُها
    /// بالشحن يجعل الجهة لا تعرف كم على منتسبيها من ديون — وهو أوّل ما
    /// تسأل عنه.</para>
    /// </summary>
    public const string Advance = "advance";

    /// <summary>قسطٌ من سلفة يُخصم — يُقابل [Advance].</summary>
    public const string AdvanceRepayment = "advance_repayment";

    public static int SignOf(string kind) => kind switch
    {
        TopUp or InvoiceRefund or AdjustmentIn or EntitlementGrant or Advance => 1,
        Spend or AdjustmentOut or EntitlementExpiry or AdvanceRepayment => -1,
        _ => throw new ArgumentOutOfRangeException(nameof(kind), kind, "نوع حركة محفظة غير معروف"),
    };

    // EF لا يترجم SignOf نفسها إلى SQL، فيُحتاج تقسيمٌ صريح للأنواع عند
    // الجمع في قاعدة البيانات. وجودهما هنا لا مكرَّرين في كل استعلام هو
    // ما يمنع أن يُحسَب الرصيد بقاعدتين مختلفتين في شاشتين مختلفتين —
    // وهو ما كان يحدث فعلاً قبل توحيدهما. تُترجَم Contains إلى IN (...).
    public static readonly string[] InKinds = { TopUp, InvoiceRefund, AdjustmentIn, EntitlementGrant };
    public static readonly string[] OutKinds = { Spend, AdjustmentOut, EntitlementExpiry };
}

public class Invoice
{
    /// <summary>
    /// مفتاح العملية الأصلي كما ولّده جهاز نقطة البيع. فريد حين يوجد.
    ///
    /// يبقى محفوظاً بعد المزامنة لا يُمحى: هو أثر التدقيق الذي يربط الفاتورة
    /// بعملية البيع التي وقعت فعلياً على الجهاز أثناء الانقطاع، ويسمح بكشف
    /// أي ازدواج لاحقاً.
    /// </summary>
    public string? ClientRequestId { get; set; }

    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid BranchId { get; set; }
    public Guid? ShiftId { get; set; }
    public Guid? CustomerId { get; set; }
    public string InvoiceNumber { get; set; } = "";
    public string InvoiceType { get; set; } = "sale"; // sale | return
    public Guid? OriginalInvoiceId { get; set; }
    public decimal Subtotal { get; set; }
    public decimal TaxAmount { get; set; }
    public decimal DiscountAmount { get; set; }
    public decimal TotalAmount { get; set; }

    /// <summary>
    /// المدفوع فعلاً. NULL أو مساوٍ للإجمالي = مدفوعة بالكامل. وأقلّ منه
    /// يعني دفعاً جزئياً، والفرق دَينٌ مقيَّد على محفظة العميل.
    /// </summary>
    public decimal? PaidAmount { get; set; }

    /// <summary>النقد الذي سلّمه الزبون — للتدقيق وتسوية الدرج.</summary>
    public decimal? TenderedAmount { get; set; }

    /// <summary>الباقي المُعاد إليه.</summary>
    public decimal? ChangeDue { get; set; }

    /// <summary>
    /// تاريخ استحقاق الجزء الآجل. NULL في البيع المدفوع كاملاً.
    ///
    /// <para>بدونه كان الدَّين قائماً **بلا موعد**: لا يُقال عنه «متأخّر»
    /// فلا تقرير أعمار ولا تذكير ولا أولوية تحصيل. وهو أقرب بنود الخطة إلى
    /// ميزة تُباع بذاتها لتاجر الجملة، لأنه يمسّ نقده لا تنظيمه.</para>
    /// </summary>
    public DateTime? DueDate { get; set; }

    public string Status { get; set; } = "completed";
    public Guid? CreatedBy { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public List<InvoiceItem> Items { get; set; } = new();
    public List<InvoicePayment> Payments { get; set; } = new();
}

/// <summary>
/// نشرة الدواء — معرفة دوائية عامة لا بيانات منظمة.
///
/// <para><b>على مستوى المنصّة لا المنظمة</b> (بلا organization_id وبلا
/// Security Policy، كجدول platform_settings): «باراسيتامول 500 مجم» له
/// نفس موانع الاستعمال في كل صيدلية. ربطه بالمنظمة كان يعني أن كل عميل
/// جديد يبدأ بنشرات فارغة ويُدخلها من الصفر — وهو ما يجعل الميزة تُهمَل
/// عملياً. والسعر والمخزون يبقيان على products وstock_levels حيث ينتميان،
/// فلا تسرّب بيانات بين المنظمات عبر هذا الجدول.</para>
///
/// <para>يُقرأ فقط لمن يملك وحدة <c>pharmacy</c> — راجع [Editions].</para>
/// </summary>
public class MedicineReference
{
    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>الاسم التجاري كما يُعرَف في السوق.</summary>
    public string Name { get; set; } = "";

    /// <summary>المادة الفعّالة — أساس كشف التكرار والبدائل.</summary>
    public string ActiveIngredient { get; set; } = "";

    /// <summary>التركيز كنصّ (500 مجم، 250 مجم/5 مل) — لا رقم: الوحدة جزء منه.</summary>
    public string? Strength { get; set; }

    /// <summary>الشكل الصيدلي: أقراص، كبسولات، شراب، حقن، مرهم…</summary>
    public string? Form { get; set; }

    public string? Indications { get; set; }
    public string? Contraindications { get; set; }
    public string? Cautions { get; set; }
    public string? SideEffects { get; set; }

    /// <summary>
    /// دواء يُصرَف بوصفة. الحقل هنا لا على products: كونه مقيَّداً خاصيةُ
    /// الدواء نفسه لا خاصيةُ صنف في متجر بعينه.
    /// </summary>
    public bool RequiresPrescription { get; set; }

    public bool IsDeleted { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// قيد في دفتر الوصفات — صرف دواء مقيَّد بوصفة.
///
/// <para><b>بيانات منظمة لا معرفة عامة</b> (بخلاف [MedicineReference]):
/// وصفة مريض بعينه صرفتها صيدلية بعينها، فتحمل organization_id وbranch_id
/// وتُطبَّق عليها سياسة العزل كبقية الجداول التشغيلية.</para>
///
/// <para><b>مرتبطة بالفاتورة:</b> الوصفة تُقدَّم لحظة الصرف، وربطها بما صُرِف
/// فعلاً هو ما يجعل الدفتر قابلاً للمراجعة — من صرف، ماذا، لمن، بأمر أي
/// طبيب. ودونه يصبح سجلاً موازياً لا أحد يوثّق أنه يطابق المبيعات.</para>
/// </summary>
public class Prescription
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid BranchId { get; set; }
    public Guid? InvoiceId { get; set; }

    /// <summary>رقم الوصفة كما كُتب عليها — اختياري: وصفات كثيرة بلا ترقيم.</summary>
    public string? PrescriptionNumber { get; set; }

    public string DoctorName { get; set; } = "";
    public string? DoctorLicense { get; set; }
    public string PatientName { get; set; } = "";
    public string? PatientPhone { get; set; }
    public DateOnly? IssuedOn { get; set; }
    public string? Notes { get; set; }
    public Guid? CreatedBy { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public class InvoiceItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid InvoiceId { get; set; }
    public Guid ProductId { get; set; }

    /// <summary>
    /// الكمية كما بيعت فعلاً (3 حبات لا 0.3 شريط)، والسعر سعرَها.
    ///
    /// حفظها محوَّلة إلى الوحدة الأساسية كان يجعل الإيصال يعرض «0.3 شريط
    /// بسعر 10» — وهو ما لم يحدث. الخصم من المخزون وحده هو ما يُحوَّل.
    /// </summary>
    public decimal Quantity { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal LineTotal { get; set; }

    /// <summary>هل بيع السطر بالوحدة الجزئية.</summary>
    public bool SoldAsSubUnit { get; set; }

    /// <summary>
    /// لقطة من Product.SubUnitsPerBase وقت البيع: حجم العلبة قد يتغيّر
    /// لاحقاً، والمرتجع يجب أن يعيد ما خرج فعلاً لا ما يقوله الكتالوج اليوم.
    /// </summary>
    public decimal SubUnitsPerBase { get; set; }

    /// <summary>
    /// من أي دفعات خرجت كمية هذا السطر. سطر واحد قد يمتدّ على أكثر من دفعة
    /// (طلب 15 حبة موجودة 10 في دفعة و5 في أخرى)، فلا يكفي عمود
    /// batch_number واحد على السطر — راجع InvoiceItemBatch.
    /// </summary>
    public List<InvoiceItemBatch> Batches { get; set; } = new();
}

/// <summary>
/// تخصيص كمية سطر الفاتورة على الدفعات التي خرجت منها فعلاً.
///
/// وجوده شرطٌ لصحّة المرتجع لا ترفٌ تحليلي: بدونه لا سبيل لمعرفة الدفعة
/// الأصلية، فكان الإرجاع يضيف الكمية إلى «دفعة عامة» بلا رقم — فينتفخ رصيد
/// وهمي بلا تاريخ صلاحية بينما تبقى الدفعة الحقيقية ناقصة. ومع تكرار
/// الإرجاعات ينحرف رصيد كل دفعة عن الواقع، ويسقط معه ترتيب FEFO نفسه لأنه
/// يقرأ من هذه الأرصدة.
///
/// السطر التجاري يبقى واحداً في invoice_items (الإيصال يعرض «15 حبة» لا
/// سطرين)، والتفصيل المخزوني هنا.
/// </summary>
public class InvoiceItemBatch
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid InvoiceItemId { get; set; }
    public string BatchNumber { get; set; } = "";
    public decimal Quantity { get; set; }
}

/// <summary>
/// دفع مقسّم — فاتورة واحدة قد يكون لها أكثر من صف دفع (راجع
/// DATABASE_TABLES_GUIDE.md §7.4). النسخة الحالية من InvoicesController
/// تُنشئ صف دفع واحداً فقط بطريقة الدفع الكاملة لكل فاتورة؛ دعم تقسيم
/// الدفع فعلياً على شاشة POS نفسها مرحلة لاحقة منفصلة.
/// </summary>
public class InvoicePayment
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid InvoiceId { get; set; }
    public string Method { get; set; } = "cash"; // cash | card | customer_wallet | credit
    public decimal Amount { get; set; }
}

/// <summary>
/// سلّم التذكير بالدين — ثلاث مراحل، كل واحدة أشدّ من سابقتها.
///
/// <para>الفواصل بالأيام **بعد** تاريخ الاستحقاق. الأولى يوم الاستحقاق
/// نفسه تذكيراً ودّياً، والثانية بعد أسبوع، والثالثة بعد ثلاثة أسابيع حين
/// يصبح التأخّر نمطاً لا سهواً.</para>
/// </summary>
public static class DebtReminderPolicy
{
    public static readonly int[] StageOffsetDays = { 0, 7, 21 };

    /// <summary>أعلى مرحلة استحقّت بعد هذا العدد من أيام التأخّر. صفر = لا شيء بعد.</summary>
    public static int StageFor(int daysOverdue)
    {
        var stage = 0;
        for (var i = 0; i < StageOffsetDays.Length; i++)
        {
            if (daysOverdue >= StageOffsetDays[i]) stage = i + 1;
        }
        return stage;
    }
}

/// <summary>
/// تذكير أُرسل فعلاً — لا تذكير مجدوَل.
///
/// <para><b>لماذا يُكتب عند الإرسال لا عند الاستحقاق:</b> الصفّ المُنشأ
/// آلياً عند حلول الموعد يعني جدولاً يمتلئ بصفوف لم يفعلها أحد، ويصبح
/// «أُرسل التذكير» كذبةً يقولها النظام عن نفسه. أما موعد الاستحقاق فيُحفَظ
/// هنا **لقطةً** (<see cref="DueOn"/>) لحظة الإرسال — فيبقى الفرق بين
/// المخطَّط والفعلي ظاهراً للتدقيق حتى لو تغيّرت السياسة لاحقاً.</para>
///
/// <para>وعلى العميل لا على الفاتورة: الدَّين رصيدٌ واحد على العميل (راجع
/// [WalletBalances])، والمطالبة تقع عليه لا على ورقة بعينها.</para>
/// </summary>
public class DebtReminder
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid CustomerId { get; set; }

    /// <summary>1 أو 2 أو 3 — راجع [DebtReminderPolicy].</summary>
    public int Stage { get; set; }

    /// <summary>تاريخ استحقاق هذه المرحلة كما كان محسوباً لحظة الإرسال.</summary>
    public DateTime DueOn { get; set; }

    public DateTime SentAt { get; set; } = DateTime.UtcNow;
    public Guid? SentBy { get; set; }

    /// <summary>مبلغ الدَّين وقت التذكير — يُظهر إن كان يتناقص أم يتراكم.</summary>
    public decimal AmountAtReminder { get; set; }

    public string? Note { get; set; }
}

public class NotificationItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid? BranchId { get; set; }
    public string Type { get; set; } = "";  // low_stock | expiry | count_variance | license | security
    public string Title { get; set; } = "";
    public string? Body { get; set; }
    public bool IsRead { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// "من فعل ماذا ومتى" لكل عملية حساسة (ARCHITECTURE.md §2.11) — راجع
/// DATABASE_TABLES_GUIDE.md §9.2. old_values/new_values بصيغة JSON حرة بدل
/// أعمدة منفصلة لكل جدول محتمل، لأن كل جدول في النظام له حقول مختلفة تماماً.
/// </summary>
/// <summary>
/// كتالوج ثابت مشترك بين كل المنظمات (لا organization_id) — نفس فكرة قاموس
/// عام، وليس بيانات تشغيلية. يُزرع مرة واحدة فقط عبر سكريبت SQL، لا يُدار
/// من أي شاشة (لا داعي لإضافة/حذف صلاحيات من الواجهة، فقط تفعيلها للأدوار).
/// </summary>
public class Permission
{
    public string Code { get; set; } = "";
    public string LabelAr { get; set; } = "";
    public string Module { get; set; } = "";
}

/// <summary>
/// هذا هو التطبيق الفعلي لمصفوفة الصلاحيات: أي دور (غير super_admin، الذي
/// يتجاوزها دائماً) يملك أي صلاحية *لهذه المنظمة تحديداً*. راجع
/// RequirePermissionAttribute.cs للتطبيق الفعلي وقت الطلب،
/// وPermissionsController.cs للتعديل من الواجهة.
/// </summary>
public class RolePermission
{
    public Guid OrganizationId { get; set; }
    public string Role { get; set; } = "";
    public string PermissionCode { get; set; } = "";
}

public class AuditLog
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid? UserId { get; set; }
    public string Action { get; set; } = "";
    public string EntityTable { get; set; } = "";
    public Guid? EntityId { get; set; }
    public string? OldValues { get; set; }
    public string? NewValues { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

// ═══════════════════════════════════════════════════════════════════════════
//  المحاسبة — دليل الحسابات والقيود
// ═══════════════════════════════════════════════════════════════════════════

/// <summary>
/// أقسام دليل الحسابات، على الدليل المحاسبي الموحّد المعروف محلياً.
///
/// <para>خمسة أقسام لا أربعة: الشجرة الظاهرة للمستخدم أربعة جذور
/// (الأصول · الالتزامات وحقوق الملكية · الاستخدامات · الإيرادات)، لكن
/// **حقوق الملكية تسلك سلوكاً مغايراً للالتزامات** عند الإقفال وفي قراءة
/// الميزانية. دمجُهما في نوع واحد يجعل التمييز مستحيلاً لاحقاً بلا ترحيل
/// مؤلم، وفصلُهما لا يكلّف اليوم شيئاً.</para>
/// </summary>
public static class AccountTypes
{
    public const string Asset = "asset";
    public const string Liability = "liability";
    public const string Equity = "equity";

    /// <summary>«الاستخدامات» في الدليل الموحّد — المصروفات والتكاليف.</summary>
    public const string Expense = "expense";
    public const string Revenue = "revenue";

    public static readonly string[] All = { Asset, Liability, Equity, Expense, Revenue };

    /// <summary>
    /// هل يزيد رصيد هذا النوع بالمدين.
    ///
    /// <para>الأصول والاستخدامات تزيد مديناً؛ والالتزامات وحقوق الملكية
    /// والإيرادات تزيد دائناً. هذه هي القاعدة التي يُشتقّ منها كل رصيد في
    /// النظام، فلا تُكرَّر في أي مكان آخر.</para>
    /// </summary>
    public static bool IsDebitNormal(string type) => type is Asset or Expense;
}

/// <summary>
/// حساب في دليل الحسابات.
///
/// <para><b>لماذا شجرة لا قائمة:</b> الميزان يُقرأ مجمَّعاً («إجمالي
/// الأصول») ومفصَّلاً («صندوق الفرع الثاني») معاً، والتجميع بالبادئة النصّية
/// للرمز يكسر أول ما يتجاوز الترقيم عشرة أبناء.</para>
/// </summary>
public class Account
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }

    /// <summary>رمز الحساب — <c>1</c>، <c>11</c>، <c>1101</c>… فريد داخل المنظمة.</summary>
    public string Code { get; set; } = "";
    public string Name { get; set; } = "";
    public Guid? ParentId { get; set; }

    /// <summary>راجع [AccountTypes]. يُورَّث من الجذر ولا يخالفه.</summary>
    public string Type { get; set; } = AccountTypes.Asset;

    /// <summary>
    /// هل يُرحَّل إليه مباشرةً.
    ///
    /// <para><b>الحسابات الوسيطة لا تُرحَّل إليها إطلاقاً:</b> قيدٌ على
    /// «الأصول» مباشرةً يجعل رصيد الأب لا يساوي مجموع أبنائه — فلا يعود
    /// للشجرة معنى، ويستحيل تفسير أي رقم بردّه إلى مفرداته. والحساب يصير
    /// غير قابل للترحيل بمجرّد أن يُولَد له ابن.</para>
    /// </summary>
    public bool IsPostable { get; set; } = true;

    /// <summary>
    /// حساب أنشأه النظام ويعتمد عليه الترحيل الآلي.
    ///
    /// <para>لا يُحذف ولا يُغيَّر نوعه ولا رمزه. حذفُ «المبيعات» يُوقف كل
    /// بيع في المحلّ — والمستخدم لا يعرف ذلك وهو يضغط «حذف».</para>
    /// </summary>
    public bool IsSystem { get; set; }

    /// <summary>
    /// قيم الحقول الإضافية لهذا الحساب — JSON بمفاتيح التعريفات.
    ///
    /// <para>راجع <see cref="Organization.AccountFieldDefsJson"/>. ومفتاحٌ
    /// لا تعريف له يُتجاهَل عند القراءة: حقلٌ حُذف من التعريفات لا يجوز أن
    /// يُسقط شاشةً بقيمةٍ يتيمة بقيت في صفّ.</para>
    /// </summary>
    public string CustomFieldsJson { get; set; } = "{}";

    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// مصادر القيود — من أين جاء القيد.
/// </summary>
public static class JournalSources
{
    public const string Invoice = "invoice";
    public const string InvoiceReturn = "invoice_return";
    public const string Expense = "expense";

    /// <summary>استلام بضاعة من مورّد.</summary>
    public const string PurchaseReceipt = "purchase_receipt";

    /// <summary>بضاعة أُعيدت إلى المورّد.</summary>
    public const string PurchaseReturn = "purchase_return";

    /// <summary>فاتورة مورّد — تُفرغ «وردت ولم تُفوتَر» إلى «الموردون».</summary>
    public const string SupplierInvoice = "supplier_invoice";

    public const string WalletTopUp = "wallet_top_up";
    public const string Payment = "payment";

    /// <summary>قيد كتبه محاسب بيده.</summary>
    public const string Manual = "manual";

    /// <summary>قيد عكسي يُصحّح قيداً سابقاً.</summary>
    public const string Reversal = "reversal";

    /// <summary>قيد إقفال مدّة مالية.</summary>
    public const string Closing = "closing";
}

/// <summary>
/// قيد يومية — رأس القيد.
///
/// <para><b>حرمة القيد:</b> لا يُعدَّل ولا يُحذف بعد إنشائه. التصحيح بقيد
/// عكسي يشير إليه، بنفس مبدأ دفتر المخزون ودفتر المحفظة في هذا النظام. دفترٌ
/// يُعدَّل ماضيه لا يصلح لإثبات شيء.</para>
/// </summary>
public class JournalEntry
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid? BranchId { get; set; }

    /// <summary>رقم متسلسل داخل المنظمة — ما يشير إليه المحاسب بلسانه.</summary>
    public long Number { get; set; }

    /// <summary>
    /// تاريخ القيد المحاسبي — قد يخالف <see cref="CreatedAt"/>.
    ///
    /// <para>فاتورة أمس تُسجَّل اليوم تنتمي محاسبياً إلى أمس. والخلط بينهما
    /// يجعل مبيعات شهرٍ تقع في الشهر التالي فتختلّ كل مقارنة.</para>
    /// </summary>
    public DateTime EntryDate { get; set; } = DateTime.UtcNow.Date;

    /// <summary>راجع [JournalSources].</summary>
    public string Source { get; set; } = JournalSources.Manual;

    /// <summary>معرّف المستند الأصل (فاتورة، مصروف…) — للتتبّع في الاتجاهين.</summary>
    public Guid? SourceId { get; set; }

    public string Description { get; set; } = "";

    /// <summary>القيد الذي يعكسه هذا القيد، إن كان تصحيحاً.</summary>
    public Guid? ReversesEntryId { get; set; }

    public Guid? CreatedBy { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public List<JournalEntryLine> Lines { get; set; } = new();
}

/// <summary>
/// سطر قيد — مدين أو دائن على حساب واحد.
///
/// <para><b>عمودان لا عمود واحد بإشارة:</b> «مدين ٥٠» و«دائن ٥٠» يُقرآن
/// كما يكتبهما المحاسب في دفتره، والمبلغ الموجب دائماً يمنع طبقةً كاملة من
/// أخطاء الإشارة في التجميع.</para>
/// </summary>
public class JournalEntryLine
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid JournalEntryId { get; set; }
    public Guid AccountId { get; set; }
    public decimal Debit { get; set; }
    public decimal Credit { get; set; }
    public string? Note { get; set; }
}

/// <summary>
/// ربط الأدوار المحاسبية بحسابات فعلية.
///
/// <para><b>لماذا جدول لا أعمدة على المنظمة:</b> الأدوار تنمو مع كل نوع
/// حركة جديد (ضريبة، خصم مسموح، فروق جرد…)، وكل واحد عموداً يعني ترحيل
/// مخطّط لكل إضافة.</para>
///
/// <para>ويُملأ كاملاً لحظة تفعيل الوحدة مع بذر الدليل. **ربطٌ ناقص يعني
/// بيعاً يفشل عند الكاشير**، فلا يُترك للمستخدم أن يكتشفه بنفسه.</para>
/// </summary>
public class AccountMapping
{
    public Guid OrganizationId { get; set; }

    /// <summary>راجع [AccountRoles].</summary>
    public string Role { get; set; } = "";
    public Guid AccountId { get; set; }
}

/// <summary>الأدوار المحاسبية التي يحتاجها الترحيل الآلي.</summary>
public static class AccountRoles
{
    public const string Cash = "cash";
    public const string Receivables = "receivables";

    /// <summary>الموردون — ما على المنشأة لهم مقابل بضاعة استُلمت.</summary>
    public const string Payables = "payables";

    /// <summary>مردودات المشتريات — بضاعة أُعيدت إلى المورّد.</summary>
    public const string PurchaseReturns = "purchase_returns";

    /// <summary>
    /// بضاعة وردت ولم تُفوتَر — التزامٌ وسيط بين الاستلام والفاتورة.
    ///
    /// <para><b>العطب الذي يسدّه:</b> كان الاستلام يُقيَّد مباشرةً على
    /// «الموردون»، أي أن الدَّين يُثبَت بورقة أمين المخزن قبل أن تصل ورقة
    /// المورّد. فإن اختلف السعران — وهو الغالب — لم يكن ثمّة موضعٌ يظهر فيه
    /// الفرق، فيُدفَع للمورّد ما طلبه ويبقى الميزان يقول رقماً آخر.</para>
    ///
    /// <para>فيصير الاستلام: من ح/ المخزون إلى ح/ <b>بضاعة وردت ولم
    /// تُفوتَر</b>. ثم تأتي الفاتورة فتُفرغه إلى «الموردون». ورصيدُه في أي
    /// لحظة هو **قيمة ما في المخزن ولم يُطالِب به المورّد بعد** — رقمٌ
    /// يُسأل عنه في كل جرد.</para>
    /// </summary>
    public const string GoodsReceivedNotInvoiced = "grni";

    /// <summary>
    /// فروق أسعار المشتريات — الفرق بين تكلفة أمر الشراء وما فوتره المورّد.
    ///
    /// <para>حسابٌ مستقلّ لا تسويةٌ صامتة على المخزون: الفرق المتراكم هنا
    /// يقول كم يُكلّف المورّد الذي يرفع أسعاره بعد الاتفاق — وهو رقمٌ
    /// تفاوضي. ودفنُه في تكلفة المخزون يجعله غير قابل للرؤية أصلاً.</para>
    /// </summary>
    public const string PurchasePriceVariance = "purchase_price_variance";

    /// <summary>
    /// الأرباح المحتجزة — وعاء نتيجة السنوات المُقفَلة.
    ///
    /// <para>إليه تُرحَّل أرصدة الإيرادات والاستخدامات عند الإقفال، فتصفر
    /// وتبدأ السنة الجديدة من الصفر بينما تبقى النتيجة في حقوق الملكية.</para>
    /// </summary>
    public const string RetainedEarnings = "retained_earnings";
    public const string SalesRevenue = "sales_revenue";
    public const string SalesTax = "sales_tax";
    public const string Inventory = "inventory";
    public const string CostOfGoodsSold = "cost_of_goods_sold";

    /// <summary>أرصدة العملاء المشحونة — التزامٌ على المنشأة لا إيراد.</summary>
    public const string CustomerWallet = "customer_wallet";

    public const string SalesReturns = "sales_returns";
    public const string GeneralExpense = "general_expense";

    /// <summary>
    /// مصاريف الشحنة الواردة المستحقّة — شحنٌ وتخليصٌ وجماركُ رُسملت على
    /// المخزون ولم تصل فاتورتها بعد.
    ///
    /// <para><b>لماذا حسابٌ مستقلّ لا «بضاعة وردت ولم تُفوتَر»:</b> ذاك
    /// رصيدُ ما سيطالب به **المورّد**، ويُفرَّغ بفاتورته هو. ومصاريف الشحن
    /// يطالب بها الناقل أو المخلّص — جهةٌ أخرى وفاتورةٌ أخرى. وخلطُهما
    /// يجعل رصيد «وردت ولم تُفوتَر» لا يطابق كشف أي مورّد، فيبطل استعماله
    /// في المطابقة أصلاً.</para>
    /// </summary>
    public const string LandedCostAccrual = "landed_cost_accrual";

    /// <summary>ما لا يمكن للترحيل أن يعمل بدونه.</summary>
    public static readonly string[] Required =
    {
        Cash, Receivables, Payables, SalesRevenue, SalesTax, Inventory,
        CostOfGoodsSold, CustomerWallet, SalesReturns, PurchaseReturns, GeneralExpense,
        RetainedEarnings, GoodsReceivedNotInvoiced, PurchasePriceVariance,
        // وهو مطلوب وإن لم تستعمله كل منظمة: وجودُه في القائمة هو ما يجعل
        // [Ledger.EnsureChartAsync] يُصلح ربط الأدلّة المبذورة قبل إضافته —
        // وإلا فشل أوّل استلامٍ بمصاريف بـ«لا حساب مربوط بالدور».
        LandedCostAccrual,
    };
}

/// <summary>
/// مصروف — إيجار، رواتب، كهرباء، نقل…
///
/// <para><b>الجدول كان موجوداً في المخطّط منذ اليوم الأول ولا يقرؤه سطر
/// واحد:</b> لا كيان ولا وحدة تحكّم ولا شاشة. أي أن «المالية المبسّطة»
/// الموعودة في ARCHITECTURE.md §2.8 لم تُبنَ أصلاً — والتاجر الذي يدفع إيجاراً
/// من درج الكاشير لا يجد له مكاناً في النظام، فيُسجّله على ورقة أو لا يسجّله.
/// وحينها يقول تقرير الأرباح ربحاً ليس ربحاً.</para>
/// </summary>
public class Expense
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid BranchId { get; set; }

    /// <summary>وصف حرّ للبند — يبقى مفيداً حتى مع المحاسبة المفعّلة.</summary>
    public string Category { get; set; } = "";
    public decimal Amount { get; set; }
    public string? Note { get; set; }

    /// <summary>
    /// حساب المصروف حين تكون وحدة المحاسبة مفعّلة.
    ///
    /// <para>NULL يعني «مصروفات عمومية» — ودعُه فارغاً أفضل من إجبار من
    /// يسجّل مصروفاً على اختيار حساب لا يعرفه، فيختار أول ما تقع عليه عينه
    /// ويُفسد التبويب. الحساب الافتراضي يقول الحقيقة: «مصروف لم يُبوَّب».</para>
    /// </summary>
    public Guid? AccountId { get; set; }

    /// <summary>
    /// تاريخ الصرف الفعلي — منفصل عن <see cref="CreatedAt"/>.
    ///
    /// <para><b>النقص الذي يسدّه:</b> كان المصروف يُقيَّد بتاريخ إدخاله
    /// دائماً. ففاتورة كهرباء الأسبوع الماضي تُدخَل اليوم فتقع في أرقام
    /// اليوم — ويُقفَل شهرٌ ناقصاً مصروفاته، وتُحمَّل بها مدّةٌ لا تخصّها.
    /// </para>
    ///
    /// <para>وهو نفس ما فُصل في <c>PurchaseReceipt.ReceivedOn</c> و
    /// <c>SupplierPayment.PaidOn</c> — والمصروف كان الوحيد بلا تاريخ خاصّ.
    /// </para>
    /// </summary>
    public DateTime SpentOn { get; set; } = DateTime.UtcNow.Date;

    /// <summary>المصرف الذي دُفع منه — NULL يعني الصندوق.</summary>
    public Guid? BankAccountId { get; set; }

    public Guid? CreatedBy { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// سداد لمورّد — دفعةٌ تُنقص ما عليك له.
///
/// <para><b>الثقب الذي يسدّه:</b> حساب «الموردون» كان يتراكم بلا طرف مقابل:
/// كل استلام بضاعة يزيد الدَّين، ولا شيء يُنقصه. فالميزان يقول إنك مدينٌ
/// بكل ما اشتريتَه منذ أول يوم — ولو سدّدتَ كلّه نقداً.</para>
///
/// <para><b>ولا يُعدَّل ولا يُحذف:</b> حركة مالية وقعت. التصحيح بدفعة عكسية
/// لا بمحوها — نفس حرمة القيد في الدفاتر الأخرى.</para>
/// </summary>
public class SupplierPayment
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid BranchId { get; set; }
    public Guid SupplierId { get; set; }
    public decimal Amount { get; set; }

    /// <summary>نقداً أو حوالة — راجع [SupplierPaymentMethods].</summary>
    public string Method { get; set; } = SupplierPaymentMethods.Cash;

    /// <summary>
    /// المصرف الذي خرج منه المبلغ — NULL يعني الصندوق.
    ///
    /// <para>كانت الحوالة تُقيَّد على الصندوق كالنقد، فتظهر النقدية الدفترية
    /// أعلى ممّا في الدرج بمقدارها. راجع [BankAccount].</para>
    /// </summary>
    public Guid? BankAccountId { get; set; }

    /// <summary>رقم الإيصال أو الحوالة كما كتبه المورّد.</summary>
    public string? Reference { get; set; }
    public string? Note { get; set; }

    /// <summary>
    /// تاريخ السداد الفعلي — منفصل عن <see cref="CreatedAt"/> عمداً:
    /// الحوالة تُرسَل الخميس ويُدخلها المحاسب الأحد، وتأريخها بالإدخال يضع
    /// سداد شهرٍ في الشهر التالي.
    /// </summary>
    public DateTime PaidOn { get; set; } = DateTime.UtcNow.Date;

    public Guid? CreatedBy { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public static class SupplierPaymentMethods
{
    public const string Cash = "cash";

    /// <summary>
    /// حوالة مصرفية.
    ///
    /// <para>تُقيَّد على «الصندوق» اليوم كالنقد: لا حسابات بنكية مربوطة في
    /// النظام بعد. **نقصٌ معلوم لا خطأ** — المبلغ صحيح، وينقصه أن يُنسب إلى
    /// المصرف حين يُبنى. ويبقى مسجَّلاً هنا فيُعرَف لاحقاً أيّها كان حوالة.
    /// </para>
    /// </summary>
    public const string Bank = "bank";

    public static readonly string[] All = { Cash, Bank };
}


/// <summary>
/// إقفال سنة مالية.
///
/// <para><b>ما يعنيه الإقفال فعلاً شيئان لا واحد:</b></para>
/// <list type="number">
/// <item>قيدٌ يُصفّر الإيرادات والاستخدامات ويُرحّل نتيجتها إلى «الأرباح
/// المحتجزة» — فتبدأ السنة الجديدة من الصفر وتبقى النتيجة في حقوق
/// الملكية.</item>
/// <item>**قفلٌ يمنع أي قيد بتاريخ داخل المدّة المُقفَلة.** وبلا هذا القفل
/// لا معنى للإقفال أصلاً: فاتورةٌ تُسجَّل بتاريخ العام الماضي تُغيّر أرقاماً
/// صدرت عنها تقارير ووُقّعت عليها ميزانية.</item>
/// </list>
///
/// <para><b>ويُفتح بقرار صريح مسجَّل:</b> خطأٌ يُكتشف بعد الإقفال حالة
/// واقعية، ومنعُ الفتح إلى الأبد يدفع المحاسب إلى تصحيحه في سنةٍ لا يخصّها.
/// لكن الفتح حدثٌ يُسجَّل باسمه وسببه.</para>
/// </summary>
public class FiscalClosing
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }

    /// <summary>آخر يوم في المدّة المُقفَلة — لا قيد بتاريخه أو قبله.</summary>
    public DateTime PeriodEnd { get; set; }

    /// <summary>صافي نتيجة المدّة المُرحَّلة إلى الأرباح المحتجزة.</summary>
    public decimal NetResult { get; set; }

    /// <summary>قيد الإقفال — منه يُعرَف ما رُحّل بالضبط.</summary>
    public Guid? JournalEntryId { get; set; }

    public Guid? ClosedBy { get; set; }
    public DateTime ClosedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// أُعيد فتحه.
    ///
    /// <para>لا يُحذف الصفّ: من راجع الدفتر يجب أن يرى أن السنة أُقفلت ثم
    /// فُتحت ولماذا — لا أن يجدها مفتوحة كأن شيئاً لم يكن.</para>
    /// </summary>
    public bool IsReopened { get; set; }
    public string? ReopenReason { get; set; }
    public Guid? ReopenedBy { get; set; }
    public DateTime? ReopenedAt { get; set; }
}


/// <summary>
/// حساب مصرفي للمنشأة.
///
/// <para><b>الثقب الذي يسدّه:</b> كل ما يُدفع أو يُقبَض كان يُقيَّد على
/// «الصندوق» — النقد والحوالة سواء. فتظهر النقدية الدفترية أعلى ممّا في
/// الدرج بمقدار كل حوالة، ولا يُعرف رصيد المصرف إطلاقاً. وهو أوّل ما يسأل
/// عنه من يُطابق كشف حسابه.</para>
///
/// <para><b>وكلٌّ له حسابه في الدليل:</b> لا حساب «المصارف» واحدٌ للجميع —
/// مطابقةُ كشف مصرفٍ بعينه تستحيل إن اختلط برصيد مصرف آخر.</para>
/// </summary>
public class BankAccount
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public string Name { get; set; } = "";

    /// <summary>رقم الحساب أو الآيبان — للعرض والمطابقة لا للتحويل.</summary>
    public string? AccountNumber { get; set; }

    /// <summary>
    /// حسابه في دليل الحسابات — تحت «المصارف» (1102).
    ///
    /// <para>يُنشأ تلقائياً عند إنشاء المصرف: تركُه للمستخدم يعني حساباً
    /// مصرفياً بلا أثر محاسبي، أو مربوطاً بحسابٍ خاطئ.</para>
    /// </summary>
    public Guid? LedgerAccountId { get; set; }

    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}


/// <summary>حالات فاتورة المورّد.</summary>
public static class SupplierInvoiceStatuses
{
    /// <summary>مُدخَلة ولم تُرحَّل — تُعدَّل وتُحذف بحرّية.</summary>
    public const string Draft = "draft";

    /// <summary>مُرحَّلة إلى الدفتر — لا تُعدَّل، والإلغاء بقيد عكسي.</summary>
    public const string Posted = "posted";

    /// <summary>مُلغاة بقيد عكسي.</summary>
    public const string Cancelled = "cancelled";
}

/// <summary>
/// فاتورة المورّد — ورقتُه هو، مطابَقةً بما استُلم فعلاً.
///
/// <para><b>الفجوة التي تسدّها:</b> لم يكن للمورّد فاتورة في النظام إطلاقاً.
/// كان الاستلام يُنشئ الدَّين مباشرةً بتكلفة **أمر الشراء** — أي بالسعر
/// المتّفق عليه لا بالسعر المُطالَب به. فإذا رفع المورّد سعره، أو فوتر كميةً
/// غير التي سلّمها، أو أضاف نقلاً، لم يكن في النظام موضعٌ واحد يُظهر الفرق.
/// يدفع أمين الصندوق ما تقوله الورقة، ويبقى الميزان يقول رقماً آخر إلى
/// الأبد.</para>
///
/// <para><b>المطابقة الثلاثية:</b> أمر الشراء (ما اتُّفق عليه) ← الاستلام
/// (ما وصل) ← الفاتورة (ما طُولب به). وثلاثتها تلتقي في هذا المستند: كل سطر
/// فيه يشير إلى سطر استلام بعينه، فالفرق يُحسَب لا يُقدَّر.</para>
///
/// <para><b>ولماذا لا تُلزَم بالمطابقة الكاملة:</b> فاتورةٌ تُرفض لأن فيها
/// فرق دينارين تُدفَع خارج النظام. فتُقبَل ويُقيَّد الفرق على
/// [AccountRoles.PurchasePriceVariance] صراحةً — ظاهراً للمراجعة، لا
/// مدفوناً في تكلفة المخزون.</para>
/// </summary>
public class SupplierInvoice
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid BranchId { get; set; }
    public Guid SupplierId { get; set; }

    /// <summary>
    /// رقم الفاتورة كما كتبه المورّد. إلزامي — بخلاف
    /// <see cref="PurchaseReceipt.SupplierNoteNumber"/>: إشعار التسليم قد
    /// لا يُرقَّم، أمّا الفاتورة فهي مستند المطالبة ولا تخلو من رقم. وهو
    /// المرجع الوحيد عند الخلاف، وأساس منع الازدواج.
    /// </summary>
    public string InvoiceNumber { get; set; } = "";

    /// <summary>تاريخ الفاتورة كما عليها — لا تاريخ الإدخال.</summary>
    public DateTime InvoiceDate { get; set; }

    /// <summary>تاريخ الاستحقاق. NULL يعني نقداً أو بلا أجل متّفق.</summary>
    public DateTime? DueDate { get; set; }

    /// <summary>
    /// إجمالي الفاتورة كما هو مكتوب عليها — يُدخله المستخدم ولا يُحسب.
    ///
    /// <para>وحسابُه من السطور يجعل النظام يُصحّح المورّد بدل أن يطابقه.
    /// المطلوب معرفة أن ثمّة فرقاً، وذلك يقتضي رقمين لا رقماً واحداً.</para>
    /// </summary>
    public decimal TotalAmount { get; set; }

    public string Status { get; set; } = SupplierInvoiceStatuses.Draft;
    public string? Notes { get; set; }

    public Guid? CreatedBy { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? PostedAt { get; set; }

    public List<SupplierInvoiceLine> Lines { get; set; } = new();
    public List<SupplierInvoiceExpense> Expenses { get; set; } = new();
}

/// <summary>
/// سطر في فاتورة المورّد، مربوطٌ بسطر استلامٍ بعينه أو منتج جديد.
/// </summary>
public class SupplierInvoiceLine
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid SupplierInvoiceId { get; set; }

    /// <summary>
    /// سطر الاستلام الذي تُفوتره. NULL للمنتجات الجديدة.
    /// </summary>
    public Guid? PurchaseReceiptItemId { get; set; }

    public Guid ProductId { get; set; }

    /// <summary>الكمية كما فوترها المورّد — قد تخالف ما وصل.</summary>
    public decimal Quantity { get; set; }

    /// <summary>سعر الشراء من المورّد — قد يخالف تكلفة الأمر.</summary>
    public decimal UnitCost { get; set; }

    /// <summary>سعر البيع — يُدخله المستخدم لتحديد الهامش.</summary>
    public decimal? SellingPrice { get; set; }

    public decimal LineTotal => Quantity * UnitCost;
}

/// <summary>
/// مصروف إضافي في فاتورة المورّد (شحن، ضرائب، إلخ).
/// </summary>
public class SupplierInvoiceExpense
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid SupplierInvoiceId { get; set; }
    public string Name { get; set; } = "";
    public decimal Amount { get; set; }
}


/// <summary>
/// مقاسات ورق الإيصال المتاحة.
///
/// <para>قائمةٌ مغلقة لا نصٌّ حرّ: مقاسٌ مجهول يُنتج PDF بأبعادٍ غير
/// متوقَّعة، ولا يكتشفه أحد إلا والورق يخرج مقصوصاً.</para>
/// </summary>
public static class ReceiptPapers
{
    /// <summary>لفّة حرارية 80 ملم — الأشيع في نقاط البيع.</summary>
    public const string Roll80 = "roll80";

    /// <summary>لفّة حرارية 58 ملم — الطابعات الصغيرة والمحمولة.</summary>
    public const string Roll58 = "roll58";

    /// <summary>A4 — الفاتورة الرسمية التي تُقدَّم لجهة.</summary>
    public const string A4 = "a4";

    /// <summary>A5 — نصف الورقة، لفواتير الجملة المختصرة.</summary>
    public const string A5 = "a5";

    public static readonly string[] All = { Roll80, Roll58, A4, A5 };
}

/// <summary>
/// مصروفٌ على شحنة أمر شراء — شحن، تخليص، جمارك، تأمين.
///
/// <para><b>سبب وجوده:</b> صنفٌ بعشرة من المورّد وشحنةٌ بمئة وخمسين لا
/// تكلفته عشرة. وحتى هذا الجدول كان النظام يحفظ سعر المورّد وحده تكلفةً
/// للصنف، فيُحسب الربح على تكلفةٍ ناقصة — وقد يُباع بخسارة والتقرير يقول
/// ربحاً. والحدّ الأدنى للسعر لا يحمي لأنه يقارن بالتكلفة الناقصة نفسها.
/// </para>
///
/// <para><b>على الأمر لا على السطر:</b> فاتورة الناقل تأتي بمبلغٍ واحد
/// للشحنة كلّها، ولا يعرف صاحبها كم منها لهذا الصنف — وهو ما يوزّعه
/// <see cref="KineticEnterprise.Api.Data.LandedCost"/> بالقيمة.</para>
///
/// <para><b>ولا يدخل في إجمالي الأمر:</b> ذاك ما سيطالب به المورّد
/// وتُطابَق به فاتورته. وضمُّ الشحن إليه يجعل كل فاتورة مورّد تبدو ناقصة.
/// </para>
/// </summary>
public class PurchaseOrderCharge
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid PurchaseOrderId { get; set; }
    public Guid OrganizationId { get; set; }

    /// <summary>ما هو: «شحن بحري»، «تخليص جمركي»، «نقل داخلي».</summary>
    public string Label { get; set; } = "";

    public decimal Amount { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// مفتاح مرور (passkey) مسجَّل لموظف — يفتح به جلسته المقفلة.
///
/// <para><b>سبب وجوده:</b> الشاشة تبقى مفتوحةً على حساب المدير بينما يقوم
/// من مكتبه، وقفلُها لا يُستعمل ما دام فتحها يعني كتابة كلمة مرورٍ طويلة
/// عشرين مرّةً في اليوم — فتُترك مفتوحة، أو تُكتب كلمة المرور على ورقةٍ
/// تحت لوحة المفاتيح. والمفتاح يفتحها ببصمةٍ أو بنمط الجهاز في ثانية.</para>
///
/// <para><b>ولا يُصدِر جلسةً من العدم:</b> الدخول الأوّل يبقى بكلمة المرور
/// وحدها. فمفتاحٌ مسروقٌ مع الجهاز يفتح ما هو مفتوح أصلاً على ذلك الجهاز،
/// ولا يفتح النظام على جهازٍ آخر — وهذا حدٌّ مقصود، وتوسيعه قرارُ إدارة
/// لا إعداد.</para>
///
/// <para><b>والمفتاح الخاصّ ليس هنا ولا يمكن أن يكون:</b> لا يغادر الجهاز
/// أصلاً. المخزَّن هو العامّ وحده، وتسريب هذا الجدول كلّه لا يمكّن أحداً من
/// انتحال أحد — بخلاف بصمات كلمات المرور.</para>
/// </summary>
public class UserPasskey
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid UserId { get; set; }

    /// <summary>معرّف الاعتماد كما أصدره المُصادِق، بترميز base64url.</summary>
    public string CredentialId { get; set; } = "";

    /// <summary>المفتاح العامّ بترميز COSE — بايتاتٌ تُقرأ عند كل تحقّق.</summary>
    public byte[] PublicKey { get; set; } = Array.Empty<byte>();

    /// <summary>
    /// عدّاد التوقيع الأخير — حارس الاستنساخ.
    ///
    /// <para>يزيده المُصادِق عند كل استعمال، فعودتُه إلى الوراء تعني نسخةً
    /// ثانية من المفتاح. وكثيرٌ من مفاتيح المرور المزامَنة تُبقيه صفراً
    /// دائماً، فلا يُفحص إلا إذا كان المخزَّن والوارد غير صفرين.</para>
    /// </summary>
    public long SignCount { get; set; }

    /// <summary>اسمٌ يعرّف الجهاز لصاحبه — «حاسوب المكتب»، «هاتفي».</summary>
    public string Label { get; set; } = "";

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? LastUsedAt { get; set; }
}

// ── نظام إدارة الأصول الثابتة والاهلاك ─────────────────────────────────

/// <summary>
/// الأصول الثابتة (Fixed Assets) — مبان، معدات، مركبات، إلخ.
/// استخدام الاهلاك في تقسيط قيمتها على سنوات حياتها الافتراضية.
/// </summary>
public class FixedAsset
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }

    /// <summary>اسم الأصل الواصف — «مبنى المقر الرئيسي»، «ماكينة إنتاج رقم 3».</summary>
    public string AssetName { get; set; } = "";

    /// <summary>رقم الأصل الفريد — كود داخلي أو رقم تسلسلي من الموردّ.</summary>
    public string AssetCode { get; set; } = "";

    /// <summary>تصنيف الأصل: buildings, equipment, vehicles, furniture, etc.</summary>
    public string AssetCategory { get; set; } = "";

    /// <summary>تاريخ الحصول على الأصل (تاريخ الشراء أو الإنشاء).</summary>
    public DateTime AcquisitionDate { get; set; } = DateTime.UtcNow;

    /// <summary>القيمة الأصلية للأصل (تكلفة الشراء أو الإنشاء).</summary>
    public decimal AcquisitionCost { get; set; }

    /// <summary>العمر الافتراضي للأصل بالسنوات.</summary>
    public int UsefulLifeYears { get; set; }

    /// <summary>القيمة المتبقية المتوقعة في نهاية العمر الافتراضي.</summary>
    public decimal ResidualValue { get; set; }

    /// <summary>طريقة الاهلاك: straight_line (القسط الثابت) أو declining_balance (التناقص).</summary>
    public string DepreciationMethod { get; set; } = "straight_line";

    /// <summary>نسبة الاهلاك السنوية (كنسبة مئوية 0-100).</summary>
    public decimal AnnualDepreciationRate { get; set; }

    /// <summary>مركز التكلفة المسؤول عن هذا الأصل.</summary>
    public string? CostCenter { get; set; }

    /// <summary>موقع الأصل الفيزيائي (الفرع أو الموقع).</summary>
    public string? Location { get; set; }

    /// <summary>هل الأصل نشط ومستخدم حالياً؟</summary>
    public bool IsActive { get; set; } = true;

    /// <summary>تاريخ استبعاد الأصل (إن وُجد).</summary>
    public DateTime? DisposalDate { get; set; }

    /// <summary>قيمة بيع/استبعاد الأصل عند التخلّي عنه.</summary>
    public decimal? DisposalAmount { get; set; }

    /// <summary>حالة الأصل: active, disposed, retired.</summary>
    public string Status { get; set; } = "active";

    public Guid? CreatedBy { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public Guid? UpdatedBy { get; set; }
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    public bool IsDeleted { get; set; }
}

/// <summary>
/// جدول الاهلاك الشهري/السنوي — تسجيل قيم الاهلاك الدوري لكل أصل.
/// مصدر الحقيقة للمعالجات المحاسبية.
/// </summary>
public class AssetDepreciation
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid FixedAssetId { get; set; }
    public Guid OrganizationId { get; set; }

    /// <summary>رقم الشهر (1-12).</summary>
    public int Month { get; set; }

    /// <summary>السنة المالية.</summary>
    public int Year { get; set; }

    /// <summary>القيمة الدفترية في بداية الفترة.</summary>
    public decimal BeginningValue { get; set; }

    /// <summary>مبلغ الاهلاك للفترة.</summary>
    public decimal DepreciationAmount { get; set; }

    /// <summary>إجمالي الاهلاك المتراكم إلى نهاية هذه الفترة.</summary>
    public decimal AccumulatedDepreciation { get; set; }

    /// <summary>القيمة الدفترية في نهاية الفترة (الأساس − المتراكم).</summary>
    public decimal EndingValue { get; set; }

    /// <summary>هل تمّ تسجيل القيد المحاسبي لهذا الاهلاك؟</summary>
    public bool IsRecorded { get; set; }

    /// <summary>رقم القيد المحاسبي المرتبط (JournalEntryId).</summary>
    public Guid? JournalEntryId { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// بيانات الشركة التجارية — المعلومات القانونية والإدارية.
/// تُستخدم في الفاتورات والتقارير الرسمية.
/// </summary>
public class CompanyInfo
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }

    /// <summary>رقم السجل التجاري.</summary>
    public string? CommercialRegistryNumber { get; set; }

    /// <summary>الرقم الضريبي للشركة.</summary>
    public string? TaxNumber { get; set; }

    /// <summary>الاسم القانوني الكامل للشركة.</summary>
    public string LegalName { get; set; } = "";

    /// <summary>العنوان التجاري الرسمي.</summary>
    public string? TradeAddress { get; set; }

    /// <summary>سنة التأسيس.</summary>
    public int? FoundationYear { get; set; }

    /// <summary>نوع الشركة: sole_proprietor, partnership, limited_company, etc.</summary>
    public string? CompanyType { get; set; }

    /// <summary>رقم حساب البنك الرئيسي.</summary>
    public string? BankAccountNumber { get; set; }

    /// <summary>اسم البنك.</summary>
    public string? BankName { get; set; }

    /// <summary>رقم IBAN الدولي للحساب البنكي.</summary>
    public string? IBAN { get; set; }

    /// <summary>رقم الهاتف المكتبي.</summary>
    public string? Phone { get; set; }

    /// <summary>البريد الإلكتروني الرسمي.</summary>
    public string? Email { get; set; }

    /// <summary>العملة المستخدمة في التقارير.</summary>
    public string? CurrencyCode { get; set; }

    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    public Guid? UpdatedBy { get; set; }
}

/// <summary>
/// توكن التجديد — يُحفظ بدل بناؤه من مطالبات التوكن القديم.
///
/// عندما ينتهي Access Token، الواجهة تطلب واحداً جديداً باستخدام Refresh Token.
/// يبقى صالحاً أطول من Access Token (مثل 90 يوم)، فحتى لو مرّ وقتٌ طويل،
/// طالما Refresh Token لم ينتهِ، يمكن تجديد الجلسة.
/// </summary>
public class RefreshToken
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Token { get; set; } = "";
    public DateTime ExpiresAt { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? RevokedAt { get; set; }

    public bool IsExpired => DateTime.UtcNow > ExpiresAt;
    public bool IsRevoked => RevokedAt.HasValue;
    public bool IsValid => !IsExpired && !IsRevoked;
}

/// <summary>طلب تجديد الجلسة — يحتوي على Refresh Token</summary>
public record RefreshTokenRequest(string RefreshToken);

/// <summary>طلب تسجيل الخروج — إلغاء Refresh Token</summary>
public record LogoutRequest(string RefreshToken);

// ═══════════════════════════════════════════════════════════════
// 🎯 v2.0.5: نظام المرتبات والفئات والمشتريات المرنة
// ═══════════════════════════════════════════════════════════════

/// <summary>
/// حقول مخصصة لفئة العملاء — تسمح بإضافة حقول ديناميكية
/// مثل: رقم الموظف، رقم الموظف الحكومي، درجة، إلخ
/// </summary>
public class CustomerCategoryField
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid CategoryId { get; set; }
    public string FieldName { get; set; } = "";      // اسم الحقل
    public string FieldLabel { get; set; } = "";     // العنوان المعروض
    public string FieldType { get; set; } = "";      // text, number, date, select
    public bool IsRequired { get; set; }
    public bool IsActive { get; set; } = true;
    public int DisplayOrder { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public CustomerCategory? Category { get; set; }
}

/// <summary>
/// حساب العميل — ربط بين العميل والمرتبات والسلف
/// كل عميل يمكن أن يكون له حساب للمرتبات
/// </summary>
public class CustomerAccount
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid CustomerId { get; set; }
    public Guid? AccountLedgerId { get; set; }       // حساب بنكي/محاسبي
    public string AccountNumber { get; set; } = "";
    public string BankName { get; set; } = "";
    public string IBAN { get; set; } = "";
    public decimal Balance { get; set; }             // الرصيد الحالي
    public decimal CreditLimit { get; set; }         // سقف الائتمان
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public bool IsActive { get; set; } = true;

    public AppUser? Customer { get; set; }
    public ICollection<SalaryRecord> SalaryRecords { get; set; } = new List<SalaryRecord>();
    public ICollection<CustomerLoan> Loans { get; set; } = new List<CustomerLoan>();
}

/// <summary>
/// سجل المرتب — المرتب الشهري للعميل
/// </summary>
public class SalaryRecord
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid CustomerAccountId { get; set; }
    public int Year { get; set; }
    public int Month { get; set; }
    public decimal BasicSalary { get; set; }        // الراتب الأساسي
    public decimal Allowances { get; set; }         // بدلات
    public decimal Deductions { get; set; }         // خصومات
    public decimal NetSalary { get; set; }          // الراتب الصافي
    public decimal PaidAmount { get; set; }         // المبلغ المدفوع
    public DateTime PaymentDate { get; set; }
    public string Status { get; set; } = "pending"; // pending, paid, partial
    public string Notes { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public CustomerAccount? CustomerAccount { get; set; }
    public ICollection<SalaryDetail> Details { get; set; } = new List<SalaryDetail>();
}

/// <summary>
/// تفاصيل المرتب — بنود المرتب (راتب، بدلات، إلخ)
/// </summary>
public class SalaryDetail
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid SalaryRecordId { get; set; }
    public string ItemType { get; set; } = "";      // basic, allowance, deduction
    public string ItemName { get; set; } = "";
    public decimal Amount { get; set; }

    public SalaryRecord? SalaryRecord { get; set; }
}

/// <summary>
/// السلف — قروض العملاء المرتبطة بحساباتهم
/// </summary>
public class CustomerLoan
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid CustomerAccountId { get; set; }
    public decimal LoanAmount { get; set; }         // مبلغ القرض
    public decimal PaidAmount { get; set; }         // المبلغ المسدد
    public decimal RemainingAmount { get; set; }    // المتبقي
    public int InstallmentCount { get; set; }       // عدد الأقساط
    public int PaidInstallments { get; set; }       // الأقساط المسددة
    public decimal MonthlyInstallment { get; set; }
    public decimal InterestRate { get; set; }       // سعر الفائدة %
    public DateTime LoanDate { get; set; }
    public DateTime DueDate { get; set; }
    public string Status { get; set; } = "active";  // active, completed, overdue
    public string Notes { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public CustomerAccount? CustomerAccount { get; set; }
    public ICollection<LoanPayment> Payments { get; set; } = new List<LoanPayment>();
}

/// <summary>
/// دفعات السلف — سداد الأقساط
/// </summary>
public class LoanPayment
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid CustomerLoanId { get; set; }
    public decimal Amount { get; set; }
    public DateTime PaymentDate { get; set; }
    public string PaymentMethod { get; set; } = ""; // cash, transfer, check
    public string Reference { get; set; } = "";     // رقم الشيك أو التحويل
    public string Notes { get; set; } = "";

    public CustomerLoan? CustomerLoan { get; set; }
}

/// <summary>
/// أنواع المشتريات — نوع تسليم البضاعة
/// </summary>
public class PurchaseType
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public string TypeName { get; set; } = "";      // Traditional, Direct, Hybrid
    public string Description { get; set; } = "";
    public string Route { get; set; } = "";         // المسار: supplier->warehouse->sale أو supplier->customer
    public bool IsActive { get; set; } = true;
    public int DisplayOrder { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public Organization? Organization { get; set; }
}

/// <summary>
/// التسليمات المباشرة — بضاعة من المورد مباشرة للعميل
/// </summary>
public class DirectDelivery
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid PurchaseId { get; set; }
    public Guid? CustomerId { get; set; }           // العميل النهائي
    public Guid? SupplierId { get; set; }           // المورد
    public decimal Amount { get; set; }
    public string DeliveryStatus { get; set; } = "pending";  // pending, delivered, received
    public DateTime DeliveryDate { get; set; }
    public DateTime? ReceivedDate { get; set; }
    public string Notes { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public ICollection<Invoice>? Invoices { get; set; }
}

/// <summary>
/// إعدادات النظام المتقدمة للعمليات المرنة
/// </summary>
public class SystemSetting
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public string SettingKey { get; set; } = "";
    public string SettingValue { get; set; } = "";
    public string SettingType { get; set; } = "";   // boolean, string, number, json
    public string Description { get; set; } = "";
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    public Organization? Organization { get; set; }
}

// ═══════════════════════════════════════════════════════════════
// 📋 API Request/Response Records
// ═══════════════════════════════════════════════════════════════

public record CreateSalaryRequest(
    Guid CustomerAccountId,
    int Month,
    int Year,
    decimal BasicSalary,
    decimal Allowances,
    decimal Deductions,
    string Notes = ""
);

public record CreateLoanRequest(
    Guid CustomerAccountId,
    decimal LoanAmount,
    int InstallmentCount,
    decimal InterestRate,
    DateTime DueDate,
    string Notes = ""
);

public record DirectDeliveryRequest(
    Guid PurchaseId,
    Guid? CustomerId,
    Guid? SupplierId,
    DateTime DeliveryDate,
    string Notes = ""
);
