import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';

/// نافذة/تبويب مفتوح — الشاشة نفسها تبقى حيّة في الذاكرة (IndexedStack في
/// AppShell) طالما تبويبها مفتوح، فلا يُعاد بناؤها من الصفر عند التنقّل
/// إليها مجدداً (هذا هو جوهر حل شكوى "فتح شاشة يشعرك كأنك فتحت النظام من
/// جديد" — راجع AppShell.dart).
@immutable
class OpenTab {
  const OpenTab({required this.route, required this.title, required this.icon});
  final String route;
  final String title;
  final IconData icon;
}

@immutable
class TabsState {
  const TabsState({required this.tabs, required this.activeRoute});
  final List<OpenTab> tabs;
  final String? activeRoute;

  TabsState copyWith({List<OpenTab>? tabs, String? activeRoute}) =>
      TabsState(tabs: tabs ?? this.tabs, activeRoute: activeRoute ?? this.activeRoute);

  static const empty = TabsState(tabs: [], activeRoute: null);
}

class OpenTabsNotifier extends StateNotifier<TabsState> {
  OpenTabsNotifier() : super(TabsState.empty);

  /// يفتح تبويباً جديداً إن لم يكن مفتوحاً أصلاً، ثم يُنشِّطه دائماً —
  /// النقر على عنصر في القائمة الجانبية مرتين لا يفتح نسختين، فقط يُركِّز
  /// على نفس التبويب الموجود (نفس سلوك تبويبات المتصفح).
  void open(String route, {required String title, required IconData icon}) {
    if (!state.tabs.any((t) => t.route == route)) {
      state = state.copyWith(tabs: [...state.tabs, OpenTab(route: route, title: title, icon: icon)]);
    }
    state = state.copyWith(activeRoute: route);
  }

  void activate(String route) => state = state.copyWith(activeRoute: route);

  void close(String route) {
    final closedIndex = state.tabs.indexWhere((t) => t.route == route);
    if (closedIndex == -1) return;
    final newTabs = List<OpenTab>.from(state.tabs)..removeAt(closedIndex);

    var newActive = state.activeRoute;
    if (state.activeRoute == route) {
      newActive = newTabs.isEmpty ? null : newTabs[closedIndex.clamp(0, newTabs.length - 1)].route;
    }
    state = TabsState(tabs: newTabs, activeRoute: newActive);
  }

  void closeAll() => state = TabsState.empty;
}

final openTabsProvider = StateNotifierProvider<OpenTabsNotifier, TabsState>((ref) => OpenTabsNotifier());

/// مشتركة بين AppShell (زر خروج الموبايل) وAdaptiveScaffold (زر خروج
/// الديسكتوب المدمَج في الشريط العلوي) — حتى لا يتكرر نفس المنطق مرتين.
Future<void> performLogout(WidgetRef ref) async {
  await ApiClient.instance.clearToken();
  ref.read(openTabsProvider.notifier).closeAll();
}
