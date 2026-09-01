import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/permissions.dart';
import '../../features/dashboard/presentation/super_admin_dashboard_screen.dart';
import '../../features/branches/presentation/branch_identity_screen.dart';
import '../../features/inventory/presentation/inventory_screen.dart';
import '../../features/purchasing/presentation/purchase_orders_screen.dart';
import '../../features/customers/presentation/customers_screen.dart';
import '../../features/wallet_cards/presentation/wallet_cards_screen.dart';
import '../../features/invoices/presentation/invoices_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/audit_log/presentation/audit_log_screen.dart';
import '../../features/users/presentation/users_screen.dart';
import '../../features/permissions/presentation/permissions_matrix_screen.dart';
import '../../features/license/presentation/license_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/stock_transfer/presentation/stock_transfer_screen.dart';
import '../../features/stock_count/presentation/stock_count_screen.dart';
import '../../features/accounting/presentation/accounting_screen.dart';
import '../../features/purchasing/presentation/supplier_invoices_screen.dart';
import '../../features/settings/presentation/receipt_designer_screen.dart';
import '../../features/payroll/presentation/payroll_screen.dart';
import '../../features/expenses/presentation/expenses_screen.dart';
import '../../features/barcode_designer/presentation/barcode_designer_screen.dart';
import '../../features/support/presentation/support_screen.dart';
import '../../features/pharmacy/presentation/medicine_reference_screen.dart';
import '../../features/reorder/presentation/reorder_screen.dart';
import '../../features/pharmacy/presentation/prescriptions_screen.dart';
import '../../features/platform/presentation/create_organization_screen.dart';
import '../../features/pos/presentation/wallet_pos_screen.dart';
import '../../features/platform/presentation/platform_organizations_screen.dart';
import '../../features/platform/presentation/platform_dashboard_screen.dart';

/// يقابل تماماً قائمة GoRoute السابقة في app_router.dart — لكن بدل أن يستبدل
/// كل مسار الصفحة كلها، يبني الودجت التي يعرضها AppShell داخل تبويب. أي
/// شاشة جديدة تُضاف مستقبلاً تُسجَّل هنا وفي nav_items.dart فقط.
Widget buildScreenForRoute(String route) {
  switch (route) {
    case '/dashboard':
      return const SuperAdminDashboardScreen();
    case '/branches':
      return const BranchIdentityScreen();
    case '/pos':
      // إصدار المحفظة له نقطة بيع مختلفة في نموذج العمل لا في الشكل:
      // مبلغ يُخصم من رصيد، لا سلّة أصناف. الاختيار داخل ودجت لا هنا،
      // لأن هذه الدالة بلا ref.
      return const PosScreenSwitcher();
    case '/inventory':
      return const InventoryScreen();
    case '/purchasing':
      return const PurchaseOrdersScreen();
    case '/customers':
      return const CustomersScreen();
    case '/wallet-cards':
      return const WalletCardsScreen();
    case '/invoices':
      return const InvoicesScreen();
    case '/notifications':
      return const NotificationsScreen();
    case '/reports':
      return const ReportsScreen();
    case '/audit-log':
      return const AuditLogScreen();
    case '/users':
      return const UsersScreen();
    case '/permissions':
      return const PermissionsMatrixScreen();
    case '/license':
      return const LicenseScreen();
    case '/settings':
      return const SettingsScreen();
    case '/stock-transfer':
      return const StockTransferScreen();
    case '/stock-count':
      return const StockCountScreen();
    case '/accounting':
      return const AccountingScreen();
    case '/supplier-invoices':
      return const SupplierInvoicesScreen();
    case '/expenses':
      return const ExpensesScreen();
    case '/barcode-designer':
      return const BarcodeDesignerScreen();
    case '/receipt-designer':
      return const ReceiptDesignerScreen();
    case '/payroll':
      return const PayrollScreen();
    case '/support':
      return const SupportScreen();
    case '/reorder':
      return const ReorderScreen();
    case '/medicine-reference':
      return const MedicineReferenceScreen();
    case '/prescriptions':
      return const PrescriptionsScreen();
    // شاشات المنصّة خلف حارس.
    //
    // إخفاؤها من القائمة ليس منعاً: المسار يُفتح بكتابته في المتصفّح أو من
    // رابطٍ محفوظ، فكانت تُفتح لأي مستخدم ثم يردّها الخادم فارغة — شاشةٌ
    // بيضاء يظنّها المستخدم عطباً ويتّصل بالدعم.
    //
    // والخادم يبقى الحارس الفعلي ([PlatformScope]) — هذا يمنع الشاشة
    // البيضاء لا يمنع الوصول.
    case '/platform':
      return const _PlatformOnly(child: PlatformDashboardScreen());
    case '/platform/organizations':
      return const _PlatformOnly(child: PlatformOrganizationsScreen());
    case '/platform/organizations/new':
      return const _PlatformOnly(child: CreateOrganizationScreen());
    default:
      return const SizedBox.shrink();
  }
}


/// شاشةٌ لا يفتحها إلا حساب منصّة — وإلا رسالةٌ تقول لماذا.
///
/// <para>ولا يُعاد توجيهٌ صامت إلى لوحة التحكّم: من فتح رابطاً محفوظاً
/// فوجد نفسه في شاشةٍ أخرى بلا كلمة يظنّ الرابط تالفاً ويعيد المحاولة.
/// والرسالة توقف المحاولة.</para>
class _PlatformOnly extends ConsumerWidget {
  const _PlatformOnly({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(isPlatformAdminProvider);

    return async.when(
      // لا شيء أثناء القراءة: وميضُ رسالة «هذه الشاشة لمشغّل النظام» ثم
      // ظهور الشاشة يُقلق مالك المنصّة نفسه في كل فتحة.
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const _PlatformDenied(),
      data: (isPlatform) => isPlatform ? child : const _PlatformDenied(),
    );
  }
}

class _PlatformDenied extends StatelessWidget {
  const _PlatformDenied();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'هذه الشاشة لمشغّل النظام وحده.',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
}
