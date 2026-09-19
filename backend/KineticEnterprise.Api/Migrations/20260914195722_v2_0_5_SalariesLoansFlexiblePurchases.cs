using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace KineticEnterprise.Api.Migrations
{
    /// <inheritdoc />
    public partial class v2_0_5_SalariesLoansFlexiblePurchases : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "direct_delivery_id",
                table: "invoices",
                type: "uniqueidentifier",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "customer_accounts",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    customer_id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    account_ledger_id = table.Column<Guid>(type: "uniqueidentifier", nullable: true),
                    account_number = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    bank_name = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    iban = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    balance = table.Column<decimal>(type: "decimal(18,2)", nullable: false),
                    credit_limit = table.Column<decimal>(type: "decimal(18,2)", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2", nullable: false),
                    is_active = table.Column<bool>(type: "bit", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_customer_accounts", x => x.id);
                    table.ForeignKey(
                        name: "fk_customer_accounts_app_users_customer_id",
                        column: x => x.customer_id,
                        principalTable: "app_users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "customer_category_fields",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    category_id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    field_name = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    field_label = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    field_type = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    is_required = table.Column<bool>(type: "bit", nullable: false),
                    is_active = table.Column<bool>(type: "bit", nullable: false),
                    display_order = table.Column<int>(type: "int", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_customer_category_fields", x => x.id);
                    table.ForeignKey(
                        name: "fk_customer_category_fields_customer_categories_category_id",
                        column: x => x.category_id,
                        principalTable: "customer_categories",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "direct_deliveries",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    purchase_id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    customer_id = table.Column<Guid>(type: "uniqueidentifier", nullable: true),
                    supplier_id = table.Column<Guid>(type: "uniqueidentifier", nullable: true),
                    amount = table.Column<decimal>(type: "decimal(18,2)", nullable: false),
                    delivery_status = table.Column<string>(type: "nvarchar(450)", nullable: false),
                    delivery_date = table.Column<DateTime>(type: "datetime2", nullable: false),
                    received_date = table.Column<DateTime>(type: "datetime2", nullable: true),
                    notes = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_direct_deliveries", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "purchase_types",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    organization_id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    type_name = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    description = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    route = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    is_active = table.Column<bool>(type: "bit", nullable: false),
                    display_order = table.Column<int>(type: "int", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_purchase_types", x => x.id);
                    table.ForeignKey(
                        name: "fk_purchase_types_organizations_organization_id",
                        column: x => x.organization_id,
                        principalTable: "organizations",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "system_settings",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    organization_id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    setting_key = table.Column<string>(type: "nvarchar(450)", nullable: false),
                    setting_value = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    setting_type = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    description = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    updated_at = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_system_settings", x => x.id);
                    table.ForeignKey(
                        name: "fk_system_settings_organizations_organization_id",
                        column: x => x.organization_id,
                        principalTable: "organizations",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "customer_loans",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    customer_account_id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    loan_amount = table.Column<decimal>(type: "decimal(18,2)", nullable: false),
                    paid_amount = table.Column<decimal>(type: "decimal(18,2)", nullable: false),
                    remaining_amount = table.Column<decimal>(type: "decimal(18,2)", nullable: false),
                    installment_count = table.Column<int>(type: "int", nullable: false),
                    paid_installments = table.Column<int>(type: "int", nullable: false),
                    monthly_installment = table.Column<decimal>(type: "decimal(18,2)", nullable: false),
                    interest_rate = table.Column<decimal>(type: "decimal(18,2)", nullable: false),
                    loan_date = table.Column<DateTime>(type: "datetime2", nullable: false),
                    due_date = table.Column<DateTime>(type: "datetime2", nullable: false),
                    status = table.Column<string>(type: "nvarchar(450)", nullable: false),
                    notes = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_customer_loans", x => x.id);
                    table.ForeignKey(
                        name: "fk_customer_loans_customer_accounts_customer_account_id",
                        column: x => x.customer_account_id,
                        principalTable: "customer_accounts",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "salary_records",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    customer_account_id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    year = table.Column<int>(type: "int", nullable: false),
                    month = table.Column<int>(type: "int", nullable: false),
                    basic_salary = table.Column<decimal>(type: "decimal(18,2)", nullable: false),
                    allowances = table.Column<decimal>(type: "decimal(18,2)", nullable: false),
                    deductions = table.Column<decimal>(type: "decimal(18,2)", nullable: false),
                    net_salary = table.Column<decimal>(type: "decimal(18,2)", nullable: false),
                    paid_amount = table.Column<decimal>(type: "decimal(18,2)", nullable: false),
                    payment_date = table.Column<DateTime>(type: "datetime2", nullable: false),
                    status = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    notes = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_salary_records", x => x.id);
                    table.ForeignKey(
                        name: "fk_salary_records_customer_accounts_customer_account_id",
                        column: x => x.customer_account_id,
                        principalTable: "customer_accounts",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "loan_payments",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    customer_loan_id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    amount = table.Column<decimal>(type: "decimal(18,2)", nullable: false),
                    payment_date = table.Column<DateTime>(type: "datetime2", nullable: false),
                    payment_method = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    reference = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    notes = table.Column<string>(type: "nvarchar(max)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_loan_payments", x => x.id);
                    table.ForeignKey(
                        name: "fk_loan_payments_customer_loans_customer_loan_id",
                        column: x => x.customer_loan_id,
                        principalTable: "customer_loans",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "salary_details",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    salary_record_id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    item_type = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    item_name = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    amount = table.Column<decimal>(type: "decimal(18,2)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_salary_details", x => x.id);
                    table.ForeignKey(
                        name: "fk_salary_details_salary_records_salary_record_id",
                        column: x => x.salary_record_id,
                        principalTable: "salary_records",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_invoices_direct_delivery_id",
                table: "invoices",
                column: "direct_delivery_id");

            migrationBuilder.CreateIndex(
                name: "ix_customer_accounts_account_ledger_id",
                table: "customer_accounts",
                column: "account_ledger_id");

            migrationBuilder.CreateIndex(
                name: "ix_customer_accounts_customer_id",
                table: "customer_accounts",
                column: "customer_id");

            migrationBuilder.CreateIndex(
                name: "ix_customer_category_fields_category_id",
                table: "customer_category_fields",
                column: "category_id");

            migrationBuilder.CreateIndex(
                name: "ix_customer_loans_customer_account_id",
                table: "customer_loans",
                column: "customer_account_id");

            migrationBuilder.CreateIndex(
                name: "ix_customer_loans_status",
                table: "customer_loans",
                column: "status");

            migrationBuilder.CreateIndex(
                name: "ix_direct_deliveries_customer_id",
                table: "direct_deliveries",
                column: "customer_id");

            migrationBuilder.CreateIndex(
                name: "ix_direct_deliveries_delivery_status",
                table: "direct_deliveries",
                column: "delivery_status");

            migrationBuilder.CreateIndex(
                name: "ix_direct_deliveries_purchase_id",
                table: "direct_deliveries",
                column: "purchase_id");

            migrationBuilder.CreateIndex(
                name: "ix_loan_payments_customer_loan_id",
                table: "loan_payments",
                column: "customer_loan_id");

            migrationBuilder.CreateIndex(
                name: "ix_loan_payments_payment_date",
                table: "loan_payments",
                column: "payment_date");

            migrationBuilder.CreateIndex(
                name: "ix_purchase_types_organization_id",
                table: "purchase_types",
                column: "organization_id");

            migrationBuilder.CreateIndex(
                name: "ix_salary_details_salary_record_id",
                table: "salary_details",
                column: "salary_record_id");

            migrationBuilder.CreateIndex(
                name: "ix_salary_records_customer_account_id",
                table: "salary_records",
                column: "customer_account_id");

            migrationBuilder.CreateIndex(
                name: "ix_salary_records_year_month",
                table: "salary_records",
                columns: new[] { "year", "month" });

            migrationBuilder.CreateIndex(
                name: "ix_system_settings_organization_id_setting_key",
                table: "system_settings",
                columns: new[] { "organization_id", "setting_key" },
                unique: true);

            migrationBuilder.AddForeignKey(
                name: "fk_invoices_direct_deliveries_direct_delivery_id",
                table: "invoices",
                column: "direct_delivery_id",
                principalTable: "direct_deliveries",
                principalColumn: "id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "fk_invoices_direct_deliveries_direct_delivery_id",
                table: "invoices");

            migrationBuilder.DropTable(
                name: "customer_category_fields");

            migrationBuilder.DropTable(
                name: "direct_deliveries");

            migrationBuilder.DropTable(
                name: "loan_payments");

            migrationBuilder.DropTable(
                name: "purchase_types");

            migrationBuilder.DropTable(
                name: "salary_details");

            migrationBuilder.DropTable(
                name: "system_settings");

            migrationBuilder.DropTable(
                name: "customer_loans");

            migrationBuilder.DropTable(
                name: "salary_records");

            migrationBuilder.DropTable(
                name: "customer_accounts");

            migrationBuilder.DropIndex(
                name: "ix_invoices_direct_delivery_id",
                table: "invoices");

            migrationBuilder.DropColumn(
                name: "direct_delivery_id",
                table: "invoices");
        }
    }
}
