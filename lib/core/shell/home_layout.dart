import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// شكل الشاشة الرئيسية.
enum HomeLayout {
  /// «تبع الجهاز»: شبكة اختصارات على الهاتف، ولوحة أرقام على الأوسع منه.
  auto,

  /// أرقام اليوم أوّلاً — لمن يفتح النظام ليعرف لا ليعمل.
  dashboard,

  /// شبكة اختصارات كبيرة — لمن يفتح النظام ليصل إلى شاشة بعينها.
  shortcuts,
}

/// تفضيل شكل الشاشة الرئيسية، محفوظاً بين الجلسات.
///
/// <para><b>سبب وجوده:</b> من يفتح النظام شخصان لا واحد. المدير يفتحه
/// ليعرف مبيعات اليوم — فلوحة الأرقام هي ما يريد. والكاشير يفتحه ليصل إلى
/// شاشة البيع في أقلّ عدد لمسات — والأرقام في طريقه عائق. وفرضُ أحدهما على
/// الآخر خسارةٌ في كل الحالات.</para>
///
/// <para><b>ومحلّي لا في جدول المنظمة</b> — كما [ThemeModeNotifier]:
/// جهازان في نفس المحلّ لصاحبه ولكاشيره، ولا معنى لأن يفرض أحدهما شكله على
/// الآخر.</para>
class HomeLayoutNotifier extends StateNotifier<HomeLayout> {
  HomeLayoutNotifier() : super(HomeLayout.auto) {
    _restore();
  }

  static const _key = 'kinetic_home_layout';
  static const _storage = FlutterSecureStorage();

  Future<void> _restore() async {
    try {
      final saved = await _storage.read(key: _key);
      state = switch (saved) {
        'dashboard' => HomeLayout.dashboard,
        'shortcuts' => HomeLayout.shortcuts,
        _ => HomeLayout.auto,
      };
    } catch (_) {
      // تعذّر التخزين الآمن لا يمنع الإقلاع — «تبع الجهاز» خيار صالح دائماً.
    }
  }

  Future<void> set(HomeLayout layout) async {
    state = layout;
    try {
      await _storage.write(key: _key, value: layout.name);
    } catch (_) {
      // فشل الحفظ يضيّع التفضيل عند إعادة التشغيل لا أكثر.
    }
  }
}

final homeLayoutProvider =
    StateNotifierProvider<HomeLayoutNotifier, HomeLayout>((ref) => HomeLayoutNotifier());
