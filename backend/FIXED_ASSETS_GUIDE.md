# نظام إدارة الأصول الثابتة والاهلاك

## نظرة عامة

نظام متكامل لإدارة الأصول الثابتة (Fixed Assets) والاهلاك (Depreciation) في kinetic_erp، يوفر:

- **تسجيل الأصول الثابتة**: مبان، معدات، مركبات، أثاث، إلخ
- **حساب الاهلاك**: بطريقة القسط الثابت (Straight Line) أو التناقص (Declining Balance)
- **تتبع القيمة الدفترية**: القيمة المتبقية للأصل في أي لحظة
- **إدارة بيانات الشركة**: المعلومات القانونية والضريبية والبنكية
- **التقارير المالية**: ملخصات القيمة حسب التصنيف

## الملفات المُضافة

### Models (Models/Entities.cs)
- `FixedAsset` - نموذج الأصل الثابت
- `AssetDepreciation` - نموذج سجل الاهلاك
- `CompanyInfo` - نموذج بيانات الشركة

### DTOs (Models/FixedAssetDtos.cs)
- `FixedAssetDto` - بيانات الأصل (للعرض)
- `CreateFixedAssetRequest` - طلب إنشاء أصل
- `UpdateFixedAssetRequest` - طلب تحديث أصل
- `DepreciationRecordDto` - سجل الاهلاك
- `DepreciationCalculationDto` - نتيجة حساب الاهلاك
- `CompanyInfoDto` - بيانات الشركة
- `AssetsValuationSummaryDto` - ملخص القيمة

### Services (Services/DepreciationService.cs)

خدمة محاسبية توفر:

#### الدوال الرئيسية

```csharp
// حساب الاهلاك للفترة المطلوبة
CalculateDepreciationAsync(assetId, month, year, organizationId)

// تسجيل سجل اهلاك جديد
RecordDepreciationAsync(calculation, organizationId)

// الحصول على سجل الاهلاك الكامل
GetAssetDepreciationHistoryAsync(assetId, organizationId)

// ملخص قيمة الأصول
GetAssetsValuationSummaryAsync(organizationId)

// الأصول المستحقة الاهلاك
GetAssetsRequiringDepreciationAsync(month, year, organizationId)

// وسم سجل كمسجل محاسبياً
MarkDepreciationAsRecordedAsync(depreciationId, journalEntryId, organizationId)
```

### Controllers

#### FixedAssetsController (Controllers/FixedAssetsController.cs)

```
GET    /api/fixed-assets                           - قائمة جميع الأصول
GET    /api/fixed-assets/{id}                      - تفاصيل أصل معين
POST   /api/fixed-assets                           - إنشاء أصل جديد
PUT    /api/fixed-assets/{id}                      - تحديث أصل
DELETE /api/fixed-assets/{id}                      - حذف أصل (soft delete)

GET    /api/fixed-assets/{id}/depreciation         - سجل الاهلاك
POST   /api/fixed-assets/{id}/calculate-depreciation - حساب الاهلاك
POST   /api/fixed-assets/{id}/record-depreciation  - تسجيل الاهلاك

GET    /api/fixed-assets/summary/valuation         - ملخص القيمة
GET    /api/fixed-assets/pending-depreciation      - الأصول المستحقة
```

#### CompanyInfoController (Controllers/CompanyInfoController.cs)

```
GET    /api/company-info                           - بيانات الشركة
PUT    /api/company-info                           - تحديث بيانات الشركة
```

## الجداول المُنشأة

### جدول fixed_assets

```sql
CREATE TABLE fixed_assets (
    id UNIQUEIDENTIFIER PRIMARY KEY,
    organization_id UNIQUEIDENTIFIER NOT NULL,
    asset_name NVARCHAR(255) NOT NULL,
    asset_code NVARCHAR(50) NOT NULL UNIQUE,
    asset_category NVARCHAR(100),
    acquisition_date DATETIME2,
    acquisition_cost DECIMAL(18,2),
    useful_life_years INT,
    residual_value DECIMAL(18,2),
    depreciation_method NVARCHAR(50),
    annual_depreciation_rate DECIMAL(5,2),
    cost_center NVARCHAR(100),
    location NVARCHAR(255),
    is_active BIT,
    disposal_date DATETIME2,
    disposal_amount DECIMAL(18,2),
    status NVARCHAR(50),
    created_at DATETIME2,
    updated_at DATETIME2,
    is_deleted BIT
);
```

### جدول asset_depreciation

```sql
CREATE TABLE asset_depreciation (
    id UNIQUEIDENTIFIER PRIMARY KEY,
    fixed_asset_id UNIQUEIDENTIFIER NOT NULL,
    organization_id UNIQUEIDENTIFIER NOT NULL,
    month INT,
    year INT,
    beginning_value DECIMAL(18,2),
    depreciation_amount DECIMAL(18,2),
    accumulated_depreciation DECIMAL(18,2),
    ending_value DECIMAL(18,2),
    is_recorded BIT,
    journal_entry_id UNIQUEIDENTIFIER,
    created_at DATETIME2,
    updated_at DATETIME2,
    UNIQUE (fixed_asset_id, year, month)
);
```

### جدول company_info

```sql
CREATE TABLE company_info (
    id UNIQUEIDENTIFIER PRIMARY KEY,
    organization_id UNIQUEIDENTIFIER NOT NULL UNIQUE,
    commercial_registry_number NVARCHAR(50),
    tax_number NVARCHAR(50),
    legal_name NVARCHAR(255),
    trade_address NVARCHAR(500),
    foundation_year INT,
    company_type NVARCHAR(100),
    bank_account_number NVARCHAR(50),
    bank_name NVARCHAR(255),
    iban NVARCHAR(50),
    phone NVARCHAR(20),
    email NVARCHAR(255),
    currency_code NVARCHAR(3),
    updated_at DATETIME2
);
```

## أمثلة الاستخدام

### 1. إنشاء أصل ثابت

```json
POST /api/fixed-assets
Content-Type: application/json

{
    "assetName": "ماكينة الإنتاج الرئيسية",
    "assetCode": "MACH-001",
    "assetCategory": "equipment",
    "acquisitionDate": "2024-01-15T00:00:00Z",
    "acquisitionCost": 50000.00,
    "usefulLifeYears": 10,
    "residualValue": 5000.00,
    "depreciationMethod": "straight_line",
    "costCenter": "Production",
    "location": "المصنع الرئيسي"
}
```

**الرد:**
```json
{
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "assetName": "ماكينة الإنتاج الرئيسية",
    "assetCode": "MACH-001",
    "assetCategory": "equipment",
    "acquisitionCost": 50000.00,
    "usefulLifeYears": 10,
    "residualValue": 5000.00,
    "currentBookValue": 50000.00,
    "accumulatedDepreciation": 0.00,
    "status": "active",
    "createdAt": "2025-09-12T10:30:00Z"
}
```

### 2. حساب الاهلاك الشهري

```json
POST /api/fixed-assets/550e8400-e29b-41d4-a716-446655440000/calculate-depreciation
Content-Type: application/json

{
    "month": 9,
    "year": 2025
}
```

**الرد:**
```json
{
    "assetId": "550e8400-e29b-41d4-a716-446655440000",
    "assetName": "ماكينة الإنتاج الرئيسية",
    "month": 9,
    "year": 2025,
    "beginningValue": 50000.00,
    "depreciationAmount": 375.00,
    "accumulatedDepreciation": 375.00,
    "endingValue": 49625.00
}
```

**شرح الحساب:**
- القيمة القابلة للاهلاك = 50000 - 5000 = 45000
- الاهلاك السنوي = 45000 / 10 = 4500
- الاهلاك الشهري = 4500 / 12 = **375**

### 3. تسجيل الاهلاك

```json
POST /api/fixed-assets/550e8400-e29b-41d4-a716-446655440000/record-depreciation
Content-Type: application/json

{
    "month": 9,
    "year": 2025
}
```

**الرد:**
```json
{
    "id": "660e8400-e29b-41d4-a716-446655440001",
    "month": 9,
    "year": 2025,
    "beginningValue": 50000.00,
    "depreciationAmount": 375.00,
    "accumulatedDepreciation": 375.00,
    "endingValue": 49625.00,
    "isRecorded": false,
    "journalEntryId": null,
    "createdAt": "2025-09-12T10:32:00Z"
}
```

### 4. الحصول على سجل الاهلاك

```
GET /api/fixed-assets/550e8400-e29b-41d4-a716-446655440000/depreciation
```

**الرد:**
```json
[
    {
        "id": "660e8400-e29b-41d4-a716-446655440001",
        "month": 9,
        "year": 2025,
        "beginningValue": 50000.00,
        "depreciationAmount": 375.00,
        "accumulatedDepreciation": 375.00,
        "endingValue": 49625.00,
        "isRecorded": false
    }
]
```

### 5. ملخص قيمة الأصول

```
GET /api/fixed-assets/summary/valuation
```

**الرد:**
```json
{
    "totalAcquisitionCost": 150000.00,
    "totalAccumulatedDepreciation": 3750.00,
    "totalNetBookValue": 146250.00,
    "totalAssetsCount": 3,
    "byCategory": {
        "equipment": 100000.00,
        "vehicles": 30000.00,
        "furniture": 20000.00
    }
}
```

### 6. إدارة بيانات الشركة

```json
PUT /api/company-info
Content-Type: application/json

{
    "legalName": "شركة الإنتاج المتقدمة ذ.م.م",
    "commercialRegistryNumber": "LY12345",
    "taxNumber": "LY-987654321",
    "tradeAddress": "طرابلس - شارع الجمهورية",
    "foundationYear": 2015,
    "companyType": "limited_company",
    "bankAccountNumber": "123456789",
    "bankName": "البنك الليبي",
    "iban": "LY12BLLY123456789",
    "phone": "+218912345678",
    "email": "info@company.ly",
    "currencyCode": "LYD"
}
```

## طرق الاهلاك المدعومة

### 1. القسط الثابت (Straight Line)

الصيغة:
```
الاهلاك السنوي = (القيمة الأصلية - القيمة المتبقية) / عدد السنوات
الاهلاك الشهري = الاهلاك السنوي / 12
```

**مثال:**
- القيمة الأصلية: 50,000
- القيمة المتبقية: 5,000
- العمر الافتراضي: 10 سنوات
- **الاهلاك السنوي** = (50,000 - 5,000) / 10 = 4,500
- **الاهلاك الشهري** = 4,500 / 12 = **375**

### 2. التناقص (Declining Balance)

الصيغة:
```
المعدل المئوي = 2 / عدد السنوات (أو معدل مخصص)
الاهلاك الشهري = القيمة الدفترية × المعدل / 12
```

**مثال:**
- القيمة الدفترية الحالية: 50,000
- العمر الافتراضي: 10 سنوات
- المعدل = 2 / 10 = 20%
- **الاهلاك الشهري** = 50,000 × 0.20 / 12 = **833.33**

## الأمان والعزل متعدد المستأجرين

- كل منظمة معزولة بـ `OrganizationId`
- التحقق من الصلاحيات `RequirePermission("fixed_assets.manage")`
- تتبع التغييرات عبر `CreatedBy`, `UpdatedBy`, `CreatedAt`, `UpdatedAt`
- حذف آمن (Soft Delete) عبر `IsDeleted` flag

## الصلاحيات المطلوبة

```
"fixed_assets.manage"    - إنشاء وتعديل وحذف الأصول والاهلاك
"company_info.manage"    - تحديث بيانات الشركة
```

## الإعدادات المتقدمة

### معدل الاهلاك المخصص

للطريقة التناقصية، يمكن تحديد معدل مخصص:

```json
{
    "assetName": "سيارة فريق المبيعات",
    "depreciation_method": "declining_balance",
    "annual_depreciation_rate": 25.0,
    ...
}
```

المعدل بصيغة نسبة مئوية (0-100).

### تحديد القيمة المتبقية

إذا كان الأصل له قيمة متبقية متوقعة (مثل سيارة تُباع بعد 5 سنوات):

```json
{
    "residual_value": 10000.00,
    ...
}
```

النظام يوقف الاهلاك تلقائياً عند الوصول للقيمة المتبقية.

## المقاييس والعمليات الحسابية

### حساب العمر المتبقي

```
الأشهر المتبقية = (العمر الافتراضي - الشهور المنقضية) × 12
```

### حساب الاهلاك حتى تاريخ معين

```
الاهلاك التراكمي = مجموع اهلاك جميع الفترات حتى التاريخ
القيمة الدفترية = القيمة الأصلية - الاهلاك التراكمي
```

## ملاحظات تقنية

1. **العملات والدقة**: جميع المبالغ بـ DECIMAL(18,2) لدقة مالية
2. **المناطق الزمنية**: كل التواريخ بـ UTC، يُحوَّل للمحلي عند العرض
3. **السجلات المنطقية**: لا حذف فعلي، بل `IsDeleted = true`
4. **الفهارس**: مفهرسة حسب التنظيم والحالة والفئة لأداء أفضل

## خطوات التثبيت

1. **تشغيل Migration SQL:**
   ```
   sqlcmd -S localhost -d kinetic_erp -i FixedAssetsMigration.sql
   ```

2. **تحديث DbContext** (تم بالفعل)

3. **إضافة الصلاحيات:**
   ```sql
   INSERT INTO permissions (code, label) VALUES
   ('fixed_assets.manage', 'إدارة الأصول الثابتة والاهلاك'),
   ('company_info.manage', 'إدارة بيانات الشركة');
   ```

4. **تفعيل الوحدة:**
   ```sql
   UPDATE licenses SET enabled_modules = 
   JSON_MODIFY(enabled_modules, 'append $', 'accounting')
   WHERE organization_id = @orgId;
   ```

## استكشاف الأخطاء

### خطأ: "الأصل المطلوب غير موجود"
- تحقق من `organization_id` الصحيح
- تأكد من أن الأصل لم يُحذف

### خطأ: "سجل اهلاك موجود بالفعل لهذه الفترة"
- لا يمكن حساب اهلاك شهري مكرر للأصل نفسه
- استعلم عن السجلات القائمة أولاً

### خطأ: "قيمة الاستحواذ يجب أن تكون موجبة"
- القيمة الأصلية يجب أن تكون > 0

## الدعم والمراجع

للأسئلة أو المشاكل، راجع:
- `Services/DepreciationService.cs` - منطق الاهلاك
- `Controllers/FixedAssetsController.cs` - نقاط النهاية
- `Models/Entities.cs` - هيكل البيانات
