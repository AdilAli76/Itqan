import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// شريط أدوات احترافي للقوائم
/// Professional list toolbar for search, filter, and actions
class ListToolbar extends StatefulWidget {
  /// عنوان البحث / Placeholder
  final String searchPlaceholder;

  /// قيمة البحث الحالية
  final String? initialSearchQuery;

  /// دالة عند تغيير البحث
  final Function(String)? onSearchChanged;

  /// دالة عند الضغط على زر الإضافة
  final VoidCallback? onAddPressed;

  /// دالة عند الضغط على زر التحديث
  final VoidCallback? onRefreshPressed;

  /// دالة عند الضغط على زر الطباعة
  final VoidCallback? onPrintPressed;

  /// دالة عند الضغط على زر التصدير
  final VoidCallback? onExportPressed;

  /// قوائم الفلاتر الإضافية
  final List<FilterOption>? filterOptions;

  /// دالة عند تغيير الفلتر
  final Function(String?)? onFilterChanged;

  /// إظهار/إخفاء أزرار الإجراءات
  final bool showActionButtons;

  /// إظهار/إخفاء أيقونة الإضافة
  final bool showAddButton;

  /// النص على زر الإضافة
  final String addButtonLabel;

  /// عرض خاص (للشاشات الضيقة)
  final bool isCompact;

  const ListToolbar({
    Key? key,
    this.searchPlaceholder = 'بحث...',
    this.initialSearchQuery,
    this.onSearchChanged,
    this.onAddPressed,
    this.onRefreshPressed,
    this.onPrintPressed,
    this.onExportPressed,
    this.filterOptions,
    this.onFilterChanged,
    this.showActionButtons = true,
    this.showAddButton = true,
    this.addButtonLabel = 'جديد',
    this.isCompact = false,
  }) : super(key: key);

  @override
  State<ListToolbar> createState() => _ListToolbarState();
}

class _ListToolbarState extends State<ListToolbar> {
  late TextEditingController _searchController;
  String? _selectedFilter;

  @override
  void initState() {
    super.initState();
    _searchController =
        TextEditingController(text: widget.initialSearchQuery ?? '');
    _selectedFilter = null;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isCompact) {
      return _buildCompactToolbar();
    }

    return _buildFullToolbar();
  }

  /// الإصدار الكامل للشاشات العريضة
  Widget _buildFullToolbar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lightBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // صف 1: البحث والأزرار الأساسية
          Row(
            children: [
              // حقل البحث
              Expanded(
                child: _buildSearchField(),
              ),
              const SizedBox(width: 12),

              // الفلتر (إن وجد)
              if (widget.filterOptions != null &&
                  widget.filterOptions!.isNotEmpty)
                _buildFilterDropdown(),

              const SizedBox(width: 8),

              // أزرار الإجراءات
              if (widget.showActionButtons) ...[
                _buildActionButton(
                  icon: Icons.refresh,
                  tooltip: 'تحديث',
                  onPressed: widget.onRefreshPressed,
                ),
                const SizedBox(width: 8),
                _buildActionButton(
                  icon: Icons.print,
                  tooltip: 'طباعة',
                  onPressed: widget.onPrintPressed,
                ),
                const SizedBox(width: 8),
                _buildActionButton(
                  icon: Icons.download,
                  tooltip: 'تصدير',
                  onPressed: widget.onExportPressed,
                ),
                const SizedBox(width: 12),
              ],

              // زر الإضافة
              if (widget.showAddButton)
                _buildAddButton(),
            ],
          ),
        ],
      ),
    );
  }

  /// الإصدار المضغوط للشاشات الضيقة
  Widget _buildCompactToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // البحث في السطر الأول
          _buildSearchField(),
          const SizedBox(height: 12),

          // الأزرار في السطر الثاني
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (widget.filterOptions != null &&
                    widget.filterOptions!.isNotEmpty) ...[
                  _buildFilterDropdown(),
                  const SizedBox(width: 8),
                ],
                if (widget.showActionButtons) ...[
                  _buildActionButton(
                    icon: Icons.refresh,
                    tooltip: 'تحديث',
                    onPressed: widget.onRefreshPressed,
                    compact: true,
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.print,
                    tooltip: 'طباعة',
                    onPressed: widget.onPrintPressed,
                    compact: true,
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.download,
                    tooltip: 'تصدير',
                    onPressed: widget.onExportPressed,
                    compact: true,
                  ),
                ],
                if (widget.showAddButton) ...[
                  const SizedBox(width: 8),
                  _buildAddButton(compact: true),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// حقل البحث
  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: widget.onSearchChanged,
      decoration: InputDecoration(
        hintText: widget.searchPlaceholder,
        hintStyle: TextStyle(color: AppColors.disabledText),
        prefixIcon: const Icon(Icons.search),
        prefixIconColor: AppColors.secondaryText,
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  widget.onSearchChanged?.call('');
                },
              )
            : null,
        suffixIconColor: AppColors.secondaryText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: 2,
          ),
        ),
        filled: true,
        fillColor: AppColors.lightBackground,
      ),
    );
  }

  /// قائمة الفلاتر
  Widget _buildFilterDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(10),
        color: AppColors.lightBackground,
      ),
      child: DropdownButton<String?>(
        value: _selectedFilter,
        isDense: true,
        underline: const SizedBox.shrink(),
        items: [
          const DropdownMenuItem(
            value: null,
            child: Text('كل الفئات'),
          ),
          ...?widget.filterOptions?.map(
            (option) => DropdownMenuItem(
              value: option.value,
              child: Text(option.label),
            ),
          ),
        ],
        onChanged: (value) {
          setState(() => _selectedFilter = value);
          widget.onFilterChanged?.call(value);
        },
      ),
    );
  }

  /// زر إجراء (تحديث، طباعة، تصدير)
  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
    bool compact = false,
  }) {
    if (compact) {
      return IconButton(
        icon: Icon(icon, size: 20),
        onPressed: onPressed,
        tooltip: tooltip,
        constraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 32,
        ),
      );
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.lightBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: IconButton(
          icon: Icon(icon),
          onPressed: onPressed,
          color: AppColors.secondaryText,
          hoverColor: AppColors.lightBackground,
        ),
      ),
    );
  }

  /// زر الإضافة (الزر الأساسي)
  Widget _buildAddButton({bool compact = false}) {
    if (compact) {
      return ElevatedButton.icon(
        onPressed: widget.onAddPressed,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('جديد'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: widget.onAddPressed,
      icon: const Icon(Icons.add),
      label: Text(widget.addButtonLabel),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

/// خيار الفلتر
class FilterOption {
  final String label;
  final String value;

  FilterOption({
    required this.label,
    required this.value,
  });
}
