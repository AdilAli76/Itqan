-- ── نظام إدارة الأصول الثابتة والاهلاك ─────────────────────────────────
-- Migration for Fixed Assets and Depreciation System
-- Version: 2025-09-12

-- جدول الأصول الثابتة (Fixed Assets)
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[fixed_assets]') AND type in (N'U'))
BEGIN
    CREATE TABLE [dbo].[fixed_assets] (
        [id] UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
        [organization_id] UNIQUEIDENTIFIER NOT NULL,
        [asset_name] NVARCHAR(255) NOT NULL,
        [asset_code] NVARCHAR(50) NOT NULL,
        [asset_category] NVARCHAR(100) NOT NULL,
        [acquisition_date] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        [acquisition_cost] DECIMAL(18, 2) NOT NULL,
        [useful_life_years] INT NOT NULL,
        [residual_value] DECIMAL(18, 2) NOT NULL DEFAULT 0,
        [depreciation_method] NVARCHAR(50) NOT NULL DEFAULT 'straight_line',
        [annual_depreciation_rate] DECIMAL(5, 2) NOT NULL DEFAULT 0,
        [cost_center] NVARCHAR(100),
        [location] NVARCHAR(255),
        [is_active] BIT NOT NULL DEFAULT 1,
        [disposal_date] DATETIME2,
        [disposal_amount] DECIMAL(18, 2),
        [status] NVARCHAR(50) NOT NULL DEFAULT 'active',
        [created_by] UNIQUEIDENTIFIER,
        [created_at] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        [updated_by] UNIQUEIDENTIFIER,
        [updated_at] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        [is_deleted] BIT NOT NULL DEFAULT 0,

        CONSTRAINT [PK_fixed_assets] PRIMARY KEY ([id])
    );

    CREATE UNIQUE INDEX [UQ_asset_code_org] ON [dbo].[fixed_assets] ([asset_code], [organization_id]) WHERE [is_deleted] = 0;
    CREATE INDEX [IX_fixed_assets_organization] ON [dbo].[fixed_assets] ([organization_id]) WHERE [is_deleted] = 0;
    CREATE INDEX [IX_fixed_assets_status] ON [dbo].[fixed_assets] ([status], [organization_id]) WHERE [is_deleted] = 0;
    CREATE INDEX [IX_fixed_assets_category] ON [dbo].[fixed_assets] ([asset_category], [organization_id]) WHERE [is_deleted] = 0;

    PRINT 'جدول fixed_assets تم إنشاؤه بنجاح';
END
ELSE
BEGIN
    PRINT 'جدول fixed_assets موجود بالفعل';
END
GO

-- جدول الاهلاك (Asset Depreciation)
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[asset_depreciation]') AND type in (N'U'))
BEGIN
    CREATE TABLE [dbo].[asset_depreciation] (
        [id] UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
        [fixed_asset_id] UNIQUEIDENTIFIER NOT NULL,
        [organization_id] UNIQUEIDENTIFIER NOT NULL,
        [month] INT NOT NULL,
        [year] INT NOT NULL,
        [beginning_value] DECIMAL(18, 2) NOT NULL,
        [depreciation_amount] DECIMAL(18, 2) NOT NULL,
        [accumulated_depreciation] DECIMAL(18, 2) NOT NULL,
        [ending_value] DECIMAL(18, 2) NOT NULL,
        [is_recorded] BIT NOT NULL DEFAULT 0,
        [journal_entry_id] UNIQUEIDENTIFIER,
        [created_at] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        [updated_at] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),

        CONSTRAINT [PK_asset_depreciation] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_asset_depreciation_period] UNIQUE ([fixed_asset_id], [year], [month])
    );

    CREATE INDEX [IX_asset_depreciation_fixed_asset] ON [dbo].[asset_depreciation] ([fixed_asset_id]);
    CREATE INDEX [IX_asset_depreciation_organization] ON [dbo].[asset_depreciation] ([organization_id]);
    CREATE INDEX [IX_asset_depreciation_period] ON [dbo].[asset_depreciation] ([year], [month], [organization_id]);
    CREATE INDEX [IX_asset_depreciation_recorded] ON [dbo].[asset_depreciation] ([is_recorded]) WHERE [is_recorded] = 0;

    PRINT 'جدول asset_depreciation تم إنشاؤه بنجاح';
END
ELSE
BEGIN
    PRINT 'جدول asset_depreciation موجود بالفعل';
END
GO

-- جدول بيانات الشركة (Company Info)
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[company_info]') AND type in (N'U'))
BEGIN
    CREATE TABLE [dbo].[company_info] (
        [id] UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
        [organization_id] UNIQUEIDENTIFIER NOT NULL,
        [commercial_registry_number] NVARCHAR(50),
        [tax_number] NVARCHAR(50),
        [legal_name] NVARCHAR(255) NOT NULL,
        [trade_address] NVARCHAR(500),
        [foundation_year] INT,
        [company_type] NVARCHAR(100),
        [bank_account_number] NVARCHAR(50),
        [bank_name] NVARCHAR(255),
        [iban] NVARCHAR(50),
        [phone] NVARCHAR(20),
        [email] NVARCHAR(255),
        [currency_code] NVARCHAR(3),
        [updated_at] DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        [updated_by] UNIQUEIDENTIFIER,

        CONSTRAINT [PK_company_info] PRIMARY KEY ([id]),
        CONSTRAINT [UQ_company_info_org] UNIQUE ([organization_id])
    );

    CREATE INDEX [IX_company_info_organization] ON [dbo].[company_info] ([organization_id]);

    PRINT 'جدول company_info تم إنشاؤه بنجاح';
END
ELSE
BEGIN
    PRINT 'جدول company_info موجود بالفعل';
END
GO

-- رسالة إتمام
PRINT '✓ نظام إدارة الأصول الثابتة والاهلاك تم تثبيته بنجاح';
