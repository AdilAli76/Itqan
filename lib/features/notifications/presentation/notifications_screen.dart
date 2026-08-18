import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/notifications_providers.dart';
import '../../../shared/widgets/filter_chip_button.dart';

// ux-audit: ignore GV-02 — الإشعارات شخصية: كل مستخدم يرى إشعاراته هو،
// والخادم يحصرها بالمنظمة والمستخدم (NotificationsController) بلا أي رمز
// صلاحية. لا يوجد إجراء هنا يملكه بعض المستخدمين دون بعض.

// getter لا final: ألوان الحالات صارت تتبع سطوع السمة، ومتغيّر final على
// مستوى الملف يُقيَّم مرّة واحدة عند أول قراءة فيلتقط ألوان الوضع النهاري
// ويحتفظ بها بعد التبديل إلى الليلي. الـgetter يُعيد البناء عند كل قراءة.
Map<String, (IconData, Color, Color)> get _typeMeta => {
  'low_stock': (Icons.inventory_2_outlined, AppColors.warning, AppColors.warningBg),
  'expiry': (Icons.event_busy_outlined, AppColors.danger, AppColors.dangerBg),
  'count_variance': (Icons.difference_outlined, AppColors.info, AppColors.infoBg),
  'license': (Icons.verified_user_outlined, AppColors.info, AppColors.infoBg),
  'security': (Icons.security_outlined, AppColors.danger, AppColors.dangerBg),
};

(IconData, Color, Color) _metaFor(String type) =>
    _typeMeta[type] ?? (Icons.notifications_outlined, AppColors.textSecondary, AppColors.surfaceAlt);

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);
    final filter = ref.watch(notificationsFilterProvider);

    return AdaptiveScaffold(
      title: 'غرفة الإشعارات',
      activeRoute: '/notifications',
      actions: [
        TextButton(
          onPressed: () => _markAllRead(context, ref),
          child: const Text('تعليم الكل كمقروء'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wrap لا Row: شرائح الفلاتر تفيض على عرض الهاتف (قياس الفحص
          // البصري: حتى 233 بكسل). الالتفاف يبقيها كلها ظاهرة وقابلة
          // للنقر بدل قصّ آخرها بصمت.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChipButton(label: 'الكل', selected: filter == null, onTap: () => ref.read(notificationsFilterProvider.notifier).state = null),
              const SizedBox(width: 8),
              FilterChipButton(label: 'غير مقروءة', selected: filter == false, onTap: () => ref.read(notificationsFilterProvider.notifier).state = false),
              const SizedBox(width: 8),
              FilterChipButton(label: 'مقروءة', selected: filter == true, onTap: () => ref.read(notificationsFilterProvider.notifier).state = true),
            ],
          ),
          const SizedBox(height: 16),
          notificationsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => _ErrorBox(onRetry: () => ref.invalidate(notificationsProvider)),
            data: (notifications) {
              if (notifications.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(48),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text('لا توجد إشعارات', style: AppTextStyles.bodyMd()),
                );
              }
              return Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: notifications
                      .map((n) => _NotificationTile(notification: n))
                      .toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _markAllRead(BuildContext context, WidgetRef ref) async {
    try {
      await ApiClient.instance.dio.post('/notifications/mark-all-read');
      ref.invalidate(notificationsProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر تحديث الإشعارات')));
      }
    }
  }
}


class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text('تعذّر تحميل الإشعارات', style: AppTextStyles.bodyMd(color: AppColors.danger)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification});
  final Map<String, dynamic> notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRead = notification['isRead'] as bool? ?? false;
    final (icon, fg, bg) = _metaFor(notification['type'] as String? ?? '');
    final createdAt = DateTime.tryParse(notification['createdAt'] as String? ?? '');

    return InkWell(
      onTap: isRead ? null : () => _markRead(ref),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 18, color: fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification['title'] as String? ?? '',
                    style: AppTextStyles.bodyLg(color: AppColors.textPrimary)
                        .copyWith(fontWeight: isRead ? FontWeight.w400 : FontWeight.w700),
                  ),
                  if (notification['body'] != null) ...[
                    const SizedBox(height: 2),
                    Text(notification['body'] as String, style: AppTextStyles.bodyMd()),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    createdAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(createdAt) : '',
                    style: AppTextStyles.labelMd(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            if (!isRead)
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: AppColors.info, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _markRead(WidgetRef ref) async {
    try {
      await ApiClient.instance.dio.post('/notifications/${notification['id']}/read');
      ref.invalidate(notificationsProvider);
    } catch (_) {
      // فشل صامت — الإشعار يبقى غير مقروء ويمكن إعادة المحاولة بالنقر مجدداً.
    }
  }
}
