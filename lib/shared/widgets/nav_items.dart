import 'package:flutter/material.dart';

/// قائمة موحّدة يشترك فيها كل من AppSidebar وAppNavbar — أي موديول جديد
/// يُسجَّل هنا بسطر واحد فقط ويظهر تلقائياً في كلا نمطي التنقّل.
class NavItem {
  const NavItem(this.icon, this.label, this.route);
  final IconData icon;
  final String label;
  final String route;
}

/// مجموعة عناصر مترابطة وظيفياً. المجموعة ذات العنصر الواحد تُرسَم كزر مباشر
/// بلا قائمة منسدلة (لا معنى لقائمة بخيار وحيد) — لهذا كل عنصر مستقل
/// يُمثَّل هنا كمجموعة من عنصر واحد، فيبقى للواجهتين نمط رسم واحد فقط.
class NavGroup {
  const NavGroup({required this.icon, required this.label, required this.items});
  final IconData icon;
  final String label;
  final List<NavItem> items;

  bool get isSingle => items.length == 1;
  NavItem get single => items.first;
  bool containsRoute(String route) => items.any((i) => i.route == route);
}

const _dashboard = NavItem(Icons.dashboard_outlined, 'لوحة التحكم', '/dashboard');
const _notifications = NavItem(Icons.notifications_outlined, 'الإشعارات', '/notifications');

// يظهر فقط لمالك المنصة (is_platform_admin في التوكن) — تزويد عملاء جدد
// على نفس السيرفر ليس جزءاً من صلاحيات أي عميل عادي مهما كان دوره.
const kPlatformNavItem = NavItem(Icons.add_business_outlined, 'إنشاء منظمة جديدة', '/platform/organizations/new');
const kPlatformManageItem = NavItem(Icons.apartment_outlined, 'الشركات المشترَكة', '/platform/organizations');

// نشرات الأدوية جدول على مستوى المنصّة يديره مالكها ويقرأه كل عملاء إصدار
// الصيدليات — فمكانه مع عناصر مالك المنصّة لا في قائمة أي عميل.
const kMedicineReferenceItem =
    NavItem(Icons.medical_information_outlined, 'نشرات الأدوية', '/medicine-reference');

// دفتر الوصفات بيانات الصيدلية نفسها (بخلاف النشرات المشتركة على مستوى
// المنصّة)، فيظهر لعملاء إصدار الصيدليات لا لمالك المنصّة وحده.
const kPrescriptionsItem =
    NavItem(Icons.assignment_outlined, 'دفتر الوصفات', '/prescriptions');

const _salesGroup = NavGroup(
  icon: Icons.point_of_sale_outlined,
  label: 'المبيعات',
  items: [
    NavItem(Icons.point_of_sale_outlined, 'نقطة البيع', '/pos'),
    NavItem(Icons.receipt_long_outlined, 'الفواتير', '/invoices'),
    NavItem(Icons.people_outline, 'العملاء', '/customers'),
    NavItem(Icons.credit_card_outlined, 'بطاقات المحفظة', '/wallet-cards'),
  ],
);

const _inventoryGroup = NavGroup(
  icon: Icons.inventory_2_outlined,
  label: 'المخزون',
  items: [
    NavItem(Icons.inventory_2_outlined, 'المخزون والموردين', '/inventory'),
    NavItem(Icons.shopping_cart_outlined, 'المشتريات', '/purchasing'),
    // بجوار المشتريات لا في التقارير: مخرَجه قرار شراء يُنفَّذ فوراً، لا رقم
    // يُقرأ ويُنسى. المكان يحدّد هل تُقرأ الشاشة أم لا.
    NavItem(Icons.shopping_cart_checkout_outlined, 'إعادة الطلب', '/reorder'),
    NavItem(Icons.sync_alt_outlined, 'تحويل المخزون بين الفروع', '/stock-transfer'),
    NavItem(Icons.fact_check_outlined, 'الجرد الدوري', '/stock-count'),
    NavItem(Icons.qr_code_outlined, 'تخصيص ملصق الباركود', '/barcode-designer'),
    NavItem(Icons.receipt_outlined, 'قالب الإيصال', '/receipt-designer'),
  ],
);

const _reportsGroup = NavGroup(
  icon: Icons.bar_chart_outlined,
  label: 'التقارير',
  items: [
    NavItem(Icons.bar_chart_outlined, 'التقارير', '/reports'),
    NavItem(Icons.history_outlined, 'سجل التدقيق', '/audit-log'),
  ],
);

const _adminGroup = NavGroup(
  icon: Icons.admin_panel_settings_outlined,
  label: 'الإدارة',
  items: [
    NavItem(Icons.admin_panel_settings_outlined, 'الصلاحيات والمستخدمون', '/users'),
    NavItem(Icons.rule_outlined, 'مصفوفة الصلاحيات', '/permissions'),
    NavItem(Icons.store_outlined, 'الفروع والهوية', '/branches'),
  ],
);

const _systemGroup = NavGroup(
  icon: Icons.settings_outlined,
  label: 'النظام',
  items: [
    NavItem(Icons.settings_outlined, 'الإعدادات العامة', '/settings'),
    NavItem(Icons.verified_user_outlined, 'الترخيص والاشتراك', '/license'),
    NavItem(Icons.support_agent_outlined, 'الدعم الفني', '/support'),
  ],
);

/// إصدارٌ على شكل المحفظة — بطاقات وأرصدة بلا بضاعة.
///
/// <para>يقابل `Editions.IsWalletShaped` في الخادم. والقائمتان تُقرآن معاً:
/// إصدارٌ يُضاف هنا ولا يُضاف هناك يُخفي شاشةً يسمح بها الخادم.</para>
bool _isWalletShaped(String edition) => edition == 'wallet' || edition == 'wallet_plus';

/// المجموعات بالترتيب المعروض.
///
/// **الوحدات تُمرَّر ولا تُشتقّ من الإصدار.** كان هنا `_hasAccounting` و
/// `edition == 'pharmacy'` يحسبان في Dart ما يحسبه الخادم في
/// `LicenseLimits.EffectiveModules`. وبعد أن صارت الوحدات تُباع فوق
/// الإصدار لا داخله، صار ذلك الحساب يُخفي عن العميل وحدةً اشتراها ويفتحها
/// له الخادم — ولا شيء في الشاشة يدلّه على السبب.
///
/// ويبقى `edition` لما هو **شكلٌ** لا وحدة: المحفظة تبيع بالقيمة الحرّة
/// وتصرف مرتَّبات، وذلك سلوكٌ لا يُشترى منفرداً.
///
/// وقائمة فارغة تعني «لم تُعرَف بعد» لا «لا شيء» — راجع [brandingProvider].
List<NavGroup> navGroupsFor({
  required bool isPlatformAdmin,
  String edition = 'standard',
  Set<String> modules = const {'inventory', 'pos', 'customers', 'reports'},
}) => [
      NavGroup(icon: _dashboard.icon, label: _dashboard.label, items: const [_dashboard]),
      _salesGroup,
      // إصدار المحفظة بلا بضاعة أصلاً: لا كتالوج ولا مخزون ولا مشتريات ولا
      // جرد ولا ملصقات باركود. إخفاء المجموعة هنا لا في كل واجهة على حدة —
      // ثلاثة مواضع تعرض هذه القائمة (الشريط الجانبي والعلوي ولوحة
      // الأوامر)، وإخفاء يُنفَّذ في اثنين يترك الشاشة قابلة للفتح من الثالث.
      if (modules.contains('inventory')) _inventoryGroup,
      // مجموعة تظهر لإصدار الصيدليات وحده — النظام يُباع لبقالة ومحل قطع
      // غيار، ودفتر الوصفات في قائمتهم بند لا معنى له.
      if (modules.contains('pharmacy'))
        const NavGroup(
          icon: Icons.local_pharmacy_outlined,
          label: 'الصيدلية',
          items: [kPrescriptionsItem],
        ),
      // المرتَّبات والسلف لإصدارات المحفظة وحدها: جهةٌ تصرف على منتسبيها
      // تحتاجهما، ومتجرٌ يبيع بضاعة لا معنى لهما في قائمته.
      if (_isWalletShaped(edition))
        const NavGroup(
          icon: Icons.account_balance_wallet_outlined,
          label: 'المرتَّبات',
          items: [
            NavItem(Icons.payments_outlined, 'المرتَّبات والسلف', '/payroll'),
          ],
        ),
      // المحاسبة لمن اشتراها — بقّالة بفرع واحد لا تحتاج ميزان مراجعة،
      // وشجرة حسابات في قائمتها بند يُربك ولا يُفيد. والترشيح هنا لا في كل
      // واجهة: ثلاثة مواضع تعرض هذه القائمة.
      if (modules.contains('accounting'))
        NavGroup(
          icon: Icons.account_balance_outlined,
          label: 'المحاسبة',
          items: [
            const NavItem(Icons.account_tree_outlined, 'دليل الحسابات', '/accounting'),
            // فواتير الموردين مع المحاسبة لا مع المشتريات: هي مستندٌ
            // محاسبي يُفرغ «وردت ولم تُفوتَر» إلى «الموردون».
            //
            // لكنها تحتاج **الاثنتين**: منظمةٌ بلا مشتريات لا استلامَ عندها
            // تُفوتره، فالشاشة تفتح فارغةً أبداً. وشاشةٌ لا تمتلئ يوماً
            // أسوأ من شاشةٍ غائبة — يظنّها المستخدم معطوبة.
            // المشتريات لا «ليست محفظة»: النقطة على الخادم تشترط
            // accounting **و** procurement معاً، فترشيحٌ بشرطٍ أوسع يعرض
            // بنداً يردّه الخادم بـ«وحدة غير مفعَّلة».
            if (modules.contains('procurement'))
              const NavItem(Icons.receipt_long_outlined, 'فواتير الموردين', '/supplier-invoices'),
          ],
        ),
      // المصروفات في كل الإصدارات عدا المحفظة البسيطة: الإيجار والرواتب
      // مصروفات كل نشاط، وبلا تسجيلها يقول تقرير الأرباح ربحاً ليس ربحاً.
      // أما إصدار المحفظة فجهةٌ تصرف على منتسبيها لا تُدير محلاً بمصروفاته.
      //
      // ومحفظةٌ **بمحاسبة** تحتاجها: دفترٌ يقيّد ما دخل ولا يقيّد ما صُرف
      // ليس دفتراً.
      if (edition != 'wallet')
        const NavGroup(
          icon: Icons.payments_outlined,
          label: 'المالية',
          items: [NavItem(Icons.payments_outlined, 'المصروفات', '/expenses')],
        ),
      _reportsGroup,
      NavGroup(icon: _notifications.icon, label: _notifications.label, items: const [_notifications]),
      _adminGroup,
      NavGroup(
        icon: _systemGroup.icon,
        label: _systemGroup.label,
        items: [
          ..._systemGroup.items,
          // نشرة الدواء تبقى هنا: محتوى منصّةٍ يُدار مرّةً، لا عملُ مشغّلٍ
          // يومي.
          if (isPlatformAdmin) kMedicineReferenceItem,
        ],
      ),
      // ── المنصّة ────────────────────────────────────────────────────
      //
      // مجموعةٌ مستقلّة لا بنودٌ مدسوسة في آخر «النظام» بجانب الإعدادات.
      // مالك المنصّة **مشغّلٌ لا مستأجر**: عملُه إدارة عملاء واشتراكات، لا
      // ضبط إعدادات منظمةٍ واحدة. وخلطُهما جعله يدخل كأي مدير فيجد ثلاثة
      // بنودٍ زائدة، ولا يرى حال أعماله كمشغّل في أي شاشة.
      if (isPlatformAdmin)
        const NavGroup(
          icon: Icons.hub_outlined,
          label: 'المنصّة',
          items: [
            NavItem(Icons.dashboard_outlined, 'لوحة المنصّة', '/platform'),
            kPlatformManageItem,
            kPlatformNavItem,
          ],
        ),
    ];

/// يُسقط من القائمة الوحدات التي يحجبها الخادم كلياً عن هذا المستخدم.
///
/// الترشيح هنا لا في كل من AppSidebar وAppNavbar ولوحة الأوامر: ثلاثة
/// مواضع تعرض القائمة نفسها، وأي ترشيح يُنفَّذ في اثنين منها فقط يترك
/// الوحدة المحجوبة قابلة للفتح من الثالث.
///
/// المجموعة التي تفرغ عناصرها تُحذف بأكملها — عنوان مجموعة بلا محتوى
/// يُوحي بعطل لا بقيد صلاحيات.
List<NavGroup> filterByPermissions(List<NavGroup> groups, bool Function(String route) canOpen) {
  final result = <NavGroup>[];
  for (final group in groups) {
    final items = group.items.where((i) => canOpen(i.route)).toList();
    if (items.isEmpty) continue;
    result.add(NavGroup(icon: group.icon, label: group.label, items: items));
  }
  return result;
}

/// قائمة مسطّحة لكل الشاشات — يستخدمها AppShell للبحث عن شاشة البداية
/// بمسارها، ولا علاقة لها بالعرض.
final kNavItems = <NavItem>[
  for (final group in navGroupsFor(isPlatformAdmin: true)) ...group.items,
];
