using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<Organization> Organizations => Set<Organization>();
    public DbSet<PlatformSettings> PlatformSettings => Set<PlatformSettings>();
    public DbSet<License> Licenses => Set<License>();
    public DbSet<Branch> Branches => Set<Branch>();
    public DbSet<AppUser> AppUsers => Set<AppUser>();
    public DbSet<LoginHistory> LoginHistories => Set<LoginHistory>();
    public DbSet<Product> Products => Set<Product>();
    public DbSet<Supplier> Suppliers => Set<Supplier>();
    public DbSet<Sponsor> Sponsors => Set<Sponsor>();
    public DbSet<ProductCategory> ProductCategories => Set<ProductCategory>();
    public DbSet<StockLevel> StockLevels => Set<StockLevel>();
    public DbSet<StockTransfer> StockTransfers => Set<StockTransfer>();
    public DbSet<StockTransferItem> StockTransferItems => Set<StockTransferItem>();
    public DbSet<StockCount> StockCounts => Set<StockCount>();
    public DbSet<StockCountItem> StockCountItems => Set<StockCountItem>();
    public DbSet<Customer> Customers => Set<Customer>();
    public DbSet<CustomerWalletTransaction> CustomerWalletTransactions => Set<CustomerWalletTransaction>();
    public DbSet<CustomerCardIndex> CustomerCardIndexes => Set<CustomerCardIndex>();
    public DbSet<CustomerPinAttempt> CustomerPinAttempts => Set<CustomerPinAttempt>();
    public DbSet<Invoice> Invoices => Set<Invoice>();
    public DbSet<InvoiceItem> InvoiceItems => Set<InvoiceItem>();
    public DbSet<InvoicePayment> InvoicePayments => Set<InvoicePayment>();
    public DbSet<NotificationItem> Notifications => Set<NotificationItem>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();
    public DbSet<Permission> Permissions => Set<Permission>();
    public DbSet<RolePermission> RolePermissions => Set<RolePermission>();
    public DbSet<PurchaseOrder> PurchaseOrders => Set<PurchaseOrder>();
    public DbSet<PurchaseOrderItem> PurchaseOrderItems => Set<PurchaseOrderItem>();
    public DbSet<PlatformOrganizationRecord> PlatformOrganizations => Set<PlatformOrganizationRecord>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // أسماء الجداول تطابق DATABASE_SCHEMA_SQLSERVER.sql بالضبط حتى لا
        // يحتاج EF Core Migrations لإعادة اختراع تسمية مختلفة عن المخطط اليدوي.
        modelBuilder.Entity<Organization>().ToTable("organizations");
        modelBuilder.Entity<PlatformSettings>().ToTable("platform_settings");
        modelBuilder.Entity<License>().ToTable("licenses");
        modelBuilder.Entity<Branch>().ToTable("branches");
        modelBuilder.Entity<AppUser>().ToTable("app_users");
        modelBuilder.Entity<LoginHistory>().ToTable("login_history");
        modelBuilder.Entity<Product>().ToTable("products");
        modelBuilder.Entity<Supplier>().ToTable("suppliers");
        modelBuilder.Entity<Sponsor>().ToTable("sponsors");
        modelBuilder.Entity<ProductCategory>().ToTable("product_categories");
        modelBuilder.Entity<StockLevel>().ToTable("stock_levels");
        modelBuilder.Entity<StockTransfer>().ToTable("stock_transfers");
        modelBuilder.Entity<StockTransferItem>().ToTable("stock_transfer_items");
        modelBuilder.Entity<StockCount>().ToTable("stock_counts");
        modelBuilder.Entity<StockCountItem>().ToTable("stock_count_items");
        modelBuilder.Entity<Customer>().ToTable("customers");
        modelBuilder.Entity<CustomerWalletTransaction>().ToTable("customer_wallet_transactions");
        modelBuilder.Entity<CustomerCardIndex>().ToTable("customer_card_index").HasKey(c => c.CardCode);
        modelBuilder.Entity<CustomerPinAttempt>().ToTable("customer_pin_attempts");
        modelBuilder.Entity<Invoice>().ToTable("invoices");
        // فهرس فريد على مفتاح العميل: هو الضمانة النهائية ضد الازدواج.
        // الفحص في الـController يمنع الحالة الشائعة، لكن طلبين متزامنين
        // بالمفتاح نفسه (إعادة محاولة تلقائية مع بطء الشبكة) قد يمرّان معاً
        // من الفحص قبل أن يُحفظ أيّهما. القيد في قاعدة البيانات يمنع ذلك
        // مهما كان التزامن — والفلتر يسمح بتعدّد NULL للفواتير المُنشأة
        // مباشرةً بلا مفتاح.
        modelBuilder.Entity<Invoice>()
            .HasIndex(i => i.ClientRequestId)
            .IsUnique()
            // [client_request_id] لا [ClientRequestId]: نصّ الفلتر يُمرَّر إلى
            // SQL Server حرفياً بلا مرور على اصطلاح التسمية، بخلاف اسم العمود
            // في HasIndex الذي يترجمه UseSnakeCaseNamingConvention. كتابته
            // بصيغة الخاصية يجعل الفهرس يشير إلى عمود غير موجود.
            .HasFilter("[client_request_id] IS NOT NULL");
        modelBuilder.Entity<InvoiceItem>().ToTable("invoice_items");
        modelBuilder.Entity<InvoicePayment>().ToTable("invoice_payments");
        modelBuilder.Entity<NotificationItem>().ToTable("notifications");
        modelBuilder.Entity<AuditLog>().ToTable("audit_logs");
        modelBuilder.Entity<Permission>().ToTable("permissions").HasKey(p => p.Code);
        modelBuilder.Entity<RolePermission>().ToTable("role_permissions")
            .HasKey(rp => new { rp.OrganizationId, rp.Role, rp.PermissionCode });
        modelBuilder.Entity<PurchaseOrder>().ToTable("purchase_orders");
        modelBuilder.Entity<PurchaseOrderItem>().ToTable("purchase_order_items");
        modelBuilder.Entity<PlatformOrganizationRecord>().ToTable("platform_organizations");

        modelBuilder.Entity<Invoice>()
            .HasMany(i => i.Items)
            .WithOne()
            .HasForeignKey(i => i.InvoiceId);

        modelBuilder.Entity<Invoice>()
            .HasMany(i => i.Payments)
            .WithOne()
            .HasForeignKey(p => p.InvoiceId);

        modelBuilder.Entity<StockTransfer>()
            .HasMany(t => t.Items)
            .WithOne()
            .HasForeignKey(i => i.TransferId);

        modelBuilder.Entity<StockCount>()
            .HasMany(c => c.Items)
            .WithOne()
            .HasForeignKey(i => i.StockCountId);

        modelBuilder.Entity<PurchaseOrder>()
            .HasMany(o => o.Items)
            .WithOne()
            .HasForeignKey(i => i.PurchaseOrderId);

        // variance عمود محسوب (PERSISTED) في SQL Server نفسه — لا يجوز على
        // EF Core محاولة كتابته ضمن INSERT/UPDATE، فقط قراءته بعد الحفظ.
        modelBuilder.Entity<StockCountItem>()
            .Property(i => i.Variance)
            .ValueGeneratedOnAddOrUpdate();

        // خطأ حقيقي كان يُسقِط GetSettings/GetBarcodeTemplate/LicensesController
        // كاملة بـ 500: تحويل snake_case التلقائي يُنتج من BarcodeTemplateJson
        // العمود barcode_template_json، بينما العمود الفعلي في SQL هو
        // barcode_template (بلا لاحقة _json) — نفس الثغرة موجودة أصلاً في
        // License.EnabledModulesJson مقابل عمود enabled_modules، وكانت خامدة
        // لأن لا شيء استعلم عن Licenses قبل بناء LicensesController الآن.
        modelBuilder.Entity<Organization>().Property(o => o.BarcodeTemplateJson).HasColumnName("barcode_template");
        modelBuilder.Entity<License>().Property(l => l.EnabledModulesJson).HasColumnName("enabled_modules");

        // خطأ حقيقي ثانٍ كان يُسقِط GetMyOrganization/GetSettings بـ 500 دائماً
        // (كل طلب فعلي بتوكن صالح، لا 401 فقط): العمود SQL receipt_width_mm
        // من نوع DECIMAL(5,2)، بينما خاصية C# من نوع double — SqlDataReader
        // يرفض قراءة عمود DECIMAL عبر GetDouble() مباشرة (InvalidCastException)
        // بصرف النظر عن قيمة الصف. التحويل الصريح هنا يخبر EF بقراءته كـ
        // decimal ثم تحويله لـ double بدل محاولة قراءته مباشرة كـ double.
        modelBuilder.Entity<Organization>().Property(o => o.ReceiptWidthMm)
            .HasConversion(d => (decimal)d, d => (double)d);
    }
}
