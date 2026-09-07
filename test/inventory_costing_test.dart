import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// طريقة تكلفة الصنف — خيارٌ على المنظمة.
///
/// <para><b>ما يحرسه هذا الملف:</b> أن يبقى الخيار **خياراً** لا سلوكاً
/// يتغيّر تحت أقدام من لم يطلبه، وألّا يمتدّ من الرقم المرجعيّ على البطاقة
/// إلى تكلفة البضاعة المباعة. فتلك تُقرأ من الدفعة التي خرجت منها فعلاً،
/// وتحويلُها إلى متوسطٍ يُفقد النظام دقّةً يملكها — وعند من يتتبّع الصلاحية
/// يخالف الواقع صراحةً.</para>
void main() {
  final entities =
      File('backend/KineticEnterprise.Api/Models/Entities.cs').readAsStringSync();
  final costing =
      File('backend/KineticEnterprise.Api/Data/InventoryCosting.cs').readAsStringSync();
  final purchasing =
      File('backend/KineticEnterprise.Api/Controllers/PurchaseOrdersController.cs').readAsStringSync();
  final ledger =
      File('backend/KineticEnterprise.Api/Data/StockLedger.cs').readAsStringSync();

  group('الخيار خيار', () {
    test('الثلاثة معرَّفة بأسمائها', () {
      expect(entities, contains('LastPurchase = "last_purchase"'));
      expect(entities, contains('WeightedAverage = "weighted_average"'));
      expect(entities, contains('Batch = "batch"'));
    });

    test('والافتراضي آخر شراء — سلوك النظام قبل الإعداد', () {
      // العطب الذي يمنعه: افتراضيٌّ آخر يغيّر أرقام بطاقات كل عميل قائم
      // في أوّل استلامٍ بعد الترقية، بلا أن يطلب ذلك أحد.
      expect(entities,
          contains('public string InventoryCostingMethod { get; set; } = CostingMethods.LastPurchase;'));
    });

    test('وقيمةٌ مجهولة تُرفض ولا تُحفظ', () {
      final organizations =
          File('backend/KineticEnterprise.Api/Controllers/OrganizationsController.cs').readAsStringSync();
      expect(organizations, contains('CostingMethods.IsKnown'));
    });

    test('وحفظُ شاشةٍ لا تعرف الحقل لا يُرجع المنظمة إلى الافتراضي', () {
      // NULL = لا تغيير. وبلا هذا كان عميلٌ قديم يمحو اختيار مديره كلما
      // حفظ شاشة العملة.
      final organizations =
          File('backend/KineticEnterprise.Api/Controllers/OrganizationsController.cs').readAsStringSync();
      expect(organizations,
          contains('if (request.InventoryCostingMethod is { } method) org.InventoryCostingMethod = method;'));
    });
  });

  group('حدوده لا تتعدّى البطاقة', () {
    test('تكلفة البضاعة المباعة تبقى من الدفعة — لا أثر للإعداد في الدفتر', () {
      // وهذا هو الحدّ كلّه: الصرف يقسّم على الإدخالات بترتيب الصرف، وكل
      // سطرٍ يحمل تكلفته هو. ولا يعرف [StockLedger] بهذا الإعداد شيئاً.
      expect(ledger, isNot(contains('CostingMethods')));
      expect(ledger, isNot(contains('InventoryCosting')));
    });

    test('والإعداد يُقرأ في الاستلام وحده', () {
      expect(purchasing, contains('InventoryCosting.ReferenceCostAsync'));
      expect(purchasing, contains('CostingMethods.LastPurchase'));
    });
  });

  group('الحساب يقرأ ما بقي لا ما مضى', () {
    test('المتوسط على الدفعات المفتوحة', () {
      // بضاعةٌ بيعت خرجت بتكلفتها؛ وضمُّها إلى المتوسط يُبقي أثر سعرٍ لم
      // يعد في المخزن منه شيء.
      expect(costing, contains('e.RemainingQuantity > 0 && !e.IsCancelled'));
      expect(costing, contains('lots.Sum(l => l.RemainingQuantity * l.UnitCost) / quantity'));
    });

    test('وتكلفة الدفعة بترتيب الصرف نفسه — FEFO ثم FIFO', () {
      // ترتيبٌ آخر يجعل البطاقة تَعِد بتكلفةٍ والفاتورة تُحمّل غيرها.
      expect(costing, contains('OrderBy(e => e.ExpiryDate == null ? 1 : 0)'));
      expect(costing, contains('ThenBy(e => e.PostedAt)'));
    });

    test('ومخزنٌ فارغ لا يُسقط الاستلام — يُرجَع إلى تكلفة الشحنة', () {
      // أوّل استلامٍ لصنفٍ جديد: لا دفعات بعد. وقسمةٌ على صفر هنا تُفشل
      // الاستلام كلّه بخطأٍ لا يفهمه أمين المخزن.
      expect(costing, contains('if (quantity <= 0) return null;'));
      expect(costing, contains('?? receivedUnitCost'));
    });
  });
}
