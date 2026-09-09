&#65279;# دليل استخدام اللغات والعملات في Kinetic ERP

## 📋 المحتويات

1. [دعم اللغات](#دعم-اللغات)
2. [دعم العملات](#دعم-العملات)
3. [أمثلة الاستخدام](#أمثلة-الاستخدام)
4. [إضافة ترجمات جديدة](#إضافة-ترجمات-جديدة)
5. [إضافة عملات جديدة](#إضافة-عملات-جديدة)

---

## 🌍 دعم اللغات

التطبيق يدعم اللغتين:
- **العربية** (ar) - الاتجاه RTL
- **الإنجليزية** (en) - الاتجاه LTR

### التبديل بين اللغات

```dart
// في أي مكان في الواجهة
ref.read(localeProvider.notifier).setLocale(const Locale('en'));
// أو
ref.read(localeProvider.notifier).toggleLanguage();
```

### الحصول على اللغة الحالية

```dart
final locale = ref.watch(localeProvider);
final isArabic = ref.watch(isArabicProvider);
final direction = ref.watch(textDirectionProvider);
```

---

## 💰 دعم العملات

العملات المدعومة تشمل:

### عملات عربية وإسلامية:
- **LYD** - دينار ليبي (الافتراضي)
- **SAR** - ريال سعودي
- **AED** - درهم إماراتي
- **EGP** - جنيه مصري
- **KWD** - دينار كويتي
- **QAR** - ريال قطري
- **BHD** - دينار بحريني
- **OMR** - ريال عماني
- **JOD** - دينار أردني
- **IQD** - دينار عراقي
- **SYP** - ليرة سورية
- **LBP** - ليرة لبنانية
- **TND** - دينار تونسي
- **DZD** - دينار جزائري
- **MAD** - درهم مغربي

### عملات دولية:
- **USD** - دولار أمريكي
- **EUR** - يورو
- **GBP** - جنيه إسترليني
- **CHF** - فرنك سويسري
- **JPY** - ين ياباني
- **CNY** - يوان صيني
- **INR** - روبية هندية

---

## 💡 أمثلة الاستخدام

### 1. الترجمة البسيطة

```dart
import 'package:kinetic_erp/core/i18n/app_translations.dart';

// الترجمة المباشرة
String title = 'app_name'.tr('ar');  // 'إتقان ERP'
String title = 'app_name'.tr('en');  // 'Kinetic ERP'

// استخدام AppTranslations
String hello = AppTranslations.translate('welcome', 'ar');
```

### 2. استخدام في Riverpod Consumer

```dart
Consumer(builder: (context, ref, child) {
  final locale = ref.watch(localeProvider);
  final isArabic = ref.watch(isArabicProvider);
  
  return Text('sales'.tr(locale.languageCode));
}),
```

### 3. تنسيق العملات

```dart
import 'package:kinetic_erp/core/i18n/translation_utils.dart';

// تنسيق كامل
String formatted = CurrencyFormatter.format(
  1250.50,
  'SAR',
  true, // isArabic
);
// النتيجة: "1250.50 ر.س"

// تنسيق منفصل
final result = CurrencyFormatter.formatSeparate(
  1250.50,
  'USD',
  false, // isArabic
);
// result.amount: "1250.50"
// result.symbol: "$"
```

### 4. استخدام في نقطة البيع (POS)

```dart
Consumer(builder: (context, ref, child) {
  final currencyCode = ref.watch(currencyProvider);
  final currencyInfo = ref.watch(currencyInfoProvider);
  final isArabic = ref.watch(isArabicProvider);
  
  final total = 1250.75;
  
  return Column(
    children: [
      Text('total'.tr(isArabic ? 'ar' : 'en')),
      Text(
        CurrencyFormatter.format(total, currencyCode, isArabic),
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    ],
  );
}),
```

### 5. تبديل العملة

```dart
// الحصول على العملات المتاحة
final available = ref.read(currencyProvider.notifier).getAvailableCurrencies();

// تعيين عملة جديدة
ref.read(currencyProvider.notifier).setCurrency('USD');
```

### 6. عرض معلومات العملة

```dart
Consumer(builder: (context, ref, child) {
  final currencyInfo = ref.watch(currencyInfoProvider);
  final isArabic = ref.watch(isArabicProvider);
  
  return ListTile(
    title: Text(currencyInfo.getName(isArabic)),
    subtitle: Text('${currencyInfo.code} - ${currencyInfo.getSymbol(isArabic)}'),
  );
}),
```

---

## ➕ إضافة ترجمات جديدة

### 1. فتح `lib/core/i18n/app_translations.dart`

### 2. أضف المفتاح والقيمة للغة المطلوبة:

```dart
'ar': {
  // الترجمات الموجودة...
  'new_key': 'القيمة العربية',
},
'en': {
  // الترجمات الموجودة...
  'new_key': 'English Value',
},
```

### 3. استخدمها في الواجهة:

```dart
Text('new_key'.tr(locale.languageCode))
```

---

## ➕ إضافة عملات جديدة

### 1. فتح `lib/core/constants/app_constants.dart`

### 2. أضف العملة الجديدة:

```dart
'EUR': CurrencyInfo(
  code: 'EUR',
  symbolAr: '€',
  symbolEn: '€',
  nameAr: 'يورو',
  nameEn: 'Euro',
  fractionDigits: 2,
),
```

### 3. استخدمها:

```dart
ref.read(currencyProvider.notifier).setCurrency('EUR');
```

---

## 🎯 ملخص الملفات الجديدة

| الملف | الوصف |
|------|--------|
| `lib/core/i18n/locale_provider.dart` | مزودات اللغة والاتجاه النصي |
| `lib/core/i18n/currency_provider.dart` | مزودات العملات |
| `lib/core/i18n/translation_utils.dart` | أدوات الترجمة وتنسيق العملات |
| `lib/core/i18n/app_translations.dart` | الترجمات الفعلية (AR/EN) |
| `lib/core/constants/app_constants.dart` | الثوابت بما فيها العملات |

---

## ⚡ نصائح الأداء

- الترجمات محفوظة في `const Map` - بلا تخصيص إضافي
- العملات مخزنة محلياً - بلا طلبات شبكية
- استخدم `ref.watch()` لاكتشاف التغييرات تلقائياً

---

## 🔄 التكامل مع الشاشات الموجودة

سيتم تحديث الشاشات التالية تلقائياً:

1. **شاشة الدخول** - ستظهر باللغة والعملة المختارة
2. **نقطة البيع** - ستعرض الأسعار بالعملة الصحيحة
3. **لوحة التحكم** - ستترجم جميع المقاييس والأرقام
4. **الإعدادات** - اختيار اللغة والعملة سهل

---

✅ **تم الإعداد بنجاح! يمكنك الآن استخدام اللغات والعملات المتعددة**
