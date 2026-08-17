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
    NavItem(Icons.sync_alt_outlined, 'تحويل المخزون بين الفروع', '/stock-transfer'),
    NavItem(Icons.fact_check_outlined, 'الجرد الدوري', '/stock-count'),
    NavItem(Icons.qr_code_outlined, 'تخصيص ملصق الباركود', '/barcode-designer'),
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

/// المجموعات بالترتيب المعروض. مالك المنصة وحده يرى "إنشاء منظمة جديدة"،
/// وتُضاف داخل مجموعة النظام بدل أن تكون عنصراً سائباً في آخر القائمة.
List<NavGroup> navGroupsFor({required bool isPlatformAdmin}) => [
      NavGroup(icon: _dashboard.icon, label: _dashboard.label, items: const [_dashboard]),
      _salesGroup,
      _inventoryGroup,
      _reportsGroup,
      NavGroup(icon: _notifications.icon, label: _notifications.label, items: const [_notifications]),
      _adminGroup,
      NavGroup(
        icon: _systemGroup.icon,
        label: _systemGroup.label,
        items: [..._systemGroup.items, if (isPlatformAdmin) kPlatformNavItem],
      ),
    ];

/// قائمة مسطّحة لكل الشاشات — يستخدمها AppShell للبحث عن شاشة البداية
/// بمسارها، ولا علاقة لها بالعرض.
final kNavItems = <NavItem>[
  for (final group in navGroupsFor(isPlatformAdmin: true)) ...group.items,
];
