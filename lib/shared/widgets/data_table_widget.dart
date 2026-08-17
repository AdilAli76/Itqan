import 'package:flutter/material.dart';
import '../../core/responsive/breakpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class AppColumn {
  const AppColumn(this.label, {this.width});
  final String label;
  final double? width;
}

/// جدول بيانات موحّد لكل شاشات القوائم في النظام. على الديسكتوب يُعرض
/// كجدول حقيقي، وعلى الموبايل يتحوّل تلقائياً إلى بطاقات مكدَّسة بدل جدول
/// أفقي يحتاج تمرير جانبي مزعج — هذا هو أساس "التوافق مع كل الشاشات".
class AppDataTable extends StatelessWidget {
  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onSearch,
    this.title,
    this.icon,
    this.emptyMessage = 'لا توجد بيانات لعرضها',
    this.emptyIcon = Icons.inbox_outlined,
  });

  final List<AppColumn> columns;
  final List<List<Widget>> rows;
  final ValueChanged<String>? onSearch;
  final String? title;
  final IconData? icon;
  final String emptyMessage;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                ],
                if (title != null) Text(title!, style: AppTextStyles.headlineMd()),
                const Spacer(),
                if (onSearch != null)
                  SizedBox(
                    width: 240,
                    height: 40,
                    child: TextField(
                      onChanged: onSearch,
                      decoration: const InputDecoration(
                        hintText: 'بحث...',
                        prefixIcon: Icon(Icons.search, size: 18),
                        isDense: true,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (rows.isEmpty)
            _buildEmptyState(context)
          else
            Breakpoints.isMobile(context) ? _buildCards(context) : _buildTable(context),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(emptyIcon, size: 32, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(emptyMessage, style: AppTextStyles.bodyMd(color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: columns.map((c) => DataColumn(label: Text(c.label, style: AppTextStyles.labelMd()))).toList(),
        rows: List.generate(rows.length, (i) {
          return DataRow(
            color: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) return AppColors.surfaceAlt;
              return i.isOdd ? AppColors.surfaceAlt.withValues(alpha: 0.4) : Colors.transparent;
            }),
            cells: rows[i].map((w) => DataCell(w)).toList(),
          );
        }),
      ),
    );
  }

  Widget _buildCards(BuildContext context) {
    return Column(
      children: rows.map((row) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(row.length, (i) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: Text(columns[i].label, style: AppTextStyles.labelMd()),
                    ),
                    Expanded(child: row[i]),
                  ],
                ),
              );
            }),
          ),
        );
      }).toList(),
    );
  }
}
