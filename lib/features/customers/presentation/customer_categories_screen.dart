import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/adaptive_dialog.dart';
import '../../../shared/widgets/currency_badge.dart';
import '../../../shared/widgets/data_table_widget.dart';
import '../../../core/auth/permissions.dart';

final customerCategoriesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final response = await ApiClient.instance.dio.get('/customer-categories');
  return (response.data as List).cast<Map<String, dynamic>>();
});

class CustomerCategoriesScreen extends ConsumerStatefulWidget {
  const CustomerCategoriesScreen({super.key});

  @override
  ConsumerState<CustomerCategoriesScreen> createState() => _CustomerCategoriesScreenState();
}

class _CustomerCategoriesScreenState extends ConsumerState<CustomerCategoriesScreen> {
  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(customerCategoriesProvider);

    return AdaptiveScaffold(
      title: 'فئات العملاء',
      activeRoute: '/customer-categories',
      actions: [
        Can(
          permission: Perm.customersManage,
          child: ElevatedButton.icon(
            onPressed: () => _openCategoryDialog(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('فئة جديدة'),
          ),
        ),
      ],
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('خطأ: $err'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(customerCategoriesProvider),
                child: const Text('إعادة محاولة'),
              ),
            ],
          ),
        ),
        data: (categories) => SingleChildScrollView(
          child: AppDataTable(
            title: 'فئات العملاء (${categories.length})',
            emptyMessage: 'لا توجد فئات بعد',
            emptyIcon: Icons.category_outlined,
            columns: const [
              AppColumn('اسم الفئة'),
              AppColumn('المبلغ الدوري'),
              AppColumn('عدد الأعضاء'),
              AppColumn('إجمالي الصرف'),
              AppColumn('الحالة'),
              AppColumn(''),
            ],
            rows: categories
                .map((c) => [
                      Text(c['name'] as String? ?? ''),
                      CurrencyBadge(amount: (c['periodAmount'] as num?)?.toDouble() ?? 0),
                      Text(NumberFormat('#,##0', 'en').format(c['customerCount'] ?? 0)),
                      CurrencyBadge(amount: (c['periodTotal'] as num?)?.toDouble() ?? 0),
                      Chip(
                        label: Text(
                          (c['isActive'] as bool?) == true ? 'فعالة' : 'معطلة',
                          style: const TextStyle(fontSize: 12),
                        ),
                        backgroundColor: (c['isActive'] as bool?) == true
                            ? AppColors.success.withValues(alpha: 0.2)
                            : AppColors.warning.withValues(alpha: 0.2),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Can(
                            permission: Perm.customersManage,
                            child: IconButton(
                              tooltip: 'تعديل',
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () => _openCategoryDialog(context, category: c),
                            ),
                          ),
                          Can(
                            permission: Perm.customersDelete,
                            child: IconButton(
                              tooltip: 'حذف',
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () => _confirmDelete(context, c),
                            ),
                          ),
                        ],
                      ),
                    ])
                .toList(),
          ),
        ),
      ),
    );
  }

  void _openCategoryDialog(BuildContext context, {Map<String, dynamic>? category}) {
    showDialog(
      context: context,
      builder: (_) => _CategoryDialog(
        category: category,
        onSaved: () {
          ref.invalidate(customerCategoriesProvider);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, Map<String, dynamic> category) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف الفئة "${category['name']}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await ApiClient.instance.dio
                    .delete('/customer-categories/${category['id']}');
                ref.invalidate(customerCategoriesProvider);
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('خطأ: $e')));
                }
              }
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }
}

class _CategoryDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic>? category;
  final VoidCallback onSaved;

  const _CategoryDialog({
    required this.category,
    required this.onSaved,
  });

  @override
  ConsumerState<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends ConsumerState<_CategoryDialog> {
  late TextEditingController _nameController;
  late TextEditingController _amountController;
  late bool _unspentExpires;
  late bool _isActive;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?['name'] ?? '');
    _amountController = TextEditingController(
      text: (widget.category?['periodAmount'] as num?)?.toString() ?? '',
    );
    _unspentExpires = widget.category?['unspentExpires'] ?? false;
    _isActive = widget.category?['isActive'] ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveDialog(
      title: widget.category == null ? 'فئة جديدة' : 'تعديل الفئة',
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('تراجع'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('حفظ'),
        ),
      ],
      body: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'اسم الفئة'),
              enabled: !_busy,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'المبلغ الدوري'),
              enabled: !_busy,
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              title: const Text('انتهاء المبالغ غير المستنفذة'),
              value: _unspentExpires,
              onChanged: _busy ? null : (v) => setState(() => _unspentExpires = v ?? false),
            ),
            CheckboxListTile(
              title: const Text('فعّالة'),
              value: _isActive,
              onChanged: _busy ? null : (v) => setState(() => _isActive = v ?? true),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('اسم الفئة مطلوب')));
      return;
    }

    setState(() => _busy = true);
    try {
      final data = {
        'name': _nameController.text.trim(),
        'periodAmount': double.tryParse(_amountController.text) ?? 0,
        'unspentExpires': _unspentExpires,
        'isActive': _isActive,
      };

      if (widget.category == null) {
        await ApiClient.instance.dio.post('/customer-categories', data: data);
      } else {
        await ApiClient.instance.dio
            .put('/customer-categories/${widget.category!['id']}', data: data);
      }
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      setState(() => _busy = false);
    }
  }
}
