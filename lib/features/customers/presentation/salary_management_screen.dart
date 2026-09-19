import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/adaptive_dialog.dart';

class SalaryManagementScreen extends ConsumerStatefulWidget {
  const SalaryManagementScreen({super.key});

  @override
  ConsumerState<SalaryManagementScreen> createState() => _SalaryManagementScreenState();
}

class _SalaryManagementScreenState extends ConsumerState<SalaryManagementScreen> {
  List<Map<String, dynamic>> _salaries = [];
  List<Map<String, dynamic>> _filteredSalaries = [];
  bool _loading = false;
  String _searchQuery = '';
  String _statusFilter = 'all'; // all, pending, paid, partial

  @override
  void initState() {
    super.initState();
    _loadSalaries();
  }

  Future<void> _loadSalaries() async {
    setState(() => _loading = true);
    try {
      final response = await ApiClient.instance.dio.get('/salaries');
      if (!mounted) return;

      setState(() {
        _salaries = (response.data as List).cast<Map<String, dynamic>>();
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تحميل المرتبات: $e')),
        );
        setState(() => _loading = false);
      }
    }
  }

  void _applyFilter() {
    var filtered = _salaries;

    if (_statusFilter != 'all') {
      filtered = filtered.where((s) => s['status'] == _statusFilter).toList();
    }

    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where((s) =>
              (s['employee']?['fullName'] ?? '').toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (s['employee']?['email'] ?? '').toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    setState(() => _filteredSalaries = filtered);
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _applyFilter();
    });
  }

  void _showSalaryDetails(Map<String, dynamic> salary) {
    showDialog(
      context: context,
      builder: (context) => _SalaryDetailsDialog(salary: salary, onRefresh: _loadSalaries),
    );
  }

  void _showCreateSalaryDialog() {
    showDialog(
      context: context,
      builder: (context) => _CreateSalaryDialog(onCreated: _loadSalaries),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'paid':
        return Colors.green;
      case 'pending':
        return Colors.red;
      case 'partial':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'paid':
        return 'مسدد';
      case 'pending':
        return 'قيد الانتظار';
      case 'partial':
        return 'مسدد جزئي';
      default:
        return 'غير معروف';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة المرتبات والرواتب'),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // البحث والفلتر
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'ابحث عن موظف...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: _onSearchChanged,
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            FilterChip(
                              label: const Text('الكل'),
                              selected: _statusFilter == 'all',
                              onSelected: (selected) {
                                setState(() {
                                  _statusFilter = 'all';
                                  _applyFilter();
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              label: const Text('قيد الانتظار'),
                              selected: _statusFilter == 'pending',
                              onSelected: (selected) {
                                setState(() {
                                  _statusFilter = 'pending';
                                  _applyFilter();
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              label: const Text('مسدد جزئي'),
                              selected: _statusFilter == 'partial',
                              onSelected: (selected) {
                                setState(() {
                                  _statusFilter = 'partial';
                                  _applyFilter();
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              label: const Text('مسدد'),
                              selected: _statusFilter == 'paid',
                              onSelected: (selected) {
                                setState(() {
                                  _statusFilter = 'paid';
                                  _applyFilter();
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // القائمة
                Expanded(
                  child: _filteredSalaries.isEmpty
                      ? Center(
                          child: Text(
                            _searchQuery.isEmpty && _statusFilter == 'all'
                                ? 'لا توجد مرتبات'
                                : 'لم يتم العثور على نتائج',
                            style: AppTextStyles.bodyMd(),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredSalaries.length,
                          itemBuilder: (context, index) {
                            final salary = _filteredSalaries[index];
                            final employee = salary['employee'] as Map<String, dynamic>?;
                            final baseSalary = salary['baseSalary'] ?? 0.0;
                            final paidAmount = salary['paidAmount'] ?? 0.0;
                            final status = salary['status'] ?? 'pending';
                            final month = salary['month'] ?? '---';

                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: ListTile(
                                leading: Icon(
                                  Icons.money,
                                  color: _getStatusColor(status),
                                ),
                                title: Text(employee?['fullName'] ?? 'موظف بلا اسم'),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('الراتب: ${baseSalary.toStringAsFixed(2)} د.ل'),
                                    Text('المسدد: ${paidAmount.toStringAsFixed(2)} د.ل'),
                                    Text('الشهر: $month'),
                                  ],
                                ),
                                trailing: Chip(
                                  label: Text(_getStatusLabel(status)),
                                  backgroundColor: _getStatusColor(status).withOpacity(0.2),
                                  labelStyle: TextStyle(color: _getStatusColor(status)),
                                ),
                                onTap: () => _showSalaryDetails(salary),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateSalaryDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ─── تفاصيل المرتب ────────────────────────────────────────────

class _SalaryDetailsDialog extends ConsumerWidget {
  final Map<String, dynamic> salary;
  final VoidCallback onRefresh;

  const _SalaryDetailsDialog({
    required this.salary,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee = salary['employee'] as Map<String, dynamic>?;
    final baseSalary = salary['baseSalary'] ?? 0.0;
    final allowances = salary['allowances'] ?? 0.0;
    final deductions = salary['deductions'] ?? 0.0;
    final netSalary = baseSalary + allowances - deductions;
    final paidAmount = salary['paidAmount'] ?? 0.0;
    final remainingAmount = netSalary - paidAmount;
    final status = salary['status'] ?? 'pending';
    final month = salary['month'] ?? '---';

    return AdaptiveDialog(
      title: 'تفاصيل المرتب',
      maxWidth: 600,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // بيانات الموظف
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('بيانات الموظف', style: AppTextStyles.headlineMd()),
                    const SizedBox(height: 12),
                    Text('الاسم: ${employee?['fullName'] ?? '-'}'),
                    Text('البريد: ${employee?['email'] ?? '-'}'),
                    Text('الشهر: $month'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // بيانات الراتب
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('بيانات الراتب', style: AppTextStyles.headlineMd()),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('الراتب الأساسي:'),
                        Text(baseSalary.toStringAsFixed(2) + ' د.ل'),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('البدلات:'),
                        Text(
                          allowances.toStringAsFixed(2) + ' د.ل',
                          style: const TextStyle(color: Colors.green),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('الخصومات:'),
                        Text(
                          deductions.toStringAsFixed(2) + ' د.ل',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('الراتب الصافي:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          netSalary.toStringAsFixed(2) + ' د.ل',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // حالة السداد
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('حالة السداد', style: AppTextStyles.headlineMd()),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('المسدد:'),
                        Text(paidAmount.toStringAsFixed(2) + ' د.ل'),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('المتبقي:'),
                        Text(
                          remainingAmount.toStringAsFixed(2) + ' د.ل',
                          style: TextStyle(
                            color: remainingAmount > 0 ? Colors.orange : Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Chip(
                          label: Text(_getStatusLabel(status)),
                          backgroundColor: _getStatusColor(status),
                          labelStyle: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // خيارات سريعة
            if (status != 'paid')
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.payment),
                      label: const Text('تسديد'),
                      onPressed: () {
                        Navigator.pop(context);
                        _showPaymentDialog(context, salary['id']);
                      },
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'paid':
        return Colors.green;
      case 'pending':
        return Colors.red;
      case 'partial':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'paid':
        return 'مسدد';
      case 'pending':
        return 'قيد الانتظار';
      case 'partial':
        return 'مسدد جزئي';
      default:
        return 'غير معروف';
    }
  }

  void _showPaymentDialog(BuildContext context, String salaryId) {
    showDialog(
      context: context,
      builder: (context) => _RecordSalaryPaymentDialog(salaryId: salaryId, onPaid: onRefresh),
    );
  }
}

// ─── تسجيل دفعة مرتب ────────────────────────────────────────

class _RecordSalaryPaymentDialog extends ConsumerStatefulWidget {
  final String salaryId;
  final VoidCallback onPaid;

  const _RecordSalaryPaymentDialog({
    required this.salaryId,
    required this.onPaid,
  });

  @override
  ConsumerState<_RecordSalaryPaymentDialog> createState() => _RecordSalaryPaymentDialogState();
}

class _RecordSalaryPaymentDialogState extends ConsumerState<_RecordSalaryPaymentDialog> {
  late TextEditingController _amountController;
  late TextEditingController _notesController;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _recordPayment() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل مبلغاً صحيحاً')),
      );
      return;
    }

    setState(() => _processing = true);
    try {
      await ApiClient.instance.dio.post(
        '/salaries/${widget.salaryId}/pay',
        data: {
          'amount': amount,
          'notes': _notesController.text.isEmpty ? null : _notesController.text,
        },
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onPaid();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تسجيل السداد بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveDialog(
      title: 'تسجيل دفعة راتب',
      maxWidth: 500,
      actions: [
        TextButton(
          onPressed: _processing ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _processing ? null : _recordPayment,
          child: const Text('تسجيل'),
        ),
      ],
      body: SingleChildScrollView(
        child: Column(
          children: [
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'المبلغ المسدد *',
                prefixIcon: Icon(Icons.money),
              ),
              enabled: !_processing,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'ملاحظات (اختياري)',
                prefixIcon: Icon(Icons.note),
              ),
              maxLines: 2,
              enabled: !_processing,
            ),
            const SizedBox(height: 16),
            if (_processing) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

// ─── إنشاء مرتب جديد ────────────────────────────────────────

class _CreateSalaryDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;

  const _CreateSalaryDialog({required this.onCreated});

  @override
  ConsumerState<_CreateSalaryDialog> createState() => _CreateSalaryDialogState();
}

class _CreateSalaryDialogState extends ConsumerState<_CreateSalaryDialog> {
  late TextEditingController _baseSalaryController;
  late TextEditingController _allowancesController;
  late TextEditingController _deductionsController;
  late TextEditingController _monthController;

  String? _selectedEmployeeId;
  List<Map<String, dynamic>> _employees = [];
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _baseSalaryController = TextEditingController();
    _allowancesController = TextEditingController(text: '0');
    _deductionsController = TextEditingController(text: '0');
    _monthController = TextEditingController();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    try {
      final response = await ApiClient.instance.dio.get('/employees');
      if (mounted) {
        setState(() {
          _employees = (response.data as List).cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تحميل الموظفين: $e')),
        );
      }
    }
  }

  Future<void> _createSalary() async {
    if (_selectedEmployeeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر موظف')),
      );
      return;
    }

    final baseSalary = double.tryParse(_baseSalaryController.text);
    if (baseSalary == null || baseSalary <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل راتباً صحيحاً')),
      );
      return;
    }

    setState(() => _processing = true);
    try {
      await ApiClient.instance.dio.post(
        '/salaries',
        data: {
          'employeeId': _selectedEmployeeId,
          'baseSalary': baseSalary,
          'allowances': double.tryParse(_allowancesController.text) ?? 0,
          'deductions': double.tryParse(_deductionsController.text) ?? 0,
          'month': _monthController.text.isEmpty ? null : _monthController.text,
        },
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء المرتب بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  void dispose() {
    _baseSalaryController.dispose();
    _allowancesController.dispose();
    _deductionsController.dispose();
    _monthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveDialog(
      title: 'إنشاء مرتب جديد',
      maxWidth: 600,
      actions: [
        TextButton(
          onPressed: _processing ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _processing ? null : _createSalary,
          child: const Text('إنشاء'),
        ),
      ],
      body: SingleChildScrollView(
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: _selectedEmployeeId,
              decoration: const InputDecoration(labelText: 'اختر الموظف'),
              items: _employees
                  .map((e) => DropdownMenuItem(
                        value: e['id'] as String,
                        child: Text(e['fullName'] as String? ?? ''),
                      ))
                  .toList(),
              onChanged: _processing ? null : (value) => setState(() => _selectedEmployeeId = value),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _baseSalaryController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'الراتب الأساسي *'),
              enabled: !_processing,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _allowancesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'البدلات'),
                    enabled: !_processing,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _deductionsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'الخصومات'),
                    enabled: !_processing,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _monthController,
              decoration: const InputDecoration(labelText: 'الشهر (مثال: 2025-09)'),
              enabled: !_processing,
            ),
            const SizedBox(height: 16),
            if (_processing) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
