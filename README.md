# Kinetic Enterprise — الأساس التقني الجاهز للبيع

> **تحديث المكدس التقني:** تم الانتقال من Supabase/PostgreSQL إلى **SQL Server + Backend منفصل بـ ASP.NET Core (.NET)**، بناءً على قرار استضافة كامل على Windows Server دون اعتماد على أي خدمة سحابية خارجية. راجع `docs/STACK_MIGRATION.md` لتفاصيل القرار، و`docs/DATABASE_SCHEMA_SQLSERVER.sql` للمخطط المحدَّث. ملف `docs/DATABASE_SCHEMA.sql` (نسخة Postgres) أُبقي للتوثيق فقط ولم يعد مستخدَماً.

## ما تم تسليمه في هذه الحزمة
1. **`docs/ARCHITECTURE.md`** — خريطة النظام الكاملة بكل الموديولات (بما فيها اثنان لم تكونا في الوثيقة الأصلية: **الترخيص/الاشتراك**، و**تحويل المخزون بين الفروع**) لضمان عدم وجود ثغرة عند التوسّع مستقبلاً.
2. **`docs/DATABASE_SCHEMA_SQLSERVER.sql`** — مخطط SQL Server كامل جاهز للتنفيذ، بعزل مزدوج (`organization_id` + `branch_id`) عبر Security Policies (المكافئ لـ Row Level Security)، يغطي كل موديول في خريطة النظام. (نسخة Postgres الأصلية محفوظة في `DATABASE_SCHEMA.sql` للأرشيف فقط.)
3. **`docs/COLOR_SYSTEM.md`** — شرح لماذا لوحة ألوان التصاميم الأصلية كانت "لوحة ذكاء اصطناعي جاهزة"، والبديل: هوية "Kinetic Ink & Amber" المصمَّمة يدوياً + محرك ألوان ديناميكي لكل زبون.
4. **مشروع Flutter فعلي** (`lib/`) يطبّق كل ما سبق: نظام Theme ديناميكي، هيكل متجاوب (Responsive) لكل الشاشات، وخمس شاشات مبنية بالكامل كنموذج معياري تُبنى عليه بقية الشاشات. يتصل الآن بالـ Backend عبر `ApiClient` (Dio + JWT) بدل Supabase Client.
5. **مشروع Backend فعلي** (`backend/KineticEnterprise.Api/`) بـ ASP.NET Core: مصادقة JWT، EF Core مع SQL Server، Middleware يفعّل Row-Level Security تلقائياً عبر `SESSION_CONTEXT`، وSignalR Hub للإشعارات اللحظية بديلاً عن Supabase Realtime.

## الشاشات المبنية في هذا التسليم
- تسجيل الدخول (`features/auth`)
- لوحة تحكم المدير العام (`features/dashboard`)
- إدارة الفروع والهوية / White-Labeling (`features/branches`)
- نقطة البيع (`features/pos`)
- إدارة المخزون (`features/inventory`)

كل شاشة أخرى في خريطة النظام محجوزة كمسار في `core/router/app_router.dart` وتعرض حالياً "قيد الإنشاء" بدل خطأ — تُبنى بنفس مكوّنات `shared/widgets/` (الجدول الموحّد، البطاقات، شارة العملة، الشريط الجانبي) فتظهر متوافقة تلقائياً مع كل الشاشات دون إعادة تصميم.

## كيف تعمل الألوان الديناميكية (لا ألوان ثابتة في الكود)
1. عند تسجيل الدخول، يصدر الـ Backend توكن JWT يحمل `organization_id` (و`branch_id` إن لم يكن مديراً عاماً).
2. `branding_provider.dart` في Flutter يستدعي `GET /api/organizations/me` على الـ .NET Backend.
3. `OrganizationsController` يرجع `primary_color` و`secondary_color` و`logo_url` من جدول `organizations` — مفلترة تلقائياً حسب منظمة المستخدم عبر Security Policy.
4. `AppTheme.build(colors)` يبني الثيم بالكامل من هذه القيم لحظياً.
5. لو لم توجد قيم بعد (أول تشغيل) أو تعذّر الاتصال، يُستخدم الافتراضي "Kinetic Ink & Amber" — وليس أي لون Material عشوائي.

هذا يعني: بيع النظام لزبون ثانٍ مستقبلاً لا يحتاج **أي تعديل كود** لتغيير الهوية البصرية — فقط تعبئة صف في جدول `organizations`، أو استخدام شاشة "إدارة الفروع والهوية" (التي تحفظ عبر `PUT /api/organizations/me/branding`).

## التشغيل

### الـ Backend (.NET) — يحتاج .NET 8 SDK و SQL Server **2019 أو 2022 Express فما فوق**
```bash
cd backend/KineticEnterprise.Api
# نفّذ docs/DATABASE_SCHEMA_SQLSERVER.sql على السيرفر أولاً لإنشاء القاعدة
dotnet restore
dotnet run
```
يشتغل افتراضياً على `https://localhost:5001`. عدّل `appsettings.json` بسلسلة الاتصال الفعلية بالسيرفر ومفتاح JWT قبل أي استخدام حقيقي.

### تطبيق Flutter — يحتاج Flutter SDK
```bash
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=https://localhost:5001/api
```

### نسخة الأندرويد
معرّف التطبيق `com.kinetic.enterprise`، أدنى نسخة Android 6.0 (API 23)، وأيقونة
تكيّفية كاملة مولَّدة من `tool/generate_app_icons.ps1`.

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://erp.your-domain.com/api
```

نسخة release تسمح بـ **HTTPS فقط** (`network_security_config.xml`)، وتتطلّب مفتاح
توقيع في `android/key.properties` وإلا وقّعت بمفاتيح debug. التفاصيل الكاملة —
إنشاء المفتاح، التوقيع، تقليل الحجم، حالة الشبكة — في `DEPLOYMENT.md` قسم 4.1.

## ما لم يُبنَ بعد (بوضوح وبدون مبالغة)
هذا التسليم أساس معماري حقيقي (بنية Flutter + Backend، Theme، Routing، مخطط قاعدة بيانات SQL Server كامل، 5 شاشات فعلية، Controller مرجعي للمصادقة والمنتجات والفواتير) — وليس نظاماً تجارياً جاهزاً للتسليم للزبون النهائي بحد ذاته. يتبقى:
- بناء بقية الـ Controllers على الـ Backend (النمط موضَّح في `ProductsController`) وربط بقية شاشات Flutter بها (استعلامات حقيقية بدل بيانات تجريبية ثابتة).
- بناء بقية الشاشات (١١ شاشة) بنفس الأنماط الموضّحة أعلاه.
- كتابة EF Core Migrations فعلية أو تنفيذ `DATABASE_SCHEMA_SQLSERVER.sql` مباشرة، واختبار Security Policies بحسابات مستخدمين مختلفة قبل الإنتاج.
- تكامل الطابعات وقارئ الباركود مع Windows (يتطلب مكتبة Native منفصلة، تُحدَّد بعد تحديد موديل الطابعة الفعلي الذي سيُستخدم).
- منطق الترخيص الفعلي (توليد المفاتيح، ربط الجهاز، تعطيل الميزات حسب الخطة).
- نشر الـ Backend على IIS فعلياً (ASP.NET Core Hosting Bundle) واختبار كامل على المتصفحات وأحجام الشاشات قبل أي عرض للزبون.

هذه القائمة ليست نقصاً في التخطيط — هي بالضبط ما تضمنه `ARCHITECTURE.md`: كل بند منها له جدول جاهز في قاعدة البيانات ومسار محجوز في التطبيق، فلا يوجد أي جزء "غير مخطَّط له".
