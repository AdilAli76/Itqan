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
    public DbSet<UserPasskey> UserPasskeys => Set<UserPasskey>();
    public DbSet<Product> Products => Set<Product>();
    public DbSet<Supplier> Suppliers => Set<Supplier>();
    public DbSet<Sponsor> Sponsors => Set<Sponsor>();
    public DbSet<ProductCategory> ProductCategories => Set<ProductCategory>();
    public DbSet<Attachment> Attachments => Set<Attachment>();
    public DbSet<StockLevel> StockLevels => Set<StockLevel>();
    public DbSet<StockLedgerEntry> StockLedgerEntries => Set<StockLedgerEntry>();
    public DbSet<Warehouse> Warehouses => Set<Warehouse>();
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
    public DbSet<InvoiceItemBatch> InvoiceItemBatches => Set<InvoiceItemBatch>();
    public DbSet<MedicineReference> MedicineReferences => Set<MedicineReference>();
    public DbSet<Prescription> Prescriptions => Set<Prescription>();
    public DbSet<InvoicePayment> InvoicePayments => Set<InvoicePayment>();
    public DbSet<DebtReminder> DebtReminders => Set<DebtReminder>();
    public DbSet<NotificationItem> Notifications => Set<NotificationItem>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();

    // ── المحاسبة ────────────────────────────────────────────────────────
    public DbSet<Expense> Expenses => Set<Expense>();
    public DbSet<SupplierPayment> SupplierPayments => Set<SupplierPayment>();

    public DbSet<Account> Accounts => Set<Account>();
    public DbSet<JournalEntry> JournalEntries => Set<JournalEntry>();
    public DbSet<JournalEntryLine> JournalEntryLines => Set<JournalEntryLine>();
    public DbSet<AccountMapping> AccountMappings => Set<AccountMapping>();
    public DbSet<FiscalClosing> FiscalClosings => Set<FiscalClosing>();
    public DbSet<BankAccount> BankAccounts => Set<BankAccount>();
    public DbSet<CustomerCategory> CustomerCategories => Set<CustomerCategory>();
    public DbSet<CustomerAdvance> CustomerAdvances => Set<CustomerAdvance>();
    public DbSet<SupplierInvoice> SupplierInvoices => Set<SupplierInvoice>();
    public DbSet<SupplierInvoiceLine> SupplierInvoiceLines => Set<SupplierInvoiceLine>();
    public DbSet<Permission> Permissions => Set<Permission>();
    public DbSet<RolePermission> RolePermissions => Set<RolePermission>();
    public DbSet<PurchaseOrder> PurchaseOrders => Set<PurchaseOrder>();
    public DbSet<PurchaseOrderItem> PurchaseOrderItems => Set<PurchaseOrderItem>();
    public DbSet<PurchaseOrderCharge> PurchaseOrderCharges => Set<PurchaseOrderCharge>();
    public DbSet<PurchaseReceipt> PurchaseReceipts => Set<PurchaseReceipt>();
    public DbSet<PurchaseReceiptItem> PurchaseReceiptItems => Set<PurchaseReceiptItem>();
    public DbSet<PlatformOrganizationRecord> PlatformOrganizations => Set<PlatformOrganizationRecord>();

    // ── نظام إدارة الأصول الثابتة والاهلاك ──────────────────────────────
    public DbSet<FixedAsset> FixedAssets => Set<FixedAsset>();
    public DbSet<AssetDepreciation> AssetDepreciations => Set<AssetDepreciation>();
    public DbSet<CompanyInfo> CompanyInfos => Set<CompanyInfo>();

    // ── نظام إدارة المخزون المتقدم ───────────────────────────────────
    public DbSet<ProductBatch> ProductBatches => Set<ProductBatch>();
    public DbSet<ProductSerialNumber> ProductSerialNumbers => Set<ProductSerialNumber>();
    public DbSet<BatchMovement> BatchMovements => Set<BatchMovement>();
    public DbSet<InventoryAlertRule> InventoryAlertRules => Set<InventoryAlertRule>();
    public DbSet<InventoryAlert> InventoryAlerts => Set<InventoryAlert>();
    public DbSet<InventoryValuation> InventoryValuations => Set<InventoryValuation>();

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
        modelBuilder.Entity<UserPasskey>().ToTable("user_passkeys");
        // معرّف الاعتماد فريدٌ عالمياً بحكم المواصفة، والفهرس الفريد يمنع
        // تسجيل المفتاح نفسه لحسابين — فمن سجّله عند الأوّل يبقى صاحبه.
        modelBuilder.Entity<UserPasskey>().HasIndex(p => p.CredentialId).IsUnique();
        modelBuilder.Entity<Product>().ToTable("products");
        modelBuilder.Entity<Supplier>().ToTable("suppliers");
        modelBuilder.Entity<Sponsor>().ToTable("sponsors");
        modelBuilder.Entity<ProductCategory>().ToTable("product_categories");
        modelBuilder.Entity<StockLevel>().ToTable("stock_levels");
        modelBuilder.Entity<StockLedgerEntry>().ToTable("stock_ledger_entries");
        modelBuilder.Entity<Warehouse>().ToTable("warehouses");
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
        modelBuilder.Entity<InvoiceItemBatch>().ToTable("invoice_item_batches");
        modelBuilder.Entity<MedicineReference>().ToTable("medicine_reference");
        modelBuilder.Entity<Prescription>().ToTable("prescriptions");
        modelBuilder.Entity<InvoicePayment>().ToTable("invoice_payments");
        modelBuilder.Entity<DebtReminder>().ToTable("debt_reminders");
        modelBuilder.Entity<NotificationItem>().ToTable("notifications");
        modelBuilder.Entity<AuditLog>().ToTable("audit_logs");
        // بلا ToTable كان الكيان **خارج فحص المخطّط تماماً** — ولهذا لم
        // يكتشف أحد أن جدول attachments غائب من ملف المخطّط وموجود في
        // الترحيل وحده. الثقب في الفحص هو ما أخفى الثقب في المخطّط.
        modelBuilder.Entity<Attachment>().ToTable("attachments");
        modelBuilder.Entity<Expense>().ToTable("expenses");
        modelBuilder.Entity<SupplierPayment>().ToTable("supplier_payments");
        modelBuilder.Entity<Account>().ToTable("accounts");
        modelBuilder.Entity<JournalEntry>().ToTable("journal_entries");
        modelBuilder.Entity<JournalEntryLine>().ToTable("journal_entry_lines");
        modelBuilder.Entity<AccountMapping>().ToTable("account_mappings");
        modelBuilder.Entity<FiscalClosing>().ToTable("fiscal_closings");
        modelBuilder.Entity<BankAccount>().ToTable("bank_accounts");
        modelBuilder.Entity<CustomerCategory>().ToTable("customer_categories");
        modelBuilder.Entity<CustomerAdvance>().ToTable("customer_advances");
        modelBuilder.Entity<SupplierInvoice>().ToTable("supplier_invoices");
        modelBuilder.Entity<SupplierInvoiceLine>().ToTable("supplier_invoice_lines");
        modelBuilder.Entity<Permission>().ToTable("permissions").HasKey(p => p.Code);
        modelBuilder.Entity<RolePermission>().ToTable("role_permissions")
            .HasKey(rp => new { rp.OrganizationId, rp.Role, rp.PermissionCode });
        modelBuilder.Entity<PurchaseOrder>().ToTable("purchase_orders");
        modelBuilder.Entity<PurchaseOrderItem>().ToTable("purchase_order_items");
        modelBuilder.Entity<PurchaseOrderCharge>().ToTable("purchase_order_charges");
        modelBuilder.Entity<PurchaseReceipt>().ToTable("purchase_receipts");
        modelBuilder.Entity<PurchaseReceiptItem>().ToTable("purchase_receipt_items");
        modelBuilder.Entity<PlatformOrganizationRecord>().ToTable("platform_organizations");

        // ── الأصول الثابتة والاهلاك ───────────────────────────────────
        modelBuilder.Entity<FixedAsset>().ToTable("fixed_assets");
        modelBuilder.Entity<AssetDepreciation>().ToTable("asset_depreciation");
        modelBuilder.Entity<CompanyInfo>().ToTable("company_info");

        // ── نظام المخزون المتقدم ───────────────────────────────────────
        modelBuilder.Entity<ProductBatch>().ToTable("product_batches");
        modelBuilder.Entity<ProductSerialNumber>().ToTable("product_serial_numbers");
        modelBuilder.Entity<BatchMovement>().ToTable("batch_movements");
        modelBuilder.Entity<InventoryAlertRule>().ToTable("inventory_alert_rules");
        modelBuilder.Entity<InventoryAlert>().ToTable("inventory_alerts");
        modelBuilder.Entity<InventoryValuation>().ToTable("inventory_valuations");

        modelBuilder.Entity<Invoice>()
            .HasMany(i => i.Items)
            .WithOne()
            .HasForeignKey(i => i.InvoiceId);

        modelBuilder.Entity<Invoice>()
            .HasMany(i => i.Payments)
            .WithOne()
            .HasForeignKey(p => p.InvoiceId);

        modelBuilder.Entity<InvoiceItem>()
            .HasMany(i => i.Batches)
            .WithOne()
            .HasForeignKey(b => b.InvoiceItemId);

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
        // ونفسها لقالب الإيصال: ReceiptTemplateJson ← receipt_template.
        modelBuilder.Entity<Organization>().Property(o => o.ReceiptTemplateJson).HasColumnName("receipt_template");
        modelBuilder.Entity<License>().Property(l => l.EnabledModulesJson).HasColumnName("enabled_modules");
        // ونفس اللاحقة في فارقَي الوحدات: granted_modules لا
        // granted_modules_json — أُلحقت بـ Json في C# لتقول إن محتواها نصّ
        // JSON لا قائمة، ولو تُرك الاسم للتحويل التلقائي لسقط كل استعلام
        // على جدول التراخيص لا هذان العمودان وحدهما.
        modelBuilder.Entity<License>().Property(l => l.GrantedModulesJson).HasColumnName("granted_modules");
        modelBuilder.Entity<License>().Property(l => l.RevokedModulesJson).HasColumnName("revoked_modules");

        // خطأ حقيقي ثانٍ كان يُسقِط GetMyOrganization/GetSettings بـ 500 دائماً
        // (كل طلب فعلي بتوكن صالح، لا 401 فقط): العمود SQL receipt_width_mm
        // من نوع DECIMAL(5,2)، بينما خاصية C# من نوع double — SqlDataReader
        // يرفض قراءة عمود DECIMAL عبر GetDouble() مباشرة (InvalidCastException)
        // بصرف النظر عن قيمة الصف. التحويل الصريح هنا يخبر EF بقراءته كـ
        // decimal ثم تحويله لـ double بدل محاولة قراءته مباشرة كـ double.
        // ── المحاسبة ────────────────────────────────────────────────────
        modelBuilder.Entity<AccountMapping>().HasKey(m => new { m.OrganizationId, m.Role });

        modelBuilder.Entity<JournalEntry>()
            .HasMany(e => e.Lines)
            .WithOne()
            .HasForeignKey(l => l.JournalEntryId);

        modelBuilder.Entity<Organization>().Property(o => o.ReceiptWidthMm)
            .HasConversion(d => (decimal)d, d => (double)d);
    }
}
