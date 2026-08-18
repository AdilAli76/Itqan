import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/network/api_client.dart';

/// هل يُسمح ببيع الأصناف مفتوحة القيمة في نقطة البيع؟
///
/// إعداد على مستوى المنظمة يضبطه مديرها من شاشة الإعدادات، ويُقرأ من
/// `GET /organizations/me/settings` — أي أن مصدر الحقيقة هو السيرفر لا
/// الجهاز. السبب: بيع بقيمة يكتبها الكاشير بنفسه هو أوسع باب لسحب نقدية
/// بلا بضاعة مقابلة، فالسماح به قرار مالك المنظمة، ولا يجوز أن يفتحه
/// الكاشير من إعدادات جهازه.
final posAllowOpenProductProvider = FutureProvider.autoDispose<bool>((ref) async {
  final response = await ApiClient.instance.dio.get('/organizations/me/settings');
  final data = response.data as Map<String, dynamic>;
  return data['posAllowOpenProduct'] as bool? ?? false;
});

/// أصناف مفتوحة القيمة المتاحة في الكتالوج (tracksStock = false).
///
/// الـ Backend يشترط productId حقيقياً في كل سطر فاتورة، فـ"المنتج المفتوح"
/// ليس سطراً بلا صنف: هو صنف في الكتالوج لا يتبع المخزون وتُكتب قيمته عند
/// البيع. لذلك تُعرَض قائمة هذه الأصناف بدل زر واحد مجهول المرجع.
final posOpenProductsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.dio.get('/products/inventory');
  final all = List<Map<String, dynamic>>.from(response.data as List);
  return all.where((p) => (p['tracksStock'] as bool? ?? true) == false).toList();
});

const _touchModeKey = 'kinetic_pos_touch_mode';

/// وضع اللمس — إعداد **للجهاز** لا للمنظمة.
///
/// جهاز الكاشير قد يكون شاشة لمس بينما جهاز المدير فأرة ولوحة مفاتيح، على
/// نفس المنظمة وفي نفس اللحظة. لذلك يُخزَّن محلياً على الجهاز، ولا يُرسَل
/// إلى السيرفر ولا يُشارك بين المستخدمين.
///
/// القيمة الافتراضية: مفعَّل على أندرويد و iOS (لا وسيلة إدخال أخرى فيهما
/// أصلاً)، ومطفأ على سطح المكتب والويب حيث الفأرة هي الأصل.
class PosTouchModeNotifier extends StateNotifier<bool> {
  PosTouchModeNotifier() : super(_platformDefault()) {
    _load();
  }

  static const _storage = FlutterSecureStorage();

  /// هل اختار المستخدم الوضع بنفسه؟ الكشف التلقائي لا يتجاوز اختياراً صريحاً
  /// — من أطفأ اللمس عمداً لا يُعاد تشغيله عليه عند أول لمسة.
  bool _userChose = false;

  static bool _platformDefault() {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  Future<void> _load() async {
    try {
      final stored = await _storage.read(key: _touchModeKey);
      if (stored != null) {
        state = stored == 'true';
        _userChose = true;
      }
    } catch (_) {
      // تعذّر قراءة التخزين الآمن (منصة بلا دعم أو صلاحية) — يبقى الافتراضي
      // حسب المنصة، وهو تفضيل عرض لا يستحق رسالة خطأ للكاشير.
    }
  }

  /// يُستدعى عند أول لمسة بإصبع على الشاشة.
  ///
  /// شاشات الكاشير التي تعمل باللمس على ويندوز لا يمكن تمييزها من نوع
  /// المنصة — ويندوز هو ويندوز سواء وُصلت به فأرة أو شاشة لمس. لكن نوع
  /// المؤشر في حدث الضغط يقولها بوضوح: touch أم mouse. فبدل أن نطلب من
  /// الكاشير اكتشاف مفتاح في الشريط، يتحوّل النظام من أول لمسة.
  Future<void> enableFromTouchInput() async {
    if (_userChose || state) return;
    state = true;
    try {
      await _storage.write(key: _touchModeKey, value: 'true');
    } catch (_) {
      // يعمل في هذه الجلسة حتى لو لم يُحفَظ.
    }
  }

  Future<void> toggle() async {
    state = !state;
    _userChose = true;
    try {
      await _storage.write(key: _touchModeKey, value: state.toString());
    } catch (_) {
      // الوضع يعمل في هذه الجلسة حتى لو لم يُحفَظ.
    }
  }
}

final posTouchModeProvider = StateNotifierProvider<PosTouchModeNotifier, bool>(
  (ref) => PosTouchModeNotifier(),
);
