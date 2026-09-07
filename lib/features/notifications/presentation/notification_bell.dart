import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/notifications_providers.dart';

/// أيقونة جرس الإشعارات في رأس التطبيق — تفتح شاشة الإشعارات عند النقر
/// وتعرض شارة بعدد الإشعارات غير المقروءة.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return notificationsAsync.when(
      loading: () => const IconButton(
        onPressed: null,
        icon: Icon(Icons.notifications_outlined),
        tooltip: 'جاري تحميل الإشعارات',
      ),
      error: (err, _) => IconButton(
        onPressed: () => context.go('/notifications'),
        icon: const Icon(Icons.notifications_outlined),
        tooltip: 'الإشعارات',
      ),
      data: (notifications) {
        final unreadCount = notifications.where((n) => n['read'] == false).length;

        return Stack(
          alignment: Alignment.topRight,
          children: [
            IconButton(
              onPressed: () => context.go('/notifications'),
              icon: const Icon(Icons.notifications_outlined),
              tooltip: unreadCount > 0
                  ? 'لديك $unreadCount إشعار جديد'
                  : 'الإشعارات',
            ),
            if (unreadCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
