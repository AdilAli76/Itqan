-- Kinetic ERP v1.6.6 Database Migrations
-- Adds support for customer tags, entitlement deductions, and print audit logging

-- ============================================================================
-- Table: customer_tags
-- Purpose: Tags for categorizing customers (VIP, frequent buyer, wholesale, etc.)
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[customer_tags]') AND type in (N'U'))
CREATE TABLE [dbo].[customer_tags] (
    [id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    [organization_id] UNIQUEIDENTIFIER NOT NULL,
    [customer_id] UNIQUEIDENTIFIER NOT NULL,
    [tag_name] NVARCHAR(50) NOT NULL,
    [color] NVARCHAR(20) NULL,
    [created_at] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT [fk_customer_tags_organization] FOREIGN KEY ([organization_id])
        REFERENCES [dbo].[organizations]([id]) ON DELETE CASCADE,
    CONSTRAINT [fk_customer_tags_customer] FOREIGN KEY ([customer_id])
        REFERENCES [dbo].[customers]([id]) ON DELETE CASCADE,
    CONSTRAINT [uq_customer_tags_unique_per_customer]
        UNIQUE ([customer_id], [tag_name])
);

CREATE INDEX [idx_customer_tags_organization] ON [dbo].[customer_tags]([organization_id]);
CREATE INDEX [idx_customer_tags_customer] ON [dbo].[customer_tags]([customer_id]);
CREATE INDEX [idx_customer_tags_name] ON [dbo].[customer_tags]([tag_name]);

-- ============================================================================
-- Table: entitlement_deduction_schedules
-- Purpose: Monthly automatic deduction schedules by customer category
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[entitlement_deduction_schedules]') AND type in (N'U'))
CREATE TABLE [dbo].[entitlement_deduction_schedules] (
    [id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    [organization_id] UNIQUEIDENTIFIER NOT NULL,
    [customer_category_id] UNIQUEIDENTIFIER NOT NULL,
    [deduction_amount] DECIMAL(18, 2) NOT NULL,
    [deduction_day_of_month] INT NOT NULL CHECK ([deduction_day_of_month] >= 1 AND [deduction_day_of_month] <= 28),
    [last_processed_date] DATETIME2 NULL,
    [is_active] BIT NOT NULL DEFAULT 1,
    [notes] NVARCHAR(500) NULL,
    [created_at] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT [fk_deduction_schedule_organization] FOREIGN KEY ([organization_id])
        REFERENCES [dbo].[organizations]([id]) ON DELETE CASCADE,
    CONSTRAINT [fk_deduction_schedule_category] FOREIGN KEY ([customer_category_id])
        REFERENCES [dbo].[customer_categories]([id]) ON DELETE CASCADE
);

CREATE INDEX [idx_deduction_schedule_organization] ON [dbo].[entitlement_deduction_schedules]([organization_id]);
CREATE INDEX [idx_deduction_schedule_category] ON [dbo].[entitlement_deduction_schedules]([customer_category_id]);
CREATE INDEX [idx_deduction_schedule_active] ON [dbo].[entitlement_deduction_schedules]([is_active]);

-- ============================================================================
-- Table: print_audit_logs
-- Purpose: Audit trail for all print operations
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[print_audit_logs]') AND type in (N'U'))
CREATE TABLE [dbo].[print_audit_logs] (
    [id] UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    [organization_id] UNIQUEIDENTIFIER NOT NULL,
    [branch_id] UNIQUEIDENTIFIER NOT NULL,
    [invoice_id] UNIQUEIDENTIFIER NULL,
    [document_type] NVARCHAR(50) NOT NULL DEFAULT 'invoice',
    [success] BIT NOT NULL,
    [error_message] NVARCHAR(500) NULL,
    [requested_by] UNIQUEIDENTIFIER NULL,
    [created_at] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT [fk_print_audit_log_organization] FOREIGN KEY ([organization_id])
        REFERENCES [dbo].[organizations]([id]) ON DELETE CASCADE,
    CONSTRAINT [fk_print_audit_log_branch] FOREIGN KEY ([branch_id])
        REFERENCES [dbo].[branches]([id]) ON DELETE CASCADE,
    CONSTRAINT [fk_print_audit_log_invoice] FOREIGN KEY ([invoice_id])
        REFERENCES [dbo].[invoices]([id]) ON DELETE SET NULL,
    CONSTRAINT [fk_print_audit_log_user] FOREIGN KEY ([requested_by])
        REFERENCES [dbo].[app_users]([id]) ON DELETE SET NULL
);

CREATE INDEX [idx_print_audit_log_organization] ON [dbo].[print_audit_logs]([organization_id]);
CREATE INDEX [idx_print_audit_log_branch] ON [dbo].[print_audit_logs]([branch_id]);
CREATE INDEX [idx_print_audit_log_invoice] ON [dbo].[print_audit_logs]([invoice_id]);
CREATE INDEX [idx_print_audit_log_created] ON [dbo].[print_audit_logs]([created_at]);
