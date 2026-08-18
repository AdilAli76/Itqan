import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'icon_action.dart';

/// شريط تنقّل بين صفحات القوائم الطويلة.
///
/// يُظهر دائماً «عرض 51–100 من 1,240» لا أرقام صفحات مجرّدة: المحاسب يسأل
/// «كم عميلاً لدينا؟» أكثر مما يسأل «في أي صفحة أنا؟»، والعدد الكلي إجابة
/// مباشرة على ذلك بلا شاشة إضافية. كما أنه الطريقة الوحيدة ليعرف المستخدم
/// أن ما يراه جزء من الكل — وهذا بالضبط سوء الفهم الذي يولّده الترقيم إذا
/// أُضيف بلا سياق: يظن أن البحث لم يجد إلا خمسين نتيجة.
///
/// يختفي الشريط كلياً حين تسع النتائج صفحة واحدة، فلا يضيف ضجيجاً للقوائم
/// القصيرة وهي الأغلب في الاستخدام اليومي.
class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.page,
    required this.pageSize,
    required this.totalCount,
    required this.onPageChanged,
  });

  final int page;
  final int pageSize;
  final int totalCount;
  final ValueChanged<int> onPageChanged;

  int get _lastPage => totalCount == 0 ? 1 : ((totalCount - 1) ~/ pageSize) + 1;

  @override
  Widget build(BuildContext context) {
    if (totalCount <= pageSize) return const SizedBox.shrink();

    final fmt = NumberFormat.decimalPattern('en');
    final first = (page - 1) * pageSize + 1;
    final last = (page * pageSize) > totalCount ? totalCount : page * pageSize;
    final hasPrev = page > 1;
    final hasNext = page < _lastPage;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // liveRegion: تغيّر الصفحة لا يُرافقه أي إعلان بصري لقارئ الشاشة —
          // المحتوى يتبدّل صامتاً. هذا النص هو ما يخبره بما حدث.
          Flexible(
            child: Semantics(
              liveRegion: true,
              label: 'عرض ${fmt.format(first)} إلى ${fmt.format(last)}'
                  ' من أصل ${fmt.format(totalCount)} سجل،'
                  ' صفحة $page من $_lastPage',
              excludeSemantics: true,
              // Flexible مع قصّ: النصّ ينمو مع الأرقام («عرض 1,201–1,250 من
              // 48,900») بينما عرض الهاتف ثابت، فيفيض الصف. الأزرار أولى
              // بالمساحة من النصّ لأنها الوظيفة، والنصّ يُقصّ ولا يُسقط.
              child: Text(
                'عرض ${fmt.format(first)}–${fmt.format(last)} من ${fmt.format(totalCount)}',
                style: AppTextStyles.labelMd(color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const Spacer(),
          IconAction(
            // arrow_back_ios لا arrow_forward_ios: أيقونات الاتجاه في Material
            // معرَّفة بـ matchTextDirection: true، فيعكسها Flutter تلقائياً في
            // الواجهة العربية. تُختار الأيقونة بمعناها الإنجليزي (back = سابق)
            // ويتولّى الإطار قلبها لتشير يميناً. اختيار forward هنا «تعويضاً
            // عن الاتجاه» يعكسها مرّتين فتشير للجهة الخطأ.
            icon: Icons.arrow_back_ios,
            iconSize: 16,
            dense: true,
            tooltip: 'الصفحة السابقة',
            onPressed: hasPrev ? () => onPageChanged(page - 1) : null,
            color: hasPrev ? AppColors.textPrimary : AppColors.textMuted,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('$page / $_lastPage', style: AppTextStyles.labelMd()),
          ),
          IconAction(
            icon: Icons.arrow_forward_ios,
            iconSize: 16,
            dense: true,
            tooltip: 'الصفحة التالية',
            onPressed: hasNext ? () => onPageChanged(page + 1) : null,
            color: hasNext ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}

/// نتيجة صفحة واحدة كما يعيدها الخادم: {items, totalCount, page, pageSize}.
///
/// نوع واحد لكل الوحدات بدل تكرار فكّ التغليف في كل مزوّد — الشكل موحَّد في
/// الخادم (AuditLogPageDto / CustomerPageDto / InvoicePageDto) فيجب أن يكون
/// موحَّداً هنا أيضاً.
class PagedResult {
  const PagedResult({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  factory PagedResult.fromJson(Map<String, dynamic> json, {int fallbackPageSize = 50}) {
    return PagedResult(
      items: List<Map<String, dynamic>>.from(json['items'] as List? ?? const []),
      totalCount: json['totalCount'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      pageSize: json['pageSize'] as int? ?? fallbackPageSize,
    );
  }

  final List<Map<String, dynamic>> items;
  final int totalCount;
  final int page;
  final int pageSize;

  bool get isEmpty => items.isEmpty;
}
