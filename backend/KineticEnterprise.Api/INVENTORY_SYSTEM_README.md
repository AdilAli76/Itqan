# نظام إدارة المخزون المتقدم - Advanced Inventory Management System

## نظرة عامة

نظام متكامل لإدارة المخزون يشمل:
- **تتبع الدفعات** (Batch Tracking): تسجيل كل دفعة من المنتجات بشكل مستقل
- **الأرقام التسلسلية** (Serial Numbers): تتبع كل وحدة على حدة
- **حركات المخزون** (Batch Movements): سجل كامل لجميع العمليات
- **التنبيهات الذكية** (Smart Alerts): تنبيهات تلقائية للمخزون المنخفض والصلاحيات المنتهية
- **تحويلات المستودعات** (Stock Transfers): نقل المخزون بين المستودعات
- **التقييمات والتقارير** (Valuations & Reports): تقارير شاملة عن قيمة المخزون

## المكونات الرئيسية

### 1. **النماذج (Models)**

#### ProductBatch
تمثل دفعة واحدة من المنتج:
```csharp
public class ProductBatch
{
    public Guid Id { get; set; }
    public string BatchNumber { get; set; }
    public DateTime ManufacturingDate { get; set; }
    public DateTime? ExpiryDate { get; set; }
    public int QuantityAvailable { get; set; }
    public decimal CostPerUnit { get; set; }
    public string QualityStatus { get; set; } // pending, approved, rejected
}
```

#### ProductSerialNumber
تمثل رقم تسلسلي لوحدة واحدة:
```csharp
public class ProductSerialNumber
{
    public string SerialNumber { get; set; }
    public string? Barcode { get; set; }
    public string Status { get; set; } // available, sold, returned, damaged, recalled
}
```

#### BatchMovement
تسجيل كل حركة (دخول/خروج):
```csharp
public class BatchMovement
{
    public string MovementType { get; set; } // receipt, sale, adjustment, transfer, damage, return
    public int Quantity { get; set; }
    public DateTime CreatedAt { get; set; }
}
```

### 2. **الخدمات (Services)**

#### InventoryService
- `CreateBatchAsync`: إنشاء دفعة جديدة
- `AddSerialNumbersAsync`: إضافة أرقام تسلسلية
- `RecordBatchMovementAsync`: تسجيل حركة
- `GetInventoryValuationAsync`: حساب قيمة المخزون
- `GetExpiringProductsAsync`: المنتجات القريبة من انتهاء الصلاحية
- `GetLowStockProductsAsync`: المنتجات ذات المخزون المنخفض
- `GetSlowMovingProductsAsync`: المنتجات البطيئة الحركة

#### InventoryAlertService
- `CheckBatchAlertsAsync`: فحص ومعالجة التنبيهات
- `CreateAlertRuleAsync`: إنشاء قاعدة تنبيه
- `GetUnresolvedAlertsAsync`: الحصول على التنبيهات المعلقة
- `GetInventoryDashboardAsync`: لوحة قيادة المخزون

### 3. **API Endpoints**

#### إدارة الدفعات
```
POST   /api/inventories/batches
GET    /api/inventories/batches/{id}
GET    /api/inventories/products/{productId}/batches
PUT    /api/inventories/batches/{id}
DELETE /api/inventories/batches/{id}
```

#### الأرقام التسلسلية
```
POST /api/inventories/batches/{batchId}/serials
GET  /api/inventories/batches/{batchId}/serials
```

#### حركات المخزون
```
POST /api/inventories/batches/{batchId}/movements
GET  /api/inventories/batches/{batchId}/movements
```

#### التحويلات بين المستودعات
```
POST /api/inventories/transfers
GET  /api/inventories/transfers/{id}
POST /api/inventories/transfers/{id}/receive
```

#### التقارير والتنبيهات
```
GET /api/inventories/valuation
GET /api/inventories/expiring?days=30
GET /api/inventories/low-stock
GET /api/inventories/slow-moving?days=90
GET /api/inventories/alerts
GET /api/inventories/dashboard
```

## قواعد التنبيهات

تدعم النظام 4 أنواع من التنبيهات:

### 1. **Low Stock Alert** (مخزون منخفض)
ينشط عندما يصل المخزون أقل من الحد الأدنى المحدد.

### 2. **Expiring Alert** (قرب انتهاء الصلاحية)
ينشط عندما يكون تاريخ انتهاء الصلاحية قريب (30 يوم افتراضياً).

### 3. **Slow Moving Alert** (حركة بطيئة)
ينشط عندما لا تحصل حركة على المنتج لفترة (90 يوم افتراضياً).

### 4. **Overstocked Alert** (إفراط في التخزين)
ينشط عندما يتجاوز المخزون الحد الأقصى المحدد.

## أنواع الحركات

| النوع | الوصف |
|------|-------|
| receipt | استقبال من المورد |
| sale | بيع للعميل |
| adjustment | تعديل يدوي |
| transfer | تحويل بين المستودعات |
| damage | تسجيل تلف |
| return | استرجاع من العميل |

## حالات الأرقام التسلصلية

| الحالة | الوصف |
|-------|-------|
| available | متاح للبيع |
| sold | تم بيعه |
| returned | تم استرجاعه |
| damaged | تالف |
| recalled | مسحوب من السوق |

## قواعد الأمان والصلاحيات

جميع العمليات محمية بـ RBAC:

```csharp
[RequireModule("inventory")]      // يتطلب تفعيل وحدة المخزون
[RequirePermission("create_batch")] // يتطلب صلاحية محددة
```

الصلاحيات المدعومة:
- `create_batch`: إنشاء دفعة
- `view_batch`: عرض الدفعات
- `edit_batch`: تعديل الدفعات
- `delete_batch`: حذف الدفعات
- `create_serial`: إضافة أرقام تسلسلية
- `view_serial`: عرض الأرقام التسلسلية
- `record_movement`: تسجيل الحركات
- `view_movement`: عرض الحركات
- `create_transfer`: إنشاء تحويلات
- `receive_transfer`: استقبال تحويل
- `view_transfer`: عرض التحويلات
- `manage_alerts`: إدارة التنبيهات
- `view_alerts`: عرض التنبيهات
- `view_reports`: عرض التقارير
- `view_dashboard`: عرض لوحة القيادة

## التفاعل مع المخزون

### مثال 1: إنشاء دفعة جديدة
```csharp
var request = new CreateBatchRequest(
    ProductId: productId,
    BatchNumber: "BATCH-001",
    ManufacturingDate: DateTime.Now,
    ExpiryDate: DateTime.Now.AddMonths(12),
    QuantityReceived: 100,
    CostPerUnit: 50.00m,
    WarehouseId: warehouseId,
    SupplierId: supplierId
);

var batch = await _inventoryService.CreateBatchAsync(orgId, request);
```

### مثال 2: تسجيل حركة بيع
```csharp
await _inventoryService.RecordBatchMovementAsync(
    organizationId: orgId,
    batchId: batchId,
    movementType: "sale",
    quantity: 10,
    referenceType: "invoice",
    referenceId: invoiceId
);
```

### مثال 3: الحصول على التقييم الكلي
```csharp
var valuation = await _inventoryService.GetInventoryValuationAsync(orgId);
Console.WriteLine($"Total Value: {valuation.TotalCurrentValue}");
```

## قاعدة البيانات

تم إنشاء 6 جداول رئيسية:

1. **product_batches** - الدفعات
2. **product_serial_numbers** - الأرقام التسلصلية
3. **batch_movements** - حركات الدفعات
4. **inventory_alert_rules** - قواعد التنبيهات
5. **inventory_alerts** - سجل التنبيهات
6. **inventory_valuations** - تقييمات المخزون

تم أيضاً توسيع جداول موجودة:
- **products**: إضافة حقول التتبع (enable_batch_tracking, require_expiry_date, إلخ)
- **warehouses**: إضافة حقول الموقع (location_code, latitude, longitude)

## نقاط الأداء والتحسينات المستقبلية

### التحسينات المخطط لها:
1. ✅ تتبع الدفعات والأرقام التسلسلية
2. ✅ التنبيهات الذكية الآلية
3. 🔄 واجهة ويب لإدارة المخزون
4. 🔄 تكامل مع نقاط البيع (POS)
5. 🔄 توقعات الطلب الآلية (AI)
6. 🔄 تطبيق الهاتف المحمول
7. 🔄 نقل PDF للتقارير

## الأداء والقيود

- الفهارس محسنة لسرعة البحث
- استخدام Soft Delete لسهولة الاسترجاع
- Multi-tenancy عبر OrganizationId
- دعم العمليات غير المتزامنة (Async/Await)

## الدعم والتطوير

للإبلاغ عن مشاكل أو اقتراح تحسينات، يرجى التواصل مع فريق التطوير.

---

**الإصدار**: 1.0  
**آخر تحديث**: 2026-09-12  
**الحالة**: جاهز للإنتاج ✅
