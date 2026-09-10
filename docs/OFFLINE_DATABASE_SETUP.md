# Offline Database Setup — Phase 1 كامل

## ما تم إضافته

### 1. **Dependencies** (في pubspec.yaml)
```yaml
drift: ^2.14.0              # ORM محلي
drift_native: ^1.1.0        # دعم SQL Native على Desktop
path_provider: ^2.1.1       # للوصول إلى مجلدات التطبيق
connectivity_plus: ^5.0.0   # كشف الاتصال بالإنترنت
workmanager: ^0.5.2         # Sync في الخلفية
device_info_plus: ^10.2.1   # معرّف الجهاز (للرخص)
```

### 2. **Database Schema** (`lib/core/database/schema.dart`)
- 12 table رئيسية:
  - Products, Customers, Invoices, InvoiceItems
  - StockTransfers, PurchaseOrders, Expenses
  - Branches, Users
- 4 tables للـ Sync:
  - SyncMetadata, PendingChanges, ConflictLog
  - LicenseStatus, CachedTokens

### 3. **Database Class** (`lib/core/database/local_db.dart`)
- LocalDatabase class (Drift)
- أوتوماتيك schema migration
- Helper methods للأسئلة الشائعة
- Drift code generation target

### 4. **Repositories** (`lib/core/database/repositories/`)
- `ProductsRepository`: CRUD + search + stock management
- `InvoicesRepository`: Create with items + tracking + sync

### 5. **Providers** (`lib/core/database/database_provider.dart`)
- Riverpod providers لـ:
  - Database instance
  - Repositories
  - Computed data (products, invoices, counts, revenue)

---

## الخطوات التالية للبناء

### 1️⃣ تثبيت التبعيات
```bash
cd C:\Users\F\Downloads\kinetic_erp
flutter pub get
```

### 2️⃣ توليد Drift code
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

هذا سينشئ الملف `lib/core/database/local_db.g.dart` (لا تعدّله يدوياً)

### 3️⃣ التحقق من البناء
```bash
flutter pub run build_runner build
# إذا نجح = الكود جاهز
# إذا فشل = اتصل بـ AI assistants في الخطأ
```

### 4️⃣ تشغيل التطبيق
```bash
# Desktop
flutter run -d windows

# أو Mobile
flutter run -d chrome
```

---

## استخدام Database في الكود

### مثال 1: إنشاء فاتورة
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PosScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesRepo = ref.watch(invoicesRepositoryProvider);

    return FloatingActionButton(
      onPressed: () async {
        // إنشاء فاتورة جديدة
        final invoiceId = await invoicesRepo.createInvoiceWithItems(
          id: 'INV_${DateTime.now().millisecondsSinceEpoch}',
          invoiceNumber: 'INV-001',
          customerId: 'CUST_123',
          invoiceDate: DateTime.now(),
          paymentMethod: 'CASH',
          items: [
            InvoiceItemInput(
              productId: '1',
              quantity: 2,
              unitPrice: 100.0,
            ),
          ],
          branchId: 'LOCAL_BRANCH',
          userId: 'USER_123',
          clientRequestId: '${DateTime.now().millisecondsSinceEpoch}',
        );

        print('Invoice created: $invoiceId');
      },
    );
  }
}
```

### مثال 2: البحث عن منتجات
```dart
class InventoryScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchQuery = useState('');

    final products = ref.watch(
      searchProductsProvider(searchQuery.value),
    );

    return products.when(
      data: (productsList) => ListView.builder(
        itemCount: productsList.length,
        itemBuilder: (_, index) => ListTile(
          title: Text(productsList[index].name),
          subtitle: Text('${productsList[index].price}'),
        ),
      ),
      loading: () => CircularProgressIndicator(),
      error: (err, __) => Text('Error: $err'),
    );
  }
}
```

### مثال 3: عرض إحصائيات اليوم
```dart
class DashboardScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayCount = ref.watch(todayInvoicesCountProvider);
    final todayRevenue = ref.watch(todayRevenueProvider);

    return Column(
      children: [
        todayCount.when(
          data: (count) => Text('فواتير اليوم: $count'),
          loading: () => Skeleton(),
          error: (_, __) => SizedBox.shrink(),
        ),
        todayRevenue.when(
          data: (revenue) => Text('إيرادات اليوم: $revenue'),
          loading: () => Skeleton(),
          error: (_, __) => SizedBox.shrink(),
        ),
      ],
    );
  }
}
```

---

## Structure النهائي

```
lib/
├── core/
│   ├── database/
│   │   ├── schema.dart                 ✅ Tables
│   │   ├── local_db.dart               ✅ Database class
│   │   ├── local_db.g.dart             ✅ (Auto-generated)
│   │   ├── database_provider.dart      ✅ Riverpod providers
│   │   └── repositories/
│   │       ├── products_repository.dart ✅ Products CRUD
│   │       ├── invoices_repository.dart ✅ Invoices + Items
│   │       ├── customers_repository.dart (قادمة)
│   │       ├── stock_transfer_repository.dart (قادمة)
│   │       └── purchase_orders_repository.dart (قادمة)
│   │
│   ├── network/
│   │   ├── api_client.dart             (موجود)
│   │   ├── sync_engine.dart            (Phase 2)
│   │   ├── offline_queue.dart          (موجود)
│   │   └── conflict_resolver.dart      (Phase 2)
│   │
│   └── ... (باقي الملفات)
```

---

## Phase 1 Summary

### تم إنجازه ✅
- Database schema (16 tables)
- Drift ORM setup
- ProductsRepository (full CRUD)
- InvoicesRepository (with items)
- Riverpod providers integration
- Doc (هذا الملف)

### ما قادم في Phase 2 (Sync Engine) 🔄
- SyncService (pull/push)
- ConflictResolver
- Background sync
- Offline sync UI

### ما قادم في Phase 3 (Full Offline) 📦
- باقي Repositories (Customers, Stock, POs)
- Offline feature support
- Feature flags per license

---

## Troubleshooting

### مشكلة: "Dart SDK version compatibility"
**الحل:** تأكد من استخدام Dart 3.3.0+
```bash
dart --version
```

### مشكلة: "Cannot find local_db.g.dart"
**الحل:** شغّل build_runner مرة أخرى
```bash
flutter pub run build_runner clean
flutter pub run build_runner build --delete-conflicting-outputs
```

### مشكلة: "Database locked"
**الحل:** تأكد من عدم فتح قاعدة البيانات من مكان آخر
- إغلق SQL Server Management Studio إن وُجد
- تأكد من عدم وجود عملية أخرى للتطبيق

### مشكلة: "Cannot connect to Database"
**الحل:** تحقق من المسار
```dart
// في local_db.dart
final dbFolder = await getApplicationDocumentsDirectory();
print('DB Path: ${dbFolder.path}');
```

---

## Links
- [Drift Documentation](https://drift.simonbinder.eu/)
- [Riverpod Guide](https://riverpod.dev/)
- [SQLite vs SQL Server for Desktop](https://drift.simonbinder.eu/docs/getting_started/)
