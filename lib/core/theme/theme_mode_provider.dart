import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// تفضيل السمة (نهاري/ليلي/تبع النظام) محفوظاً بين الجلسات.
///
/// يُحفظ محلياً لا في جدول المنظمة عمداً: هذا تفضيل شخص لا إعداد مؤسسة.
/// موظفان على الجهاز نفسه في ورديتين مختلفتين — واحدة نهارية وأخرى مسائية —
/// لكلٍّ منهما تفضيله، ولا معنى لأن يفرض أحدهما سمته على الآخر أو أن يُخزَّن
/// ذلك في قاعدة بيانات مشتركة.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _restore();
  }

  static const _key = 'kinetic_theme_mode';
  static const _storage = FlutterSecureStorage();

  Future<void> _restore() async {
    try {
      final saved = await _storage.read(key: _key);
      state = switch (saved) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      // تعذّر قراءة التخزين الآمن لا يجوز أن يمنع إقلاع التطبيق؛ يبقى
      // التفضيل على «تبع النظام» وهو خيار صالح دائماً.
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    try {
      await _storage.write(key: _key, value: value);
    } catch (_) {
      // الحفظ الفاشل يعني ضياع التفضيل عند إعادة التشغيل فقط — لا داعي
      // لإزعاج المستخدم برسالة خطأ عن تفضيل عرض.
    }
  }

  /// تبديل سريع بين النهاري والليلي.
  ///
  /// يبدأ من السطوع الفعلي الحالي لا من الحالة المخزَّنة: لو كان التفضيل
  /// «تبع النظام» والنظام داكن، فالضغط على زر التبديل يجب أن ينقل إلى
  /// النهاري — لا إلى الداكن الذي هو فيه أصلاً.
  Future<void> toggle(Brightness current) =>
      set(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) => ThemeModeNotifier());
