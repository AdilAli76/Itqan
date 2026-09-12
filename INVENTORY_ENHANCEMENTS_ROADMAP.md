# 🗺️ خارطة طريق تحسينات المخزون - Kinetic ERP

**التاريخ:** 2026-09-12  
**الهدف:** إضافة ميزات متقدمة للمخزون بناءً على تحليل dan-erp.com

---

## 📋 الميزات المقترحة

### 🔴 **المرحلة الأولى - الأولويات العالية (High Priority)**

**المدة المقدرة:** 2-3 أسابيع

#### 1. تتبع الدفعات والأرقام التسلصلية (Batch/Serial Tracking)

**الوصف:**
- تتبع كامل لكل دفعة من المنتجات
- الرقم التسلسلي الفريد لكل قطعة
- تاريخ الإنتاج والانتهاء (Expiry)
- تاريخ انتهاء الصلاحية

**الجداول المطلوبة:**
```sql
-- جدول تتبع الدفعات
CREATE TABLE product_batches (
    id GUID PRIMARY KEY,
    product_id GUID,
    batch_number VARCHAR(100) UNIQUE,
    serial_numbers JSON,
    manufacturing_date DATETIME2,
    expiry_date DATETIME2,
    quantity_received INT,
    quantity_available INT,
    warehouse_id GUID,
    cost_per_unit DECIMAL(18,2),
    created_at DATETIME2,
    updated_at DATETIME2
);

-- جدول الحركات بالدفعات
CREATE TABLE batch_movements (
    id GUID PRIMARY KEY,
    batch_id GUID,
    movement_type VARCHAR(50), -- 'in', 'out', 'adjustment'
    quantity INT,
    reference_id GUID, -- فاتورة، أمر تحويل، إلخ
    reference_type VARCHAR(50),
    reason VARCHAR(500),
    created_by GUID,
    created_at DATETIME2
);
```

**API Endpoints:**
```
GET    /api/inventory/batches
GET    /api/inventory/batches/{id}
POST   /api/inventory/batches
PUT    /api/inventory/batches/{id}
GET    /api/inventory/batches/{id}/movements
POST   /api/inventory/batches/{id}/adjust
GET    /api/inventory/batches/expiring-soon
POST   /api/inventory/batches/{id}/track-serial
```

**واجهة المستخدم:**
```
شاشة "إدارة الدفعات":
├─ [➕ دفعة جديدة]
├─ البحث عن دفعة
├─ قائمة الدفعات
│  ├─ رقم الدفعة
│  ├─ المنتج
│  ├─ التاريخ
│  ├─ الكمية المتاحة
│  ├─ تاريخ الانتهاء
│  └─ الإجراءات
└─ تقرير الدفعات القريبة من الانتهاء
```

---

#### 2. نظام التنبيهات والتحذيرات (Alerts & Warnings System)

**الوصف:**
- تنبيهات تلقائية للمخزون المنخفض
- تنبيهات انتهاء الصلاحية
- توصيات الشراء التلقائية
- تنبيهات المخزون الراكد

**الجداول المطلوبة:**
```sql
-- إعدادات التنبيهات
CREATE TABLE inventory_alert_settings (
    id GUID PRIMARY KEY,
    organization_id GUID,
    product_id GUID,
    alert_type VARCHAR(50), -- 'low_stock', 'expiring', 'slow_moving', 'overstocked'
    minimum_quantity INT,
    reorder_point INT,
    expiry_warning_days INT,
    slow_moving_days INT,
    is_active BIT,
    created_at DATETIME2,
    updated_at DATETIME2
);

-- سجل التنبيهات
CREATE TABLE inventory_alerts (
    id GUID PRIMARY KEY,
    organization_id GUID,
    product_id GUID,
    alert_type VARCHAR(50),
    severity VARCHAR(20), -- 'low', 'medium', 'high', 'critical'
    message NVARCHAR(MAX),
    suggested_action NVARCHAR(MAX),
    is_resolved BIT,
    resolved_at DATETIME2,
    created_at DATETIME2
);
```

**الميزات:**
```
✅ تنبيهات في الوقت الفعلي
✅ تنبيهات عبر البريد الإلكتروني
✅ تنبيهات في لوحة البيانات
✅ توصيات الشراء التلقائية
✅ إجراءات سريعة (إنشاء PO تلقائياً)
```

**API Endpoints:**
```
GET    /api/inventory/alerts
GET    /api/inventory/alerts/{id}
POST   /api/inventory/alerts/{id}/resolve
GET    /api/inventory/alerts/summary
POST   /api/inventory/alerts/settings
PUT    /api/inventory/alerts/settings/{id}
GET    /api/inventory/alerts/recommendations
```

---

#### 3. إدارة المستودعات المتعددة (Multi-Warehouse Management)

**الوصف:**
- دعم كامل لعدة مستودعات
- نقل المخزون بين المستودعات
- توازن المخزون التلقائي
- تتبع الموقع الجغرافي

**تحسينات الجداول:**
```sql
-- تحديث جدول المخزون
ALTER TABLE stock_levels ADD warehouse_id GUID;
ALTER TABLE stock_levels ADD location_code VARCHAR(100);
ALTER TABLE stock_levels ADD shelf_number VARCHAR(50);

-- جدول تحويل المخزون
CREATE TABLE stock_transfers (
    id GUID PRIMARY KEY,
    from_warehouse_id GUID,
    to_warehouse_id GUID,
    transfer_date DATETIME2,
    expected_delivery_date DATETIME2,
    actual_delivery_date DATETIME2,
    status VARCHAR(50), -- 'pending', 'in_transit', 'received', 'cancelled'
    created_by GUID,
    created_at DATETIME2,
    updated_at DATETIME2
);

-- تفاصيل تحويل المخزون
CREATE TABLE stock_transfer_items (
    id GUID PRIMARY KEY,
    transfer_id GUID,
    product_id GUID,
    batch_id GUID,
    quantity INT,
    quantity_received INT,
    notes NVARCHAR(500)
);
```

**API Endpoints:**
```
GET    /api/inventory/warehouses
GET    /api/inventory/warehouses/{id}/stock
GET    /api/inventory/transfers
POST   /api/inventory/transfers
PUT    /api/inventory/transfers/{id}
POST   /api/inventory/transfers/{id}/receive
GET    /api/inventory/transfers/{id}/status
POST   /api/inventory/stock/rebalance
```

---

### 🟡 **المرحلة الثانية - الأولويات المتوسطة (Medium Priority)**

**المدة المقدرة:** 3-4 أسابيع

#### 4. قوائم الأسعار الديناميكية (Dynamic Price Lists)

**الميزات:**
```
✅ أسعار مختلفة لعملاء مختلفين
✅ أسعار موسمية وترويجية
✅ خصومات بناءً على الكمية (Tiered Pricing)
✅ أسعار حسب الفئة أو المستودع
✅ سياسات التسعير التلقائية
```

**الجداول:**
```sql
CREATE TABLE price_lists (
    id GUID PRIMARY KEY,
    organization_id GUID,
    name VARCHAR(255),
    description NVARCHAR(MAX),
    customer_group_id GUID,
    effective_from DATETIME2,
    effective_to DATETIME2,
    priority INT,
    is_active BIT,
    created_at DATETIME2
);

CREATE TABLE price_list_items (
    id GUID PRIMARY KEY,
    price_list_id GUID,
    product_id GUID,
    cost_price DECIMAL(18,2),
    selling_price DECIMAL(18,2),
    discount_percentage DECIMAL(5,2),
    min_quantity INT,
    max_quantity INT
);
```

---

#### 5. تقارير المخزون المتقدمة (Advanced Inventory Reports)

**التقارير المطلوبة:**

```
📊 1. تقرير حركة المخزون (Movement Report)
   - الفترة الزمنية: يومي/أسبوعي/شهري
   - الكمية الداخلة والخارجة
   - الأرصدة الحالية
   - تحليل الاتجاهات

📊 2. تقرير المنتجات الراكدة (Slow-Moving Products)
   - منتجات لم تُباع لفترة طويلة
   - توصيات التصفية أو الترويج
   - التأثير على الربحية

📊 3. تقرير المخزون المتقادم (Aging Report)
   - منتجات قديمة في المستودع
   - تكاليف التخزين المتراكمة
   - توصيات الاستبعاد

📊 4. تقرير دقة المخزون (Inventory Accuracy)
   - مقارنة الجرد النظري والفعلي
   - نسب الدقة حسب المنتج/الفئة
   - أسباب الفروقات

📊 5. تقرير قيمة المخزون (Valuation Report)
   - إجمالي قيمة المخزون
   - تحليل حسب الفئة/المستودع
   - التغييرات الشهرية

📊 6. تقرير دورة رأس المال العامل (Working Capital)
   - أيام المخزون المتوسط (DIO)
   - معدل دوران المخزون
   - التنبؤات المستقبلية
```

---

### 🟢 **المرحلة الثالثة - التحسينات المستقبلية (Future Enhancements)**

**المدة المقدرة:** 4-6 أسابيع

#### 6. التنبؤ بالطلب (Demand Forecasting)

- استخدام الذكاء الاصطناعي للتنبؤ
- تحليل الأنماط التاريخية
- توصيات الشراء الذكية
- تقليل المخزون الزائد

#### 7. إعادة الترتيب التلقائي (Automatic Reordering)

- إنشاء أوامر شراء تلقائية
- تحديد أفضل الموردين
- تحسين التكاليف والمهل الزمنية
- إدارة المستويات الآمنة

#### 8. إدارة دورة حياة المنتج (Product Lifecycle)

- تتبع من الإطلاق إلى الإيقاف
- إدارة النسخ والتحديثات
- توثيق تغييرات الصيغة
- إرشادات الانتقال

---

## 🎯 جدول التنفيذ

```
┌─────────────────────────────────────────────────────────┐
│        الأسبوع 1-2: تتبع الدفعات والتسلسلي          │
├─────────────────────────────────────────────────────────┤
│        الأسبوع 3-4: نظام التنبيهات والتحذيرات       │
├─────────────────────────────────────────────────────────┤
│      الأسبوع 5-6: إدارة المستودعات المتعددة        │
├─────────────────────────────────────────────────────────┤
│        الأسبوع 7-10: التقارير المتقدمة             │
├─────────────────────────────────────────────────────────┤
│      الأسبوع 11-12: قوائم الأسعار الديناميكية      │
└─────────────────────────────────────────────────────────┘
```

---

## 📊 تقدير الجهود

| الميزة | المدة | الصعوبة | التأثير |
|--------|------|--------|--------|
| تتبع الدفعات | 2 أسابيع | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| التنبيهات | 1 أسبوع | ⭐⭐ | ⭐⭐⭐⭐ |
| المستودعات | 1.5 أسبوع | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| التقارير | 2 أسابيع | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| الأسعار | 1 أسبوع | ⭐⭐ | ⭐⭐⭐ |

---

## 💰 تقدير الموارد

```
👨‍💻 مهندس Backend: 8 أسابيع (50% من وقته)
👩‍💻 مهندسة Frontend: 6 أسابيع (40% من وقته)
🧪 مهندس QA: 4 أسابيع (30% من وقته)
📊 محلل أعمال: أسبوع واحد (20% من وقته)
```

---

## ✅ معايير الاستقبال

### لكل ميزة:

```
☑️ جميع الوحدات الحسابية مُختبرة
☑️ جميع رسائل الخطأ واضحة بالعربية
☑️ الأداء مقبول (< 2 ثوانية)
☑️ توثيق شامل
☑️ اختبارات تكامل كاملة
☑️ موافقة المستخدم النهائي
```

---

## 🚀 الخطوات الفورية

### هذا الأسبوع:

1. ✅ عقد اجتماع مع فريق الهندسة
2. ✅ تفصيل متطلبات قاعدة البيانات
3. ✅ تصميم واجهات المستخدم
4. ✅ بدء التطوير - المرحلة الأولى

### الأسبوع القادم:

1. 📌 مراجعة الكود الأول
2. 📌 اختبار الوحدات
3. 📌 بناء النسخة الأولية

---

## 📞 التواصل والملاحظات

**المالك:** فريق الهندسة  
**التاريخ:** 2026-09-12  
**الحالة:** مخطط للموافقة

---

*تم إنشاء هذه الخارطة بناءً على تحليل dan-erp.com والاحتياجات المحددة*
