import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/adaptive_dialog.dart';

class CustomerFormDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic>? customer;
  final VoidCallback onSaved;

  const CustomerFormDialog({
    super.key,
    required this.customer,
    required this.onSaved,
  });

  @override
  ConsumerState<CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends ConsumerState<CustomerFormDialog> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _notesController;
  late TextEditingController _creditLimitController;
  late TextEditingController _creditDaysController;
  late TextEditingController _entitlementCeilingController;

  String _accountModel = 'prepaid'; // prepaid | entitlement
  String? _selectedCategoryId;
  DateOnly? _entitlementExpiresOn;
  List<Map<String, dynamic>> _categories = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.customer?['fullName'] ?? '');
    _phoneController = TextEditingController(text: widget.customer?['phone'] ?? '');
    _emailController = TextEditingController(text: widget.customer?['email'] ?? '');
    _notesController = TextEditingController(text: widget.customer?['notes'] ?? '');
    _creditLimitController =
        TextEditingController(text: (widget.customer?['creditLimit'] as num?)?.toString() ?? '');
    _creditDaysController =
        TextEditingController(text: (widget.customer?['creditDays'] as num?)?.toString() ?? '');
    _entitlementCeilingController = TextEditingController(
        text: (widget.customer?['entitlementCeiling'] as num?)?.toString() ?? '');

    _accountModel = widget.customer?['accountModel'] ?? 'prepaid';
    _selectedCategoryId = widget.customer?['categoryId'] as String?;

    if (widget.customer?['entitlementExpiresOn'] is String) {
      _entitlementExpiresOn = DateOnly.parse(widget.customer!['entitlementExpiresOn'] as String);
    }

    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final response = await ApiClient.instance.dio.get('/customer-categories');
      setState(() {
        _categories = (response.data as List).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطأ تحميل الفئات: $e')));
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    _creditLimitController.dispose();
    _creditDaysController.dispose();
    _entitlementCeilingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveDialog(
      title: widget.customer == null ? 'عميل جديد' : 'تعديل العميل',
      maxWidth: 600,
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
            Text('البيانات الأساسية', style: AppTextStyles.bodyLg()),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'الاسم الكامل *',
                hintText: 'أحمد محمد علي',
              ),
              enabled: !_busy,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      hintText: '218912345678',
                    ),
                    enabled: !_busy,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني',
                      hintText: 'email@example.com',
                    ),
                    enabled: !_busy,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'ملاحظات',
                hintText: 'معلومات إضافية عن العميل',
              ),
              maxLines: 2,
              enabled: !_busy,
            ),
            const SizedBox(height: 24),
            Text('الفئة والنموذج', style: AppTextStyles.headlineMd()),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _selectedCategoryId,
              decoration: const InputDecoration(
                labelText: 'فئة العميل',
                hintText: 'اختر فئة (اختياري)',
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('بلا فئة')),
                ..._categories.map((cat) => DropdownMenuItem(
                      value: cat['id'] as String,
                      child: Text(cat['name'] as String? ?? ''),
                    )),
              ],
              onChanged: _busy ? null : (v) => setState(() => _selectedCategoryId = v),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'prepaid', label: Text('رصيد مدفوع')),
                ButtonSegment(value: 'entitlement', label: Text('استحقاق')),
              ],
              selected: {_accountModel},
              onSelectionChanged: _busy
                  ? null
                  : (newSelection) => setState(() => _accountModel = newSelection.first),
            ),
            const SizedBox(height: 24),
            if (_accountModel == 'prepaid') ...[
              Text('خيارات الرصيد', style: AppTextStyles.headlineMd()),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _creditLimitController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'سقف الائتمان',
                      ),
                      enabled: !_busy,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _creditDaysController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'أيام السداد',
                      ),
                      enabled: !_busy,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Text('خيارات الاستحقاق', style: AppTextStyles.headlineMd()),
              const SizedBox(height: 12),
              TextField(
                controller: _entitlementCeilingController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'سقف الاستحقاق',
                ),
                enabled: !_busy,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'انتهاء الاستحقاق: ${_entitlementExpiresOn?.toString() ?? "لم يتم التحديد"}',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: _busy
                    ? null
                    : () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _entitlementExpiresOn?.toDateTime() ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 3650)),
                        );
                        if (date != null) {
                          setState(() =>
                              _entitlementExpiresOn = DateOnly.fromDateTime(date));
                        }
                      },
              ),
            ],
            const SizedBox(height: 24),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('الاسم مطلوب')));
      return;
    }

    setState(() => _busy = true);
    try {
      final data = {
        'fullName': _nameController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        'categoryId': _selectedCategoryId,
        'accountModel': _accountModel,
        'creditLimit': double.tryParse(_creditLimitController.text) ?? 0,
        'creditDays': int.tryParse(_creditDaysController.text) ?? 0,
        'entitlementCeiling': double.tryParse(_entitlementCeilingController.text) ?? 0,
        'entitlementExpiresOn': _entitlementExpiresOn?.toString(),
      };

      if (widget.customer == null) {
        await ApiClient.instance.dio.post('/customers', data: data);
      } else {
        await ApiClient.instance.dio.put(
          '/customers/${widget.customer!['id']}',
          data: data,
        );
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

class DateOnly {
  final int year;
  final int month;
  final int day;

  DateOnly({required this.year, required this.month, required this.day});

  factory DateOnly.fromDateTime(DateTime dt) {
    return DateOnly(year: dt.year, month: dt.month, day: dt.day);
  }

  factory DateOnly.parse(String str) {
    final parts = str.split('-');
    return DateOnly(
      year: int.parse(parts[0]),
      month: int.parse(parts[1]),
      day: int.parse(parts[2]),
    );
  }

  DateTime toDateTime() => DateTime(year, month, day);

  @override
  String toString() => '$year-$month-$day';
}
