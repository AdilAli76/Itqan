import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/app_surface.dart';

/// تقريرٌ واحد في بطاقةٍ تُطوى وتُطبع.
///
/// <para><b>الفجوة التي تسدّها:</b> التقارير كانت أقساماً متتالية في تمريرة
/// واحدة. وقد صارت أربعة، وتزيد — فمن يريد أعمار الديون يمرّ على المبيعات
/// والمخزون كلّها، ومن يريد المبيعات وحدها يحمّل الباقي معها. ولا يُطبع
/// منها شيء، فمن أراد رقماً على ورق صوّر الشاشة بهاتفه.</para>
///
/// <para><b>والأوّل مفتوح والبقية مطويّة:</b> كلّها مفتوحةً تعيد المشكلة،
/// وكلّها مطويّةً تجعل الشاشة قائمة عناوين تحتاج نقرةً لترى أي رقم.</para>
class ReportCard extends StatefulWidget {
  const ReportCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.initiallyExpanded = false,
    this.onPrint,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  final bool initiallyExpanded;

  /// فارغةٌ تعني تقريراً لا يُطبع بعد — فيُخفى الزرّ لا يُعطَّل.
  final Future<void> Function()? onPrint;

  @override
  State<ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<ReportCard> {
  late bool _expanded = widget.initiallyExpanded;
  bool _printing = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // الرأس كلّه قابل للنقر لا السهم وحده: هدفٌ بعرض البطاقة أسهل
            // على الإبهام من أيقونةٍ في زاوية.
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 20, color: AppColors.textSecondary),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.title, style: AppTextStyles.bodyLg()),
                          if (widget.subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(widget.subtitle!,
                                style: AppTextStyles.caption(
                                    color: AppColors.textSecondary)),
                          ],
                        ],
                      ),
                    ),
                    if (widget.onPrint != null)
                      IconButton(
                        // الطباعة لا تفتح التقرير: من يعرف ما فيه يطبعه بلا
                        // أن ينتظر انفتاحه.
                        onPressed: _printing ? null : _print,
                        icon: _printing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.print_outlined, size: 20),
                        tooltip: 'طباعة ${widget.title}',
                      ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                child: widget.child,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _print() async {
    setState(() => _printing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onPrint!();
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذّرت طباعة ${widget.title}')),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }
}
