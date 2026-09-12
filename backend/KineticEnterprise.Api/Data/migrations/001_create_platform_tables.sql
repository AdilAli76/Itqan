-- Migration: Create Platform Tables
-- Created: 2026-09-12
-- Purpose: Create platform_organizations, platform_settings, and user_passkeys tables

-- Check if tables exist before creating
IF OBJECT_ID('platform_organizations', 'U') IS NULL
BEGIN
    CREATE TABLE platform_organizations (
        id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        organization_id UNIQUEIDENTIFIER NOT NULL UNIQUE,
        storage_used_mb FLOAT NOT NULL DEFAULT 0,
        backup_path NVARCHAR(500) NULL,
        is_active BIT NOT NULL DEFAULT 1,
        created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE()
    );
    PRINT 'Created table: platform_organizations';
END
ELSE
BEGIN
    PRINT 'Table platform_organizations already exists';
    -- Add is_active column if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'platform_organizations' AND COLUMN_NAME = 'is_active')
    BEGIN
        ALTER TABLE platform_organizations ADD is_active BIT NOT NULL DEFAULT 1;
        PRINT 'Added column: platform_organizations.is_active';
    END
END

IF OBJECT_ID('platform_settings', 'U') IS NULL
BEGIN
    CREATE TABLE platform_settings (
        id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        setting_key NVARCHAR(255) NOT NULL UNIQUE,
        setting_value NVARCHAR(MAX) NULL,
        updated_at DATETIME2 NOT NULL DEFAULT GETUTCDATE()
    );
    PRINT 'Created table: platform_settings';
END
ELSE
    PRINT 'Table platform_settings already exists';

IF OBJECT_ID('user_passkeys', 'U') IS NULL
BEGIN
    CREATE TABLE user_passkeys (
        id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        user_id UNIQUEIDENTIFIER NOT NULL,
        public_key NVARCHAR(MAX) NOT NULL,
        counter INT NOT NULL DEFAULT 0,
        created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE()
    );
    PRINT 'Created table: user_passkeys';
END
ELSE
    PRINT 'Table user_passkeys already exists';
