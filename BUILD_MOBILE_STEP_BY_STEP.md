# 🚀 بناء نسخة الهاتف — خطوة بخطوة

## ⚡ الخطوات السريعة

### Android (APK) — 15 دقيقة

```bash
# 1. من مجلد المشروع
cd C:\Users\F\Downloads\itqan_erp

# 2. تحميل التبعيات
flutter pub get

# 3. بناء APK
flutter build apk --release

# النتيجة:
# build/app/outputs/apk/release/app-release.apk
```

### iOS (IPA) — 30 دقيقة

```bash
# 1. من مجلد المشروع
cd C:\Users\F\Downloads\itqan_erp

# 2. تحديث التبعيات
flutter pub get

# 3. بناء iOS
flutter build ios --release

# النتيجة:
# build/ios/ipa/Runner.ipa
```

---

## 📋 قائمة المتطلبات

### لبناء Android

```
✅ Flutter SDK (موجود)
✅ Android SDK (تأكد من تثبيته)
✅ Gradle (يأتي مع Android Studio)
✅ Java JDK 11+ (مطلوب)

التحقق:
flutter doctor -v
```

### لبناء iOS (على Mac فقط)

```
✅ macOS 11.0+
✅ Xcode 13+
✅ CocoaPods
✅ iOS 11.0+ Deployment Target

التحقق:
xcode-select --print-path
```

---

## 🔑 إعداد التوقيع (Signing) — Android

### الخطوة 1: إنشاء مفتاح التوقيع

```bash
# على Windows:
cd C:\
keytool -genkey -v -keystore itqan-key.jks ^
  -keyalg RSA -keysize 2048 -validity 10000 ^
  -alias itqan-key

# على Mac/Linux:
keytool -genkey -v -keystore ~/itqan-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias itqan-key

# سيطلب منك:
# Full Name: Your Name or Company
# Organization: Your Company
# State: Your State
# Country: SA (for Saudi Arabia)
# Keystore password: your_password_here (احفظها!)
# Key password: same_as_above
```

### الخطوة 2: إنشاء الملف config

```bash
# android/key.properties

storePassword=your_keystore_password_here
keyPassword=your_key_password_here
keyAlias=itqan-key
storeFile=/path/to/itqan-key.jks

# على Windows مثال:
storeFile=C:/itqan-key.jks

# على Mac مثال:
storeFile=/Users/yourname/itqan-key.jks
```

### الخطوة 3: تفعيل التوقيع في build.gradle

```gradle
// android/app/build.gradle

def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    // ...
    
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile file(keystoreProperties['storeFile'])
            storePassword keystoreProperties['storePassword']
        }
    }
    
    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled true
            shrinkResources true
        }
    }
}
```

---

## 🏗️ البناء الكامل — Android

### الطريقة 1: من Terminal (موصى به)

```bash
# 1. انتقل لمجلد المشروع
cd C:\Users\F\Downloads\itqan_erp

# 2. نظف البناء السابق
flutter clean

# 3. حمّل التبعيات
flutter pub get

# 4. بناء Release APK
flutter build apk --release

# 5. النتيجة:
# build/app/outputs/apk/release/app-release.apk ✅
```

### الطريقة 2: من Android Studio

```
1. فتح المشروع في Android Studio
2. Build > Generate Signed Bundle / APK
3. APK > Next
4. Select existing key store
5. اختر الملف itqan-key.jks
6. أدخل كلمة المرور
7. اختر Release
8. اضغط Finish
```

### الطريقة 3: بناء App Bundle (للنشر على Play Store)

```bash
# أصغر حجم، الأفضل للنشر
flutter build appbundle --release

# النتيجة:
# build/app/outputs/bundle/release/app-release.aab
```

---

## 📱 البناء الكامل — iOS

### الخطوة 1: الإعدادات الأساسية

```bash
# 1. انتقل لمجلد المشروع
cd C:\Users\F\Downloads\itqan_erp

# 2. نظف البناء
flutter clean
flutter pub get

# 3. فتح iOS Project في Xcode
open ios/Runner.xcworkspace

# ❌ لا تفتح Runner.xcodeproj
# ✅ افتح Runner.xcworkspace (مهم!)
```

### الخطوة 2: إعدادات التوقيع في Xcode

```
1. اختر Runner من الـ Project Navigator
2. انقر على Runner تحت TARGETS
3. اختر Signing & Capabilities
4. اختر Team (حسابك Apple)
5. تأكد من Bundle Identifier مختلف عن غيره
6. Bundle ID: com.itqan.mobile (مثال)
```

### الخطوة 3: البناء

```bash
# البناء المباشر
flutter build ios --release

# أو من Xcode:
# Product > Archive
# ثم Distribute App
```

### الخطوة 4: الملف النهائي

```
build/ios/ipa/Runner.ipa
├─ حجم: 60-100 MB
├─ جاهز للنشر على App Store
└─ أو توزيع مباشر via TestFlight
```

---

## 🧪 الاختبار قبل البناء

### اختبار على الجهاز الحقيقي

```bash
# قائمة الأجهزة المتصلة
flutter devices

# تشغيل على جهاز معين
flutter run -d <device_id>

# إذا كان عدد جهاز واحد:
flutter run
```

### اختبار Offline Mode

```bash
# في terminal، قطع الإنترنت من الجهاز:
# 1. أطفئ WiFi
# 2. أطفئ Cellular

# في التطبيق:
# 1. افتح الشاشة الرئيسية
# 2. انقر على "بيع منتج"
# 3. يجب أن يعمل بدون أخطاء
# 4. البيانات تُحفظ محليا ✅

# ثم أشغل الإنترنت:
# 1. شغّل WiFi أو Cellular
# 2. App يبدأ المزامنة تلقائياً ✅
```

### اختبار الأداء

```bash
# اختبر الذاكرة والمعالج
flutter run -v

# أو استخدم DevTools
flutter pub global activate devtools
flutter pub global run devtools

# اختبر حجم التطبيق
flutter build apk --analyze-size
```

---

## 📊 حجم الملفات النهائية

### Android APK

```
debug:         200-300 MB (للتطوير فقط)
release:       50-80 MB  ✅ (للمستخدمين)

بعد الضغط والتحسين:
App Size:      40-60 MB
Install Size:  80-120 MB (على الجهاز)
```

### iOS IPA

```
Debug:         300-500 MB (للتطوير فقط)
Release:       60-100 MB  ✅ (للمتجر)

على App Store:
Compressed:    30-50 MB
Download Size: 40-80 MB
```

---

## 🚀 النشر على المتاجر

### Google Play Store

```bash
# 1. أنشئ حساب مطور
#    https://play.google.com/console
#    الرسوم: $25 مرة واحدة

# 2. أنشئ تطبيق جديد
#    - اسم التطبيق: منظومة إتقان ERP
#    - App ID: com.itqan.mobile
#    - الفئة: Business

# 3. أضف App Bundle
#    - Upload: build/app/outputs/bundle/release/app-release.aab

# 4. أضف معلومات التطبيق
#    - الوصف
#    - الصور (Screenshots)
#    - الفيديو (اختياري)

# 5. أضف سياسة الخصوصية
#    - يجب أن تكون URL

# 6. احفظ التقارير
#    - تصنيف العمر (Everyone)
#    - المقياس (Content Rating)

# 7. أرسل للمراجعة
#    - Google تراجع خلال ساعات
#    - إذا وافقت → متاح على المتجر
```

### App Store (Apple)

```bash
# 1. أنشئ حساب مطور Apple
#    https://developer.apple.com/
#    الرسوم: $99 سنوياً

# 2. إنشاء Bundle ID
#    - Bundle ID: com.itqan.mobile
#    - يجب فريد عالمياً

# 3. إنشاء Certificates و Profiles
#    - في Apple Developer Portal
#    - Distribution Certificate
#    - App Store Provisioning Profile

# 4. في Xcode → Archive
#    - Product > Archive
#    - Validate App
#    - Upload to App Store

# 5. في App Store Connect
#    - Create new app
#    - أضف معلومات
#    - أضف صور وفيديو
#    - اختبار في TestFlight (اختياري)

# 6. Submit for Review
#    - Apple تراجع خلال 1-2 يوم
#    - إذا وافقت → متاح على المتجر
```

### توزيع مباشر (بدون متاجر)

```bash
# Android APK مباشر
# 1. أرسل APK للمستخدمين
# 2. هم يثبتون بأنفسهم

scp build/app/outputs/apk/release/app-release.apk user@server:~/

# أو على الموقع:
https://yourcompany.com/download/app-release.apk

# iOS عبر TestFlight
# 1. في Xcode: Archive
# 2. في App Store Connect:
#    - TestFlight > Internal Testing
#    - أضف المختبرين
#    - هم يحملون التطبيق من TestFlight
```

---

## 📋 قائمة التحقق قبل النشر

### General

```
[ ] التطبيق يعمل بدون أخطاء
[ ] Offline Mode يعمل
[ ] المزامنة تعمل
[ ] البطارية تبدو معقولة
[ ] الرام معقول
[ ] لا توجد رسائل خطأ
```

### Android

```
[ ] اختبر على 3+ أجهزة مختلفة
[ ] اختبر على Android 7, 10, 12, 13
[ ] اختبر الكاميرا والميكروفون
[ ] اختبر الإشعارات
[ ] اختبر الطباعة (إن وجدت)
[ ] حجم APK < 100 MB
[ ] وقت البدء < 3 ثوانٍ
```

### iOS

```
[ ] اختبر على iPhone و iPad
[ ] اختبر على iOS 12+
[ ] اختبر Dark Mode
[ ] تحقق من Permissions (Privacy)
[ ] اختبر Siri Shortcuts (إن وجدت)
[ ] لا توجد تحذيرات من Xcode
[ ] Certificates صالحة
```

---

## 🔐 نصائح الأمان

### لا تحفظ هذه في الكود:

```dart
// ❌ خطأ - لا تفعل هذا:
const String apiKey = "sk-1234567890";
const String serverPassword = "admin123";

// ✅ صحيح - استخدم .env:
const String apiKey = String.fromEnvironment('API_KEY');
const String serverPassword = String.fromEnvironment('SERVER_PASSWORD');
```

### استخدم .env للبيئات

```bash
# .env.development
API_BASE_URL=https://dev-api.itqan.com
API_KEY=dev_key_12345

# .env.production
API_BASE_URL=https://api.itqan.com
API_KEY=prod_key_67890
```

### بناء مع متغيرات البيئة:

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.itqan.com \
  --dart-define=API_KEY=your_key_here
```

---

## 📞 أوامر مفيدة

```bash
# فحص الجهاز
flutter doctor -v

# قائمة الأجهزة
flutter devices

# نظف كل شيء
flutter clean

# تحديث التبعيات
flutter pub get
flutter pub upgrade

# تحليل الكود
flutter analyze

# اختبر الكود
flutter test

# بناء جميع المنصات
flutter build appbundle  # Android
flutter build ios       # iOS
flutter build web       # Web
flutter build windows   # Windows
flutter build linux     # Linux
flutter build macos     # macOS
```

---

## ✅ الملخص السريع

```
خطوات البناء:

Android:
1. flutter clean
2. flutter pub get
3. flutter build apk --release
4. النتيجة: build/app/outputs/apk/release/app-release.apk

iOS:
1. flutter clean
2. flutter pub get
3. flutter build ios --release
4. النتيجة: build/ios/ipa/Runner.ipa

النشر:
- Google Play: ارفع AAB (App Bundle)
- App Store: ارفع IPA عبر Xcode
```

---

## 🎉 هل أنت جاهز؟

```
✅ الكود جاهز
✅ التبعيات جاهزة
✅ Offline Mode جاهز
✅ أدوات البناء موجودة

لن تحتاج سوى:
1. Signing Keys (مفتاح التوقيع)
2. Developer Accounts (حسابات المتاجر)
3. اختبار سريع
4. بناء وتحميل!
```

---

**اختر:
1. 🚀 بناء APK الآن؟
2. 📱 تثبيت على جهاز للاختبار؟
3. 📤 نشر على Google Play/App Store؟**
