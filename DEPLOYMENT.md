# نشر Kinetic Enterprise على Windows Server 2019

دليل تشغيل النظام على سيرفر حقيقي، من رفعه على GitHub إلى تسليم أول عميل.

---

## 🔴 قبل أي شيء: الأسرار

**تم استخراج الأسرار من الكود بالفعل.** `appsettings.json` المرفوع على GitHub
يحوي قيماً **فارغة** فقط:

| الملف | المحتوى | يُرفع على GitHub؟ |
|---|---|---|
| `appsettings.json` | إعدادات عامة، أسرار فارغة | ✅ نعم |
| `appsettings.Production.example.json` | قالب للتعبئة | ✅ نعم |
| `appsettings.Production.json` | **سلسلة الاتصال + مفتاح JWT الحقيقيان** | ❌ **أبداً** (في `.gitignore`) |

### ⚠️ ولّد مفتاح JWT جديداً على السيرفر

المفتاح الحالي ظهر أثناء التطوير، **لا تستخدمه في الإنتاج**. مفتاح مسرَّب =
إمكانية تزوير توكن دخول لأي مستخدم في **أي منظمة** على السيرفر.

```powershell
$bytes = New-Object byte[] 48
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
[Convert]::ToBase64String($bytes)
```

> تغيير المفتاح يُبطل كل التوكنات الحالية — الجميع يسجّل دخوله من جديد. هذا
> متوقَّع ومطلوب.

---

## 1. رفع المشروع على GitHub

```bash
cd C:\Users\F\Downloads\kinetic_erp
git init
git add .
git status
```

**قبل أول `commit`، تحقّق أن هذه غير مدرَجة في `git status`:**

- `appsettings.Production.json`
- `build/` و `.dart_tool/` (‏‎305 و254 ميغابايت)
- `backend/**/bin/` و `backend/**/obj/` (‏40 ميغابايت)

إن ظهر أيٌّ منها، فـ `.gitignore` لم يُطبَّق — أوقف العملية وراجعه.

```bash
git commit -m "Kinetic Enterprise ERP"
git branch -M main
git remote add origin https://github.com/<حسابك>/<المستودع>.git
git push -u origin main
```

> **اجعل المستودع Private** إن كان النظام تجارياً. وإن سبق أن رُفع مفتاح
> أو كلمة مرور بالخطأ، لا يكفي حذفهما في commit جديد — يبقيان في تاريخ
> Git؛ غيّرهما فوراً واعتبرهما مكشوفَين.

---

## 2. تجهيز Windows Server 2019

### أ. SQL Server

ثبّت **SQL Server 2019 Express** (مجاني) أو Standard. أثناء التثبيت:

- فعّل **Mixed Mode** أو أبقِ **Windows Authentication** (الأبسط والأأمن هنا)
- شغّل **SQL Server Browser** إن استخدمت اسم Instance مسمّى

> النظام يستخدم `SESSION_CONTEXT` و`CREATE SECURITY POLICY` لعزل بيانات كل
> عميل — **تتطلب SQL Server 2016 فما فوق**. لا تعمل على 2008/2012.

### ب. إنشاء قاعدة البيانات

نفّذ ملف المخطط كاملاً عبر SSMS أو:

```powershell
sqlcmd -S .\SQLEXPRESS -E -i "C:\kinetic_erp\docs\DATABASE_SCHEMA_SQLSERVER.sql"
```

هذا يُنشئ الجداول وسياسات العزل (Row-Level Security) ودوالّها.

### ج. .NET 8 Hosting Bundle

نزّل **ASP.NET Core 8 Hosting Bundle** من موقع مايكروسوفت وثبّته
(يشمل Runtime + وحدة IIS). أعد تشغيل السيرفر بعده.

---

## 3. نشر الـ Backend

على جهاز التطوير:

```powershell
cd backend\KineticEnterprise.Api
dotnet publish -c Release -o C:\publish\kinetic-api
```

انسخ محتوى `C:\publish\kinetic-api` إلى السيرفر (مثلاً `C:\inetpub\kinetic-api`)،
ثم **أنشئ `appsettings.Production.json` هناك يدوياً**:

```json
{
  "ConnectionStrings": {
    "Default": "Server=.\\SQLEXPRESS;Database=KineticEnterprise;Trusted_Connection=True;TrustServerCertificate=True;"
  },
  "Jwt": { "Key": "<المفتاح الذي ولّدته أعلاه>" },
  "AllowedOrigins": "https://erp.your-domain.com"
}
```

### التشغيل كخدمة عبر IIS (موصى به)

1. أضف **Site** جديداً في IIS يشير إلى مجلد النشر
2. في **Application Pool**: اضبط `.NET CLR Version` = **No Managed Code**
3. اضبط هوية الـ App Pool على حساب له صلاحية على قاعدة البيانات
   (أو استخدم `ApplicationPoolIdentity` وامنحه صلاحية في SQL Server)
4. أضف الحساب في SQL Server:

```sql
CREATE LOGIN [IIS APPPOOL\KineticApiPool] FROM WINDOWS;
USE KineticEnterprise;
CREATE USER [IIS APPPOOL\KineticApiPool] FOR LOGIN [IIS APPPOOL\KineticApiPool];
ALTER ROLE db_datareader ADD MEMBER [IIS APPPOOL\KineticApiPool];
ALTER ROLE db_datawriter ADD MEMBER [IIS APPPOOL\KineticApiPool];
GRANT EXECUTE ON SCHEMA::dbo TO [IIS APPPOOL\KineticApiPool];
```

> **مهم:** لا تمنحه `db_owner`. صلاحيات القراءة/الكتابة تكفي، وسياسات العزل
> تبقى فعّالة — بينما `db_owner` قد يتجاوزها.

### شهادة HTTPS

استخدم شهادة حقيقية (Let's Encrypt عبر win-acme، أو شهادة مشتراة) واربطها
بالموقع في IIS على المنفذ 443. **لا تشغّل نظاماً مالياً على HTTP** — كلمات
المرور والتوكنات تمرّ نصاً واضحاً.

---

## 4. تجهيز تطبيق سطح المكتب للعملاء

التطبيق يحتاج معرفة عنوان السيرفر وقت البناء:

```powershell
flutter build windows --release --dart-define=API_BASE_URL=https://erp.your-domain.com/api
```

انسخ محتوى `build\windows\x64\runner\Release\` كاملاً إلى جهاز العميل
(الملف التنفيذي وحده لا يكفي — يحتاج ملفات `.dll` ومجلد `data`).

---

## 4.1 نسخة الأندرويد

معرّف التطبيق: `com.kinetic.enterprise` — أدنى نسخة مدعومة: Android 6.0 (API 23).

### أ. متطلبات جهاز البناء

Android SDK (Platform 35 + Build-Tools + platform-tools) و JDK 17+. عبر
Android Studio، أو أدوات سطر الأوامر وحدها ثم:

```powershell
flutter config --android-sdk C:\Android\sdk
```

تأكد من `flutter doctor` أن سطر **Android toolchain** أخضر قبل المتابعة.

### ب. مفتاح التوقيع (مرة واحدة لعمر التطبيق)

```powershell
keytool -genkey -v -keystore C:\keys\kinetic-release.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias kinetic
```

ثم انسخ `android/key.properties.example` إلى `android/key.properties` واملأ
القيم. بدون هذا الملف يوقّع البناء بمفاتيح debug — للتجربة فقط، لا للتسليم.

> **احتفظ بنسخة من `.jks` خارج الجهاز.** فقدانه يعني عدم القدرة على نشر أي
> تحديث لنفس التطبيق مستقبلاً.

### ج. البناء

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://erp.your-domain.com/api
```

المخرج: `build\app\outputs\flutter-apk\app-release.apk` — يُوزَّع مباشرة على
أجهزة العميل. للنشر على Google Play استخدم `flutter build appbundle` بنفس
الـ `--dart-define`.

لتقليل حجم الملف عند التوزيع المباشر:

```powershell
flutter build apk --release --split-per-abi --dart-define=API_BASE_URL=https://erp.your-domain.com/api
```

### د. الشبكة

نسخة release تسمح بـ **HTTPS فقط** (`res/xml/network_security_config.xml`).
عنوان `http://` لن يعمل، وكذلك شهادة موقّعة داخلياً غير مثبَّتة في نظام
الجهاز — إن كان السيرفر داخل الشبكة المحلية بشهادة داخلية، أضف الشهادة الجذر
إلى `res/raw` وأدرجها في `<trust-anchors>` لنطاق السيرفر.

أثناء التطوير على المحاكي، `10.0.2.2` هو عنوان جهازك، و`localhost` يشير إلى
المحاكي نفسه:

```powershell
flutter run --dart-define=API_BASE_URL=https://10.0.2.2:5001/api
```

---

## 5. أول عميل

1. سجّل دخولك كمالك المنصة
2. **النظام ← إنشاء منظمة جديدة** — تُنشأ منظمة + فرع + ترخيص + مدير عام
3. سلّم العميل بريده وكلمة مروره الأولى
4. العميل يضبط اسمه وألوانه وفروعه بنفسه من **الإدارة ← الفروع والهوية**

> عملاء متعددون على نفس السيرفر وقاعدة البيانات — العزل مضمون على مستوى
> قاعدة البيانات نفسها (RLS)، لا بشروط في الكود يمكن نسيانها.

---

## 6. النسخ الاحتياطي (غير مُعَد بعد — أعِدّه قبل التسليم)

قاعدة بيانات واحدة تخدم كل عملائك؛ فقدانها = فقدان الجميع.

```sql
BACKUP DATABASE KineticEnterprise
TO DISK = 'D:\Backups\KineticEnterprise.bak'
WITH FORMAT, COMPRESSION, STATS = 10;
```

اجعلها مهمة يومية في **SQL Server Agent** (غير متوفر في Express — استخدم
**Task Scheduler** مع `sqlcmd`)، واحتفظ بنسخة **خارج السيرفر**.

---

## ملخص فحص ما قبل الإطلاق

- [ ] مفتاح JWT جديد وعشوائي على السيرفر
- [ ] `appsettings.Production.json` غير مرفوع على GitHub
- [ ] المستودع Private إن كان النظام تجارياً
- [ ] HTTPS بشهادة حقيقية
- [ ] حساب قاعدة البيانات ليس `db_owner`
- [ ] نسخ احتياطي مجدوَل ومختبَر الاسترجاع
- [ ] `AllowedOrigins` مضبوط على نطاقك لا `localhost`
- [ ] نسخة الأندرويد موقّعة بمفتاح إصدار حقيقي (`android/key.properties`)
- [ ] نسخة احتياطية من ملف `.jks` محفوظة خارج جهاز البناء
- [ ] تغيير كلمة مرور حسابك من الافتراضية
