import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/stat_card.dart';
import '../data/license_providers.dart';
import '../../../core/auth/permissions.dart';

const _planLabels = {
  'trial': 'تجريبية',
  'standard': 'قياسية',
  'professional': 'احترافية',
  'enterprise': 'مؤسسات',
};

const _statusLabels = {
  'active': 'نشط',
  'grace_period': 'فترة سماح',
  'expired': 'منتهي',
  'revoked': 'ملغى',
};

const _moduleLabels = {
  'inventory': 'المخزون والموردون',
  'pos': 'نقطة البيع',
  'customers': 'العملاء',
  'invoices': 'الفواتير',
  'reports': 'التقارير والتحليلات',
  'notifications': 'الإشعارات',
};

class LicenseScreen extends ConsumerWidget {
  const LicenseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final licenseAsync = ref.watch(licenseProvider);

    // حارس على مستوى الوحدة لا الزر: الخادم يحرس هذا الـController
    // كاملاً، فبلا الصلاحية لا توجد بيانات تُعرض أصلاً — وعرض جدول
    // فارغ هنا كان يُفهَم كـ«لا توجد سجلات» لا كـ«ليست لك صلاحية».
    if (!ref.perms.can(Perm.licenseView)) {
      return const AdaptiveScaffold(
        title: 'الترخيص والاشتراك',
        activeRoute: '/license',
        body: NoPermissionView(moduleName: 'الترخيص والاشتراك'),
      );
    }


    return AdaptiveScaffold(
      title: 'الترخيص والاشتراك',
      activeRoute: '/license',
      body: licenseAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (err, _) {
          final isNotFound = err is DioException && err.response?.statusCode == 404;
          return Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Text(
                  isNotFound ? 'لا يوجد ترخيص مسجَّل لهذه المنظمة بعد' : 'تعذّر تحميل بيانات الترخيص',
                  style: AppTextStyles.bodyMd(color: AppColors.danger),
                ),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: () => ref.invalidate(licenseProvider), child: const Text('إعادة المحاولة')),
              ],
            ),
          );
        },
        data: (license) => _LicenseContent(license: license),
      ),
    );
  }
}

class _LicenseContent extends StatelessWidget {
  const _LicenseContent({required this.license});
  final Map<String, dynamic> license;

  @override
  Widget build(BuildContext context) {
    final status = license['status'] as String? ?? '';
    final daysRemaining = (license['daysRemaining'] as num?)?.toInt() ?? 0;
    final expiresAt = DateTime.tryParse(license['expiresAt'] as String? ?? '');
    final modules = List<String>.from(license['enabledModules'] as List? ?? []);
    final crossAxisCount = Breakpoints.isDesktop(context) ? 4 : (Breakpoints.isTablet(context) ? 2 : 1);

    Color statusColor;
    switch (status) {
      case 'active':
        statusColor = AppColors.success;
        break;
      case 'grace_period':
        statusColor = AppColors.warning;
        break;
      default:
        statusColor = AppColors.danger;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(_planLabels[license['planTier']] ?? license['planTier'] as String? ?? '', style: AppTextStyles.headlineLg()),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                    child: Text(_statusLabels[status] ?? status, style: AppTextStyles.labelMd(color: statusColor)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                expiresAt != null
                    ? 'ينتهي في ${DateFormat('yyyy-MM-dd').format(expiresAt)}'
                        '${daysRemaining >= 0 ? " (بعد $daysRemaining يوماً)" : " (منتهي منذ ${-daysRemaining} يوماً)"}'
                    : '-',
                style: AppTextStyles.bodyMd(color: daysRemaining <= 14 ? AppColors.warning : AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              Text('رمز الترخيص: ${license['licenseKey']}', style: AppTextStyles.labelMd(color: AppColors.textMuted)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          mainAxisExtent: 168,
          children: [
            StatCard(
              label: 'الفروع المستخدَمة',
              value: '${license['currentBranches']} / ${license['maxBranches']}',
              icon: Icons.store_outlined,
              accentColor: _usageColor(license['currentBranches'], license['maxBranches']),
            ),
            StatCard(
              label: 'المستخدمون النشطون',
              value: '${license['currentUsers']} / ${license['maxUsers']}',
              icon: Icons.people_outline,
              accentColor: _usageColor(license['currentUsers'], license['maxUsers']),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('الموديولات المفعَّلة', style: AppTextStyles.headlineMd()),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: modules
                    .map((m) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(8)),
                          child: Text(_moduleLabels[m] ?? m, style: AppTextStyles.bodyMd(color: AppColors.textPrimary)),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.info, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'لتجديد الترخيص أو ترقية الخطة، تواصل مع مزوّد النظام — لا يوجد تجديد ذاتي من داخل التطبيق حالياً.',
                  style: AppTextStyles.bodyMd(color: AppColors.info),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _usageColor(dynamic current, dynamic max) {
    final c = (current as num?)?.toDouble() ?? 0;
    final m = (max as num?)?.toDouble() ?? 1;
    if (m <= 0) return AppColors.textSecondary;
    final ratio = c / m;
    if (ratio >= 1) return AppColors.danger;
    if (ratio >= 0.8) return AppColors.warning;
    return AppColors.success;
  }
}
