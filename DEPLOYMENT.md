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

## 0. الطريق السريع — حزمة جاهزة بأمر واحد

بدل تنفيذ خطوات البناء يدوياً، السكربت يبنيها كلها ويُخرج ملفاً واحداً
للرفع:

```powershell
.	ool\publish.ps1 -ApiUrl https://erp.example.ly/api
```

يُنتج `publish.zip` (نحو ٢٢ ميغابايت) يحوي: الخادم مبنياً للإنتاج، وتطبيق
الويب مبنياً على عنوان الـ API الممرَّر، وملفات SQL الثلاثة، وقالب إعدادات
بقيم فارغة، وتعليمات التثبيت.

يرفض السكربت المتابعة إن كان `ApiUrl` بـ HTTP لا HTTPS، ويحذف أي ملف أسرار
تسلّل إلى المخرجات قبل الضغط.

**ما لا تحويه الحزمة عمداً: أي سرّ.** ملف الإعدادات فيها قالب فارغ يُملأ على
السيرفر — حزمة تنتقل عبر البريد أو USB وفيها مفتاح توقيع JWT هي أسهل طريق
لتسريبه، والمفتاح المسرَّب يعني تزوير توكن لأي مستخدم في أي منظمة.

القسم أدناه يشرح الخطوات يدوياً لمن يريد فهم ما يفعله السكربت أو تنفيذ
جزء منها فقط.

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
sqlcmd -S .\SQLEXPRESS -E -d KineticEnterprise -i "C:\kinetic_erp\docs\MIGRATIONS.sql"
sqlcmd -S .\SQLEXPRESS -E -d KineticEnterprise -i "C:\kinetic_erp\docs\INDEXES.sql"
```

الأول يُنشئ الجداول وسياسات العزل (Row-Level Security) ودوالّها. والثاني
والثالث **إلزاميان** ولا يكفي الأول وحده: `MIGRATIONS.sql` يضيف ما استجدّ
بعد كتابة المخطط الأصلي (منها عمود `ClientRequestId` الذي يعتمد عليه البيع
دون اتصال في نقطة البيع)، و`INDEXES.sql` فهارس الأداء.

كلاهما **آمن للإعادة**: كل تغيير فيهما ملفوف بـ `IF NOT EXISTS`، فتنفيذهما
مرّتين لا يضرّ. وهذا ما يجعلهما أيضاً طريق **ترقية** قاعدة قائمة: نفّذهما
وحدهما بلا `DATABASE_SCHEMA_SQLSERVER.sql` الذي يفترض قاعدة فارغة.

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

## 4.2 أول حساب — مالك المنصة

قاعدة البيانات تُنشأ **فارغة من المستخدمين**، ولا تسجيل ذاتي في النظام:
`AuthController` فيه `login` وحده، و`PlatformController` يتطلّب ادّعاء
`is_platform_admin`، و`UsersController` يتطلّب توكناً صالحاً. فأول حساب
يُنشأ بأمر يُنفَّذ **على السيرفر نفسه**:

```powershell
cd backend\KineticEnterprise.Api
dotnet run -- create-platform-owner
```

يسأل عن الاسم والبريد وكلمة المرور (12 حرفاً على الأقل)، ويُنشئ منظمة إدارية
لك — لا لعميل، بلا فروع ولا ترخيص — ثم الحساب فيها بـ `is_platform_admin = 1`.

> **لماذا أمر لا صفحة تسجيل؟** أي نقطة نهاية عامة لإنشاء أول مالك تبقى باباً
> مفتوحاً على السيرفر بعد استخدامها؛ ينساها أحدهم فتصبح ثغرة استيلاء كامل على
> كل منظمات كل العملاء. ومن يملك تنفيذ أوامر على السيرفر يملك قاعدة البيانات
> أصلاً، فالأمر لا يضيف خطراً جديداً.

كلمة المرور تُقرأ تفاعلياً ولا تُمرَّر كوسيط: الوسائط تُسجَّل في تاريخ الأوامر
وفي قائمة العمليات. ولا تُحفظ في أي ملف — لا يمكن استرجاعها، فقط تغييرها.

### إنشاء مستخدم (كاشير، مدير فرع، …)

الطريق المعتاد هو شاشة **الإدارة ← المستخدمون**. وهذا الأمر بديل من السيرفر،
ويُستخدم خصوصاً لاختبار الصلاحيات: `super_admin` ومالك المنصة يتجاوزان كل
فحوص الصلاحيات بحكم التصميم، فلا يُثبَت بهما أن المنع يعمل — الكاشير يُثبته.

```powershell
dotnet run -- create-user
```

يسأل عن منظمة (تُحدَّد ببريد مستخدم قائم فيها)، ثم الفرع والدور والاسم
والبريد وكلمة المرور. يرفض البريد المكرَّر على حساب نشط، ويرفض الإنشاء إن
لم يكن في المنظمة فرع نشط — كاشير بلا فرع لا يستطيع فتح نقطة البيع.

### استعادة كلمة مرور

لا يوجد من هو أعلى من مالك المنصة ليعيد تعيينها له، فالطريق من السيرفر:

```powershell
dotnet run -- reset-user-password
```

يقبل البريد أو اسم المستخدم، ويعرض الحسابات المتطابقة ليُختار الصف المقصود إن
تكرّر البريد بين منظمتين.

> **تنبيه على تكرار البريد:** قيد التفرّد هو `(organization_id, email)` لا
> البريد وحده، فنفس البريد قد يوجد في منظمتين. لكن تسجيل الدخول يبحث بالبريد
> **بلا منظمة** (لا سبيل لمعرفتها قبل الدخول)، فيأخذ أول صف يرجعه SQL Server
> — أي أن الدخول ببريد مكرَّر **غير محدَّد النتيجة** وقد يدخل المستخدم إلى
> منظمة غير منظمته. تجنّب تكرار البريد بين المنظمات، أو عطّل الحساب غير
> المستخدم (`is_active = 0`).

---

## 5. أول عميل

1. سجّل دخولك كمالك المنصة
2. **النظام ← إنشاء منظمة جديدة** — تُنشأ منظمة + فرع + ترخيص + مدير عام
3. سلّم العميل بريده وكلمة مروره الأولى
4. العميل يضبط اسمه وألوانه وفروعه بنفسه من **الإدارة ← الفروع والهوية**

> عملاء متعددون على نفس السيرفر وقاعدة البيانات — العزل مضمون على مستوى
> قاعدة البيانات نفسها (RLS)، لا بشروط في الكود يمكن نسيانها.

---

## 6. النسخ الاحتياطي

قاعدة بيانات واحدة تخدم كل عملائك؛ فقدانها = فقدان الجميع.

```powershell
# نسخة الآن
.	oolackup.ps1

# جدولتها يومياً (تتطلّب PowerShell كمسؤول)
.	oolackup.ps1 -Install -Time 02:00
```

السكربت لا يكتفي بأخذ النسخة:

- **يتحقّق من سلامتها** بـ `RESTORE VERIFYONLY WITH CHECKSUM`. النسخة غير
  المتحقَّق منها وعدٌ لا ضمان: أعطال القرص تُكتشف عند الاسترجاع لا عند
  الأخذ — أي في أسوأ لحظة ممكنة. والنسخة الفاشلة تُحذف فوراً، لأن ملف
  `.bak` تالف أخطر من غيابه: يُحتسب نسخةً موجودة حتى تُجرَّب ساعةَ الحاجة.
- **يمنح حساب خدمة SQL Server** صلاحية الكتابة في المجلد. الصلاحية تخصّه
  هو لا المستخدم الذي يشغّل السكربت، لأن `BACKUP` ينفّذه محرّك القاعدة
  بهويته — وهذا أشيع سبب لفشل أول نسخة، ورسالته الخام
  (`Operating system error 5`) لا تقول ذلك.
- **يحذف النسخ الأقدم من 30 يوماً** بعد نجاح الجديدة لا قبلها، ولا يحذفها
  كلها أبداً مهما بلغ عمرها: ساعة نظام خاطئة أو توقّف المهمة شهرين يجعل
  «كل النسخ قديمة»، والحذف حينها يمحو آخر ما تبقّى.
- **يجدولها بحساب SYSTEM** لا حساب المستخدم، فتعمل والسيرفر بلا جلسة
  مفتوحة. (SQL Server Express بلا SQL Server Agent، فالجدولة عبر Task
  Scheduler.)
- **يكتب سجلاً** بكل عملية في `backup.log` — نسخة توقّفت صامتةً قبل شهر
  هي الحالة الشائعة لا النادرة.

**خطوة لا يفعلها سكربت عنك:** انسخ مجلد النسخ إلى **خارج السيرفر** دورياً.
نسخة على القرص نفسه لا تحمي من فقدان الجهاز ولا من فدية.

والاسترجاع يُجرَّب مرّة على الأقل قبل التسليم — نسخة لم تُختبَر استعادتها
ليست نسخة احتياطية بعد.

---

## 7. التجربة محلياً قبل النشر

```powershell
.	ool
un_local.ps1
```

يُنشئ قاعدة تجربة مستقلة (`KineticLocal`) لا يلمس أي قاعدة أخرى، ويولّد
`appsettings.Development.json` بمفتاح JWT عشوائي، ثم يشغّل الخادم وتطبيق
الويب معاً على `http://localhost:8080`.

بعده أنشئ حساب مالك المنصة (أمر تفاعلي، نافذة أوامر منفصلة):

```powershell
cd backend\KineticEnterprise.Api
dotnet run -- create-platform-owner
```

`-Recreate` يعيد بناء قاعدة التجربة من الصفر، و`-SetupOnly` يجهّز بلا تشغيل.

---

## 8. جولة اللقطات — تحقّق بصري آلي

```powershell
# التقاط عيّنات من الخادم المحلي (مرّة، أو بعد أي تغيير في عقد الـAPI)
python tool\capture_fixtures.py

# توليد لقطة لكل شاشة × كل مقاس
flutter test test\screenshot_tour_test.dart --update-goldens
```

يُنتج 57 لقطة في `test/screenshots/` — تسع عشرة شاشة × ثلاثة مقاسات.

**لماذا تستحق أن تُشغَّل قبل كل تسليم:** الوصف يضلّل. «الشاشة تعمل» جملة
تصدُق ما دام أحد لم ينظر، وقد ثبت ذلك مراراً هنا — بحث الأصناف كان «يعمل»
بينما ينهار التخطيط، وشرائح الفلترة «موجودة» بينما تظهر قائمةً رأسية.
الجولة كشفت في أول تشغيل أربع شبكات بطاقات تفيض على الجهاز اللوحي.

البيانات من عيّنات ملتقطة من الخادم الحقيقي تُخدَم عبر اعتراض طبقة نقل
Dio، فتمرّ كل شاشة بمسار التحليل الحقيقي في مزوّدها — وهو المسار الذي
انكسر فعلاً حين تغيّر عقد نقاط النهاية.

ومن دون `--update-goldens` تُقارَن اللقطات بالمحفوظة، فتكشف أي تغيّر بصري
غير مقصود: هي جولة توثيق وحارس انحدار في آن.

---

## ملخص فحص ما قبل الإطلاق

- [ ] مفتاح JWT جديد وعشوائي على السيرفر
- [ ] `appsettings.Production.json` غير مرفوع على GitHub
- [ ] المستودع Private إن كان النظام تجارياً
- [ ] HTTPS بشهادة حقيقية
- [ ] حساب قاعدة البيانات ليس `db_owner`
- [ ] نسخ احتياطي مجدوَل (`toolackup.ps1 -Install`) ومختبَر الاسترجاع
- [ ] مجلد النسخ يُنسَخ دورياً خارج السيرفر
- [ ] `AllowedOrigins` مضبوط على نطاقك لا `localhost`
- [ ] نسخة الأندرويد موقّعة بمفتاح إصدار حقيقي (`android/key.properties`)
- [ ] نسخة احتياطية من ملف `.jks` محفوظة خارج جهاز البناء
- [ ] تغيير كلمة مرور حسابك من الافتراضية
- [ ] `MIGRATIONS.sql` و`INDEXES.sql` منفَّذان على قاعدة الإنتاج
- [ ] `tool\schema_check.ps1` يمرّ: أعمدة الكيانات متطابقة، ولا جدول بلا
      سياسة عزل أو إعفاء موثَّق
- [x] الخط مضمَّن في `assets/fonts` — لا اعتماد على الشبكة
- [ ] جولة اللقطات مُشغَّلة ومُراجَعة بالعين (`test/screenshots/`)
