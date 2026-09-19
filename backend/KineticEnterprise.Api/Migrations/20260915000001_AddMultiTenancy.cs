using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace KineticEnterprise.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddMultiTenancy : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // ════════════════════════════════════════════════════════════════
            // 1️⃣ إنشاء جداول Tenant الأساسية
            // ════════════════════════════════════════════════════════════════

            migrationBuilder.CreateTable(
                name: "tenants",
                columns: table => new
                {
                    id = table.Column<string>(type: "nvarchar(36)", maxLength: 36, nullable: false),
                    name = table.Column<string>(type: "nvarchar(255)", maxLength: 255, nullable: false),
                    name_arabic = table.Column<string>(type: "nvarchar(255)", maxLength: 255, nullable: false),
                    domain = table.Column<string>(type: "nvarchar(255)", maxLength: 255, nullable: false),
                    phone = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: true),
                    email = table.Column<string>(type: "nvarchar(255)", maxLength: 255, nullable: true),
                    address = table.Column<string>(type: "nvarchar(500)", maxLength: 500, nullable: true),
                    plan_type = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false, defaultValue: "basic"),
                    subscription_start_date = table.Column<DateTime>(type: "datetime2", nullable: false),
                    subscription_end_date = table.Column<DateTime>(type: "datetime2", nullable: false),
                    is_active = table.Column<bool>(type: "bit", nullable: false, defaultValue: true),
                    current_version = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: true, defaultValue: "2.0.5"),
                    database_name = table.Column<string>(type: "nvarchar(128)", maxLength: 128, nullable: true),
                    connection_string_key = table.Column<string>(type: "nvarchar(128)", maxLength: 128, nullable: true),
                    created_at = table.Column<DateTime>(type: "datetime2", nullable: false, defaultValueSql: "GETUTCDATE()"),
                    created_by = table.Column<string>(type: "nvarchar(36)", nullable: false),
                    updated_at = table.Column<DateTime>(type: "datetime2", nullable: true),
                    updated_by = table.Column<string>(type: "nvarchar(36)", nullable: true),
                    is_deleted = table.Column<bool>(type: "bit", nullable: false, defaultValue: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_tenants", x => x.id);
                    table.UniqueConstraint("uq_tenants_domain", x => x.domain);
                });

            // ────────────────────────────────────────────────────────────────
            // 2️⃣ جدول مستخدمي المؤسسة
            // ────────────────────────────────────────────────────────────────

            migrationBuilder.CreateTable(
                name: "tenant_users",
                columns: table => new
                {
                    id = table.Column<string>(type: "nvarchar(36)", maxLength: 36, nullable: false),
                    tenant_id = table.Column<string>(type: "nvarchar(36)", nullable: false),
                    user_id = table.Column<string>(type: "nvarchar(36)", nullable: false),
                    role = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false),
                    permissions = table.Column<string>(type: "nvarchar(max)", nullable: false, defaultValue: "[]"),
                    joined_at = table.Column<DateTime>(type: "datetime2", nullable: false, defaultValueSql: "GETUTCDATE()"),
                    is_active = table.Column<bool>(type: "bit", nullable: false, defaultValue: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_tenant_users", x => x.id);
                    table.ForeignKey(
                        name: "fk_tenant_users_tenants",
                        column: x => x.tenant_id,
                        principalTable: "tenants",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            // ────────────────────────────────────────────────────────────────
            // 3️⃣ جدول رخص الوحدات
            // ────────────────────────────────────────────────────────────────

            migrationBuilder.CreateTable(
                name: "module_licenses",
                columns: table => new
                {
                    id = table.Column<string>(type: "nvarchar(36)", maxLength: 36, nullable: false),
                    tenant_id = table.Column<string>(type: "nvarchar(36)", nullable: false),
                    module_name = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    is_enabled = table.Column<bool>(type: "bit", nullable: false, defaultValue: true),
                    version = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false),
                    license_start_date = table.Column<DateTime>(type: "datetime2", nullable: false),
                    license_end_date = table.Column<DateTime>(type: "datetime2", nullable: false),
                    enabled_at = table.Column<DateTime>(type: "datetime2", nullable: false, defaultValueSql: "GETUTCDATE()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_module_licenses", x => x.id);
                    table.ForeignKey(
                        name: "fk_module_licenses_tenants",
                        column: x => x.tenant_id,
                        principalTable: "tenants",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            // ────────────────────────────────────────────────────────────────
            // 4️⃣ جدول سجل الأنشطة (Audit Log)
            // ────────────────────────────────────────────────────────────────

            migrationBuilder.CreateTable(
                name: "audit_logs",
                columns: table => new
                {
                    id = table.Column<string>(type: "nvarchar(36)", maxLength: 36, nullable: false),
                    tenant_id = table.Column<string>(type: "nvarchar(36)", nullable: false),
                    user_id = table.Column<string>(type: "nvarchar(36)", nullable: false),
                    action = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false),
                    entity = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    entity_id = table.Column<string>(type: "nvarchar(36)", nullable: false),
                    old_values = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    new_values = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    created_at = table.Column<DateTime>(type: "datetime2", nullable: false, defaultValueSql: "GETUTCDATE()"),
                    ip_address = table.Column<string>(type: "nvarchar(45)", maxLength: 45, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_audit_logs", x => x.id);
                    table.ForeignKey(
                        name: "fk_audit_logs_tenants",
                        column: x => x.tenant_id,
                        principalTable: "tenants",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            // ════════════════════════════════════════════════════════════════
            // 5️⃣ إضافة TenantId إلى جميع الجداول الموجودة
            // ════════════════════════════════════════════════════════════════

            // جداول v2.0.5 الجديدة
            migrationBuilder.AddColumn<string>(
                name: "tenant_id",
                table: "customer_accounts",
                type: "nvarchar(36)",
                maxLength: 36,
                nullable: false,
                defaultValue: "default"); // قيمة افتراضية مؤقتة

            migrationBuilder.AddColumn<string>(
                name: "tenant_id",
                table: "salary_records",
                type: "nvarchar(36)",
                maxLength: 36,
                nullable: false,
                defaultValue: "default");

            migrationBuilder.AddColumn<string>(
                name: "tenant_id",
                table: "customer_loans",
                type: "nvarchar(36)",
                maxLength: 36,
                nullable: false,
                defaultValue: "default");

            migrationBuilder.AddColumn<string>(
                name: "tenant_id",
                table: "loan_payments",
                type: "nvarchar(36)",
                maxLength: 36,
                nullable: false,
                defaultValue: "default");

            migrationBuilder.AddColumn<string>(
                name: "tenant_id",
                table: "purchase_types",
                type: "nvarchar(36)",
                maxLength: 36,
                nullable: false,
                defaultValue: "default");

            migrationBuilder.AddColumn<string>(
                name: "tenant_id",
                table: "direct_deliveries",
                type: "nvarchar(36)",
                maxLength: 36,
                nullable: false,
                defaultValue: "default");

            // جداول قديمة موجودة
            migrationBuilder.AddColumn<string>(
                name: "tenant_id",
                table: "customers",
                type: "nvarchar(36)",
                maxLength: 36,
                nullable: false,
                defaultValue: "default");

            migrationBuilder.AddColumn<string>(
                name: "tenant_id",
                table: "invoices",
                type: "nvarchar(36)",
                maxLength: 36,
                nullable: false,
                defaultValue: "default");

            migrationBuilder.AddColumn<string>(
                name: "tenant_id",
                table: "customer_categories",
                type: "nvarchar(36)",
                maxLength: 36,
                nullable: false,
                defaultValue: "default");

            // ════════════════════════════════════════════════════════════════
            // 6️⃣ إضافة حقول التتبع (Tracking) للجداول الموجودة
            // ════════════════════════════════════════════════════════════════

            migrationBuilder.AddColumn<DateTime>(
                name: "created_at",
                table: "customers",
                type: "datetime2",
                nullable: false,
                defaultValueSql: "GETUTCDATE()");

            migrationBuilder.AddColumn<string>(
                name: "created_by",
                table: "customers",
                type: "nvarchar(36)",
                maxLength: 36,
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "updated_at",
                table: "customers",
                type: "datetime2",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "updated_by",
                table: "customers",
                type: "nvarchar(36)",
                maxLength: 36,
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "is_deleted",
                table: "customers",
                type: "bit",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<DateTime>(
                name: "deleted_at",
                table: "customers",
                type: "datetime2",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "deleted_by",
                table: "customers",
                type: "nvarchar(36)",
                maxLength: 36,
                nullable: true);

            // ════════════════════════════════════════════════════════════════
            // 7️⃣ إنشاء الفهارس للأداء
            // ════════════════════════════════════════════════════════════════

            migrationBuilder.CreateIndex(
                name: "ix_tenants_domain",
                table: "tenants",
                column: "domain",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_tenants_is_active",
                table: "tenants",
                column: "is_active");

            migrationBuilder.CreateIndex(
                name: "ix_tenant_users_tenant_id",
                table: "tenant_users",
                column: "tenant_id");

            migrationBuilder.CreateIndex(
                name: "ix_tenant_users_user_id",
                table: "tenant_users",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "ix_module_licenses_tenant_id",
                table: "module_licenses",
                column: "tenant_id");

            migrationBuilder.CreateIndex(
                name: "ix_module_licenses_tenant_module",
                table: "module_licenses",
                columns: new[] { "tenant_id", "module_name" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_audit_logs_tenant_id",
                table: "audit_logs",
                column: "tenant_id");

            migrationBuilder.CreateIndex(
                name: "ix_audit_logs_created_at",
                table: "audit_logs",
                column: "created_at");

            // فهارس TenantId للجداول الموجودة
            migrationBuilder.CreateIndex(
                name: "ix_customers_tenant_id",
                table: "customers",
                column: "tenant_id");

            migrationBuilder.CreateIndex(
                name: "ix_customer_accounts_tenant_id",
                table: "customer_accounts",
                column: "tenant_id");

            migrationBuilder.CreateIndex(
                name: "ix_customer_loans_tenant_id",
                table: "customer_loans",
                column: "tenant_id");

            migrationBuilder.CreateIndex(
                name: "ix_invoices_tenant_id",
                table: "invoices",
                column: "tenant_id");

            migrationBuilder.CreateIndex(
                name: "ix_customer_categories_tenant_id",
                table: "customer_categories",
                column: "tenant_id");

            // ════════════════════════════════════════════════════════════════
            // ✅ Migration Complete
            // ════════════════════════════════════════════════════════════════
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // حذف الأعمدة المضافة
            migrationBuilder.DropColumn(name: "tenant_id", table: "customer_accounts");
            migrationBuilder.DropColumn(name: "tenant_id", table: "salary_records");
            migrationBuilder.DropColumn(name: "tenant_id", table: "customer_loans");
            migrationBuilder.DropColumn(name: "tenant_id", table: "loan_payments");
            migrationBuilder.DropColumn(name: "tenant_id", table: "purchase_types");
            migrationBuilder.DropColumn(name: "tenant_id", table: "direct_deliveries");
            migrationBuilder.DropColumn(name: "tenant_id", table: "customers");
            migrationBuilder.DropColumn(name: "tenant_id", table: "invoices");
            migrationBuilder.DropColumn(name: "tenant_id", table: "customer_categories");

            migrationBuilder.DropColumn(name: "created_at", table: "customers");
            migrationBuilder.DropColumn(name: "created_by", table: "customers");
            migrationBuilder.DropColumn(name: "updated_at", table: "customers");
            migrationBuilder.DropColumn(name: "updated_by", table: "customers");
            migrationBuilder.DropColumn(name: "is_deleted", table: "customers");
            migrationBuilder.DropColumn(name: "deleted_at", table: "customers");
            migrationBuilder.DropColumn(name: "deleted_by", table: "customers");

            // حذف الجداول
            migrationBuilder.DropTable(name: "audit_logs");
            migrationBuilder.DropTable(name: "module_licenses");
            migrationBuilder.DropTable(name: "tenant_users");
            migrationBuilder.DropTable(name: "tenants");
        }
    }
}
