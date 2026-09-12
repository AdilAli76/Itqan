import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// جدول بيانات احترافي قابل للتخصيص
/// Professional customizable data table widget
class CustomDataTable extends StatefulWidget {
  /// العناوين
  final List<String> columns;

  /// الصفوف (كل صف هو قائمة من Widgets)
  final List<List<Widget>> rows;

  /// العنوان (اختياري)
  final String? title;

  /// الارتفاع لكل صف (افتراضي 56)
  final double rowHeight;

  /// السماح بالتحديد متعدد
  final bool selectable;

  /// دالة عند تحديد صفوف
  final Function(List<int>)? onSelectionChanged;

  /// الألوان البديلة للصفوف
  final bool alternateRowColors;

  /// إظهار الترقيم
  final bool showRowNumbers;

  /// عدد الأعمدة المثبتة من اليسار (للعربية)
  final int frozenColumnsCount;

  /// يسمح بالتمرير الأفقي للصفوف الطويلة
  final bool allowHorizontalScroll;

  /// رسالة عند عدم وجود بيانات
  final String emptyMessage;

  /// التنسيق المضغوط (بدون حشو كبير)
  final bool isCompact;

  const CustomDataTable({
    Key? key,
    required this.columns,
    required this.rows,
    this.title,
    this.rowHeight = 56,
    this.selectable = false,
    this.onSelectionChanged,
    this.alternateRowColors = true,
    this.showRowNumbers = true,
    this.frozenColumnsCount = 0,
    this.allowHorizontalScroll = true,
    this.emptyMessage = 'لا توجد بيانات',
    this.isCompact = false,
  }) : super(key: key);

  @override
  State<CustomDataTable> createState() => _CustomDataTableState();
}

class _CustomDataTableState extends State<CustomDataTable> {
  late Set<int> _selectedRows;

  @override
  void initState() {
    super.initState();
    _selectedRows = <int>{};
  }

  void _toggleRowSelection(int index) {
    setState(() {
      if (_selectedRows.contains(index)) {
        _selectedRows.remove(index);
      } else {
        _selectedRows.add(index);
      }
    });
    widget.onSelectionChanged?.call(_selectedRows.toList());
  }

  void _toggleAllSelection() {
    setState(() {
      if (_selectedRows.length == widget.rows.length) {
        _selectedRows.clear();
      } else {
        _selectedRows = Set.from(List.generate(widget.rows.length, (i) => i));
      }
    });
    widget.onSelectionChanged?.call(_selectedRows.toList());
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      return _buildEmptyState();
    }

    final padding = widget.isCompact ? 12.0 : 16.0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // العنوان
          if (widget.title != null) ...[
            Container(
              padding: EdgeInsets.all(padding),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.lightBorder),
                ),
              ),
              child: Text(
                widget.title!,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                ),
              ),
            ),
          ],

          // الجدول
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: MediaQuery.of(context).size.width - 32,
              ),
              child: DataTable(
                columns: _buildColumns(),
                rows: _buildRows(),
                columnSpacing: widget.isCompact ? 12 : 16,
                dataRowHeight: widget.rowHeight,
                headingRowHeight: widget.rowHeight,
                border: TableBorder.symmetric(
                  inside: BorderSide(
                    color: AppColors.lightBorder.withOpacity(0.5),
                    width: 0.5,
                  ),
                ),
                showCheckboxColumn: widget.selectable,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// بناء رؤوس الأعمدة
  List<DataColumn> _buildColumns() {
    final columns = <DataColumn>[];

    // إضافة العمود الأول (رقم الصف)
    if (widget.showRowNumbers) {
      columns.add(
        DataColumn(
          label: const Text('م'),
          numeric: true,
        ),
      );
    }

    // الأعمدة الأساسية
    for (final col in widget.columns) {
      columns.add(
        DataColumn(
          label: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              col,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
              ),
            ),
          ),
        ),
      );
    }

    return columns;
  }

  /// بناء الصفوف
  List<DataRow> _buildRows() {
    final rows = <DataRow>[];

    for (int i = 0; i < widget.rows.length; i++) {
      final rowData = widget.rows[i];
      final isSelected = _selectedRows.contains(i);
      final isAlternate = widget.alternateRowColors && i.isEven;

      final cells = <DataCell>[];

      // إضافة رقم الصف
      if (widget.showRowNumbers) {
        cells.add(
          DataCell(
            Text((i + 1).toString()),
          ),
        );
      }

      // الخلايا الأساسية
      for (final widget in rowData) {
        cells.add(DataCell(widget));
      }

      rows.add(
        DataRow(
          cells: cells,
          selected: isSelected && widget.selectable,
          onSelectChanged: widget.selectable
              ? (_) => _toggleRowSelection(i)
              : null,
          color: WidgetStateProperty.resolveWith<Color?>((states) {
            if (isSelected) {
              return AppColors.primary.withOpacity(0.1);
            }
            if (isAlternate) {
              return AppColors.lightBackground;
            }
            return null;
          }),
        ),
      );
    }

    return rows;
  }

  /// حالة عدم وجود بيانات
  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 64,
            color: AppColors.secondaryText,
          ),
          const SizedBox(height: 16),
          Text(
            widget.emptyMessage,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.secondaryText,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// مساعد لبناء جداول بسيطة بسرعة
class SimpleDataTable extends StatelessWidget {
  final String title;
  final List<String> columns;
  final List<List<String>> data;
  final bool showRowNumbers;

  const SimpleDataTable({
    Key? key,
    required this.title,
    required this.columns,
    required this.data,
    this.showRowNumbers = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomDataTable(
      title: title,
      columns: columns,
      rows: data
          .map((row) => row.map((cell) => Text(cell)).toList())
          .toList(),
      showRowNumbers: showRowNumbers,
    );
  }
}

/// جدول البيانات المتقدم مع الفرز والتصفية
class AdvancedDataTable extends StatefulWidget {
  final String title;
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final Function(String, bool)? onSort;
  final bool sortable;
  final bool filterable;

  const AdvancedDataTable({
    Key? key,
    required this.title,
    required this.columns,
    required this.rows,
    this.onSort,
    this.sortable = true,
    this.filterable = true,
  }) : super(key: key);

  @override
  State<AdvancedDataTable> createState() => _AdvancedDataTableState();
}

class _AdvancedDataTableState extends State<AdvancedDataTable> {
  String _sortColumn = '';
  bool _sortAscending = true;

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows
        .map<List<Widget>>((row) {
          return widget.columns
              .map((col) => Text(
                    (row[col] ?? '').toString(),
                    overflow: TextOverflow.ellipsis,
                  ))
              .toList();
        })
        .toList();

    return CustomDataTable(
      title: widget.title,
      columns: widget.columns,
      rows: rows,
      alternateRowColors: true,
      showRowNumbers: true,
    );
  }
}
