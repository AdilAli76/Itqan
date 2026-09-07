import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'print_settings_provider.dart';
import 'printer_profiles.dart';

const _printerProfileKey = 'kinetic_printer_profile';

/// الطابعة المختارة على **هذا الجهاز** — لا على المنظمة.
///
/// <para><b>سبب كونه إعداد جهاز:</b> فرعٌ عنده NB80 وآخر عنده ٥٨ ملم، على
/// المنظمة نفسها وفي اللحظة نفسها. وجعلُه إعداداً مركزياً يعني أن ضبط أحدهما
/// يُفسد طباعة الآخر — وهو نفس منطق [PosTouchModeNotifier].</para>
///
/// <para>وقبل أن يختار أحد: يُستنتَج من عرض الإيصال المحفوظ في إعدادات
/// المنظمة، فلا يُسأل المستخدم عمّا سبق أن أجاب عنه.</para>
final selectedPrinterProfileProvider =
    StateNotifierProvider<PrinterProfileNotifier, PrinterProfile>((ref) {
  final notifier = PrinterProfileNotifier();
  // العرض المحفوظ يصل متأخّراً (نداء شبكة)، ولا يتجاوز اختياراً صريحاً.
  ref.listen(receiptWidthMmProvider, (_, next) {
    final width = next.valueOrNull;
    if (width != null) notifier.applyOrganizationDefault(width);
  }, fireImmediately: true);
  return notifier;
});

class PrinterProfileNotifier extends StateNotifier<PrinterProfile> {
  PrinterProfileNotifier() : super(PrinterProfiles.nb80) {
    _load();
  }

  static const _storage = FlutterSecureStorage();

  /// أاختار المستخدم طابعةً بنفسه على هذا الجهاز؟
  bool _userChose = false;

  Future<void> _load() async {
    try {
      final stored = await _storage.read(key: _printerProfileKey);
      if (stored != null) {
        state = PrinterProfiles.byId(stored);
        _userChose = true;
      }
    } catch (_) {
      // تخزينٌ محجوب (متصفّح صارم، أو ملفٌّ تالف): يبقى الاستنتاج من
      // الإعدادات. وطابعةٌ افتراضية خيرٌ من شاشةٍ لا تطبع.
    }
  }

  Future<void> select(PrinterProfile profile) async {
    state = profile;
    _userChose = true;
    try {
      await _storage.write(key: _printerProfileKey, value: profile.id);
    } catch (_) {
      // يبقى الاختيار في هذه الجلسة ولو لم يُحفظ.
    }
  }

  /// يُطبَّق ما لم يختر المستخدم — راجع [_userChose].
  void applyOrganizationDefault(double receiptWidthMm) {
    if (_userChose) return;
    state = PrinterProfiles.fromReceiptWidth(receiptWidthMm);
  }
}
