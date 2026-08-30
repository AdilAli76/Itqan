import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/app_surface.dart';
import '../../../shared/widgets/data_table_widget.dart';
import '../../../shared/widgets/pagination_bar.dart';
import '../../../shared/widgets/skeleton.dart';
import '../data/prescriptions_providers.dart';

/// دفتر الوصفات — سجلّ كل صرف لدواء مقيَّد.
///
/// <b>قراءة فقط بلا زر إضافة</b>: القيد يُكتب لحظة الصرف مع الفاتورة داخل
/// معاملة واحدة، وزرّ «إضافة» هنا كان ينتج دفتراً يمكن ملؤه بقيود لا يقابلها
/// صرف — أي مستنداً لا يُوثَق به. وتصحيح قيد خاطئ يمرّ باسترجاع الفاتورة،
/// فيبقى الخطأ وتصحيحه ظاهرين معاً.
class PrescriptionsScreen extends ConsumerStatefulWidget {
  const PrescriptionsScreen({super.key});

  @override
  ConsumerState<PrescriptionsScreen> createState() => _PrescriptionsScreenState();
}

class _PrescriptionsScreenState extends ConsumerState<PrescriptionsScreen> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(prescriptionSearchProvider.notifier).state = value;
      ref.read(prescriptionsPageProvider.notifier).state = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(prescriptionsProvider);

    return AdaptiveScaffold(
      title: 'دفتر الوصفات',
      activeRoute: '/prescriptions',
      body: async.when(
        loading: () => const TableSkeleton(),
        error: (err, _) => AppSurface(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(
                  err is DioException && err.response?.statusCode == 403
                      ? 'ليست لديك صلاحية الاطّلاع على دفتر الوصفات'
                      : 'تعذّر تحميل الدفتر',
                  style: AppTextStyles.bodyMd(color: AppColors.danger),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(prescriptionsProvider),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
        data: (page) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDataTable(
              title: 'دفتر الوصفات (${page.totalCount})',
              icon: Icons.assignment_outlined,
              onSearch: _onSearch,
              emptyMessage: 'لا قيود بعد — تُسجَّل تلقائياً عند صرف دواء مقيَّد بوصفة',
              emptyIcon: Icons.assignment_outlined,
              columns: const [
                AppColumn('التاريخ'),
                AppColumn('رقم الوصفة'),
                AppColumn('الطبيب'),
                AppColumn('المريض'),
                AppColumn('الفاتورة'),
                AppColumn('صرفها'),
              ],
              rows: page.items.map(_row).toList(),
            ),
            PaginationBar(
              page: page.page,
              pageSize: page.pageSize,
              totalCount: page.totalCount,
              onPageChanged: (p) => ref.read(prescriptionsPageProvider.notifier).state = p,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _row(Map<String, dynamic> p) {
    final created = DateTime.tryParse(p['createdAt'] as String? ?? '');
    final doctorLicense = (p['doctorLicense'] as String?)?.trim();
    final patientPhone = (p['patientPhone'] as String?)?.trim();
    return [
      Text(created == null ? '-' : DateFormat('yyyy-MM-dd HH:mm').format(created)),
      Text((p['prescriptionNumber'] as String?)?.trim().isNotEmpty == true
          ? p['prescriptionNumber'] as String
          : '—'),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(p['doctorName'] as String? ?? ''),
          if (doctorLicense != null && doctorLicense.isNotEmpty)
            Text('ترخيص $doctorLicense', style: AppTextStyles.caption()),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(p['patientName'] as String? ?? ''),
          if (patientPhone != null && patientPhone.isNotEmpty)
            Text(patientPhone, style: AppTextStyles.caption()),
        ],
      ),
      Text((p['invoiceNumber'] as String?) ?? '—'),
      Text((p['dispensedBy'] as String?) ?? '—'),
    ];
  }
}
