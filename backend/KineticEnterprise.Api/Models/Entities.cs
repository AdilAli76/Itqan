namespace KineticEnterprise.Api.Models;

public class Organization
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string LegalName { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public string? LogoUrl { get; set; }
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
    // شريط جانبي أو شريط علوي — تفضيل عرض بحت لا يغيّر أي وظيفة.
    public string NavLayout { get; set; } = "sidebar";
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
    public string EnabledModulesJson { get; set; } = "[\"inventory\",\"pos\",\"customers\",\"reports\"]";
    public string? HardwareFingerprint { get; set; }
    public DateTime IssuedAt { get; set; } = DateTime.UtcNow;
    public DateTime ExpiresAt { get; set; }
    public string Status { get; set; } = "active"; // active | grace_period | expired | revoked
}

public class Branch
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public string Name { get; set; } = "";
    public string Code { get; set; } = "";
    public string? Address { get; set; }
    public string? Phone { get; set; }
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
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
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

public class Product
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
    public decimal CostPrice { get; set; }
    public decimal SalePrice { get; set; }
    public bool TrackExpiry { get; set; }
    public decimal ReorderLevel { get; set; }

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

public class StockLevel
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid BranchId { get; set; }
    public Guid ProductId { get; set; }
    public decimal Quantity { get; set; }
    public string BatchNumber { get; set; } = "";
    public DateTime? ExpiryDate { get; set; }
}

/// <summary>
/// تسلسل status (راجع DATABASE_TABLES_GUIDE.md §5.5): pending (أُنشئ، بلا
/// أثر مخزوني بعد) ← in_transit (خُصمت الكمية من الفرع المصدر فعلياً) ←
/// received (أُضيفت للفرع الهدف) — يمنع ازدواج الكمية أو فقدانها أثناء
/// النقل. لا مسار رجوع من in_transit إلى cancelled عمداً؛ البضاعة تكون قد
/// غادرت الفرع المصدر فعلياً، فالتصحيح بعد هذه النقطة تعديل مخزون يدوي.
/// </summary>
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
    public string Status { get; set; } = "open"; // open | reconciled | cancelled
    public Guid? CreatedBy { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? ClosedAt { get; set; }
    public List<StockCountItem> Items { get; set; } = new();
}

/// <summary>
/// Variance عمود محسوب (PERSISTED) في قاعدة البيانات نفسها — لا يُكتَب من
/// EF Core إطلاقاً (راجع AppDbContext.OnModelCreating)، فقط يُقرأ بعد الحفظ.
/// </summary>
public class StockCountItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid StockCountId { get; set; }
    public Guid ProductId { get; set; }
    public decimal SystemQuantity { get; set; }
    public decimal CountedQuantity { get; set; }
    public decimal Variance { get; set; }
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
}

/// <summary>
/// لا يحمل WalletBalance عمداً — الرصيد مجموع دفتر
/// [CustomerWalletTransaction] ولا يُخزَّن كعمود قابل للكتابة إطلاقاً
/// (راجع libyan_models/ACCOUNTING_RULES.md §3: عمود رصيد قابل للكتابة هو
/// أسرع طريق إلى بطاقة رصيدها لا يطابق محاسبتها).
/// </summary>
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
    public int LoyaltyPoints { get; set; }
    public bool IsDeleted { get; set; }
    // الرقم السري مُجزَّأ بـ BCrypt كأي كلمة مرور، ورمز البطاقة نفسه يعيش
    // في customer_card_index وحده (راجع تعليقه).
    //
    // القفل واحد لكل مداخل الرقم السري (بوابة العميل + نقطة البيع) لا لكل
    // مدخل على حدة — راجع [CustomerPinGate] لسبب كون ذلك شرطاً أمنياً.
    public string? PinHash { get; set; }
    public DateTime? PinLockedUntil { get; set; }

    // ---- نموذج الحساب ----
    // راجع [AccountModels] لسبب الفصل بين النموذجين.
    public string AccountModel { get; set; } = AccountModels.Prepaid;

    /// <summary>الجهة الممولة — للاستحقاق الممنوح وحده.</summary>
    public Guid? SponsorId { get; set; }

    /// <summary>سقف ما يُمنَح خلال الفترة الواحدة. صفر = بلا سقف.</summary>
    public decimal EntitlementCeiling { get; set; }

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
public class CustomerWalletTransaction
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OrganizationId { get; set; }
    public Guid CustomerId { get; set; }
    public Guid? InvoiceId { get; set; }
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

    public static int SignOf(string kind) => kind switch
    {
        TopUp or InvoiceRefund or AdjustmentIn or EntitlementGrant => 1,
        Spend or AdjustmentOut or EntitlementExpiry => -1,
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
    public string Status { get; set; } = "completed";
    public Guid? CreatedBy { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public List<InvoiceItem> Items { get; set; } = new();
    public List<InvoicePayment> Payments { get; set; } = new();
}

public class InvoiceItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid InvoiceId { get; set; }
    public Guid ProductId { get; set; }
    public decimal Quantity { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal LineTotal { get; set; }
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
