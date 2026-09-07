import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// استرجاع المحذوف من سجلّ التدقيق.
///
/// <para><b>لماذا يستحقّ اختباراً:</b> نافذة الحذف تَعِد صراحةً «يمكن
/// استرجاعه لاحقاً من سجل التدقيق». والوعد يُخلَف بصمت بطريقين: زرٌّ
/// يَعِد بنقطةٍ لا وجود لها (فيردّ الخادم 404 بعد أن ضغط المستخدم مطمئنّاً)،
/// أو حذفٌ ناعم بلا زرٍّ أصلاً — فتبقى البيانات في القاعدة سليمة ولا يصل
/// إليها أحد. وهذا الثاني هو ما وقع فعلاً بالمورّد والجهة الراعية:
/// محفوظان، ومفقودان.</para>
void main() {
  final ui = File('lib/features/audit_log/presentation/audit_log_screen.dart').readAsStringSync();

  /// أفعال الحذف المعروضة بزرّ استرجاع، ومسار كلٍّ منها.
  Map<String, String> restorable() {
    final block = RegExp(r'const _restorableActions = \{(.*?)\};', dotAll: true).firstMatch(ui);
    expect(block, isNotNull, reason: 'لم تُعثر خريطة _restorableActions');
    final out = <String, String>{};
    for (final m in RegExp(r"'([a-z_.]+)': \('(/[a-z-]+)'").allMatches(block!.group(1)!)) {
      out[m.group(1)!] = m.group(2)!;
    }
    return out;
  }

  String controllerFor(String route) {
    final name = route.substring(1); // customers
    final camel = name[0].toUpperCase() + name.substring(1);
    return 'backend/KineticEnterprise.Api/Controllers/${camel}Controller.cs';
  }

  group('كل زرّ استرجاع خلفه نقطة', () {
    test('الخريطة ليست فارغة — وإلا مرّ الاختبار بلا أن يفحص شيئاً', () {
      expect(restorable(), isNotEmpty);
    });

    test('لكل فعلٍ معروض نقطةُ استرجاع في وحدة تحكّمه', () {
      restorable().forEach((action, route) {
        final file = File(controllerFor(route));
        expect(file.existsSync(), isTrue, reason: '$action → ${file.path} غير موجود');
        expect(
          file.readAsStringSync(),
          contains('[HttpPost("{id:guid}/restore")]'),
          // زرٌّ بلا نقطة أسوأ من لا زرّ: يَعِد ثم يردّ 404 بعد الضغط.
          reason: '$action يَعِد باسترجاع ولا نقطة في ${file.path}',
        );
      });
    });
  });

  group('وكل حذفٍ ناعم له زرّ', () {
    // ما يُحذف حذفاً ناعماً وليس في سجلّ التدقيق أصلاً، فلا زرّ يُعرض له:
    // مرجع الأدوية جدولٌ عامّ لا يخصّ منظمة، وحذفه لمدير المنصّة وحده،
    // ولا يُسجَّل في التدقيق — فلا سطر يحمل زرّاً.
    const notAudited = {'MedicineReferenceController.cs'};

    test('لا يبقى صفٌّ محفوظاً في القاعدة ولا سبيل إليه', () {
      final dir = Directory('backend/KineticEnterprise.Api/Controllers');
      final missing = <String>[];

      for (final file in dir.listSync().whereType<File>()) {
        if (notAudited.contains(file.uri.pathSegments.last)) continue;
        final src = file.readAsStringSync();
        if (!src.contains('IsDeleted = true;')) continue;

        // فعلُ الحذف كما يُسجَّل في التدقيق: "supplier.deleted".
        final action = RegExp(r'"([a-z_]+\.deleted)"').firstMatch(src)?.group(1);
        if (action == null) continue;
        if (!restorable().containsKey(action)) missing.add('$action (${file.uri.pathSegments.last})');
      }

      expect(missing, isEmpty,
          reason: 'حذفٌ ناعم بلا زرّ استرجاع — البيانات باقية ولا يصل إليها أحد: ${missing.join('، ')}');
    });
  });

  group('ولا يُوعَد بما لا يُرَدّ', () {
    test('المحذوف حذفاً فعلياً ليس في القائمة', () {
      // الفئة والحساب والمرفق تُحذف بـRemove: الصفّ يذهب من القاعدة، وملفّ
      // المرفق من القرص معه. وإدراجها هنا يعني زرّاً يَعِد بما لا يعود.
      final actions = restorable().keys;
      expect(actions, isNot(contains('category.deleted')));
      expect(actions, isNot(contains('account.deleted')));
      expect(actions, isNot(contains('attachment.deleted')));
    });
  });
}
