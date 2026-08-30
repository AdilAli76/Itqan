import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// نغمات نقطة البيع.
///
/// الكاشير ينظر إلى الزبون وإلى البضاعة لا إلى الشاشة، فرسالة خطأ حمراء
/// تمرّ دون أن يراها أحد. والصوت هو ما يمنع الخطأين الأشيع في المتجر: مسح
/// الصنف مرّتين لأن المسحة الأولى بدت صامتة، والانصراف بعد مسحة فاشلة ظنّاً
/// أنها نجحت.
///
/// النغمات مضمَّنة في الحزمة لا مُنزَّلة: جهاز نقطة بيع قد يعمل بلا إنترنت،
/// وصوتٌ لا يُسمع إلا بالشبكة لا يُعتمد عليه.
class PosSounds {
  PosSounds._();

  // مشغّلات منفصلة لكل نغمة: مشغّل واحد يقطع الصوت السابق عند تشغيل التالي،
  // ومسح صنفين متتابعين بسرعة كان يُسمع كنغمة واحدة مبتورة.
  static final _scan = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
  static final _success = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
  static final _error = AudioPlayer()..setReleaseMode(ReleaseMode.stop);

  static bool enabled = true;

  static Future<void> _play(AudioPlayer player, String file) async {
    if (!enabled) return;
    try {
      await player.stop();
      await player.play(AssetSource('sounds/$file'), volume: 0.6);
    } catch (e) {
      // جهاز بلا مخرج صوت، أو متصفح يمنع التشغيل قبل أول تفاعل من المستخدم.
      // البيع لا يتوقّف لأجل نغمة.
      if (kDebugMode) debugPrint('تعذّر تشغيل النغمة: $e');
    }
  }

  /// صنف أُضيف إلى السلة أو مسحة نجحت — نغمة قصيرة جداً تُسمع عشرات المرّات
  /// في الساعة، فطولها متعمَّد.
  static Future<void> scan() => _play(_scan, 'scan.wav');

  /// فاتورة أُصدرت، أو عملية اكتملت.
  static Future<void> success() => _play(_success, 'success.wav');

  /// رفض من السيرفر، أو صنف غير موجود، أو رصيد غير كافٍ.
  static Future<void> error() => _play(_error, 'error.wav');
}
