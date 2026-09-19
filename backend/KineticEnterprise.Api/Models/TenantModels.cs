using System;

namespace KineticEnterprise.Api.Models;

/// <summary>
/// نموذج المؤسسة/الشركة - كل مؤسسة لها بيانات منفصلة تماماً
/// </summary>
public class Tenant
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Name { get; set; } // اسم المؤسسة: شركة الإتقان
    public string NameArabic { get; set; } // شركة الإتقان
    public string Domain { get; set; } // itqan.local أو itqan.com.ly

    // معلومات الاتصال
    public string Phone { get; set; }
    public string Email { get; set; }
    public string Address { get; set; }

    // إعدادات الخطة
    public string PlanType { get; set; } // basic, professional, enterprise
    public DateTime SubscriptionStartDate { get; set; }
    public DateTime SubscriptionEndDate { get; set; }
    public bool IsActive { get; set; } = true;

    // إعدادات النسخة
    public string? CurrentVersion { get; set; } // v2.0.5, v2.0.6, إلخ
    public string? DatabaseName { get; set; } // ItqanEnterprise_Org1, ItqanEnterprise_Org2
    public string? ConnectionStringKey { get; set; } // Key في appsettings لاسترجاع connection string

    // تتبع
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public string CreatedBy { get; set; } // Admin ID
    public DateTime? UpdatedAt { get; set; }
    public string? UpdatedBy { get; set; }
    public bool IsDeleted { get; set; } = false;

    // العلاقات
    public ICollection<TenantUser> Users { get; set; } = new List<TenantUser>();
    public ICollection<TenantSubscription> Subscriptions { get; set; } = new List<TenantSubscription>();
    public ICollection<ModuleLicense> ModuleLicenses { get; set; } = new List<ModuleLicense>();
}

/// <summary>
/// مستخدم المؤسسة - كل مستخدم ينتمي إلى مؤسسة واحدة فقط
/// </summary>
public class TenantUser
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string TenantId { get; set; } // FK إلى Tenant
    public Tenant Tenant { get; set; }

    public string UserId { get; set; } // FK إلى ApplicationUser
    // Navigation property (AppUser) سيتم إضافتها لاحقاً بعد تعريف AppUser

    // الدور في المؤسسة
    public string Role { get; set; } // admin, manager, user
    public string Permissions { get; set; } = "[]"; // JSON array من الصلاحيات

    public DateTime JoinedAt { get; set; } = DateTime.UtcNow;
    public bool IsActive { get; set; } = true;
}

/// <summary>
/// الاشتراك - لتتبع حالة الاشتراك والنسخة
/// </summary>
public class TenantSubscription
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string TenantId { get; set; }
    public Tenant Tenant { get; set; }

    public string Edition { get; set; } // Basic, Professional, Enterprise
    public int MaxUsers { get; set; } // عدد المستخدمين المسموح
    public int MaxCustomers { get; set; } // عدد العملاء المسموح
    public decimal MonthlyPrice { get; set; }

    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public bool IsActive { get; set; }

    public string Status { get; set; } // active, expired, cancelled
}

/// <summary>
/// رخصة الوحدات - تحديد أي وحدة مفعلة لكل مؤسسة
/// </summary>
public class ModuleLicense
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string TenantId { get; set; }
    public Tenant Tenant { get; set; }

    // الوحدات المتاحة
    public string ModuleName { get; set; } // "Customers", "Salaries", "Loans", "Purchases", "Reports", "Analytics"
    public bool IsEnabled { get; set; } = true;

    // الإصدار المفعل
    public string Version { get; set; } // v2.0.5

    public DateTime LicenseStartDate { get; set; }
    public DateTime LicenseEndDate { get; set; }

    public DateTime EnabledAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// Context معلومات المؤسسة الحالية - يتم تعيينها من Token
/// </summary>
public class TenantContext
{
    public string TenantId { get; set; } // من JWT claims
    public string TenantName { get; set; }
    public string CurrentUserId { get; set; }
    public List<string> Permissions { get; set; } = new();
    public List<string> EnabledModules { get; set; } = new(); // الوحدات المفعلة فقط
    public string CurrentVersion { get; set; }
}

// ملاحظة: AuditLog موجودة في Migration
// سيتم إنشاؤها تلقائياً عند تطبيق Migration
