-- ============================================================================
-- Kinetic Enterprise ERP — SQL Server Schema (نسخة .NET Backend)
-- تحويل كامل من DATABASE_SCHEMA.sql (Postgres) — نفس التغطية بدون نقصان
--
-- ⚠ الحد الأدنى المطلوب: SQL Server 2016 (13.x) فما فوق.
-- الموصى به فعلياً: SQL Server 2019 أو 2022 Express (مجاني، ومدعوم أمنياً
-- من مايكروسوفت حتى 2025/2028 على التوالي، بخلاف 2008 المتوقف دعمه منذ 2019).
-- السبب: SESSION_CONTEXT وCREATE SECURITY POLICY (المستخدَمان في نظام
-- العزل بين الفروع والزبائن أسفل هذا الملف) وISJSON غير متوفرة قبل 2016.
-- ============================================================================

CREATE DATABASE KineticEnterprise;
GO
USE KineticEnterprise;
GO

-- ضبط صريح لمستوى التوافق (150 = محرك 2019، 160 = محرك 2022) — غير
-- إلزامي لعمل SESSION_CONTEXT/Security Policy (يعتمدان على إصدار المحرك
-- نفسه لا على مستوى التوافق)، لكنه ممارسة سليمة لضمان استخدام أحدث
-- سلوك لمُحسِّن الاستعلامات المتاح فعلياً على السيرفر المُثبَّت.
-- عدّل الرقم إلى 160 إذا كان المحرك المثبَّت 2022.
ALTER DATABASE KineticEnterprise SET COMPATIBILITY_LEVEL = 150;
GO

-- ----------------------------------------------------------------------------
-- 1. المنظمات (Tenants) والتراخيص
-- ----------------------------------------------------------------------------
CREATE TABLE organizations (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  legal_name NVARCHAR(200) NOT NULL,
  display_name NVARCHAR(200) NOT NULL,
  -- شكل النظام لا حجمه: standard | wallet | pharmacy | trial | enterprise.
  -- منه تُشتقّ الوحدات المتاحة — راجع Editions في Entities.cs.
  --
  -- كان يُضاف بالترحيل وحده وغائباً عن هذا الملف، فقاعدة تُبنى منه مباشرةً
  -- تفتقد عموداً يقرأه النظام في كل طلب محميّ بـRequireModule.
  edition NVARCHAR(20) NOT NULL DEFAULT 'standard',
  logo_url NVARCHAR(400) NULL,
  primary_color CHAR(7) NOT NULL DEFAULT '#0B2540',
  secondary_color CHAR(7) NOT NULL DEFAULT '#C8952B',
  currency_code CHAR(3) NOT NULL DEFAULT 'LYD',
  currency_symbol NVARCHAR(10) NOT NULL DEFAULT N'د.ل',
  locale NVARCHAR(5) NOT NULL DEFAULT 'ar',
  tax_rate DECIMAL(5,2) NOT NULL DEFAULT 0,           -- ARCHITECTURE.md §2.14
  password_min_length INT NOT NULL DEFAULT 6,          -- ARCHITECTURE.md §2.14
  barcode_template NVARCHAR(MAX) NOT NULL              -- ARCHITECTURE.md §2.12
    DEFAULT N'{"widthMm":40,"heightMm":25,"showName":true,"showPrice":true,"showSku":false}',
  -- الرقم الضريبي ورقم السجلّ التجاري — تطلبهما الفاتورة الرسمية، ولم يكن
  -- لهما موضع فيُكتبان بخطّ اليد أو لا يُكتبان.
  tax_number NVARCHAR(50) NULL,
  commercial_registry NVARCHAR(50) NULL,
  -- قالب الإيصال: JSON واحد لا عمودٌ لكل خيار — نفس نهج barcode_template.
  receipt_template NVARCHAR(MAX) NOT NULL
    CONSTRAINT df_organizations_receipt_template DEFAULT
    N'{"paper":"roll80","showLogo":true,"showTaxNumber":true,"showCommercialRegistry":false,"showQr":false,"headerText":null,"footerText":"شكراً لتعاملكم معنا"}',
  receipt_width_mm DECIMAL(5,2) NOT NULL DEFAULT 80,    -- ARCHITECTURE.md §2.12
  -- تخطيط التنقّل: شريط جانبي ثابت أو شريط علوي أفقي — يختاره كل عميل
  -- لمنظمته حسب تفضيله، بلا أي فرق في الوظائف.
  nav_layout NVARCHAR(20) NOT NULL DEFAULT 'sidebar'
    CHECK (nav_layout IN ('sidebar','navbar')),
  -- السماح ببيع الأصناف مفتوحة القيمة في نقطة البيع. مطفأ افتراضياً: قيمة
  -- يكتبها الكاشير بنفسه لا تقابلها بضاعة في المخزون. يضبطه مدير المنظمة.
  pos_allow_open_product BIT NOT NULL DEFAULT 0,
  -- منطقة المنظمة الزمنية. «اليوم» يُقاس بها لا بـUTC: محلٌّ في طرابلس بين
  -- العاشرة مساءً ومنتصف الليل كان يُسجّل مصروف اليوم في يوم أمس.
  -- والتخزين يبقى UTC — يُحوَّل ما يُقارَن باليوم أو يُعرَض فقط.
  time_zone_id NVARCHAR(60) NOT NULL DEFAULT N'Libya',
  -- مظروف أنماط بطاقة المحفظة: المنظمة تحدّد المسموح والسقف والافتراضي،
  -- والزبون يختار داخله. راجع CardModeGate.
  card_modes_allowed NVARCHAR(100) NOT NULL DEFAULT 'card,pin',
  card_mode_default NVARCHAR(20) NOT NULL DEFAULT 'pin',
  -- سقف نمط «بطاقة فقط». صفر = النمط معطَّل فعلياً.
  card_open_mode_daily_cap DECIMAL(18,2) NOT NULL DEFAULT 50,
  -- النسخة الاحتياطية التلقائية إلى Google Drive. الساعة بتوقيت المنظمة لا
  -- بـUTC (راجع OrgClock)، ورمز التحديث سرٌّ لا يخرج في أي استجابة.
  auto_backup_enabled BIT NOT NULL DEFAULT 0,
  auto_backup_hour INT NOT NULL DEFAULT 3,
  google_refresh_token NVARCHAR(MAX) NULL,
  google_account_email NVARCHAR(200) NULL,
  google_folder_id NVARCHAR(100) NULL,
  last_auto_backup_at DATETIME2 NULL,
  last_auto_backup_status NVARCHAR(20) NULL,
  last_auto_backup_error NVARCHAR(500) NULL,
  -- حقول إضافية يعرّفها مالك المنظمة لحسابات الدليل. JSON لا أعمدة: قيمُ
  -- عرضٍ لا يُستعلَم عنها، وعمودٌ لكل حقل يعني هجرةً لكل عميل.
  account_field_defs_json NVARCHAR(MAX) NOT NULL DEFAULT N'[]',
  is_active BIT NOT NULL DEFAULT 1,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  updated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE licenses (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  license_key NVARCHAR(100) NOT NULL UNIQUE,
  plan_tier NVARCHAR(20) NOT NULL DEFAULT 'standard'
    CHECK (plan_tier IN ('trial','standard','professional','enterprise')),
  max_branches INT NOT NULL DEFAULT 1,
  max_users INT NOT NULL DEFAULT 5,
  enabled_modules NVARCHAR(MAX) NOT NULL DEFAULT N'["inventory","pos","customers","reports"]', -- JSON
  -- الوحدات تُباع فوق الإصدار: فارقان لا قائمة كاملة — راجع
  -- LicenseLimits.EffectiveModules، وenabled_modules أعلاه مشتقّة منهما
  -- للعرض والعقد لا للفرض.
  granted_modules NVARCHAR(MAX) NOT NULL DEFAULT N'[]', -- JSON
  revoked_modules NVARCHAR(MAX) NOT NULL DEFAULT N'[]', -- JSON
  hardware_fingerprint NVARCHAR(200) NULL,
  issued_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  expires_at DATETIME2 NOT NULL,
  status NVARCHAR(20) NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','grace_period','expired','revoked')),
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  -- قراءة فقط: كل ما ليس GET يُرفض. عمود واحد يخدم ثلاث حاجات — نسخة
  -- العرض التي تُرى ولا تُعدَّل، والعميل المتأخّر يُجمَّد بلا فقد بياناته،
  -- ومهلة ما بعد الانتهاء (ARCHITECTURE.md §2.2). راجع LicenseGateAttribute.
  is_read_only BIT NOT NULL DEFAULT 0,
  -- سبب التجميد أو الإنهاء — يُعرض للعميل نفسه لا لنا وحدنا.
  status_reason NVARCHAR(300) NULL,
  status_changed_at DATETIME2 NULL,
  -- شروط العقد المالية — على licenses لا على organizations: هي شروط الاشتراك
  -- لا هوية الشركة، وتتغيّر مع كل تجديد بينما الهوية ثابتة.
  monthly_fee DECIMAL(18,3) NOT NULL CONSTRAINT df_licenses_monthly_fee DEFAULT 0,
  storage_fee DECIMAL(18,3) NOT NULL CONSTRAINT df_licenses_storage_fee DEFAULT 0,
  maintenance_rate DECIMAL(9,3) NOT NULL CONSTRAINT df_licenses_maintenance_rate DEFAULT 0,
  CONSTRAINT CK_licenses_modules_json CHECK (ISJSON(enabled_modules) = 1),
  CONSTRAINT CK_licenses_granted_modules_json CHECK (ISJSON(granted_modules) = 1),
  CONSTRAINT CK_licenses_revoked_modules_json CHECK (ISJSON(revoked_modules) = 1)
);
GO

-- صف واحد عالمي (لا organization_id) — بيانات تواصل مالك المنصة (مشغّل
-- النظام) نفسه، تُعرض لكل عملاء المنصة كافة كجهة دعم فني واحدة. لا تحتاج
-- RLS لأنها ليست بيانات تخص منظمة بعينها. راجع PlatformSettingsController.cs.
CREATE TABLE platform_settings (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  company_name NVARCHAR(200) NOT NULL DEFAULT N'',
  owner_name NVARCHAR(150) NOT NULL DEFAULT N'',
  phone NVARCHAR(30) NULL,
  whatsapp NVARCHAR(30) NULL,
  email NVARCHAR(200) NULL,
  address NVARCHAR(300) NULL,
  updated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- ----------------------------------------------------------------------------
-- 2. الفروع
-- ----------------------------------------------------------------------------
CREATE TABLE branches (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name NVARCHAR(150) NOT NULL,
  code NVARCHAR(20) NOT NULL,
  address NVARCHAR(300) NULL,
  phone NVARCHAR(30) NULL,
  is_active BIT NOT NULL DEFAULT 1,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  updated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  -- لوح خلفية الفرع: يميّز **المكان** لا الشخص. موظف ينتقل بين فرعين يعرف
  -- من اللون أين هو، وهو ما يمنع إدخال بيانات في الفرع الخطأ — أشيع أخطاء
  -- الأنظمة متعدّدة الفروع. ولا يمسّ ألوان العلامة التجارية.
  theme_palette NVARCHAR(20) NOT NULL DEFAULT 'default',
  CONSTRAINT CK_branches_theme_palette
    CHECK (theme_palette IN ('default','warm','cool','green','slate')),
  CONSTRAINT UQ_branches_org_code UNIQUE (organization_id, code)
);
GO

-- ----------------------------------------------------------------------------
-- 3. المستخدمون والصلاحيات
-- ----------------------------------------------------------------------------
CREATE TABLE app_users (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),      -- يقابل AspNetUsers.Id
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NULL REFERENCES branches(id),  -- NULL = صلاحية على كل الفروع
  full_name NVARCHAR(150) NOT NULL,
  email NVARCHAR(200) NOT NULL,
  -- اسم دخول مختصر اختياري (بديل عن البريد الكامل للعمال) — تفرّده يُطبَّق
  -- عبر فهرس مُصفَّى أدناه، وليس CONSTRAINT UNIQUE عادي: خلافاً لِـ Postgres،
  -- SQL Server يمنع تكرار NULL في UNIQUE CONSTRAINT عادي (صف واحد فقط بلا
  -- اسم مستخدم لكل منظمة)، وهذا بالضبط عكس المطلوب لحقل اختياري.
  username NVARCHAR(50) NULL,
  password_hash NVARCHAR(400) NOT NULL,   -- أو FK إلى AspNetUsers إذا استُخدم Identity كاملاً
  role NVARCHAR(30) NOT NULL DEFAULT 'cashier'
    CHECK (role IN ('super_admin','branch_manager','cashier','inventory_officer','accountant','custom')),
  is_active BIT NOT NULL DEFAULT 1,
  -- مالك المنصة (مشغّل النظام) فقط — يمنح صلاحية تزويد منظمات (عملاء) جدد
  -- عبر PlatformController، منفصلة عن super_admin العادي المحصور بمنظمته.
  is_platform_admin BIT NOT NULL DEFAULT 0,
  -- دور حساب المنصّة بعد البوّابة: مالكٌ يرى الكلّ، أو مهندس بيع يرى ما
  -- باعه. وNULL يعني **مالكاً** — حسابات المنصّة القائمة قبل هذا العمود
  -- أُنشئت كلّها مالكة. راجع PlatformRoles.IsOwner وPlatformScope.
  platform_role NVARCHAR(20) NULL
    CONSTRAINT CK_app_users_platform_role
    CHECK (platform_role IS NULL OR platform_role IN ('owner','engineer')),
  -- رقم ترخيص البائع — يُطبع في عقد كل عميل باعه، فيُعرَف من باع لمن من
  -- الورقة وحدها. تفرّده عبر فهرس مُصفَّى أدناه لنفس سبب username.
  reseller_license NVARCHAR(40) NULL,
  -- كلمةٌ مؤقّتة تنتظر التغيير: تُرفع عند كل إعادة تعيين من غير صاحب
  -- الحساب، وتُخفض حين يغيّرها هو. راجع MustChangePasswordFilter.
  must_change_password BIT NOT NULL DEFAULT 0,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT UQ_app_users_org_email UNIQUE (organization_id, email)
);
GO

CREATE UNIQUE INDEX UQ_app_users_reseller_license
  ON app_users(reseller_license) WHERE reseller_license IS NOT NULL;
GO

-- فهرس مُصفَّى (WHERE username IS NOT NULL) بدل UNIQUE CONSTRAINT عادي —
-- يسمح بأي عدد من المستخدمين بلا اسم مستخدم، وتفرّد فقط عند تعيينه فعلياً.
CREATE UNIQUE INDEX UQ_app_users_org_username ON app_users (organization_id, username)
  WHERE username IS NOT NULL;
GO

-- فهرس عالمي (لا RLS) لكل المنظمات التي زوَّدها مالك المنصة — منفصل عمداً
-- عن organizations نفسها (المحمية بـ RLS) لأن مالك المنصة يحتاج رؤية كل
-- عملائه معاً في شاشة واحدة، وRLS لا تسمح بذلك دون تعديل دوال المسند
-- المستخدَمة في 15+ جدولاً آخر (مخاطرة أعلى من فائدتها هنا). يُملأ من
-- PlatformController.Create فقط، عبر الاتصال العادي (لا Security Policy
-- على هذا الجدول إطلاقاً فلا حاجة لأي التفاف).
CREATE TABLE platform_organizations (
  id UNIQUEIDENTIFIER PRIMARY KEY,
  legal_name NVARCHAR(200) NOT NULL,
  display_name NVARCHAR(200) NOT NULL,
  is_active BIT NOT NULL DEFAULT 1,
  -- حساب المنصّة الذي باع هذه المنظمة — مدار العزل بين مهندسي البيع.
  --
  -- هنا لا على جدول organizations: هذا الجدول هو الوحيد غير المحميّ بعزل
  -- الصفوف (عمداً — يقرؤه مالك المنصّة كلّه)، فعليه يقع الترشيح.
  --
  -- ولا مفتاح أجنبي إلى app_users عمداً: حذف حساب مهندس غادر يجب ألّا
  -- يمنعه عميلٌ منسوب إليه. والنسبة المعلّقة تُصلَح من نقطة assign.
  owner_user_id UNIQUEIDENTIFIER NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE permissions (
  code NVARCHAR(60) PRIMARY KEY,
  label_ar NVARCHAR(150) NOT NULL,
  module NVARCHAR(60) NOT NULL
);
GO

-- الصلاحيات المتاحة في النظام — كتالوج ثابت يقرأه RequirePermissionAttribute
-- وتعرضه شاشة مصفوفة الصلاحيات. بادئة N إلزامية على كل نص عربي: بدونها
-- يُحوَّل إلى ترميز النظام ويُخزَّن تالفاً بلا أي رسالة خطأ.
--
-- role_permissions يحمل مفتاحاً أجنبياً على هذا الجدول، وإنشاء أي منظمة
-- يُدرج صفوف الأدوار الافتراضية — فبقاء هذا الجدول فارغاً كان يعني فشل
-- إنشاء أول منظمة على أي تثبيت جديد.
INSERT INTO permissions (code, label_ar, module) VALUES
  ('inventory.manage',        N'إدارة المنتجات (إضافة/تعديل/تسوية مخزون)', N'inventory'),
  ('inventory.delete',        N'حذف المنتجات',                              N'inventory'),
  ('categories.manage',       N'إدارة تصنيفات المنتجات',                    N'inventory'),
  ('suppliers.manage',        N'إدارة الموردين',                            N'suppliers'),
  ('suppliers.delete',        N'حذف الموردين',                              N'suppliers'),
  ('purchasing.manage',       N'إدارة أوامر الشراء',                        N'purchasing'),
  ('stock_transfer.manage',   N'تحويل المخزون بين الفروع',                  N'stock_transfer'),
  ('stock_count.manage',      N'الجرد الدوري',                              N'stock_count'),
  ('customers.manage',        N'إدارة بيانات العملاء',                      N'customers'),
  ('customers.delete',        N'حذف العملاء',                               N'customers'),
  ('customers.wallet_adjust', N'تعديل رصيد محفظة العميل',                   N'customers'),
  ('cards.issue',             N'إصدار بطاقات العملاء وضبط أرقامها السرية',  N'customers'),
  ('prescriptions.dispense',  N'صرف الأدوية المقيَّدة بوصفة وتسجيلها',       N'pharmacy'),
  ('invoices.refund',         N'استرجاع الفواتير',                          N'invoices'),
  ('pos.price_override',      N'البيع بسعر مخالف لسعر الكتالوج',            N'pos'),
  ('expenses.manage',        N'تسجيل المصروفات',                           N'expenses'),
  ('reports.view',            N'عرض التقارير',                              N'reports'),
  ('audit_log.view',          N'عرض سجل التدقيق',                           N'audit_log'),
  ('license.view',            N'عرض الترخيص والاشتراك',                     N'license'),
  ('backup.manage',           N'تنزيل نسخة احتياطية من بيانات المنظمة',      N'backup');
GO

CREATE TABLE role_permissions (
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  role NVARCHAR(30) NOT NULL,
  permission_code NVARCHAR(60) NOT NULL REFERENCES permissions(code),
  CONSTRAINT PK_role_permissions PRIMARY KEY (organization_id, role, permission_code)
);
GO

CREATE TABLE login_history (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  user_id UNIQUEIDENTIFIER NOT NULL REFERENCES app_users(id),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id),
  ip_address NVARCHAR(50) NULL,
  device_info NVARCHAR(300) NULL,
  success BIT NOT NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- ----------------------------------------------------------------------------
-- 4. المخزون والموردون
-- ----------------------------------------------------------------------------
CREATE TABLE suppliers (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name NVARCHAR(150) NOT NULL,
  phone NVARCHAR(30) NULL,
  balance DECIMAL(14,2) NOT NULL DEFAULT 0,
  is_deleted BIT NOT NULL DEFAULT 0,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE product_categories (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name NVARCHAR(150) NOT NULL,
  parent_id UNIQUEIDENTIFIER NULL REFERENCES product_categories(id)
);
GO

-- ----------------------------------------------------------------------------
--  نشرة الدواء — معرفة دوائية عامة على مستوى المنصّة
--
--  بلا organization_id وبلا Security Policy، كجدول platform_settings:
--  «باراسيتامول 500 مجم» له نفس موانع الاستعمال في كل صيدلية. ربطه بالمنظمة
--  كان يعني أن كل عميل جديد يبدأ بنشرات فارغة يُدخلها من الصفر — فتُهمَل
--  الميزة عملياً. والسعر والمخزون يبقيان على products وstock_levels حيث
--  ينتميان، فلا تسرّب بيانات بين المنظمات عبر هذا الجدول.
--
--  يُقرأ فقط لمن يملك وحدة pharmacy (إصدار الصيدليات) — النظام يُباع لبقالة
--  ومحل قطع غيار أيضاً، وحقول «موانع الاستعمال» في شاشة أصنافهم ضوضاء لا
--  ميزة. راجع Editions في Entities.cs.
-- ----------------------------------------------------------------------------
CREATE TABLE medicine_reference (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  name NVARCHAR(200) NOT NULL,
  active_ingredient NVARCHAR(200) NOT NULL,
  -- نصّ لا رقم: الوحدة جزء من التركيز (500 مجم، 250 مجم/5 مل).
  strength NVARCHAR(60) NULL,
  form NVARCHAR(60) NULL,
  indications NVARCHAR(1000) NULL,
  contraindications NVARCHAR(1000) NULL,
  cautions NVARCHAR(1000) NULL,
  side_effects NVARCHAR(1000) NULL,
  requires_prescription BIT NOT NULL DEFAULT 0,
  is_deleted BIT NOT NULL DEFAULT 0,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  updated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE products (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  category_id UNIQUEIDENTIFIER NULL REFERENCES product_categories(id),
  supplier_id UNIQUEIDENTIFIER NULL REFERENCES suppliers(id),
  sku NVARCHAR(60) NOT NULL,
  barcode NVARCHAR(60) NULL,
  name NVARCHAR(200) NOT NULL,
  unit_base NVARCHAR(30) NOT NULL DEFAULT 'piece',
  unit_conversion_factor DECIMAL(10,3) NOT NULL DEFAULT 1,
  -- ---- البيع بالوحدة الجزئية ----
  -- الصيدلية تشتري شريطاً وتبيع حبّة. المخزون يُعدّ بالوحدة الأساسية دائماً
  -- (شريط)، والبيع الجزئي يخصم كسراً منها — وquantity في stock_levels
  -- من نوع DECIMAL(14,3) فيتّسع للكسر أصلاً.
  --
  -- أعمدة صريحة لا إعادة استعمال unit_conversion_factor: اسمه لا يقول
  -- الاتجاه (من الأساس إلى الجزء أم العكس)، والالتباس في حساب مال ومخزون
  -- لا يُحتمَل. وهو غير مستعمل في أي منطق حتى الآن.
  sub_unit_name NVARCHAR(30) NULL,               -- حبّة، قرص، مل
  -- كم وحدة جزئية في الوحدة الأساسية. صفر أو واحد = لا بيع جزئي.
  sub_units_per_base DECIMAL(10,3) NOT NULL DEFAULT 0,
  -- سعر الوحدة الجزئية مستقلٌّ لا يُشتقّ بالقسمة: الصيدلية تربح على التجزئة،
  -- فحبّة من شريط بثمانية دنانير تُباع بدينار لا بـ0.80.
  sub_unit_price DECIMAL(14,2) NOT NULL DEFAULT 0,
  cost_price DECIMAL(14,2) NOT NULL DEFAULT 0,
  sale_price DECIMAL(14,2) NOT NULL DEFAULT 0,
  -- الحدّ الأدنى لسعر البيع. صفر = بلا حدّ.
  --
  -- لم يكن ثمّة ما يمنع البيع تحت التكلفة: صلاحية تعديل السعر تسمح بأي رقم،
  -- ومدير المنظمة يملكها دائماً. وهو حدٌّ مطلق لا يتجاوزه أحد — حدٌّ له
  -- استثناء ليس حدّاً.
  min_sale_price DECIMAL(14,2) NOT NULL CONSTRAINT df_products_min_sale_price DEFAULT 0,
  -- اختياري دائماً: الصيدلية نفسها تبيع مستحضرات تجميل وحفاضات وأدوات.
  medicine_ref_id UNIQUEIDENTIFIER NULL REFERENCES medicine_reference(id),
  track_expiry BIT NOT NULL DEFAULT 0,
  -- صنف غير متتبَّع مخزنياً (خدمة أو قيمة مفتوحة) — يُباع بلا رصيد ولا خصم
  tracks_stock BIT NOT NULL DEFAULT 1,
  -- حدّ إعادة الطلب اليدوي. يبقى المرجع الفعلي للتنبيه، والنظام يقترح
  -- بديلاً مشتقّاً من الاستهلاك دون أن يكتبه فوقه — راجع تقرير إعادة الطلب.
  reorder_level DECIMAL(14,2) NOT NULL DEFAULT 0,
  -- مهلة التوريد بالأيام: كم يوماً بين إرسال أمر الشراء ووصول البضاعة.
  -- هي نصف معادلة إعادة الطلب (الاستهلاك اليومي × المهلة)، وبدونها يصبح
  -- الحدّ رقماً يُخمَّن. سبعة أيام افتراض معقول لمورّد محلي ويُعدَّل لكل صنف.
  lead_time_days INT NOT NULL DEFAULT 7,
  -- آخر مرّة عُدّ فيها هذا الصنف فعلياً (اعتُمد جرد يشمله). هو ما يجعل
  -- الجرد الدوري الموزَّع ممكناً: يُعدّ ما لم يُعدّ منذ مدّة بدل إغلاق
  -- المحل يوماً كاملاً لعدّ كل شيء.
  last_counted_at DATETIME2 NULL,
  is_deleted BIT NOT NULL DEFAULT 0,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  updated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT UQ_products_org_sku UNIQUE (organization_id, sku)
);
GO

-- ----------------------------------------------------------------------------
--  المستودعات — تحت الفرع لا بدلاً منه
--
--  warehouse_id قابل للـ NULL في كل مكان يشير إليه، وNULL يعني «مستودع
--  الفرع الافتراضي». هذه القابلية هي ما يجعل الشجرة تُضاف بلا ترحيل بيانات
--  ولا كسر لبقالة أو صيدلية قائمة.
--
--  ومستودع العبور يصلح عطباً قائماً: تحويل في حالة in_transit كان يُخصم من
--  المصدر ولا يُضاف للهدف، فتختفي البضاعة من كل تقرير طوال الترحيل.
-- ----------------------------------------------------------------------------
CREATE TABLE warehouses (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id) ON DELETE NO ACTION,
  parent_warehouse_id UNIQUEIDENTIFIER NULL REFERENCES warehouses(id),
  name NVARCHAR(120) NOT NULL,
  code NVARCHAR(40) NOT NULL DEFAULT '',
  kind NVARCHAR(20) NOT NULL DEFAULT 'main',
  CONSTRAINT CK_warehouses_kind
    CHECK (kind IN ('main','transit','damaged','returns','quarantine')),
  -- عقدة تجميعية لا تُخزَّن فيها بضاعة: السماح بالتخزين فيها يجعل المجموع
  -- يعدّ الأب والابن معاً.
  is_group BIT NOT NULL DEFAULT 0,
  is_active BIT NOT NULL DEFAULT 1,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- ----------------------------------------------------------------------------
--  دفتر حركة المخزون — مصدر الحقيقة، وstock_levels ذاكرة مشتقّة منه
--
--  كان الرصيد يُعدَّل في مكانه: فلا جواب عن «كم كان الرصيد يوم كذا»، ولا
--  تكلفة حقيقية (سعر واحد ثابت للصنف مهما اختلفت أسعار الشراء)، ولا أثر
--  يُجمَع حسابياً لمن غيّر ماذا.
--
--  يُلحَق به ولا يُعدَّل: التصحيح بسطر عكسي لا بمحو الماضي — نفس حرمة القيد
--  في دفتر المحفظة. وis_cancelled إلغاء منطقي لا حذف.
--
--  **كل** حركة مخزون في النظام تمرّ من StockLedger وحده (Data/StockLedger.cs)
--  داخل المعاملة التي تُعدّل الرصيد. لا مسار يستثنيه.
-- ----------------------------------------------------------------------------
CREATE TABLE stock_ledger_entries (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id) ON DELETE NO ACTION,
  warehouse_id UNIQUEIDENTIFIER NULL REFERENCES warehouses(id),
  product_id UNIQUEIDENTIFIER NOT NULL REFERENCES products(id),
  batch_number NVARCHAR(60) NOT NULL DEFAULT '',
  expiry_date DATETIME2 NULL,
  -- datetime لا date: ترتيب حركات اليوم الواحد يحدّد الرصيد بعد كلٍّ منها،
  -- وتاريخ بلا وقت يجعل ترتيب البيع والاستلام في اليوم نفسه اعتباطياً.
  posted_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  -- الفرق موجباً أو سالباً — لا رصيداً.
  quantity_change DECIMAL(14,3) NOT NULL,
  balance_after DECIMAL(14,3) NOT NULL,
  unit_cost DECIMAL(14,2) NOT NULL DEFAULT 0,
  value_after DECIMAL(18,2) NOT NULL DEFAULT 0,
  value_change DECIMAL(18,2) NOT NULL DEFAULT 0,
  source_type NVARCHAR(30) NOT NULL,
  source_id UNIQUEIDENTIFIER NULL,
  -- سطر الإدخال الذي استُهلك منه — في سطور الصرف وحدها.
  --
  -- هذا ما يميّز الدفتر عن دفتر عادي: الأخير يقول «خرجت خمس قطع»، وهذا يقول
  -- «خرجت خمس قطع من الشحنة التي وصلت يوم كذا بتكلفة كذا». منه تُقرأ التكلفة
  -- الدقيقة بلا طابور FIFO يُخزَّن ويُصان، ومنه يُجاب سؤال التتبّع العكسي —
  -- وهو مطلب تنظيمي في الأدوية والغذاء لا رفاهية.
  source_entry_id UNIQUEIDENTIFIER NULL REFERENCES stock_ledger_entries(id),
  -- المتبقّي من هذا الإدخال لم يُستهلَك بعد — في سطور الإدخال وحدها.
  remaining_quantity DECIMAL(14,3) NOT NULL DEFAULT 0,
  created_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  is_cancelled BIT NOT NULL DEFAULT 0,
  cancel_reason NVARCHAR(300) NULL
);
GO

CREATE TABLE stock_levels (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  -- branch_id وproduct_id بدون CASCADE عمداً: كلاهما يصل لجدول organizations
  -- عبر مسار آخر (branches->organizations وproducts->organizations)،
  -- فلو أضفنا CASCADE هنا أيضاً سيصبح لدى SQL Server أكثر من مسار حذف
  -- متتالٍ لنفس الجدول الجذري، وهذا مرفوض دائماً بغض النظر عن الإصدار.
  -- عملياً هذا متوافق مع مبدأ "لا حذف فعلي" أصلاً (راجع DATABASE_TABLES_GUIDE.md §1.4).
  branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id) ON DELETE NO ACTION,
  product_id UNIQUEIDENTIFIER NOT NULL REFERENCES products(id) ON DELETE NO ACTION,
  quantity DECIMAL(14,3) NOT NULL DEFAULT 0,
  batch_number NVARCHAR(60) NOT NULL DEFAULT '',
  expiry_date DATE NULL,
  -- موضع التخزين داخل الفرع. NULL = مستودع الفرع الافتراضي — راجع warehouses.
  warehouse_id UNIQUEIDENTIFIER NULL REFERENCES warehouses(id),
  -- تاريخ الاستراتيجية: أساس ترتيب الصرف بحقل واحد.
  --
  --   صنف بصلاحية   → تاريخ الانتهاء  ⇒ FEFO (الأقرب انتهاءً أولاً)
  --   صنف بلا صلاحية → تاريخ الإدخال   ⇒ FIFO (الأقدم دخولاً أولاً)
  --
  -- فقاعدة ترتيب واحدة تخدم الحالتين بدل منطقين منفصلين. والعطب الذي
  -- يصلحه: الصنف بلا صلاحية كان يُرتَّب برقم دفعته أبجدياً — أي عشوائياً —
  -- فتبقى دفعته القديمة على الرفّ لأن رقمها يبدأ بحرف متأخّر.
  --
  -- NULL = صنف يتتبّع الصلاحية ووصلت دفعته بلا تاريخ. يُؤخَّر في الترتيب
  -- عمداً: المعلوم أولى بالتصريف من المجهول.
  strategy_date DATETIME2 NULL,
  -- القفل: إيقاف الدفعة عن الصرف مع بقائها في مكانها وبكمّيتها.
  --
  -- تصل دفعة بشبهة عيب أو تُرتجع بضاعة تنتظر المعاينة، والحلول الثلاثة
  -- الأخرى كلها معطوبة: حذف الصفّ يفقد الكمية ويكسر التدقيق، وتركه يعني
  -- بيعها، ونقلها إلى فرع وهمي يشوّه تقارير الفروع.
  --
  -- الموقوف يخرج من: البيع، وحساب إعادة الطلب، والتحويل بين الفروع.
  -- ويبقى في: الجرد، وقيمة المخزون، وتقرير الصلاحية.
  --
  -- على الدفعة لا الصنف: ثلاث شحنات من نفس الدواء تُشتبَه واحدة منها،
  -- وقفل الصنف كلّه كان يوقف بضاعة سليمة.
  is_locked BIT NOT NULL DEFAULT 0,
  -- إلزامي منطقياً عند القفل (يفرضه StockLocksController لا القيد، لأن
  -- الصفوف غير الموقوفة تحمله NULL): قفلٌ بلا سبب يصبح بعد أسبوعين كميةً
  -- مجمَّدة لا يعرف أحد لماذا جُمِّدت ولا متى يُفرَج عنها.
  lock_reason NVARCHAR(300) NULL,
  locked_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  locked_at DATETIME2 NULL,
  updated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT UQ_stock_levels UNIQUE (branch_id, product_id, batch_number)
);
GO

CREATE TABLE stock_transfers (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  from_branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id),
  to_branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id),
  status NVARCHAR(20) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','in_transit','received','cancelled')),
  created_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE stock_transfer_items (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  transfer_id UNIQUEIDENTIFIER NOT NULL REFERENCES stock_transfers(id) ON DELETE CASCADE,
  product_id UNIQUEIDENTIFIER NOT NULL REFERENCES products(id),
  quantity DECIMAL(14,3) NOT NULL
);
GO

CREATE TABLE purchase_orders (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id),
  supplier_id UNIQUEIDENTIFIER NULL REFERENCES suppliers(id),
  status NVARCHAR(20) NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','ordered','received','cancelled')),
  -- أمرٌ ولّده اقتراح إعادة الطلب لا يدُ مستخدم. يجعل الأتمتة قابلة
  -- للمراجعة: مدير يرى عشرين أمراً لا يعرف أيّها قراره وأيّها قرار معادلة،
  -- فلا يستطيع الحكم على المعادلة أصلاً — وصندوقٌ أسود يُوقَف بعد أول خطأ.
  is_auto BIT NOT NULL DEFAULT 0,
  total_amount DECIMAL(14,2) NOT NULL DEFAULT 0,
  created_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE purchase_order_items (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  purchase_order_id UNIQUEIDENTIFIER NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
  product_id UNIQUEIDENTIFIER NOT NULL REFERENCES products(id),
  quantity DECIMAL(14,3) NOT NULL,
  unit_cost DECIMAL(14,2) NOT NULL,
  -- سعر بيع اختياري جديد لهذه الدفعة — عند الاستلام يُحدَّث سعر بيع الصنف
  -- به إن حُدِّد (NULL = يبقى سعر البيع الحالي كما هو).
  sale_price DECIMAL(14,2) NULL,
  -- الكمية المستلَمة فعلياً. كان الاستلام كلّه-أو-لا-شيء، فأي توريد ناقص لا
  -- يمكن تسجيله كما وقع: إمّا يُستلَم الأمر كاملاً (فيدخل المخزون بضاعة لم
  -- تصل) أو يبقى معلَّقاً (فلا تدخل بضاعة وصلت). كلاهما رصيد خاطئ.
  received_quantity DECIMAL(18,3) NOT NULL CONSTRAINT df_po_items_received DEFAULT 0
);
GO

-- ----------------------------------------------------------------------------
--  مستند الاستلام — شحنة واحدة وصلت فعلياً من أمر شراء
--
--  كان الاستلام يزيد purchase_order_items.received_quantity فقط. فثلاث
--  شحنات جزئية تُبتلع في رقم واحد، ويضيع معها ما لا يُستعاد: متى وصلت كل
--  شحنة (فلا تُقاس مهلة التوريد الحقيقية)، ورقم إشعار المورّد وهو المرجع
--  الوحيد عند الخلاف، وأي شحنة تخصّ أي فاتورة مورّد حين تُبنى المطابقة.
--
--  وهو شرط مسبق لدفتر حركة المخزون (ARCHITECTURE.md §2.15): سطر الإدخال
--  يجب أن يشير إلى مستند وصول حقيقي لا إلى أمر شراء يصل على دفعات.
-- ----------------------------------------------------------------------------
CREATE TABLE purchase_receipts (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id) ON DELETE NO ACTION,
  purchase_order_id UNIQUEIDENTIFIER NOT NULL REFERENCES purchase_orders(id) ON DELETE NO ACTION,
  -- رقم إشعار المورّد كما كتبه على ورقته. اختياري: مورّد محلي كثيراً ما
  -- يسلّم بلا إشعار مرقَّم، وإلزامه يدفع المستخدم إلى كتابة أي شيء ليمرّ —
  -- وحقلٌ مملوء بالقمامة أسوأ من حقل فارغ لأن الأول يُصدَّق.
  supplier_note_number NVARCHAR(60) NULL,
  -- تاريخ الوصول الفعلي، منفصل عن created_at عمداً: الشحنة تصل الخميس
  -- ويُدخلها أمين المخزن الأحد، فقياس المهلة بتاريخ الإدخال يضيف يومين
  -- وهميين في كل مرّة.
  received_on DATETIME2 NOT NULL,
  received_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  notes NVARCHAR(300) NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE purchase_receipt_items (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  purchase_receipt_id UNIQUEIDENTIFIER NOT NULL REFERENCES purchase_receipts(id) ON DELETE CASCADE,
  -- سطر الأمر إلى جانب الصنف لا بدلاً منه: الأمر قد يحمل سطرين لنفس الصنف
  -- بتكلفتين، والربط بالصنف وحده يجعل نسبة الشحنة إلى سطرها تخميناً.
  purchase_order_item_id UNIQUEIDENTIFIER NOT NULL REFERENCES purchase_order_items(id) ON DELETE NO ACTION,
  product_id UNIQUEIDENTIFIER NOT NULL REFERENCES products(id),
  quantity DECIMAL(14,3) NOT NULL,
  batch_number NVARCHAR(60) NOT NULL DEFAULT '',
  expiry_date DATE NULL,
  -- لقطة التكلفة وقت الوصول، **محمَّلةً** بنصيب الوحدة من مصاريف الشحنة
  -- (راجع Data/LandedCost.cs). وهي التي تدخل الدفعة وتُحسب منها تكلفة
  -- البضاعة المباعة.
  unit_cost DECIMAL(14,2) NOT NULL DEFAULT 0,
  -- سعر المورّد وحده: مطابقة فاتورته تقارن بما طالب هو به، والفرق بينهما
  -- شحنٌ يطالب به غيره. وبعمود واحد يستحيل التمييز بعد الحفظ.
  supplier_unit_cost DECIMAL(14,2) NOT NULL DEFAULT 0
);
GO

-- مصاريف الشحنة الواردة — تُوزَّع بالقيمة على سطور الأمر (LandedCost.cs).
-- على الأمر لا على السطر: فاتورة الناقل مبلغٌ واحد للشحنة كلّها. ولا تدخل
-- في إجمالي الأمر: ذاك ما يطالب به المورّد وتُطابَق به فاتورته.
CREATE TABLE purchase_order_charges (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  purchase_order_id UNIQUEIDENTIFIER NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id),
  label NVARCHAR(120) NOT NULL DEFAULT '',
  amount DECIMAL(18,2) NOT NULL DEFAULT 0,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE INDEX ix_purchase_order_charges_order ON purchase_order_charges(purchase_order_id);
GO

CREATE TABLE stock_counts (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id),
  -- open (قيد العد) ← pending_review (انتهى العدّ وفيه فروقات تنتظر قراراً)
  -- ← reconciled أو عودة إلى open (طُلبت إعادة عدّ). cancelled يُلغي بلا أثر.
  --
  -- الحالة الوسيطة تمنع تطبيق فرق عدّ خاطئ على المخزون بلا أن يراه أحد.
  -- والفرق ليس رقماً محايداً: زيادة تُخفي سرقة، ونقصٌ يشطب بضاعة موجودة.
  -- وجردٌ بلا فرق واحد لا يمرّ بها — لا قرار حيث لا شيء يُقرَّر فيه.
  --
  -- القيد مسمّى صراحةً (لا مكتوب داخل تعريف العمود): الاسم المولَّد يحمل
  -- لاحقة هاش تختلف بين القواعد، فيستحيل ربط رسالة عربية به في
  -- DbConstraintMessageMiddleware.
  status NVARCHAR(20) NOT NULL DEFAULT 'open',
  CONSTRAINT CK_stock_counts_status
    CHECK (status IN ('open','pending_review','reconciled','cancelled')),
  -- periodic: جرد دوري على مخزون قائم يبدأ بالكمية النظامية مملوءة.
  -- initial:  جرد ابتدائي لإدخال مخزون موجود إلى نظام جديد، يبدأ بأصفار
  --           لأنه لا كمية نظامية أصلاً — وملؤه بالنظامي كان يجعل «قبول
  --           الافتراضي» يُثبّت صفراً لكل صنف على الرفّ.
  kind NVARCHAR(20) NOT NULL DEFAULT 'periodic',
  CONSTRAINT CK_stock_counts_kind CHECK (kind IN ('periodic','initial')),
  created_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  closed_at DATETIME2 NULL,
  -- من أنهى العدّ ومن بتّ في الفروقات — منفصلان ليظهر تطابقهما لمن يدقّق.
  -- ولا يمنع النظام تطابقهما: محلٌّ يديره صاحبه وحده لا يملك شخصاً ثانياً.
  submitted_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  submitted_at DATETIME2 NULL,
  reviewed_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  reviewed_at DATETIME2 NULL,
  recount_reason NVARCHAR(300) NULL,
  -- جردٌ أُعيد ثلاث مرّات ليس دقيقاً بل مؤشّر على خلل في العدّ أو المخزون.
  recount_rounds INT NOT NULL DEFAULT 0
);
GO

CREATE TABLE stock_count_items (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  stock_count_id UNIQUEIDENTIFIER NOT NULL REFERENCES stock_counts(id) ON DELETE CASCADE,
  product_id UNIQUEIDENTIFIER NOT NULL REFERENCES products(id),
  system_quantity DECIMAL(14,3) NOT NULL,
  counted_quantity DECIMAL(14,3) NOT NULL,
  -- متى عُدَّ هذا السطر فعلاً. NULL = لم يُمَسّ بعد.
  --
  -- الجرد الدوري يبدأ بـ counted_quantity = system_quantity، فسطرٌ لم يره
  -- أحد يبدو «عُدَّ وطابق». الكمية وحدها لا تفرّق بين «طابق» و«لم يُنظَر
  -- إليه»، والفرق بينهما هو الجرد كلّه.
  counted_at DATETIME2 NULL,
  -- أُضيف أثناء العدّ لأنه وُجد على الرفّ ولم يكن في القائمة (الجرد
  -- الموزَّع يستبعد ما عُدَّ حديثاً، فيقف العامل أمام صنف لا يجده).
  added_during_count BIT NOT NULL DEFAULT 0,
  variance AS (counted_quantity - system_quantity) PERSISTED
);
GO

-- ----------------------------------------------------------------------------
-- 5. العملاء
-- ----------------------------------------------------------------------------
-- لا يحمل عمود wallet_balance عمداً — الرصيد مجموع دفتر
-- customer_wallet_transactions أدناه ولا يُخزَّن أبداً كعمود قابل للكتابة.
-- ----------------------------------------------------------------------------
-- الجهات الممولة لأرصدة العملاء (شركة لموظفيها، جمعية، مدرسة) — الطرف الذي
-- تُحاسبه المنشأة في نموذج الاستحقاق الممنوح، لا المستفيد نفسه.
-- لا تحمل branch_id: الجهة تتعامل مع المنظمة ككل، بنفس مبرر suppliers.
-- ----------------------------------------------------------------------------
--  فئات العملاء — اسمٌ ومرتَّبٌ دوري
--
--  كان مبلغ الاستحقاق رقماً على كل عميل على حدة. وجهةٌ تصرف على ألف منتسب في
--  ثلاث فئات كانت ترفع مرتب الفئة بتعديل ألف صفّ يدوياً — وأوّل صفٍّ
--  يُنسى يُنتج منتسباً يقبض أقلّ من زملائه بلا سببٍ معلوم.
--
--  ⚠ قبل customers: العميل يشير إليها.
-- ----------------------------------------------------------------------------
CREATE TABLE customer_categories (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name NVARCHAR(80) NOT NULL,
  period_amount DECIMAL(18,2) NOT NULL DEFAULT 0,
  -- أيسقط ما لم يُصرَف من مرتَّب الدورة عند صرف التالية؟ قرارُ إدارة.
  unspent_expires BIT NOT NULL DEFAULT 1,
  is_active BIT NOT NULL DEFAULT 1,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  -- فئتان بنفس الاسم في منظمةٍ واحدة تجعلان اختيار الصحيحة تخميناً.
  CONSTRAINT uq_customer_categories_name UNIQUE (organization_id, name)
);
GO

-- ----------------------------------------------------------------------------
CREATE TABLE sponsors (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name NVARCHAR(150) NOT NULL,
  phone NVARCHAR(30) NULL,
  notes NVARCHAR(500) NULL,
  is_deleted BIT NOT NULL DEFAULT 0,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE customers (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NULL REFERENCES branches(id),
  full_name NVARCHAR(150) NOT NULL,
  phone NVARCHAR(30) NULL,
  email NVARCHAR(200) NULL,
  notes NVARCHAR(500) NULL,
  -- فهرس فريد مُصفّى لا قيد UNIQUE عادي: SQL Server يعتبر كل قيم NULL
  -- متساوية، فقيد UNIQUE عادي هنا كان يمنع وجود عميلَين بلا بطاقة أصلاً
  -- (نفس علّة اسم المستخدم في app_users) — راجع UX_customers_card_barcode أدناه.
  card_barcode NVARCHAR(60) NULL,
  credit_limit DECIMAL(14,2) NOT NULL DEFAULT 0,
  -- مهلة سداد الآجل بالأيام. صفر = مستحقّ يوم البيع.
  -- على العميل لا على المنظمة: تاجر الجملة يمنح مستشفى ثلاثين يوماً
  -- وبقّالاً سبعة، ومهلة واحدة للجميع تعني مطاردة من له مهلة أو ترك من
  -- لا مهلة له.
  credit_days INT NOT NULL DEFAULT 0,
  -- ---- نموذج الحساب ----
  -- prepaid: رصيد دفعه العميل من ماله — لا يسقط ولا سقف له (إسقاط مال دفعه
  --          صاحبه مصادرة له).
  -- entitlement: استحقاق منحته جهة ثالثة بسقف وفترة — ما لا يُصرف يسقط،
  --          والمحاسبة مع الجهة الممولة. راجع AccountModels في Entities.cs.
  account_model NVARCHAR(20) NOT NULL DEFAULT 'prepaid'
    CHECK (account_model IN ('prepaid','entitlement')),
  sponsor_id UNIQUEIDENTIFIER NULL REFERENCES sponsors(id),
  entitlement_ceiling DECIMAL(18,3) NOT NULL DEFAULT 0,
  entitlement_expires_on DATE NULL,
  -- فئة العميل — منها يُؤخذ مبلغ المنحة. NULL = بلا فئة.
  category_id UNIQUEIDENTIFIER NULL REFERENCES customer_categories(id),
  -- صورة صاحب البطاقة — مسارُ مرفق لا الصورة. بطاقةٌ بلا رقم سرّي يحميها
  -- أن يعرف الكاشير أن حاملها صاحبها.
  photo_url NVARCHAR(400) NULL,
  -- مبلغٌ يخصّ هذا العميل وحده يَجُبّ فئته. NULL = اتبع الفئة، والصفر
  -- قرارٌ صريح بإيقاف منحته هذه الدورة.
  entitlement_override DECIMAL(18,2) NULL,

  loyalty_points INT NOT NULL DEFAULT 0,
  is_deleted BIT NOT NULL DEFAULT 0,
  -- بوابة العميل: الرقم السري مُجزَّأ بـ BCrypt، ورمز البطاقة نفسه يعيش في
  -- customer_card_index وحده (لا نسخة منه هنا حتى لا يوجد مصدرا حقيقة).
  pin_hash NVARCHAR(400) NULL,
  pin_locked_until DATETIME2 NULL,
  -- نمط التحقّق عند الصرف: 'card' (مسح فقط بسقف يومي) أو 'pin'. NULL =
  -- افتراضي المنظمة. يختاره صاحب الحساب لا الكاشير — ماله هو.
  -- القيد مُسمّى صراحةً ليطابق ما يُنشئه MIGRATIONS.sql: القيود السطرية
  -- تأخذ اسماً مُجزَّأً يختلف بين كل قاعدة وأخرى، فلا يجدها فحص المخطّط ولا
  -- تُترجَم رسالتها إلى العربية في DbConstraintMessageMiddleware.
  --
  -- و'phone' مقبول هنا ولو لم يُعرَض في الواجهة بعد: القيد يحرس ما يُكتَب،
  -- والنمط يُفعَّل يوم تُبنى قناة الإرسال بلا تغيير مخطّط.
  card_mode NVARCHAR(20) NULL
    CONSTRAINT CK_customers_card_mode CHECK (card_mode IS NULL OR card_mode IN ('card','pin','phone')),
  -- سقف يومي أشدّ يختاره الزبون لنفسه. صفر = سقف المنظمة. ويُقبل الأقلّ فقط:
  -- التشديد على النفس حقٌّ بلا إذن، والتخفيف تجاوزٌ لحدّ صاحب المحل.
  daily_cap DECIMAL(18,2) NOT NULL DEFAULT 0,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- ----------------------------------------------------------------------------
-- فهرس بطاقات العملاء — معفى من RLS عمداً وبنفس مبرر app_users بالضبط:
-- دخول العميل للبوابة يحدث *قبل* وجود أي SESSION_CONTEXT، فأي FILTER
-- PREDICATE هنا كان سيمنع كل عمليات الدخول. رمز البطاقة فريد عالمياً وهو ما
-- يحدّد منظمة العميل قبل ضبط السياق.
--
-- الرمز 12 خانة من أبجدية بلا حروف ملتبسة (لا 0/O ولا 1/I) لأنه يُطبَع على
-- بطاقة ويُكتب باليد — راجع CustomerCards.cs.
-- ----------------------------------------------------------------------------
CREATE TABLE customer_card_index (
  card_code NVARCHAR(12) NOT NULL PRIMARY KEY,
  customer_id UNIQUEIDENTIFIER NOT NULL REFERENCES customers(id),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  issued_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  -- دورة حياة البطاقة. البطاقة المنتهية الصلاحية تُرفض وقت الاستخدام حتى لو
  -- بقيت حالتها 'active' (لا وظيفة مجدوَلة تُحدّثها) — راجع
  -- CustomerCardIndex.IsUsable.
  state NVARCHAR(20) NOT NULL DEFAULT 'active'
    CHECK (state IN ('active','blocked','expired')),
  expiry_date DATE NULL,
  issued_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  blocked_reason NVARCHAR(200) NULL,
  -- الاسم المطبوع على البطاقة، قد يختلف عن اسم العميل المسجَّل (بطاقة شركة
  -- يحملها موظف مثلاً). NULL = يُطبع اسم العميل نفسه.
  holder_name NVARCHAR(150) NULL
);
GO

CREATE UNIQUE INDEX UQ_customer_card_index_customer ON customer_card_index (customer_id);
GO

-- سجل محاولات الرقم السري — أساس القفل (5 محاولات فاشلة خلال 15 دقيقة)
-- ودليل تدقيق على أي محاولة اختراق. معفى من RLS لنفس سبب الفهرس أعلاه.
-- ----------------------------------------------------------------------------
--  سداد الموردين
--
--  الثقب الذي يسدّه: حساب «الموردون» كان يتراكم بلا طرف مقابل — كل استلام
--  يزيد الدَّين ولا شيء يُنقصه. فالميزان يقول إنك مدينٌ بكل ما اشتريتَه منذ
--  أول يوم، ولو سدّدتَ كلّه نقداً.
--
--  ولا رصيد مخزَّن للمورّد: يُشتقّ من الافتتاحي + المستلَم − المُعاد − المسدَّد.
--  عمودٌ مخزَّن يتعارض مع مجموع حركاته عند أول مسار ينسى تحديثه — نفس درس
--  رصيد المحفظة ودفتر المخزون.
-- ----------------------------------------------------------------------------
CREATE TABLE supplier_payments (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id),
  supplier_id UNIQUEIDENTIFIER NOT NULL REFERENCES suppliers(id),
  amount DECIMAL(18,3) NOT NULL,
  method NVARCHAR(20) NOT NULL
    CONSTRAINT CK_supplier_payments_method CHECK (method IN ('cash','bank')),
  -- المصرف الذي خرج منه المبلغ. NULL = الصندوق.
  bank_account_id UNIQUEIDENTIFIER NULL REFERENCES bank_accounts(id),
  reference NVARCHAR(80) NULL,
  note NVARCHAR(300) NULL,
  -- تاريخ السداد الفعلي، منفصل عن تاريخ الإدخال.
  paid_on DATETIME2 NOT NULL,
  created_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT CK_supplier_payments_amount CHECK (amount > 0)
);
GO

CREATE INDEX ix_supplier_payments_supplier ON supplier_payments (organization_id, supplier_id, paid_on);
GO

-- ----------------------------------------------------------------------------
--  المرفقات — شعار المنظمة، فواتير الموردين، مستندات الاستلام
--
--  اسم الملف على القرص فقط لا مسار كامل: نقل مجلد التخزين أو تغيير حرف
--  القرص لا يُبطل الصفوف.
-- ----------------------------------------------------------------------------
CREATE TABLE attachments (
  id               UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
  organization_id  UNIQUEIDENTIFIER NOT NULL,
  -- الكيان المرتبط: 'organization_logo' أو 'purchase_order' …
  entity_type      NVARCHAR(40)  NOT NULL,
  entity_id        UNIQUEIDENTIFIER NULL,
  file_name        NVARCHAR(260) NOT NULL,
  content_type     NVARCHAR(120) NOT NULL,
  size_bytes       BIGINT        NOT NULL,
  stored_name      NVARCHAR(120) NOT NULL,
  uploaded_by      UNIQUEIDENTIFIER NULL,
  created_at       DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE INDEX ix_attachments_entity ON attachments (organization_id, entity_type, entity_id);
GO

CREATE TABLE customer_pin_attempts (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  customer_id UNIQUEIDENTIFIER NOT NULL REFERENCES customers(id),
  success BIT NOT NULL,
  ip_address NVARCHAR(60) NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE INDEX IX_customer_pin_attempts_customer ON customer_pin_attempts (customer_id, created_at);
GO

-- ----------------------------------------------------------------------------
-- 6. نقطة البيع والمبيعات
-- ----------------------------------------------------------------------------
CREATE TABLE pos_shifts (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id),
  cashier_id UNIQUEIDENTIFIER NOT NULL REFERENCES app_users(id),
  opening_cash DECIMAL(14,2) NOT NULL DEFAULT 0,
  closing_cash DECIMAL(14,2) NULL,
  status NVARCHAR(10) NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed')),
  opened_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  closed_at DATETIME2 NULL
);
GO

CREATE TABLE invoices (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id),
  shift_id UNIQUEIDENTIFIER NULL REFERENCES pos_shifts(id),
  customer_id UNIQUEIDENTIFIER NULL REFERENCES customers(id),
  invoice_number NVARCHAR(40) NOT NULL,
  invoice_type NVARCHAR(10) NOT NULL DEFAULT 'sale' CHECK (invoice_type IN ('sale','return')),
  original_invoice_id UNIQUEIDENTIFIER NULL REFERENCES invoices(id),
  subtotal DECIMAL(14,2) NOT NULL DEFAULT 0,
  tax_amount DECIMAL(14,2) NOT NULL DEFAULT 0,
  discount_amount DECIMAL(14,2) NOT NULL DEFAULT 0,
  total_amount DECIMAL(14,2) NOT NULL DEFAULT 0,
  -- 'refunded' كان ناقصاً هنا بينما InvoicesController.Refund يكتبه فعلاً،
  -- فكانت كل عملية استرجاع تفشل بـ 500 منذ بنائها ولم يُكتشف الأمر حتى اختبار
  -- دفتر المحفظة.
  -- تاريخ استحقاق الجزء الآجل. NULL في البيع المدفوع كاملاً. لقطةً من مهلة
  -- العميل لحظة البيع لا مرجعاً إليها: تغيير المهلة لاحقاً يجب ألّا يحرّك
  -- استحقاق فواتير مضت، وإلا أمكن إخفاء تأخّر بتعديل حقل في شاشة العملاء.
  due_date DATETIME2 NULL,
  status NVARCHAR(15) NOT NULL DEFAULT 'completed' CHECK (status IN ('completed','pending','cancelled','refunded')),
  -- مفتاح يولّده العميل مرّة لكل عملية بيع ويُعيد إرساله مع كل مزامنة. هو ما
  -- يجعل إعادة الإرسال آمنة: انقطاع الشبكة بعد وصول الطلب وقبل وصول الرد
  -- حالة شائعة في متجر، وبدونه تُنشأ الفاتورة مرّتين ويُخصَم المخزون مرّتين.
  client_request_id NVARCHAR(64) NULL,
  -- المدفوع فعلاً من الإجمالي. NULL أو مساوٍ للإجمالي = مدفوعة بالكامل،
  -- وأقلّ منه = دفع جزئي والفرق دَينٌ مقيَّد على محفظة العميل. لا جدول ديون
  -- منفصل: دفتر المحفظة هو دفتر العميل، ورصيده السالب هو دَينه.
  paid_amount DECIMAL(18,3) NULL,
  -- النقد المستلَم والباقي. كانت حاسبة النقد تحسبهما وتعرضهما ثم تنساهما:
  -- لا يُطبَعان على الإيصال ولا يُراجَعان في تسوية الدرج آخر اليوم. ورقمٌ لا
  -- يُحفَظ لا يُدقَّق — والدرج الناقص حينها لا يُعرف أهو خطأ صرف أم سرقة.
  tendered_amount DECIMAL(18,3) NULL,
  change_due DECIMAL(18,3) NULL,
  created_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT UQ_invoices_number UNIQUE (organization_id, branch_id, invoice_number)
);
GO

-- فهرس فريد مُرشَّح: NULL مسموح ومتكرّر (فواتير ما قبل العمل دون اتصال)،
-- والقيمة الموجودة لا تتكرّر. وهو ما يجعل إعادة الإرسال تُعيد الفاتورة
-- نفسها بدل إنشاء ثانية.
CREATE UNIQUE INDEX UX_invoices_client_request_id
  ON invoices (client_request_id)
  WHERE client_request_id IS NOT NULL;
GO


CREATE TABLE invoice_items (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  invoice_id UNIQUEIDENTIFIER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  product_id UNIQUEIDENTIFIER NOT NULL REFERENCES products(id),
  quantity DECIMAL(14,3) NOT NULL,
  unit_price DECIMAL(14,2) NOT NULL,
  line_total DECIMAL(14,2) NOT NULL,
  -- الكمية والسعر يُحفَظان كما بيعا فعلاً (3 حبات × دينار)، لا محوَّلين إلى
  -- الوحدة الأساسية — وإلا عرض الإيصال «0.3 شريط بسعر 10» وهو ما لم يحدث.
  -- الخصم من المخزون وحده هو ما يُحوَّل.
  sold_as_sub_unit BIT NOT NULL DEFAULT 0,
  -- لقطة من sub_units_per_base وقت البيع: حجم العلبة قد يتغيّر لاحقاً،
  -- والمرتجع يجب أن يعيد ما خرج فعلاً لا ما يقوله الكتالوج اليوم.
  sub_units_per_base DECIMAL(10,3) NOT NULL DEFAULT 0
);
GO

-- ----------------------------------------------------------------------------
--  تخصيص كمية سطر الفاتورة على الدفعات (FEFO)
--
--  جدول منفصل لا عمود batch_number على invoice_items: سطر واحد قد يمتدّ على
--  أكثر من دفعة (طُلب 15 حبة، منها 10 من دفعة و5 من أخرى)، فعمود واحد لا
--  يسعه. والسطر التجاري يبقى واحداً — الإيصال يعرض «15 حبة» لا سطرين.
--
--  وهو شرط صحّة المرتجع: بدونه تعود الكمية إلى دفعة عامة بلا تاريخ صلاحية،
--  فينحرف رصيد كل دفعة عن الواقع ويسقط ترتيب FEFO معه لأنه يقرأ من هذه
--  الأرصدة. راجع InvoiceItemBatch في Entities.cs.
-- ----------------------------------------------------------------------------
CREATE TABLE invoice_item_batches (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  invoice_item_id UNIQUEIDENTIFIER NOT NULL REFERENCES invoice_items(id) ON DELETE CASCADE,
  batch_number NVARCHAR(60) NOT NULL DEFAULT '',
  quantity DECIMAL(14,3) NOT NULL
);
GO

-- ----------------------------------------------------------------------------
--  دفتر الوصفات — إصدار الصيدليات
--
--  سجلٌّ لكل صرف دواء مقيَّد بوصفة (medicine_reference.requires_prescription).
--  بخلاف نشرة الدواء، هذا الجدول **بيانات منظمة** لا معرفة عامة: وصفة مريض
--  بعينه صرفتها صيدلية بعينها. ولهذا يحمل organization_id وbranch_id وتُطبَّق
--  عليه سياسة العزل كبقية الجداول التشغيلية.
--
--  مرتبط بالفاتورة: الوصفة تُقدَّم لحظة الصرف لا قبله ولا بعده، فربطها بما
--  صُرِف فعلاً هو ما يجعل الدفتر قابلاً للمراجعة — من صرف، ماذا، لمن، بأمر
--  أي طبيب. ودونه يصبح سجلاً موازياً لا أحد يوثّق أنه يطابق المبيعات.
-- ----------------------------------------------------------------------------
CREATE TABLE prescriptions (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id) ON DELETE NO ACTION,
  -- الفاتورة التي صُرفت بها. NO ACTION لا CASCADE: الفاتورة لا تُحذف أصلاً
  -- (مبدأ «لا حذف فعلي»)، وحذف دفتر الوصفات تبعاً لأي عملية آلية مرفوض —
  -- هو المستند النظامي الذي يُسأل عنه الصيدلي.
  invoice_id UNIQUEIDENTIFIER NULL REFERENCES invoices(id) ON DELETE NO ACTION,
  prescription_number NVARCHAR(60) NULL,
  doctor_name NVARCHAR(150) NOT NULL,
  doctor_license NVARCHAR(60) NULL,
  patient_name NVARCHAR(150) NOT NULL,
  patient_phone NVARCHAR(30) NULL,
  issued_on DATE NULL,
  notes NVARCHAR(500) NULL,
  created_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE invoice_payments (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  invoice_id UNIQUEIDENTIFIER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  method NVARCHAR(20) NOT NULL CHECK (method IN ('cash','card','customer_wallet','credit')),
  amount DECIMAL(14,2) NOT NULL
);
GO

-- ----------------------------------------------------------------------------
-- دفتر حركات محفظة العميل — يُضاف إليه فقط ولا يُعدَّل صف فيه أبداً.
-- الرصيد = مجموع الدفتر (راجع WalletBalances.cs — الطريق الوحيد لحسابه).
-- يُنشأ بعد invoices لأنه يحمل مفتاحاً خارجياً عليها.
--
-- سبب هذا التصميم (مأخوذ من نموذج التوطين الليبي، ACCOUNTING_RULES.md §3):
-- عمود رصيد قابل للكتابة هو أسرع طريق إلى بطاقة رصيدها لا يطابق محاسبتها.
-- التصحيح يكون بحركة معاكسة جديدة لا بتعديل حركة سابقة (حرمة القيد).
--
-- amount موجب دائماً (مفروض بـ CHECK)، والإشارة تُشتق من kind وحده عبر
-- WalletKinds.SignOf في الكود — فلا يمكن أن تتناقض قيمة مع إشارتها.
-- ----------------------------------------------------------------------------
-- ----------------------------------------------------------------------------
--  سلف المنتسبين
--
--  السلفة مالٌ يُقرَض لا يُعطى: ترفع رصيد البطاقة كالشحن، وتبقى ديناً حتى
--  تُستردّ من المرتَّب. وخلطُها بالشحن يجعل الجهة لا تعرف كم على منتسبيها.
--
--  والمتبقّي محسوبٌ لا مخزَّن: أصلها ناقص مجموع أقساطها في دفتر المحفظة.
-- ----------------------------------------------------------------------------
CREATE TABLE customer_advances (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  customer_id UNIQUEIDENTIFIER NOT NULL REFERENCES customers(id),
  amount DECIMAL(18,2) NOT NULL,
  -- ما يُخصم من كل مرتَّب. صفر = كامل المتبقّي دفعةً واحدة.
  installment_amount DECIMAL(18,2) NOT NULL DEFAULT 0,
  issued_on DATE NOT NULL,
  note NVARCHAR(300) NULL,
  -- مُلغاة لا محذوفة: أقساطها في الدفتر تشير إليها.
  is_cancelled BIT NOT NULL DEFAULT 0,
  created_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT ck_customer_advances_amount CHECK (amount > 0)
);
GO

CREATE TABLE customer_wallet_transactions (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  customer_id UNIQUEIDENTIFIER NOT NULL REFERENCES customers(id),
  invoice_id UNIQUEIDENTIFIER NULL REFERENCES invoices(id),
  -- السلفة التي تخصّها الحركة — صرفاً أو سداداً. بدونه يستحيل معرفة كم بقي
  -- من سلفةٍ بعينها حين يكون على المنتسب أكثر من واحدة.
  advance_id UNIQUEIDENTIFIER NULL REFERENCES customer_advances(id),
  kind NVARCHAR(20) NOT NULL
    CHECK (kind IN ('topup','spend','invoice_refund','adjustment_in','adjustment_out',
                    'entitlement_grant','entitlement_expiry')),
  amount DECIMAL(18,3) NOT NULL CHECK (amount > 0),
  note NVARCHAR(300) NULL,
  created_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE INDEX IX_customer_wallet_transactions_customer
  ON customer_wallet_transactions (customer_id) INCLUDE (kind, amount);
GO

-- ----------------------------------------------------------------------------
-- 6.9 المحاسبة — دليل الحسابات والقيود  (وحدة accounting، إصدار المؤسسات)
--
-- ⚠ **قبل قسم المالية المبسّطة عمداً:** expenses.account_id يشير إلى
-- accounts، وSQL Server ينفّذ الملف بالترتيب فيرفض مفتاحاً خارجياً إلى جدول
-- لم يُنشأ بعد. نفس الإشارة الأمامية التي أصابت stock_levels ← warehouses.
--
-- على الدليل المحاسبي الموحّد: 1 الأصول · 2 الالتزامات وحقوق الملكية ·
-- 3 الاستخدامات · 4 الإيرادات.
-- ----------------------------------------------------------------------------
CREATE TABLE accounts (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  code NVARCHAR(20) NOT NULL,
  name NVARCHAR(200) NOT NULL,
  -- بلا ON DELETE: حذف أبٍ له أبناء يجب أن يُرفض لا أن يتتالى — التتالي
  -- يمحو فرعاً كاملاً من الدليل بضغطة واحدة.
  parent_id UNIQUEIDENTIFIER NULL REFERENCES accounts(id),
  type NVARCHAR(20) NOT NULL
    CONSTRAINT CK_accounts_type CHECK (type IN ('asset','liability','equity','expense','revenue')),
  -- الوسيط لا يُرحَّل إليه: قيدٌ على «الأصول» مباشرةً يجعل رصيد الأب لا
  -- يساوي مجموع أبنائه، فيستحيل تفسير أي رقم بردّه إلى مفرداته.
  is_postable BIT NOT NULL DEFAULT 1,
  -- أنشأه النظام ويعتمد عليه الترحيل الآلي — لا يُحذف. حذف «المبيعات»
  -- يُوقف كل بيع في المحلّ، والمستخدم لا يعرف ذلك وهو يضغط «حذف».
  is_system BIT NOT NULL DEFAULT 0,
  -- قيم الحقول الإضافية بمفاتيح تعريفات المنظمة — راجع
  -- organizations.account_field_defs_json.
  custom_fields_json NVARCHAR(MAX) NOT NULL DEFAULT N'{}',
  is_active BIT NOT NULL DEFAULT 1,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT UQ_accounts_org_code UNIQUE (organization_id, code)
);
GO

CREATE TABLE journal_entries (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NULL REFERENCES branches(id),
  -- تسلسل داخل المنظمة بلا فجوات: يُولَّد بقفل داخل المعاملة لا بـIDENTITY،
  -- لأن IDENTITY يترك فجوات عند أي تراجع — وفجوةٌ في تسلسل دفتر اليومية
  -- سؤالٌ يطرحه كل مراجع.
  number BIGINT NOT NULL,
  -- التاريخ المحاسبي قد يخالف تاريخ الإدخال: فاتورة أمس تُسجَّل اليوم
  -- تنتمي محاسبياً إلى أمس.
  entry_date DATETIME2 NOT NULL,
  source NVARCHAR(30) NOT NULL,
  source_id UNIQUEIDENTIFIER NULL,
  description NVARCHAR(400) NOT NULL DEFAULT N'',
  -- القيد الذي يعكسه هذا القيد. حرمة القيد: لا تعديل ولا حذف، والتصحيح
  -- بعكسٍ يشير إلى أصله — نفس مبدأ دفتر المخزون ودفتر المحفظة.
  reverses_entry_id UNIQUEIDENTIFIER NULL REFERENCES journal_entries(id),
  created_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT UQ_journal_entries_number UNIQUE (organization_id, number)
);
GO

CREATE TABLE journal_entry_lines (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  journal_entry_id UNIQUEIDENTIFIER NOT NULL REFERENCES journal_entries(id) ON DELETE CASCADE,
  account_id UNIQUEIDENTIFIER NOT NULL REFERENCES accounts(id),
  -- عمودان لا عمود واحد بإشارة: يُقرآن كما يكتبهما المحاسب، والمبلغ الموجب
  -- دائماً يمنع طبقةً كاملة من أخطاء الإشارة في التجميع.
  debit DECIMAL(18,2) NOT NULL DEFAULT 0,
  credit DECIMAL(18,2) NOT NULL DEFAULT 0,
  note NVARCHAR(300) NULL,
  -- سطرٌ بمدين ودائن معاً، أو بصفرَين، أو بسالب: كلّها بلا معنى محاسبي.
  -- القيد هنا لا في الكود: الكود يُنسى في مسار جديد، والقاعدة لا تنسى.
  CONSTRAINT CK_journal_lines_side CHECK (
    debit >= 0 AND credit >= 0 AND (
      (debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0)
    )
  )
);
GO

CREATE TABLE account_mappings (
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  role NVARCHAR(40) NOT NULL,
  account_id UNIQUEIDENTIFIER NOT NULL REFERENCES accounts(id),
  PRIMARY KEY (organization_id, role)
);
GO

-- ----------------------------------------------------------------------------
--  فاتورة المورّد والمطابقة بالاستلام
--
--  لم يكن للمورّد فاتورة في النظام. كان الاستلام يُنشئ الدَّين بتكلفة أمر
--  الشراء — أي بالسعر المتّفق عليه لا بالسعر المُطالَب به. فإذا رفع المورّد
--  سعره أو فوتر كميةً غير التي سلّمها، لم يكن ثمّة موضعٌ يُظهر الفرق.
--
--  ⚠ بعد purchase_receipts: كل سطر فاتورة يشير إلى سطر استلام.
-- ----------------------------------------------------------------------------
CREATE TABLE supplier_invoices (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id),
  supplier_id UNIQUEIDENTIFIER NOT NULL REFERENCES suppliers(id),
  -- رقم الفاتورة كما كتبه المورّد. إلزامي: هو المرجع عند الخلاف وأساس
  -- منع الازدواج.
  invoice_number NVARCHAR(80) NOT NULL,
  invoice_date DATETIME2 NOT NULL,
  due_date DATETIME2 NULL,
  -- الإجمالي كما هو مكتوب على الفاتورة — يُدخَل ولا يُحسب من السطور، وإلا
  -- صحّح النظامُ المورّدَ بدل أن يطابقه.
  total_amount DECIMAL(18,2) NOT NULL,
  status NVARCHAR(20) NOT NULL CONSTRAINT df_supplier_invoices_status DEFAULT 'draft',
  notes NVARCHAR(500) NULL,
  created_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  posted_at DATETIME2 NULL,
  CONSTRAINT ck_supplier_invoices_status
    CHECK (status IN ('draft', 'posted', 'cancelled')),
  -- لا فاتورتان بنفس الرقم من نفس المورّد: أشيع خطأ إدخال هو تسجيل الورقة
  -- مرّتين، فيتضاعف الدَّين بلا أن يلاحظ أحد.
  CONSTRAINT uq_supplier_invoices_number UNIQUE (organization_id, supplier_id, invoice_number)
);
GO

CREATE TABLE supplier_invoice_lines (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  supplier_invoice_id UNIQUEIDENTIFIER NOT NULL
    REFERENCES supplier_invoices(id) ON DELETE CASCADE,
  -- محور المطابقة: بدونه يبقى السطر ادّعاءً لا يقابله وصول.
  purchase_receipt_item_id UNIQUEIDENTIFIER NOT NULL REFERENCES purchase_receipt_items(id),
  product_id UNIQUEIDENTIFIER NOT NULL REFERENCES products(id),
  quantity DECIMAL(18,3) NOT NULL,
  unit_cost DECIMAL(18,2) NOT NULL,
  -- سطر استلامٍ فُوتر مرّة لا يُفوتر ثانية.
  CONSTRAINT uq_supplier_invoice_lines_receipt_item UNIQUE (purchase_receipt_item_id)
);
GO

-- ----------------------------------------------------------------------------
--  الحسابات المصرفية
--
--  كل ما يُدفع أو يُقبَض كان يُقيَّد على «الصندوق» — النقد والحوالة سواء.
--  فتظهر النقدية الدفترية أعلى ممّا في الدرج بمقدار كل حوالة، ولا يُعرف
--  رصيد المصرف إطلاقاً.
--
--  ولكلٍّ حسابه في الدليل تحت «المصارف»: حسابٌ واحد للجميع يجعل مطابقة كشف
--  مصرفٍ بعينه مستحيلة.
--
--  ⚠ بعد كتلة المحاسبة: ledger_account_id يشير إلى accounts.
-- ----------------------------------------------------------------------------
CREATE TABLE bank_accounts (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name NVARCHAR(150) NOT NULL,
  account_number NVARCHAR(60) NULL,
  ledger_account_id UNIQUEIDENTIFIER NULL REFERENCES accounts(id),
  is_active BIT NOT NULL DEFAULT 1,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- ----------------------------------------------------------------------------
--  الإقفال السنوي
--
--  ⚠ **بعد كتلة المحاسبة عمداً:** journal_entry_id يشير إلى journal_entries،
--  وSQL Server ينفّذ الملف بالترتيب فيرفض مفتاحاً خارجياً إلى جدول لم
--  يُنشأ بعد. رابع إشارة أمامية في هذا الملف — راجع §2.23.
--
--  الإقفال شيئان لا واحد: قيدٌ يُصفّر الإيرادات والاستخدامات ويُرحّل نتيجتها
--  إلى «الأرباح المحتجزة»، **وقفلٌ يمنع أي قيد بتاريخ داخل المدّة**. وبلا
--  القفل لا معنى للإقفال: فاتورةٌ تُسجَّل بتاريخ العام الماضي تُغيّر أرقاماً
--  صدرت عنها تقارير ووُقّعت عليها ميزانية.
--
--  ويُفتح بقرار صريح مسجَّل — لا يُحذف الصفّ: من راجع الدفتر يجب أن يرى أن
--  السنة أُقفلت ثم فُتحت ولماذا، لا أن يجدها مفتوحة كأن شيئاً لم يكن.
-- ----------------------------------------------------------------------------
CREATE TABLE fiscal_closings (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  -- آخر يوم في المدّة المُقفَلة.
  period_end DATETIME2 NOT NULL,
  net_result DECIMAL(18,3) NOT NULL DEFAULT 0,
  journal_entry_id UNIQUEIDENTIFIER NULL REFERENCES journal_entries(id),
  closed_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  closed_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  is_reopened BIT NOT NULL DEFAULT 0,
  reopen_reason NVARCHAR(300) NULL,
  reopened_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  reopened_at DATETIME2 NULL
);
GO

CREATE INDEX ix_fiscal_closings_period ON fiscal_closings (organization_id, period_end);
GO

-- ----------------------------------------------------------------------------
-- 7. المالية المبسّطة
-- ----------------------------------------------------------------------------
CREATE TABLE expenses (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NOT NULL REFERENCES branches(id),
  category NVARCHAR(80) NOT NULL,
  amount DECIMAL(14,2) NOT NULL,
  note NVARCHAR(300) NULL,
  -- حساب المصروف حين تكون وحدة المحاسبة مفعّلة. NULL = «مصروفات عمومية».
  -- تركُه فارغاً أفضل من إجبار من يسجّل مصروفاً على اختيار حساب لا يعرفه،
  -- فيختار أول ما تقع عليه عينه ويُفسد التبويب.
  -- القيد مُسمّى ليطابق ما يُنشئه MIGRATIONS.sql: القيود السطرية تأخذ اسماً
  -- مُجزَّأً يختلف بين كل قاعدة وأخرى، فتختلف قاعدةٌ مُرحَّلة عن قاعدةٍ
  -- مُنشأة من المخطّط في أسماء قيودها — ولا تُترجَم رسالتها إلى العربية.
  account_id UNIQUEIDENTIFIER NULL
    CONSTRAINT FK_expenses_account REFERENCES accounts(id),
  -- تاريخ الصرف الفعلي، منفصل عن تاريخ الإدخال: فاتورة الأسبوع الماضي
  -- تُدخَل اليوم ويجب أن تقع في مدّتها هي.
  spent_on DATETIME2 NOT NULL CONSTRAINT df_expenses_spent_on DEFAULT SYSUTCDATETIME(),
  -- المصرف الذي دُفع منه. NULL = الصندوق.
  bank_account_id UNIQUEIDENTIFIER NULL REFERENCES bank_accounts(id),
  created_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- ----------------------------------------------------------------------------
-- 8. الإشعارات وسجل التدقيق
-- ----------------------------------------------------------------------------
-- ----------------------------------------------------------------------------
--  تذكير أُرسل فعلاً بدَين متأخّر
--
--  يُكتب عند الإرسال لا عند حلول الموعد: صفٌّ يُنشأ آلياً يجعل «أُرسل
--  التذكير» كذبةً يقولها النظام عن نفسه، ويوقف المطالبة الحقيقية لأنه
--  يظنّها تمّت. وموعد الاستحقاق يُحفَظ لقطةً هنا فيبقى الفرق بين المخطَّط
--  والفعلي ظاهراً للتدقيق حتى لو تغيّرت السياسة لاحقاً.
--
--  وعلى العميل لا على الفاتورة: الدَّين رصيدٌ واحد عليه (مجموع دفتر
--  المحفظة)، والمطالبة تقع عليه لا على ورقة بعينها.
-- ----------------------------------------------------------------------------
CREATE TABLE debt_reminders (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  customer_id UNIQUEIDENTIFIER NOT NULL REFERENCES customers(id) ON DELETE NO ACTION,
  -- 1 أو 2 أو 3 — راجع DebtReminderPolicy في Entities.cs.
  stage INT NOT NULL,
  CONSTRAINT CK_debt_reminders_stage CHECK (stage BETWEEN 1 AND 3),
  due_on DATETIME2 NOT NULL,
  sent_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  sent_by UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  -- مبلغ الدَّين وقت التذكير — يُظهر إن كان يتناقص أم يتراكم.
  amount_at_reminder DECIMAL(14,2) NOT NULL DEFAULT 0,
  note NVARCHAR(300) NULL
);
GO

CREATE TABLE notifications (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  branch_id UNIQUEIDENTIFIER NULL REFERENCES branches(id),
  type NVARCHAR(30) NOT NULL,   -- low_stock | expiry | count_variance | license | security
  title NVARCHAR(200) NOT NULL,
  body NVARCHAR(500) NULL,
  is_read BIT NOT NULL DEFAULT 0,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE audit_logs (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  organization_id UNIQUEIDENTIFIER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id UNIQUEIDENTIFIER NULL REFERENCES app_users(id),
  action NVARCHAR(80) NOT NULL,
  entity_table NVARCHAR(80) NOT NULL,
  entity_id UNIQUEIDENTIFIER NULL,
  old_values NVARCHAR(MAX) NULL,   -- JSON
  new_values NVARCHAR(MAX) NULL,   -- JSON
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- ============================================================================
-- Row-Level Security — بديل SQL Server لعزل organization_id + branch_id
-- يعتمد على SESSION_CONTEXT الذي يضبطه الـ .NET Backend في بداية كل اتصال
-- (انظر Middleware/TenantContextMiddleware.cs في مشروع الـ Backend)
-- ============================================================================

CREATE SCHEMA Security;
GO

-- دالة الحماية العامة: تقارن organization_id دائماً، وbranch_id فقط إن لم
-- يكن المستخدم مديراً عاماً (branch_id = NULL في السياق يعني "كل الفروع").
CREATE FUNCTION Security.fn_TenantPredicate(@OrgId UNIQUEIDENTIFIER, @BranchId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE @OrgId = CAST(SESSION_CONTEXT(N'organization_id') AS UNIQUEIDENTIFIER)
  AND (
    SESSION_CONTEXT(N'branch_id') IS NULL
    OR @BranchId = CAST(SESSION_CONTEXT(N'branch_id') AS UNIQUEIDENTIFIER)
  );
GO

-- تطبَّق على كل جدول يحمل organization_id + branch_id.
-- (الجداول التي على مستوى المنظمة فقط، مثل organizations وproducts، تُفلتر
-- بدالة أبسط تعتمد على organization_id فقط — انظر fn_OrgOnlyPredicate أسفله)

CREATE SECURITY POLICY Security.InvoicesPolicy
  ADD FILTER PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.invoices,
  ADD BLOCK PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.invoices AFTER INSERT
  WITH (STATE = ON);
GO

-- دفتر الوصفات بيانات منظمة لا معرفة عامة (بخلاف medicine_reference) —
-- وصفة مريض بعينه صرفتها صيدلية بعينها، فتُعزَل كبقية الجداول التشغيلية.
CREATE SECURITY POLICY Security.PrescriptionsPolicy
  ADD FILTER PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.prescriptions,
  ADD BLOCK PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.prescriptions AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.StockLevelsPolicy
  ADD FILTER PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.stock_levels,
  ADD BLOCK PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.stock_levels AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.ExpensesPolicy
  ADD FILTER PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.expenses,
  ADD BLOCK PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.expenses AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.StockCountsPolicy
  ADD FILTER PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.stock_counts,
  ADD BLOCK PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.stock_counts AFTER INSERT
  WITH (STATE = ON);
GO

-- جداول على مستوى المنظمة فقط (لا branch_id) — عزل بـ organization_id فقط
CREATE FUNCTION Security.fn_OrgOnlyPredicate(@OrgId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE @OrgId = CAST(SESSION_CONTEXT(N'organization_id') AS UNIQUEIDENTIFIER);
GO

CREATE SECURITY POLICY Security.ProductsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.products,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.products AFTER INSERT
  WITH (STATE = ON);
GO

-- ── المحاسبة ────────────────────────────────────────────────────────────
-- ============================================================================
--  سياسات الجداول الأبناء
--
--  **جدولٌ بلا organization_id ليس محميّاً بحماية أبيه.** ما دام يُقرأ فعلياً
--  عبر استعلام يمرّ بالأب فهي حماية بالمصادفة لا بالتصميم، وأول استعلام
--  مباشر يكسرها. والقياس أثبت ذلك: purchase_order_items كان يُظهر الصفوف
--  الخمسة نفسها من سياق كل منظمة.
-- ============================================================================

-- ── الأبناء: يصلون إلى المنظمة عبر الأب ─────────────────────────────────
CREATE FUNCTION Security.fn_InvoiceChild(@InvoiceId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE EXISTS (
    SELECT 1 FROM dbo.invoices i
    WHERE i.id = @InvoiceId
      AND i.organization_id = CAST(SESSION_CONTEXT(N'organization_id') AS UNIQUEIDENTIFIER)
);
GO

-- ── الحفيد: سطر الدفعة يصل عبر قفزتين ───────────────────────────────────
--
-- invoice_item_batches لا يحمل invoice_id ولا organization_id، بل
-- invoice_item_id وحده. وليس جدولاً هامشياً: منه يُبنى المرتجع، ومنه يُعرف
-- ما بيع من أي شحنة.
CREATE FUNCTION Security.fn_InvoiceGrandChild(@InvoiceItemId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE EXISTS (
    SELECT 1 FROM dbo.invoice_items ii
    JOIN dbo.invoices i ON i.id = ii.invoice_id
    WHERE ii.id = @InvoiceItemId
      AND i.organization_id = CAST(SESSION_CONTEXT(N'organization_id') AS UNIQUEIDENTIFIER)
);
GO

CREATE FUNCTION Security.fn_PurchaseOrderChild(@PurchaseOrderId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE EXISTS (
    SELECT 1 FROM dbo.purchase_orders p
    WHERE p.id = @PurchaseOrderId
      AND p.organization_id = CAST(SESSION_CONTEXT(N'organization_id') AS UNIQUEIDENTIFIER)
);
GO

CREATE FUNCTION Security.fn_PurchaseReceiptChild(@PurchaseReceiptId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE EXISTS (
    SELECT 1 FROM dbo.purchase_receipts r
    WHERE r.id = @PurchaseReceiptId
      AND r.organization_id = CAST(SESSION_CONTEXT(N'organization_id') AS UNIQUEIDENTIFIER)
);
GO

CREATE FUNCTION Security.fn_SupplierInvoiceChild(@SupplierInvoiceId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE EXISTS (
    SELECT 1 FROM dbo.supplier_invoices i
    WHERE i.id = @SupplierInvoiceId
      AND i.organization_id = CAST(SESSION_CONTEXT(N'organization_id') AS UNIQUEIDENTIFIER)
);
GO

CREATE FUNCTION Security.fn_StockCountChild(@StockCountId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE EXISTS (
    SELECT 1 FROM dbo.stock_counts c
    WHERE c.id = @StockCountId
      AND c.organization_id = CAST(SESSION_CONTEXT(N'organization_id') AS UNIQUEIDENTIFIER)
);
GO

CREATE FUNCTION Security.fn_StockTransferChild(@TransferId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE EXISTS (
    SELECT 1 FROM dbo.stock_transfers t
    WHERE t.id = @TransferId
      AND t.organization_id = CAST(SESSION_CONTEXT(N'organization_id') AS UNIQUEIDENTIFIER)
);
GO

CREATE SECURITY POLICY Security.InvoiceItemsPolicy
  ADD FILTER PREDICATE Security.fn_InvoiceChild(invoice_id) ON dbo.invoice_items,
  ADD BLOCK PREDICATE Security.fn_InvoiceChild(invoice_id) ON dbo.invoice_items AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.InvoicePaymentsPolicy
  ADD FILTER PREDICATE Security.fn_InvoiceChild(invoice_id) ON dbo.invoice_payments,
  ADD BLOCK PREDICATE Security.fn_InvoiceChild(invoice_id) ON dbo.invoice_payments AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.InvoiceItemBatchesPolicy
  ADD FILTER PREDICATE Security.fn_InvoiceGrandChild(invoice_item_id) ON dbo.invoice_item_batches,
  ADD BLOCK PREDICATE Security.fn_InvoiceGrandChild(invoice_item_id) ON dbo.invoice_item_batches AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.PurchaseOrderItemsPolicy
  ADD FILTER PREDICATE Security.fn_PurchaseOrderChild(purchase_order_id) ON dbo.purchase_order_items,
  ADD BLOCK PREDICATE Security.fn_PurchaseOrderChild(purchase_order_id) ON dbo.purchase_order_items AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.PurchaseReceiptItemsPolicy
  ADD FILTER PREDICATE Security.fn_PurchaseReceiptChild(purchase_receipt_id) ON dbo.purchase_receipt_items,
  ADD BLOCK PREDICATE Security.fn_PurchaseReceiptChild(purchase_receipt_id) ON dbo.purchase_receipt_items AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.StockCountItemsPolicy
  ADD FILTER PREDICATE Security.fn_StockCountChild(stock_count_id) ON dbo.stock_count_items,
  ADD BLOCK PREDICATE Security.fn_StockCountChild(stock_count_id) ON dbo.stock_count_items AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.StockTransferItemsPolicy
  ADD FILTER PREDICATE Security.fn_StockTransferChild(transfer_id) ON dbo.stock_transfer_items,
  ADD BLOCK PREDICATE Security.fn_StockTransferChild(transfer_id) ON dbo.stock_transfer_items AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.CustomerAdvancesPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.customer_advances,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.customer_advances AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.CustomerCategoriesPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.customer_categories,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.customer_categories AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.SupplierInvoicesPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.supplier_invoices,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.supplier_invoices AFTER INSERT
  WITH (STATE = ON);
GO

-- سطور الفاتورة بلا organization_id — تُحمى عبر أبيها كسائر جداول الأبناء.
CREATE SECURITY POLICY Security.SupplierInvoiceLinesPolicy
  ADD FILTER PREDICATE Security.fn_SupplierInvoiceChild(supplier_invoice_id) ON dbo.supplier_invoice_lines,
  ADD BLOCK PREDICATE Security.fn_SupplierInvoiceChild(supplier_invoice_id) ON dbo.supplier_invoice_lines AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.BankAccountsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.bank_accounts,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.bank_accounts AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.FiscalClosingsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.fiscal_closings,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.fiscal_closings AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.SupplierPaymentsPolicy
  ADD FILTER PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.supplier_payments,
  ADD BLOCK PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.supplier_payments AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.AttachmentsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.attachments,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.attachments AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.CustomerPinAttemptsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.customer_pin_attempts,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.customer_pin_attempts AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.PosShiftsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.pos_shifts,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.pos_shifts AFTER INSERT
  WITH (STATE = ON);
GO

-- FILTER بلا BLOCK: سجلّ الدخول يُكتب **قبل** وجود أي سياق — المستخدم لم
-- يُصادَق عليه بعد. فمنعُ الإدراج يمنع تسجيل المحاولات الفاشلة، وهي أهمّ ما
-- في هذا الجدول.
CREATE SECURITY POLICY Security.LoginHistoryPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.login_history
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.PurchaseOrderChargesPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.purchase_order_charges,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.purchase_order_charges AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.AccountsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.accounts,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.accounts AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.JournalEntriesPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.journal_entries,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.journal_entries AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.AccountMappingsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.account_mappings,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.account_mappings AFTER INSERT
  WITH (STATE = ON);
GO

-- سطر القيد لا يحمل organization_id — يصل إليها عبر رأس القيد، بنفس نمط
-- invoice_items تماماً.
CREATE FUNCTION Security.fn_JournalChild(@EntryId UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE EXISTS (
    SELECT 1 FROM dbo.journal_entries e
    WHERE e.id = @EntryId
      AND e.organization_id = CAST(SESSION_CONTEXT(N'organization_id') AS UNIQUEIDENTIFIER)
);
GO

CREATE SECURITY POLICY Security.JournalEntryLinesPolicy
  ADD FILTER PREDICATE Security.fn_JournalChild(journal_entry_id) ON dbo.journal_entry_lines,
  ADD BLOCK PREDICATE Security.fn_JournalChild(journal_entry_id) ON dbo.journal_entry_lines AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.CustomersPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.customers,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.customers AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.CustomerWalletTransactionsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.customer_wallet_transactions,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.customer_wallet_transactions AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.SuppliersPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.suppliers,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.suppliers AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.ProductCategoriesPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.product_categories,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.product_categories AFTER INSERT
  WITH (STATE = ON);
GO

-- notifications.branch_id وصفي فقط (NULL = تنبيه على مستوى المنظمة كلها)
-- وليس عزلاً أمنياً — نفس معاملة customers.branch_id، فالفلترة حسب الفرع
-- تتم في NotificationsController نفسه وليس عبر fn_TenantPredicate.
CREATE SECURITY POLICY Security.NotificationsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.notifications,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.notifications AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.AuditLogsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.audit_logs,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.audit_logs AFTER INSERT
  WITH (STATE = ON);
GO

-- كانت branches بلا أي Security Policy رغم استخدامها من BranchesController
-- الآن — ثغرة عزل حقيقية (كل المنظمات كانت سترى فروع بعضها البعض).
CREATE SECURITY POLICY Security.BranchesPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.branches,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.branches AFTER INSERT
  WITH (STATE = ON);
GO

-- ثغرة أخطر: OrganizationsController.GetMyOrganization كان يستعلم
-- organizations.FirstOrDefaultAsync() بلا أي فلترة على افتراض وجود Security
-- Policy — لم تكن موجودة إطلاقاً، فكل منظمة كانت ترى بيانات (اسم/شعار/ألوان)
-- أول صف في الجدول بدل بياناتها الفعلية. آمن الإضافة هنا لأن /me محمي أصلاً
-- بـ [Authorize] (يوجد SESSION_CONTEXT دائماً وقت الاستعلام)، على عكس
-- app_users التي لا يمكن حمايتها بنفس الطريقة (راجع UsersController).
CREATE SECURITY POLICY Security.OrganizationsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(id) ON dbo.organizations,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(id) ON dbo.organizations AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.LicensesPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.licenses,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.licenses AFTER INSERT
  WITH (STATE = ON);
GO

-- stock_transfers لا يحمل عمود branch_id واحداً (بل from_branch_id/
-- to_branch_id معاً)، فلا يمكن استخدام fn_TenantPredicate هنا مباشرة —
-- عزل المنظمة فقط عبر fn_OrgOnlyPredicate، وفلترة "تحويلات فرعي تحديداً"
-- تتم يدوياً في StockTransfersController (راجع تعليقه).
CREATE SECURITY POLICY Security.StockTransfersPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.stock_transfers,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.stock_transfers AFTER INSERT
  WITH (STATE = ON);
GO

-- مصفوفة الصلاحيات الفعلية (RequirePermissionAttribute.cs) — role_permissions
-- يحمل organization_id فيُعزَل مثل أي جدول تشغيلي آخر. permissions نفسها
-- كتالوج عالمي مشترك بلا organization_id، فلا تحتاج عزلاً.
CREATE SECURITY POLICY Security.RolePermissionsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.role_permissions,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.role_permissions AFTER INSERT
  WITH (STATE = ON);
GO

-- كانت purchase_orders موثَّقة في هذا الملف بلا أي Security Policy رغم
-- حمل عمودَي organization_id + branch_id معاً (نفس حالة stock_levels) —
-- ثغرة عزل حقيقية لم تُكتشَف لأن لا Controller استعلم عنها قبل الآن.
CREATE SECURITY POLICY Security.PurchaseOrdersPolicy
  ADD FILTER PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.purchase_orders,
  ADD BLOCK PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.purchase_orders AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.WarehousesPolicy
  ADD FILTER PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.warehouses,
  ADD BLOCK PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.warehouses AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.StockLedgerEntriesPolicy
  ADD FILTER PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.stock_ledger_entries,
  ADD BLOCK PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.stock_ledger_entries AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.DebtRemindersPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.debt_reminders,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.debt_reminders AFTER INSERT
  WITH (STATE = ON);
GO

CREATE SECURITY POLICY Security.PurchaseReceiptsPolicy
  ADD FILTER PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.purchase_receipts,
  ADD BLOCK PREDICATE Security.fn_TenantPredicate(organization_id, branch_id) ON dbo.purchase_receipts AFTER INSERT
  WITH (STATE = ON);
GO

-- ملاحظة تنفيذية ثابتة: أي جدول تشغيلي جديد يُضاف مستقبلاً يجب أن يُنشأ له
-- Security Policy بنفس النمط أعلاه (fn_TenantPredicate إن كان يحمل branch_id،
-- أو fn_OrgOnlyPredicate إن كان على مستوى المنظمة فقط) — هذا هو العقد
-- الثابت الذي يمنع ثغرة عزل بيانات بين الفروع أو بين الزبائن مستقبلاً.

-- ============================================================================
-- سياسة عزل الجهات الممولة — نفس نمط suppliers (المنظمة ككل لا الفرع)
-- ============================================================================
CREATE SECURITY POLICY Security.SponsorsPolicy
  ADD FILTER PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.sponsors,
  ADD BLOCK PREDICATE Security.fn_OrgOnlyPredicate(organization_id) ON dbo.sponsors AFTER INSERT
  WITH (STATE = ON);
GO

-- ============================================================================
-- الفهارس
--
-- كل فهرس هنا يقابل استعلاماً فعلياً في الكود لا تخميناً: فهرس زائد يبطئ
-- الكتابة ويستهلك مساحة بلا مقابل. النسخة الكاملة مع تعليق كل فهرس واستعلامه
-- في backend/KineticEnterprise.Api/migrate_entitlement.sql.
--
-- SET إلزامي: sqlcmd يعمل افتراضياً بـ QUOTED_IDENTIFIER OFF والفهارس
-- المُصفّاة ترفض ذلك.
-- ============================================================================
SET QUOTED_IDENTIFIER ON;
GO

-- بديل قيد UNIQUE العادي: يسمح بعملاء كثيرين بلا بطاقة، ويمنع تكرار الرمز.
CREATE UNIQUE INDEX UX_customers_card_barcode ON customers (card_barcode) WHERE card_barcode IS NOT NULL;
CREATE INDEX IX_customers_org_name ON customers (organization_id, full_name) WHERE is_deleted = 0;
CREATE INDEX IX_customers_card_barcode ON customers (card_barcode) WHERE card_barcode IS NOT NULL;
CREATE INDEX IX_customers_sponsor ON customers (sponsor_id) WHERE sponsor_id IS NOT NULL;
CREATE INDEX IX_customers_entitlement_expiry ON customers (entitlement_expires_on) WHERE entitlement_expires_on IS NOT NULL;
CREATE INDEX IX_wallet_tx_customer_created ON customer_wallet_transactions (customer_id, created_at) INCLUDE (kind, amount);
CREATE INDEX IX_pin_attempts_customer_created ON customer_pin_attempts (customer_id, created_at) INCLUDE (success);
CREATE INDEX IX_products_org_name ON products (organization_id, name) WHERE is_deleted = 0;
CREATE INDEX IX_products_barcode ON products (barcode) WHERE barcode IS NOT NULL;
CREATE INDEX IX_invoices_branch_created ON invoices (branch_id, created_at);
CREATE INDEX IX_stock_levels_branch_product ON stock_levels (branch_id, product_id);
CREATE INDEX IX_audit_logs_org_created ON audit_logs (organization_id, created_at DESC);
GO
