# 🧪 اختبر LocalDatabase الآن!

## ⚡ البدء السريع

### الخطوة 1: فتح Terminal

```bash
# Windows: اضغط Windows + R
# اكتب: cmd
# اضغط: Enter

# أو من VS Code:
# Ctrl + Shift + ` (grave accent)
```

### الخطوة 2: انتقل للمشروع

```bash
cd C:\Users\F\Downloads\itqan_erp
```

### الخطوة 3: شغّل التطبيق

```bash
flutter run
```

### الخطوة 4: انتظر إلى أن ترى الشاشة

```
تحديث ...
Building...
Installing and launching...
```

---

## 🎨 ستظهر شاشة اختبار تفاعلية

### الشاشة ستحتوي على:

```
┌─────────────────────────────────────────┐
│  اختبار قاعدة البيانات المحلية          │
├─────────────────────────────────────────┤
│                                         │
│  [السجل المحلي يظهر هنا]                │
│                                         │
│  📋 اختبار LocalDatabase               │
│                                         │
│  ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅                  │
│  الأزرار (اضغط على أي زر)             │
│                                         │
└─────────────────────────────────────────┘
```

---

## 🔴 اختبر هذه الأزرار بالترتيب

### 1️⃣ **➕ إضافة منتج** (أزرق)
```
متوقع في السجل:
✅ Product inserted: prod-001
```

### 2️⃣ **📋 جلب منتجات** (أخضر)
```
متوقع في السجل:
✅ Fetched 1 products
   • منتج تجريبي: 100 ريال
```

### 3️⃣ **✏️ تحديث منتج** (برتقالي)
```
متوقع في السجل:
✅ Product updated: prod-001
```

### 4️⃣ **📋 جلب منتجات** مرة أخرى
```
متوقع في السجل:
✅ Fetched 1 products
   • منتج محدّث: 150 ريال
```

### 5️⃣ **💰 إنشاء فاتورة** (بنفسجي)
```
متوقع في السجل:
✅ Invoice created: [ID] (INV-[timestamp])
✅ Invoice item added: [ID]
```

### 6️⃣ **📄 جلب فواتير** (أزرق مائل)
```
متوقع في السجل:
✅ Fetched 1 invoices
   • INV-[number]: 525 ريال
```

### 7️⃣ **🔄 Sync Queue** (نيلي)
```
متوقع في السجل:
✅ Found X pending sync items
   • products: INSERT
   • invoices: INSERT
   • invoice_items: INSERT
```

### 8️⃣ **🗑️ حذف منتج** (أحمر)
```
متوقع في السجل:
✅ Product deleted: prod-001
```

---

## ✅ قائمة التحقق

بعد الاختبار تأكد من:

```
[ ] الشاشة ظهرت بنجاح
[ ] اختبار إضافة منتج نجح
[ ] اختبار جلب منتجات نجح
[ ] اختبار تحديث منتج نجح
[ ] اختبار إنشاء فاتورة نجح
[ ] اختبار جلب فواتير نجح
[ ] اختبار Sync Queue نجح
[ ] اختبار حذف منتج نجح
[ ] لا توجد أخطاء في console
[ ] قاعدة البيانات تعمل بنجاح
```

---

## 🐛 إذا حدث خطأ

### خطأ: "LocalDatabase not found"
```bash
# تأكد من أن الملف موجود:
# lib/core/local_database/local_db.dart
# إذا لم يكن موجوداً، أنسخ الكود من جديد
```

### خطأ: "No such table: products"
```bash
# احذف قاعدة البيانات القديمة:
flutter clean
flutter pub get
flutter run
```

### خطأ: Compilation Error
```bash
# جرّب:
flutter pub get
flutter analyze
flutter run
```

---

## 📊 ماذا يحدث؟

عندما تختبر:

```
1. افتح التطبيق
   ↓
2. اضغط "➕ إضافة منتج"
   ↓
3. LocalDatabase ينشئ قاعدة البيانات
   ↓
4. ينشئ الجداول (products, invoices, إلخ)
   ↓
5. يضيف منتج تجريبي
   ↓
6. السجل يعرض: ✅ Product inserted
   ↓
7. اضغط "📋 جلب منتجات"
   ↓
8. السجل يعرض: ✅ Fetched 1 products
   ↓
9. وهكذا...
```

---

## 📝 ماذا تتوقع في Console

```
flutter run

I/flutter ( 2850): 📦 Creating database tables...
I/flutter ( 2850):    ✓ products table created
I/flutter ( 2850):    ✓ invoices table created
I/flutter ( 2850):    ✓ invoice_items table created
I/flutter ( 2850):    ✓ customers table created
I/flutter ( 2850):    ✓ sync_queue table created
I/flutter ( 2850): ✅ All tables created successfully

I/flutter ( 2850): 📊 Database Structure:
I/flutter ( 2850):    ✓ Table: products
I/flutter ( 2850):    ✓ Table: invoices
I/flutter ( 2850):    ✓ Table: invoice_items
I/flutter ( 2850):    ✓ Table: customers
I/flutter ( 2850):    ✓ Table: sync_queue
```

---

## 🎉 بعد الاختبار الناجح

```
✅ LocalDatabase يعمل
✅ الجداول موجودة
✅ العمليات تعمل
✅ Sync Queue جاهز

الخطوة التالية:
└─ اليوم 3-4: ConnectivityService
```

---

**الآن ابدأ الاختبار! 🚀**

```
cd C:\Users\F\Downloads\itqan_erp
flutter run
```

**استمتع! 🎊**
