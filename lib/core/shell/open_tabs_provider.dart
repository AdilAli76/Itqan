import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/permissions.dart';
import '../network/api_client.dart';
import '../network/offline_queue.dart';

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
  const TabsState({required this.tabs, required this.activeRoute, this.history = const []});
  final List<OpenTab> tabs;
  final String? activeRoute;

  /// <summary>
  /// التبويبات التي زارها المستخدم قبل الحالي — الأحدث آخراً.
  ///
  /// <para><b>سبب وجوده:</b> بعد الدخول لا مسار في الموجّه إلا <c>/app</c>
  /// وحده، والتنقّل كلّه بين تبويبات في الذاكرة. فزرّ الرجوع في الهاتف لا
  /// يجد ما يرجع إليه — **فيُغلق التطبيق كلّه** من أوّل ضغطة، وهي شكوى
  /// زبونٍ حقيقية. وهذا التاريخ هو ما يرجع إليه.</para>
  /// </summary>
  final List<String> history;

  TabsState copyWith({List<OpenTab>? tabs, String? activeRoute, List<String>? history}) => TabsState(
        tabs: tabs ?? this.tabs,
        activeRoute: activeRoute ?? this.activeRoute,
        history: history ?? this.history,
      );

  static const empty = TabsState(tabs: [], activeRoute: null, history: []);
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
    _activate(route);
  }

  void activate(String route) => _activate(route);

  /// التنشيط مع تسجيل ما كان قبله — راجع [TabsState.history].
  void _activate(String route) {
    if (state.activeRoute == route) return;

    final previous = state.activeRoute;
    final history = previous == null
        ? state.history
        // ولا يتكرّر المسار في التاريخ: من تنقّل بين شاشتين عشر مرّات كان
        // يحتاج عشر ضغطات رجوع ليخرج من الثانية.
        : [...state.history.where((r) => r != previous), previous];

    state = state.copyWith(activeRoute: route, history: history);
  }

  /// <summary>
  /// الرجوع إلى التبويب السابق. يُعيد <c>false</c> إن لم يبقَ ما يُرجع إليه
  /// — وعندها يقرّر [AppShell] ما يفعله بضغطة الرجوع.
  /// </summary>
  bool back() {
    final history = List<String>.from(state.history);
    while (history.isNotEmpty) {
      final candidate = history.removeLast();
      // تبويبٌ أُغلق بعد زيارته لا يُرجَع إليه: الرجوع يجب أن يُظهر شاشةً
      // موجودة لا أن يفتح واحدةً أغلقها صاحبها عمداً.
      if (state.tabs.any((t) => t.route == candidate)) {
        state = TabsState(tabs: state.tabs, activeRoute: candidate, history: history);
        return true;
      }
    }
    if (history.length != state.history.length) {
      state = state.copyWith(history: history);
    }
    return false;
  }

  void close(String route) {
    final closedIndex = state.tabs.indexWhere((t) => t.route == route);
    if (closedIndex == -1) return;
    final newTabs = List<OpenTab>.from(state.tabs)..removeAt(closedIndex);
    final newHistory = state.history.where((r) => r != route).toList();

    var newActive = state.activeRoute;
    if (state.activeRoute == route) {
      newActive = newTabs.isEmpty ? null : newTabs[closedIndex.clamp(0, newTabs.length - 1)].route;
    }
    state = TabsState(tabs: newTabs, activeRoute: newActive, history: newHistory);
  }

  void closeAll() => state = TabsState.empty;
}

final openTabsProvider = StateNotifierProvider<OpenTabsNotifier, TabsState>((ref) => OpenTabsNotifier());

/// مشتركة بين AppShell (زر خروج الموبايل) وAdaptiveScaffold (زر خروج
/// الديسكتوب المدمَج في الشريط العلوي) — حتى لا يتكرر نفس المنطق مرتين.
Future<void> performLogout(WidgetRef ref) async {
  await ApiClient.instance.clearToken();
  ref.read(openTabsProvider.notifier).closeAll();
  // وإلا بقيت صلاحيات الخارج معروضةً لمن يدخل بعده على نفس الجهاز.
  invalidateUserScopedProviders(ref);

  // الطابور يُخفى عن الشاشة ولا يُمحى من التخزين: قد يحمل مبيعات حقيقية لم
  // تصل الخادم بعد، ومحوُها عند الخروج يُضيّع مالاً قُبض فعلاً. ويعود
  // ظهوره حين يدخل صاحبه — راجع OfflineQueueNotifier.reloadForCurrentUser.
  await ref.read(offlineQueueProvider.notifier).reloadForCurrentUser();
}
