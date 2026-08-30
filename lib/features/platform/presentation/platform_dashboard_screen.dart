import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/shell/open_tabs_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/app_surface.dart';
import '../../../shared/widgets/stat_card.dart';

final _money = NumberFormat('#,##0.00', 'en');
final _integer = NumberFormat('#,##0', 'en');
final _date = DateFormat('yyyy-MM-dd');

final platformDashboardProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final response = await ApiClient.instance.dio.get('/platform/dashboard');
  return Map<String, dynamic>.from(response.data as Map);
});

/// لوحة مالك المنصّة.
///
/// <para><b>الفجوة التي تسدّها:</b> بنود المنصّة كانت مدسوسة في آخر مجموعة
/// «النظام» بجانب الإعدادات والترخيص، ومالك المنصّة يدخل كأي مدير منظمة
/// فيجد ثلاثة بنودٍ زائدة في قائمته. فلا يرى حال أعماله **كمشغّل**: كم
/// عميلاً عنده، وكم اشتراكاً يقترب انتهاؤه، وكم يُحصّل شهرياً.</para>
///
/// <para><b>وأعماله هو ليست في هذه الأرقام:</b> منظمته الخاصّة لا صفَّ لها
/// في فهرس العملاء — راجع <c>PlatformOwnerBootstrap</c>. فما يُعرَض هنا
/// عملاؤه وحدهم.</para>
class PlatformDashboardScreen extends ConsumerWidget {
  const PlatformDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(platformDashboardProvider);

    return AdaptiveScaffold(
      title: 'لوحة المنصّة',
      activeRoute: '/platform',
      // القائمة تمرّر نفسها: لفّها بمُمرِّر خارجي يعطيها ارتفاعاً غير
      // محدود فتنهار بـ«Vertical viewport was given unbounded height» —
      // شاشةٌ بيضاء عند المستخدم. راجع AdaptiveScaffold.scrollable.
      scrollable: false,
      actions: [
        TextButton.icon(
          onPressed: () => ref.invalidate(platformDashboardProvider),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('تحديث'),
        ),
      ],
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_errorText(err, 'تعذّر تحميل اللوحة'),
                    style: AppTextStyles.bodyMd(color: AppColors.danger)),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => ref.invalidate(platformDashboardProvider),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
        data: (data) => _Body(data: data),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columns =
        Breakpoints.isDesktop(context) ? 4 : (Breakpoints.isTablet(context) ? 2 : 1);
    final suspended = (data['suspendedOrganizations'] as num?)?.toInt() ?? 0;
    final expiring = (data['expiringSoon'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return ListView(
      children: [
        GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          mainAxisExtent: 168,
          children: [
            StatCard(
              label: 'العملاء',
              value: _integer.format(data['totalOrganizations'] ?? 0),
              icon: Icons.apartment_outlined,
              trend: '${data['activeOrganizations'] ?? 0} نشطة',
            ),
            StatCard(
              label: 'الإيراد الشهري',
              // الموقوفة لا تدفع، فلا تُجمَع — رقمٌ لا يصل الحساب يُبنى
              // عليه قرار.
              value: '${_money.format((data['monthlyRecurring'] as num?) ?? 0)} د.ل',
              icon: Icons.payments_outlined,
              trend: 'من النشطة وحدها',
            ),
            StatCard(
              label: 'الفروع والمستخدمون',
              value: '${_integer.format(data['totalBranches'] ?? 0)}'
                  ' · ${_integer.format(data['totalUsers'] ?? 0)}',
              icon: Icons.store_outlined,
            ),
            StatCard(
              label: 'المساحة المستهلَكة',
              value: _formatBytes((data['totalStorageBytes'] as num?)?.toInt() ?? 0),
              icon: Icons.storage_outlined,
              // الرقم الذي يُسنِد رسم التخزين — راجع License.StorageFee.
              trend: 'أساس رسم التخزين',
            ),
          ],
        ),
        if (suspended > 0) ...[
          const SizedBox(height: 16),
          _Banner(
            color: AppColors.warning,
            icon: Icons.pause_circle_outline,
            text: '$suspended منظمة موقوفة — لا تدفع ولا تعمل. '
                'راجعها من شاشة الشركات المشترَكة.',
          ),
        ],
        const SizedBox(height: 20),
        Text('تراخيص تقترب من الانتهاء', style: AppTextStyles.bodyLg()),
        const SizedBox(height: 4),
        Text(
          // ثلاثون يوماً لا سبعة: تجديدٌ يحتاج تواصلاً وتحصيلاً، وأسبوعٌ
          // لا يكفي لملاحقة عميلٍ لا يردّ.
          'خلال ثلاثين يوماً أو انتهت — والأقرب أولاً',
          style: AppTextStyles.caption(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        if (expiring.isEmpty)
          AppSurface(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text('لا ترخيص يقترب انتهاؤه',
                    style: AppTextStyles.bodyMd(color: AppColors.textSecondary)),
              ),
            ),
          )
        else
          ...expiring.map((e) => _ExpiringRow(row: e)),
        const SizedBox(height: 24),
      ],
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes بايت';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} ك.ب';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} غ.ب';
  }
}

class _ExpiringRow extends ConsumerWidget {
  const _ExpiringRow({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = (row['daysLeft'] as num?)?.toInt() ?? 0;
    final expired = days < 0;
    final expires = DateTime.tryParse('${row['expiresAt']}');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppSurface(
        child: ListTile(
          leading: Icon(
            expired ? Icons.error_outline : Icons.schedule_outlined,
            color: expired ? AppColors.danger : AppColors.warning,
          ),
          title: Text('${row['displayName']}', style: AppTextStyles.bodyMd()),
          subtitle: Text(
            '${row['planTier']} · '
            '${expires == null ? '—' : _date.format(expires)}',
            style: AppTextStyles.caption(color: AppColors.textSecondary),
          ),
          trailing: Text(
            // «انتهى منذ» لا «-٣ أيام»: الرقم السالب يُقرأ مرّتين قبل أن
            // يُفهَم، والكلمة تُفهَم من أوّل نظرة.
            expired ? 'انتهى منذ ${-days} يوماً' : 'يتبقّى $days يوماً',
            style: AppTextStyles.bodyMd(
                color: expired ? AppColors.danger : AppColors.warning),
          ),
          onTap: () => ref
              .read(openTabsProvider.notifier)
              .open('/platform/organizations',
                  title: 'الشركات المشترَكة', icon: Icons.apartment_outlined),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text});
  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: AppTextStyles.bodyMd(color: color))),
          ],
        ),
      );
}

String _errorText(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
  }
  return fallback;
}
