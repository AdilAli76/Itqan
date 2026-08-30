import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/app_surface.dart';
import '../../../shared/widgets/data_table_widget.dart';
import '../../../shared/widgets/skeleton.dart';
import '../data/reorder_providers.dart';

/// تقرير إعادة الطلب — ما يجب شراؤه الآن، ولماذا.
///
/// <b>لماذا يعرض الحدّين معاً:</b> الحدّ اليدوي رقم يُدخَل مرّة ثم يُنسى،
/// والمقترَح مشتقٌّ من الاستهلاك الفعلي. عرضهما جنباً إلى جنب يجعل الفارق
/// ظاهراً — صنف حدّه اليدوي 20 واستهلاكه يقول 4 راكدٌ يُشترى بلا داعٍ، وآخر
/// حدّه 5 واستهلاكه يقول 40 ينفد قبل أن ينبّه.
///
/// <b>ولا يُكتب المقترَح تلقائياً:</b> زرّ صريح لكل صنف. الكتابة الصامتة فوق
/// قرار إداري تُفقد الثقة بالنظام — وقد يكون للمدير سبب لا يعرفه النظام.
class ReorderScreen extends ConsumerStatefulWidget {
  const ReorderScreen({super.key});

  @override
  ConsumerState<ReorderScreen> createState() => _ReorderScreenState();
}

class _ReorderScreenState extends ConsumerState<ReorderScreen> {
  final _applying = <String>{};

  Future<void> _applySuggestion(Map<String, dynamic> item) async {
    final id = item['productId'] as String;
    setState(() => _applying.add(id));
    try {
      // يُقرأ الصنف كاملاً ثم يُعاد بحقل واحد معدَّل: نقطة التحديث تستبدل
      // الكيان كلّه، وإرسال الحدّ وحده كان يمسح بقية الحقول.
      final current = await ApiClient.instance.dio.get('/products/$id');
      final body = Map<String, dynamic>.from(current.data as Map);
      body['reorderLevel'] = item['suggestedReorderLevel'];
      await ApiClient.instance.dio.put('/products/$id', data: body);
      ref.invalidate(reorderReportProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حُدِّث حدّ «${item['productName']}» إلى ${item['suggestedReorderLevel']}')),
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.response?.statusCode == 403
            ? 'ليست لديك صلاحية تعديل الأصناف'
            : 'تعذّر تحديث الحدّ')),
      );
    } finally {
      if (mounted) setState(() => _applying.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(reorderSettingsProvider);
    final async = ref.watch(reorderReportProvider);

    return AdaptiveScaffold(
      title: 'إعادة الطلب',
      activeRoute: '/reorder',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSurface(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _NumberSetting(
                    label: 'نافذة القياس (يوم)',
                    value: settings.windowDays,
                    options: const [30, 60, 90, 180, 365],
                    onChanged: (v) => ref.read(reorderSettingsProvider.notifier).state =
                        settings.copyWith(windowDays: v),
                  ),
                  _NumberSetting(
                    label: 'أيام الأمان',
                    value: settings.coverageDays,
                    options: const [0, 7, 14, 30, 60],
                    onChanged: (v) => ref.read(reorderSettingsProvider.notifier).state =
                        settings.copyWith(coverageDays: v),
                  ),
                  FilterChip(
                    label: const Text('ما يحتاج طلباً فقط'),
                    selected: settings.onlyBelowThreshold,
                    onSelected: (v) => ref.read(reorderSettingsProvider.notifier).state =
                        settings.copyWith(onlyBelowThreshold: v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          async.when(
            loading: () => const TableSkeleton(),
            error: (err, _) => AppSurface(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      err is DioException && err.response?.statusCode == 403
                          ? 'ليست لديك صلاحية عرض التقارير'
                          : 'تعذّر تحميل التقرير',
                      style: AppTextStyles.bodyMd(color: AppColors.danger),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => ref.invalidate(reorderReportProvider),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ),
            data: (data) {
              final items = (data['items'] as List?) ?? const [];
              return AppDataTable(
                title: 'إعادة الطلب (${items.length})',
                icon: Icons.shopping_cart_checkout_outlined,
                emptyMessage: 'لا صنف يحتاج طلباً الآن',
                emptyIcon: Icons.check_circle_outline,
                columns: const [
                  AppColumn('الصنف'),
                  AppColumn('الرصيد'),
                  AppColumn('في الطريق'),
                  AppColumn('استهلاك يومي'),
                  AppColumn('يكفي'),
                  AppColumn('الحدّ الحالي'),
                  AppColumn('الحدّ المقترَح'),
                  AppColumn('يُطلب'),
                  AppColumn('المورّد'),
                  AppColumn(''),
                ],
                rows: items.map((e) => _row(e as Map<String, dynamic>)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _row(Map<String, dynamic> i) {
    final cover = (i['daysOfCover'] as num?)?.toDouble();
    final suggested = (i['suggestedReorderLevel'] as num?)?.toDouble() ?? 0;
    final configured = (i['configuredReorderLevel'] as num?)?.toDouble() ?? 0;
    final orderQty = (i['suggestedOrderQuantity'] as num?)?.toDouble() ?? 0;
    final id = i['productId'] as String;

    // لون التغطية هو الإشارة الوحيدة التي تُقرأ بلا حساب: أقلّ من أسبوع خطر،
    // وأقلّ من أسبوعين تحذير. والراكد (بلا استهلاك) لا لون له — ليس عاجلاً.
    Color? coverColor;
    if (cover != null) {
      if (cover < 7) {
        coverColor = AppColors.danger;
      } else if (cover < 14) {
        coverColor = AppColors.warning;
      }
    }

    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(i['productName'] as String? ?? ''),
          Text(i['sku'] as String? ?? '', style: AppTextStyles.caption()),
        ],
      ),
      Text('${i['quantity']} ${i['unitBase'] ?? ''}'),
      // القادم بأمر شراء مُرسَل. عرضه بجوار الرصيد هو ما يمنع تكرار الطلب:
      // «الرصيد صفر» وحدها تدفع إلى شراء ثانٍ لبضاعة في الطريق.
      Builder(builder: (_) {
        final onOrder = (i['onOrderQuantity'] as num?)?.toDouble() ?? 0;
        return Text(
          onOrder <= 0 ? '-' : '+${NumberFormat('#,##0.###', 'en').format(onOrder)}',
          style: AppTextStyles.bodyMd(
              color: onOrder > 0 ? AppColors.info : AppColors.textMuted),
        );
      }),
      Text('${i['avgDailyUsage']}'),
      Text(
        cover == null ? 'راكد' : '$cover يوم',
        style: AppTextStyles.bodyMd(color: coverColor)
            .copyWith(fontWeight: coverColor == null ? null : FontWeight.w600),
      ),
      Text(configured.toString()),
      Text(
        suggested.toString(),
        // الاختلاف الجوهري وحده يُميَّز: فارق ضئيل ضجيج، وتلوينه يُفقد اللون
        // معناه حين يهمّ فعلاً.
        style: AppTextStyles.bodyMd(
          color: (suggested - configured).abs() > (configured * 0.25).clamp(1, double.infinity)
              ? AppColors.info
              : null,
        ),
      ),
      Text(
        orderQty > 0 ? orderQty.toString() : '—',
        style: AppTextStyles.bodyMd(color: orderQty > 0 ? AppColors.textPrimary : null)
            .copyWith(fontWeight: orderQty > 0 ? FontWeight.w600 : null),
      ),
      Text((i['supplierName'] as String?) ?? '—'),
      _applying.contains(id)
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : TextButton(
              onPressed: suggested > 0 && suggested != configured ? () => _applySuggestion(i) : null,
              child: const Text('اعتمد المقترَح'),
            ),
    ];
  }
}

/// اختيار رقم من قيم معهودة — أسرع من كتابة رقم حرّ، ويمنع مدىً بلا معنى.
class _NumberSetting extends StatelessWidget {
  const _NumberSetting({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTextStyles.caption()),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: options.contains(value) ? value : options.first,
          underline: const SizedBox.shrink(),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text('$o'))).toList(),
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      ],
    );
  }
}
