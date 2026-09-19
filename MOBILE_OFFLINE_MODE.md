# 📱 نسخة الهاتف Offline — iOS و Android

## 🎯 الفكرة الأساسية

```
نفس الكود (Flutter)
    ↓
يعمل على Windows Desktop  ✅
يعمل على الويب           ✅
يعمل على iPhone          ✅
يعمل على Android         ✅
    ↓
SQLite محلي على كل جهاز
    ↓
مزامنة تلقائية عند الاتصال
```

**الميزة:** كود واحد فقط! بلا نسخ مختلفة! 🎉

---

## 📲 كيفية عمل Offline على الهاتف

### 1️⃣ عامل في المتجر (بدون انترنت 4G/WiFi)

```
الهاتف في جيب العامل
    ↓
عند البيع، يحفظ في SQLite على الجهاز
    ↓
عند العودة للمتجر (مع WiFi)
    ↓
البيانات ترسل تلقائياً للسيرفر
    ↓
الجهاز يحدّث البيانات من الخادم
```

### 2️⃣ موظف المبيعات (متنقل)

```
يزور عملاء مختلفين
    ├─ بدون انترنت ← LocalDB يعمل عادي
    ├─ مع انترنت ضعيفة ← Sync في الخلفية
    └─ مع انترنت قوية ← Sync فوري
```

---

## 🔧 الفرق بين Desktop و Mobile

| الميزة | Desktop | Mobile |
|--------|---------|--------|
| **قاعدة البيانات** | SQLite محلي | SQLite محلي (ROM) |
| **المزامنة** | Dio + BackgroundSync | Dio + Workmanager |
| **الاتصال** | WiFi/Ethernet | 4G/WiFi/3G |
| **التخزين** | GB | MB (محدود) |
| **الصلاحيات** | كل شيء مسموح | يحتاج Permissions |

---

## 📁 بنية المشروع (نفسها للجميع)

```
lib/
├── core/
│   ├── local_database/
│   │   └── local_db.dart           ← نفس الملف للجميع!
│   │
│   ├── connectivity/
│   │   └── connectivity_service.dart ← نفس الملف!
│   │
│   └── sync/
│       └── sync_engine.dart         ← نفس الملف!
│
├── features/
│   ├── pos/                         ← بيع
│   ├── inventory/                   ← مخزون
│   └── customers/                   ← عملاء
│
└── main.dart                        ← نقطة دخول واحدة
```

**الكود واحد = جميع المنصات!** 🎯

---

## 📦 التبعيات (موجودة بالفعل)

```yaml
dependencies:
  # Local Database
  sqflite: ^2.3.0              ✅ يعمل على iOS و Android
  path_provider: ^2.1.1        ✅ يعمل على جميع المنصات
  
  # Connectivity
  connectivity_plus: ^5.0.0    ✅ يعمل على iOS و Android
  
  # Background Sync
  workmanager: ^0.10.10        ✅ يعمل على iOS و Android
  
  # HTTP Client
  dio: ^5.7.0                  ✅ يعمل على جميع المنصات
```

---

## 🚀 البناء والتوزيع

### بناء نسخة Android (APK)

#### الخطوة 1: التوقيع (Signing)

```bash
# إنشاء مفتاح التوقيع (مرة واحدة فقط)
keytool -genkey -v -keystore ~/key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias key

# أو استخدم Android Studio:
# Build > Generate Signed Bundle/APK
```

#### الخطوة 2: إنشاء الملف config

```bash
# android/key.properties
storePassword=your_store_password
keyPassword=your_key_password
keyAlias=key
storeFile=/path/to/key.jks
```

#### الخطوة 3: البناء

```bash
# Release APK (أصغر حجماً، أسرع تحميلاً)
flutter build apk --release \
  --dart-define=API_BASE_URL=https://your-server.com/api

# أو App Bundle (للنشر على Google Play)
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://your-server.com/api
```

#### النتيجة:
```
build/app/outputs/apk/release/app-release.apk
├─ الحجم: 50-80 MB (أول مرة)
├─ التثبيت: سريع جداً
└─ الرام: 100-200 MB عند التشغيل
```

---

### بناء نسخة iPhone (IPA)

#### الخطوة 1: الإعدادات

```bash
# في Xcode:
# 1. فتح iOS Project
open ios/Runner.xcworkspace

# 2. تعيين Bundle ID
#    Runner > General > Bundle Identifier
#    com.yourcompany.itqan

# 3. تعيين Team ID
#    Runner > Signing & Capabilities > Team
```

#### الخطوة 2: البناء

```bash
# Build for iOS
flutter build ios --release \
  --dart-define=API_BASE_URL=https://your-server.com/api

# أو مباشرة من Xcode:
# Product > Archive > Distribute App
```

#### النتيجة:
```
build/ios/ipa/Runner.ipa
├─ الحجم: 60-100 MB
├─ للنشر على App Store
└─ أو توزيع مباشر
```

---

## 🔐 الصلاحيات المطلوبة

### Android (AndroidManifest.xml)

```xml
<!-- android/app/src/main/AndroidManifest.xml -->

<manifest>
  <!-- قراءة وكتابة الملفات على الجهاز -->
  <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
  <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
  
  <!-- الاتصال بالإنترنت -->
  <uses-permission android:name="android.permission.INTERNET" />
  
  <!-- كشف نوع الاتصال -->
  <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
  
  <!-- المزامنة في الخلفية -->
  <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
  
  <!-- الطباعة -->
  <uses-permission android:name="android.permission.PRINT" />
  
  <!-- الكاميرا (لماسح الباركود) -->
  <uses-permission android:name="android.permission.CAMERA" />
  
  <application>
    <!-- ... -->
  </application>
</manifest>
```

### iOS (Info.plist)

```xml
<!-- ios/Runner/Info.plist -->

<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <!-- وصول الكاميرا -->
  <key>NSCameraUsageDescription</key>
  <string>نحتاج الكاميرا لماسح الباركود</string>
  
  <!-- الوصول للصور -->
  <key>NSPhotoLibraryUsageDescription</key>
  <string>نحتاج للصور لتحميل الشعار</string>
  
  <!-- الوصول للمستندات -->
  <key>NSDocumentsFolderUsageDescription</key>
  <string>نحتاج للملفات للنسخ الاحتياطية</string>
  
  <!-- ... الإعدادات الأخرى ... -->
</dict>
</plist>
```

---

## 💾 حجم التخزين على الهاتف

### حساب المساحة المطلوبة

```
App APK:              50-80 MB
SQLite Database:      10-50 MB (حسب حجم البيانات)
Cache & Temp:         5-20 MB
متسع آمن:             20 MB

المجموع:             85-170 MB
```

### تحسين الحجم

```dart
// في main.dart

// 1. تقليل حجم Fonts
// احذف الخطوط غير المستخدمة

// 2. ضغط الصور
// استخدم webp بدل PNG

// 3. تقليل Dependencies
// احذف packages غير المستخدمة

// 4. تفعيل Shrinking
// flutter build apk --shrink
```

---

## 🔄 المزامنة على الهاتف

### المزامنة الذكية

```dart
// lib/core/sync/smart_sync.dart

class SmartSync {
  // 1. مزامنة عند الاتصال
  Future<void> syncOnConnect() async {
    final connectivity = ConnectivityService();
    
    connectivity.connectionStatusStream.listen((isConnected) {
      if (isConnected) {
        // ابدأ المزامنة
        startFullSync();
      }
    });
  }
  
  // 2. مزامنة دورية (كل 30 دقيقة)
  Future<void> schedulePeriodicSync() async {
    Workmanager().registerPeriodicTask(
      'periodic_sync',
      'syncTask',
      frequency: Duration(minutes: 30),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresDeviceIdle: false,
      ),
    );
  }
  
  // 3. مزامنة ذكية (حسب حجم البيانات)
  Future<void> smartSync() async {
    final queueSize = await _localDb.getPendingSyncItemsCount();
    
    if (queueSize > 100) {
      // بيانات كثيرة، استخدم WiFi فقط
      await _waitForWiFi();
    }
    
    if (queueSize > 1000) {
      // بيانات ضخمة جداً، استخدم WiFi + شاحن
      await _waitForWiFiAndCharging();
    }
    
    await startSync();
  }
}
```

---

## 📊 مراقبة الأداء على الهاتف

### استهلاك الرام

```
التطبيق في الخلفية:    50-100 MB
عند الاستخدام:       150-250 MB
أثناء المزامنة:      200-300 MB
```

### استهلاك البطارية

```
بدون مزامنة:  5-10 % / ساعة
مع مزامنة:    15-20 % / ساعة
```

### حل لتقليل الاستهلاك

```dart
// 1. مزامنة فقط عند الشاحن
Workmanager().registerPeriodicTask(
  'charging_sync',
  'syncTask',
  frequency: Duration(hours: 1),
  constraints: Constraints(
    requiresCharging: true,  // ← يعمل فقط عند الشاحن
    networkType: NetworkType.connected,
  ),
);

// 2. تقليل تكرار الفحص
// بدل كل 30 دقيقة → كل ساعة

// 3. تجميع البيانات قبل الإرسال
// بدل 100 طلب → طلب واحد
```

---

## 🎯 حالات الاستخدام الفعلية

### حالة 1: عامل في المتجر

```
الصباح:
├─ يفتح التطبيق
├─ App يحمّل آخر البيانات من السيرفر
│  (إذا كان متصل)
└─ يبدأ البيع بدون انترنت

الظهيرة:
├─ عشر بيعات بدون انترنت
├─ كل فاتورة تُحفظ محليا
└─ قائمة انتظار (Queue) تتسجل التغييرات

المساء:
├─ يرجع للمكتب (WiFi)
├─ App يكتشف الاتصال
├─ مزامنة تلقائية للـ 10 فواتير
├─ سيرفر يحفظها
└─ Backup تلقائي ✅
```

### حالة 2: مدير في الطريق

```
يقود السيارة (بدون انترنت محمول)
├─ App يعرض الأوامر المحفوظة محليا
├─ يقدر حالة كل عميل
└─ يسجل ملاحظات

عند وصول المكتب (WiFi):
├─ App يزامن البيانات
├─ سيرفر يحدّث حالات العملاء
└─ Backup آمن ✅
```

### حالة 3: مستودع بدون انترنت دائم

```
المستودع لا يوجد فيه انترنت
├─ App يعمل 100% محليا
├─ كل العمليات تُحفظ محليا
└─ SQL Server Express محلي

عند الاتصال بـ VPN:
├─ Backend يتصل بـ SQL Server المحلي
├─ يجلب البيانات
├─ يحفظها في السيرفر المركزي
└─ Backup كامل ✅
```

---

## 🛠️ أدوات التطوير والاختبار

### محاكاة بدون انترنت

```dart
// في أثناء التطوير، اختبر بدون انترنت
class MockOfflineConnectivity implements Connectivity {
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged {
    // محاكاة بدون اتصال
    return Stream.value([ConnectivityResult.none]);
  }
}

// استخدم في التطبيق
final connectivity = kDebugMode 
  ? MockOfflineConnectivity() 
  : Connectivity();
```

### اختبار الأداء

```bash
# مراقبة استخدام الرام والمعالج
flutter run -v

# أو استخدم DevTools
flutter pub global activate devtools
flutter pub global run devtools

# اختبر على جهاز حقيقي
flutter run -d <device_id>
```

---

## 📱 خطوات التطبيق على الهاتف

### الخطوة 1: نفس Offline Code
```dart
// lib/core/local_database/local_db.dart
// lib/core/connectivity/connectivity_service.dart
// lib/core/sync/sync_engine.dart

// نفسها للجميع! Desktop + Web + iOS + Android
```

### الخطوة 2: إضافة Platform-Specific Code (اختياري)

```dart
// lib/platform/platform_service.dart

class PlatformService {
  static Future<String> getDeviceId() async {
    // معرف فريد للجهاز
    if (Platform.isAndroid) {
      return getAndroidDeviceId();
    } else if (Platform.isIOS) {
      return getIosDeviceId();
    }
    return 'unknown';
  }
  
  static Future<void> scheduleBackgroundSync() async {
    // مزامنة في الخلفية
    if (Platform.isAndroid || Platform.isIOS) {
      Workmanager().registerPeriodicTask(
        'background_sync',
        'syncTask',
        frequency: Duration(minutes: 30),
      );
    }
  }
}
```

### الخطوة 3: الإعدادات الخاصة بـ Android

```gradle
// android/app/build.gradle

android {
  compileSdk 33
  
  defaultConfig {
    applicationId "com.itqan.mobile"
    minSdkVersion 21         // Android 5.0+
    targetSdkVersion 33
    versionCode 1
    versionName "1.0.0"
  }
  
  buildTypes {
    release {
      minifyEnabled true      // تقليل الحجم
      proguardFiles getDefaultProguardFile(
        'proguard-android-optimize.txt'
      ), 'proguard-rules.pro'
    }
  }
}
```

### الخطوة 4: الإعدادات الخاصة بـ iOS

```yaml
# ios/Podfile

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    
    # تحسينات الأداء
    target.build_configurations.each do |config|
      config.build_settings['GCC_OPTIMIZATION_LEVEL'] = 's'
    end
  end
end
```

---

## 🎯 قائمة النشر

### قبل النشر على Google Play

```
✅ اختبر على 5+ أجهزة Android مختلفة
✅ اختبر Offline Mode الكامل
✅ اختبر المزامنة على 4G و WiFi
✅ تأكد من المساحة المتاحة
✅ اختبر البطارية (24 ساعة استخدام)
✅ تحقق من الصوت والإشعارات
✅ اختبر الكاميرا وماسح الباركود
```

### قبل النشر على App Store

```
✅ اختبر على iPhone و iPad
✅ تحقق من الشهادات (Certificates)
✅ اختبر بدون انترنت
✅ تحقق من صلاحيات الخصوصية
✅ اختبر Siri Shortcuts (اختياري)
✅ اختبر Dark Mode
```

---

## 📦 حزمة النشر الكاملة

```
Android:
└─ Google Play Store (موصى به)
   ├─ وصول مليارات المستخدمين
   ├─ Automatic Updates
   └─ Security Scanning

iOS:
└─ App Store (الخيار الوحيد)
   ├─ مراجعة Apple (2-48 ساعة)
   ├─ مدفوع (99$ سنوياً)
   └─ متطلبات صارمة

توزيع مباشر:
├─ APK على موقع الشركة
├─ Testflight (iOS)
└─ Firebase App Distribution
```

---

## 💡 نصائح مهمة

### 1. اختبر في بيئة واقعية

```
✅ اختبر بدون انترنت حقاً
✅ اختبر مع بطاريتك تنفد
✅ اختبر مع رام محدودة
✅ اختبر مع مساحة تخزين قليلة
```

### 2. راقب استهلاك الموارد

```
✅ استخدام الرام < 300 MB
✅ استهلاك البطارية معقول
✅ حجم التطبيق < 100 MB
✅ السرعة < 3 ثواني للتحميل
```

### 3. ركز على UX

```
✅ عرض حالة الاتصال واضحة
✅ إشعارات عند نجاح/فشل المزامنة
✅ زر Manual Sync
✅ رسائل خطأ واضحة
```

---

## ✅ الملخص

```
نفس الكود = جميع المنصات!

Desktop  ✅ (مبني بالفعل)
Web      ✅ (مبني بالفعل)
Android  ✅ (جاهز الآن)
iOS      ✅ (جاهز الآن)

Offline Mode:
├─ SQLite محلي
├─ Connectivity Monitoring
├─ Auto Sync عند الاتصال
└─ Backup على السيرفر

كود واحد
لا تكرار
لا مشاكل! 🎉
```

---

## 📱 الملفات المطلوبة

```
┌─────────────────────────────────────┐
│ نفس lib/ القديمة (Desktop + Web)    │
│                                     │
│ ✅ local_database/local_db.dart    │
│ ✅ connectivity/connectivity_...   │
│ ✅ sync/sync_engine.dart           │
│ ✅ providers/offline_providers.dart│
└─────────────────────────────────────┘
         ↓
  تعمل على الهاتف أيضاً!
         ↓
     + صلاحيات Android
     + إعدادات iOS
     + تحسينات الأداء
         ↓
    APK و IPA جاهزة!
```

---

**هل تريد البدء بـ:
1. ⚡ بناء APK للاختبار الآن؟
2. 📚 شرح تفصيلي لكل خطوة؟
3. 🔧 إضافة features خاصة بـ Mobile؟**
