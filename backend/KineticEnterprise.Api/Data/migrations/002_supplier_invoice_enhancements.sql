-- Migration: Supplier Invoice Enhancements
-- Created: 2026-09-12
-- Purpose: Add support for new products, selling prices, and expenses in supplier invoices

-- Add SellingPrice to SupplierInvoiceLine
IF OBJECT_ID('supplier_invoice_lines', 'U') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'supplier_invoice_lines' AND COLUMN_NAME = 'selling_price')
    BEGIN
        ALTER TABLE supplier_invoice_lines ADD selling_price DECIMAL(18, 2) NULL;
        PRINT 'Added column: supplier_invoice_lines.selling_price';
    END
    ELSE
    BEGIN
        PRINT 'Column supplier_invoice_lines.selling_price already exists';
    END

    -- Make PurchaseReceiptItemId nullable to support new products
    -- First check if the constraint exists and drop it
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
               WHERE TABLE_NAME = 'supplier_invoice_lines'
               AND CONSTRAINT_TYPE = 'UNIQUE'
               AND CONSTRAINT_NAME = 'uq_supplier_invoice_lines_receipt_item')
    BEGIN
        ALTER TABLE supplier_invoice_lines DROP CONSTRAINT uq_supplier_invoice_lines_receipt_item;
        PRINT 'Dropped constraint: uq_supplier_invoice_lines_receipt_item';
    END

    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'supplier_invoice_lines' AND COLUMN_NAME = 'purchase_receipt_item_id')
    BEGIN
        ALTER TABLE supplier_invoice_lines ALTER COLUMN purchase_receipt_item_id UNIQUEIDENTIFIER NULL;
        PRINT 'Made column nullable: supplier_invoice_lines.purchase_receipt_item_id';
    END
END
ELSE
BEGIN
    PRINT 'Table supplier_invoice_lines does not exist - skipping modifications';
END

-- Create SupplierInvoiceExpense table
IF OBJECT_ID('supplier_invoice_expenses', 'U') IS NULL
BEGIN
    IF OBJECT_ID('supplier_invoices', 'U') IS NOT NULL
    BEGIN
        CREATE TABLE supplier_invoice_expenses (
            id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
            supplier_invoice_id UNIQUEIDENTIFIER NOT NULL,
            name NVARCHAR(255) NOT NULL,
            amount DECIMAL(18, 2) NOT NULL,
            FOREIGN KEY (supplier_invoice_id) REFERENCES supplier_invoices(id) ON DELETE CASCADE
        );
        PRINT 'Created table: supplier_invoice_expenses';

        CREATE INDEX idx_supplier_invoice_expenses_invoice ON supplier_invoice_expenses(supplier_invoice_id);
        PRINT 'Created index: idx_supplier_invoice_expenses_invoice';
    END
    ELSE
    BEGIN
        PRINT 'Table supplier_invoices does not exist - cannot create supplier_invoice_expenses';
    END
END
ELSE
    PRINT 'Table supplier_invoice_expenses already exists';
