-- ============================================================================
-- نظام إدارة المخزون المتقدم - Migration
-- التاريخ: 2026-09-12
-- ============================================================================

-- جدول الدفعات - تتبع كل دفعة من المنتجات
CREATE TABLE product_batches (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    organization_id UNIQUEIDENTIFIER NOT NULL,
    product_id UNIQUEIDENTIFIER NOT NULL,
    batch_number NVARCHAR(100) NOT NULL,
    manufacturing_date DATETIME2 NOT NULL,
    expiry_date DATETIME2 NULL,
    quantity_received INT NOT NULL DEFAULT 0,
    quantity_available INT NOT NULL DEFAULT 0,
    warehouse_id UNIQUEIDENTIFIER NULL,
    cost_per_unit DECIMAL(18,4) NOT NULL DEFAULT 0,
    supplier_id UNIQUEIDENTIFIER NULL,
    certificate_of_analysis_json NVARCHAR(2000) NULL,
    quality_status NVARCHAR(50) NOT NULL DEFAULT 'pending', -- pending, approved, rejected
    is_deleted BIT NOT NULL DEFAULT 0,
    created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_ProductBatches_Product FOREIGN KEY (product_id) REFERENCES products(id),
    CONSTRAINT FK_ProductBatches_Warehouse FOREIGN KEY (warehouse_id) REFERENCES warehouses(id),
    CONSTRAINT FK_ProductBatches_Organization FOREIGN KEY (organization_id) REFERENCES organizations(id)
);

-- فهارس الأداء على الدفعات
CREATE INDEX IX_ProductBatches_Organization ON product_batches(organization_id) WHERE is_deleted = 0;
CREATE INDEX IX_ProductBatches_Product ON product_batches(product_id) WHERE is_deleted = 0;
CREATE INDEX IX_ProductBatches_Warehouse ON product_batches(warehouse_id) WHERE is_deleted = 0;
CREATE INDEX IX_ProductBatches_ExpiryDate ON product_batches(expiry_date) WHERE is_deleted = 0 AND expiry_date IS NOT NULL;
CREATE UNIQUE INDEX UQ_ProductBatches_BatchNumber ON product_batches(batch_number, organization_id) WHERE is_deleted = 0;

-- جدول الأرقام التسلسلية - تتبع كل قطعة على حدة
CREATE TABLE product_serial_numbers (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    batch_id UNIQUEIDENTIFIER NOT NULL,
    serial_number NVARCHAR(255) NOT NULL,
    barcode NVARCHAR(255) NULL,
    status NVARCHAR(50) NOT NULL DEFAULT 'available', -- available, sold, returned, damaged, recalled
    warehouse_location NVARCHAR(255) NULL,
    sold_at DATETIME2 NULL,
    invoice_id UNIQUEIDENTIFIER NULL,
    created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_SerialNumbers_Batch FOREIGN KEY (batch_id) REFERENCES product_batches(id),
    CONSTRAINT FK_SerialNumbers_Invoice FOREIGN KEY (invoice_id) REFERENCES invoices(id)
);

-- فهارس الأرقام التسلسلية
CREATE INDEX IX_SerialNumbers_Batch ON product_serial_numbers(batch_id);
CREATE INDEX IX_SerialNumbers_SerialNumber ON product_serial_numbers(serial_number);
CREATE INDEX IX_SerialNumbers_Barcode ON product_serial_numbers(barcode);
CREATE INDEX IX_SerialNumbers_Status ON product_serial_numbers(status);

-- جدول حركات الدفعات - سجل الدخول والخروج
CREATE TABLE batch_movements (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    batch_id UNIQUEIDENTIFIER NOT NULL,
    organization_id UNIQUEIDENTIFIER NOT NULL,
    movement_type NVARCHAR(50) NOT NULL, -- receipt, sale, adjustment, transfer, damage, return
    quantity INT NOT NULL,
    reference_type NVARCHAR(50) NULL, -- invoice, transfer, adjustment, return
    reference_id UNIQUEIDENTIFIER NULL,
    from_warehouse_id UNIQUEIDENTIFIER NULL,
    to_warehouse_id UNIQUEIDENTIFIER NULL,
    notes NVARCHAR(500) NULL,
    created_by UNIQUEIDENTIFIER NULL,
    created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_BatchMovements_Batch FOREIGN KEY (batch_id) REFERENCES product_batches(id),
    CONSTRAINT FK_BatchMovements_Organization FOREIGN KEY (organization_id) REFERENCES organizations(id),
    CONSTRAINT FK_BatchMovements_FromWarehouse FOREIGN KEY (from_warehouse_id) REFERENCES warehouses(id),
    CONSTRAINT FK_BatchMovements_ToWarehouse FOREIGN KEY (to_warehouse_id) REFERENCES warehouses(id),
    CONSTRAINT FK_BatchMovements_User FOREIGN KEY (created_by) REFERENCES app_users(id)
);

-- فهارس حركات الدفعات
CREATE INDEX IX_BatchMovements_Batch ON batch_movements(batch_id);
CREATE INDEX IX_BatchMovements_Organization ON batch_movements(organization_id);
CREATE INDEX IX_BatchMovements_CreatedAt ON batch_movements(created_at DESC);
CREATE INDEX IX_BatchMovements_MovementType ON batch_movements(movement_type);

-- جدول قواعد التنبيهات
CREATE TABLE inventory_alert_rules (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    organization_id UNIQUEIDENTIFIER NOT NULL,
    product_id UNIQUEIDENTIFIER NULL, -- NULL = لجميع المنتجات
    alert_type NVARCHAR(50) NOT NULL, -- low_stock, expiring, slow_moving, overstocked
    threshold INT NULL,
    expiry_warning_days INT NULL,
    slow_moving_days INT NULL,
    action_type NVARCHAR(50) NOT NULL DEFAULT 'notification', -- email, notification, auto_po
    is_active BIT NOT NULL DEFAULT 1,
    created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_AlertRules_Organization FOREIGN KEY (organization_id) REFERENCES organizations(id),
    CONSTRAINT FK_AlertRules_Product FOREIGN KEY (product_id) REFERENCES products(id)
);

-- فهارس قواعد التنبيهات
CREATE INDEX IX_AlertRules_Organization ON inventory_alert_rules(organization_id) WHERE is_active = 1;
CREATE INDEX IX_AlertRules_Product ON inventory_alert_rules(product_id) WHERE is_active = 1;

-- جدول سجل التنبيهات
CREATE TABLE inventory_alerts (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    organization_id UNIQUEIDENTIFIER NOT NULL,
    product_id UNIQUEIDENTIFIER NOT NULL,
    alert_type NVARCHAR(50) NOT NULL,
    severity NVARCHAR(20) NOT NULL DEFAULT 'medium', -- low, medium, high, critical
    message NVARCHAR(1000) NOT NULL,
    suggested_action NVARCHAR(1000) NULL,
    is_resolved BIT NOT NULL DEFAULT 0,
    resolved_at DATETIME2 NULL,
    created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_Alerts_Organization FOREIGN KEY (organization_id) REFERENCES organizations(id),
    CONSTRAINT FK_Alerts_Product FOREIGN KEY (product_id) REFERENCES products(id)
);

-- فهارس سجل التنبيهات
CREATE INDEX IX_Alerts_Organization ON inventory_alerts(organization_id) WHERE is_resolved = 0;
CREATE INDEX IX_Alerts_Product ON inventory_alerts(product_id);
CREATE INDEX IX_Alerts_CreatedAt ON inventory_alerts(created_at DESC);
CREATE INDEX IX_Alerts_Severity ON inventory_alerts(severity) WHERE is_resolved = 0;

-- جدول تقييمات المخزون
CREATE TABLE inventory_valuations (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    organization_id UNIQUEIDENTIFIER NOT NULL,
    product_id UNIQUEIDENTIFIER NOT NULL,
    total_quantity INT NOT NULL DEFAULT 0,
    total_cost DECIMAL(18,4) NOT NULL DEFAULT 0,
    average_cost DECIMAL(18,4) NOT NULL DEFAULT 0,
    current_value DECIMAL(18,4) NOT NULL DEFAULT 0,
    calculated_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_Valuations_Organization FOREIGN KEY (organization_id) REFERENCES organizations(id),
    CONSTRAINT FK_Valuations_Product FOREIGN KEY (product_id) REFERENCES products(id),
    CONSTRAINT UQ_Valuations_OrgProduct UNIQUE (organization_id, product_id)
);

-- فهارس التقييمات
CREATE INDEX IX_Valuations_Organization ON inventory_valuations(organization_id);

-- توسيع جداول موجودة
-- إضافة حقول تتبع الدفعات إلى جدول المنتجات
ALTER TABLE products ADD
    enable_batch_tracking BIT NOT NULL DEFAULT 0,
    enable_serial_number_tracking BIT NOT NULL DEFAULT 0,
    require_expiry_date BIT NOT NULL DEFAULT 0,
    minimum_stock_level INT NOT NULL DEFAULT 0,
    reorder_point INT NOT NULL DEFAULT 0,
    maximum_stock_level INT NOT NULL DEFAULT 0;

-- إضافة حقول الموقع إلى جدول المستودعات
ALTER TABLE warehouses ADD
    location_code NVARCHAR(100) NULL,
    latitude INT NULL,
    longitude INT NULL;

-- أضف فهرسة على حقول المنتجات الجديدة للأداء
CREATE INDEX IX_Products_BatchTracking ON products(enable_batch_tracking) WHERE is_deleted = 0;
