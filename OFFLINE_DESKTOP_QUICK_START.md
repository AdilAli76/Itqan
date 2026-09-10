# Offline Desktop — Quick Start Guide

## ✅ Phase 1 Complete: Local Database

تم إضافة قاعدة بيانات محلية كاملة لتطبيق Kinetic Desktop بـ Drift ORM.

---

## 🚀 البدء الآن

### الخطوة 1: تثبيت التبعيات
```bash
cd C:\Users\F\Downloads\kinetic_erp
flutter pub get
```

### الخطوة 2: توليد Drift Code
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

**ملاحظة:** قد يستغرق 1-2 دقيقة في أول مرة. ستشاهد:
```
[INFO] Running build...
[INFO] Generating Dart code...
[INFO] Build completed successfully
```

### الخطوة 3: التحقق
```bash
flutter doctor
flutter analyze
```

### الخطوة 4: تشغيل التطبيق (Desktop)
```bash
flutter run -d windows
```

أو للـ Chrome:
```bash
flutter run -d chrome --dart-define=API_BASE_URL=https://localhost:5001/api
```

---

## 📊 ما تم إنجازه

### ✅ Completed
- [ ] Database Schema (16 tables)
- [ ] Drift ORM Integration
- [ ] Products Repository
- [ ] Invoices Repository  
- [ ] Riverpod Providers
- [ ] Documentation

### 🔄 Next: Phase 2 (Sync Engine)
- [ ] DeltaSync Service
- [ ] Pull/Push Logic
- [ ] Conflict Resolution
- [ ] Background Sync

### 📦 Then: Phase 3 (Full Offline)
- [ ] Inventory Management
- [ ] Purchase Orders
- [ ] Expenses
- [ ] Stock Transfers
- [ ] Accounting

---

## 📝 الملفات الجديدة

```
lib/core/database/
├── schema.dart                          ← الجداول
├── local_db.dart                        ← قاعدة البيانات
├── database_provider.dart               ← Riverpod providers
└── repositories/
    ├── products_repository.dart         ← منتجات
    └── invoices_repository.dart         ← فواتير
```

---

## 💡 استخدام سريع

### في أي شاشة:
```dart
class MyScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. اختر البيانات
    final products = ref.watch(allProductsProvider);
    
    // 2. استخدمها
    return products.when(
      data: (list) => ListView.builder(
        itemCount: list.length,
        itemBuilder: (_, i) => Text(list[i].name),
      ),
      loading: () => CircularProgressIndicator(),
      error: (err, __) => Text('Error: $err'),
    );
  }
}
```

---

## 🐛 إذا حدثت مشاكل

### "Cannot find local_db.g.dart"
```bash
flutter pub run build_runner clean
flutter pub run build_runner build --delete-conflicting-outputs
```

### "Drift version mismatch"
```bash
flutter pub upgrade
flutter pub run build_runner build
```

### "Database locked"
```bash
# أغلق أي نافذة SQL Server Management Studio
# أو أعد تشغيل التطبيق
```

---

## 📖 الوثائق
- [`docs/OFFLINE_DATABASE_SETUP.md`](docs/OFFLINE_DATABASE_SETUP.md) — شرح مفصل
- [`docs/OFFLINE_DESKTOP_ARCHITECTURE.md`](../OFFLINE_DESKTOP_ARCHITECTURE.md) — المعمارية الكاملة

---

## ⏭️ الخطوة التالية
بعد تشغيل هذا بنجاح، نبدأ **Phase 2: Sync Engine** وهي تحتوي على:
- DeltaSync Service (تنزيل/رفع تغييرات)
- Conflict Resolver (حل التضارب)
- Background Sync (مزامنة في الخلفية)

**احفظ هذا الملف** وأرسل اللقطة الأولى للتطبيق لنتأكد من البناء ✅

---

**Last Updated**: 2026-09-10
**Status**: Ready for Phase 2 ✅
