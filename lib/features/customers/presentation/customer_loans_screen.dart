import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/adaptive_dialog.dart';

class CustomerLoansScreen extends ConsumerStatefulWidget {
  const CustomerLoansScreen({super.key});

  @override
  ConsumerState<CustomerLoansScreen> createState() => _CustomerLoansScreenState();
}

class _CustomerLoansScreenState extends ConsumerState<CustomerLoansScreen> {
  List<Map<String, dynamic>> _loans = [];
  List<Map<String, dynamic>> _filteredLoans = [];
  bool _loading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadLoans();
  }

  Future<void> _loadLoans() async {
    setState(() => _loading = true);
    try {
      final response = await ApiClient.instance.dio.get('/customer-loans');
      if (!mounted) return;

      setState(() {
        _loans = (response.data as List).cast<Map<String, dynamic>>();
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تحميل السلف: $e')),
        );
        setState(() => _loading = false);
      }
    }
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredLoans = _loans;
    } else {
      _filteredLoans = _loans
          .where((loan) =>
              (loan['customer']?['fullName'] ?? '').toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (loan['loanNumber'] ?? '').contains(_searchQuery))
          .toList();
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _applyFilter();
    });
  }

  void _showLoanDetails(Map<String, dynamic> loan) {
    showDialog(
      context: context,
      builder: (context) => _LoanDetailsDialog(loan: loan, onRefresh: _loadLoans),
    );
  }

  void _showCreateLoanDialog() {
    showDialog(
      context: context,
      builder: (context) => _CreateLoanDialog(onCreated: _loadLoans),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة السلف والتسليفات'),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // البحث
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'ابحث عن سلف...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),

                // القائمة
                Expanded(
                  child: _filteredLoans.isEmpty
                      ? Center(
                          child: Text(
                            _searchQuery.isEmpty ? 'لا توجد سلف' : 'لم يتم العثور على نتائج',
                            style: AppTextStyles.bodyMd(),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredLoans.length,
                          itemBuilder: (context, index) {
                            final loan = _filteredLoans[index];
                            final customer = loan['customer'] as Map<String, dynamic>?;
                            final amount = loan['amount'] ?? 0.0;
                            final paidAmount = loan['paidAmount'] ?? 0.0;
                            final interestRate = loan['interestRate'] ?? 0.0;
                            final status = loan['status'] ?? 'active';

                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: ListTile(
                                leading: Icon(
                                  Icons.trending_down,
                                  color: status == 'active' ? Colors.red : Colors.green,
                                ),
                                title: Text(customer?['fullName'] ?? 'عميل بلا اسم'),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('السلف: ${amount.toStringAsFixed(2)} د.ل'),
                                    Text('المدفوع: ${paidAmount.toStringAsFixed(2)} د.ل'),
                                    Text('الفائدة: $interestRate% سنوياً'),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.arrow_forward),
                                  onPressed: () => _showLoanDetails(loan),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateLoanDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ─── تفاصيل السلف ────────────────────────────────────────────

class _LoanDetailsDialog extends ConsumerWidget {
  final Map<String, dynamic> loan;
  final VoidCallback onRefresh;

  const _LoanDetailsDialog({
    required this.loan,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = loan['customer'] as Map<String, dynamic>?;
    final amount = loan['amount'] ?? 0.0;
    final paidAmount = loan['paidAmount'] ?? 0.0;
    final remainingAmount = amount - paidAmount;
    final interestRate = loan['interestRate'] ?? 0.0;
    final monthlyInstallment = loan['monthlyInstallment'] ?? 0.0;
    final status = loan['status'] ?? 'active';

    return AdaptiveDialog(
      title: 'تفاصيل السلف',
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
            // بيانات العميل
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('بيانات العميل', style: AppTextStyles.headlineMd()),
                    const SizedBox(height: 12),
                    Text('الاسم: ${customer?['fullName'] ?? '-'}'),
                    Text('رقم الهاتف: ${customer?['phone'] ?? '-'}'),
                    Text('الفئة: ${customer?['category']?['name'] ?? 'بلا فئة'}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // بيانات السلف
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('بيانات السلف', style: AppTextStyles.headlineMd()),
                    const SizedBox(height: 12),
                    Text('المبلغ الأصلي: ${amount.toStringAsFixed(2)} د.ل'),
                    Text('المدفوع: ${paidAmount.toStringAsFixed(2)} د.ل'),
                    Text(
                      'المتبقي: ${remainingAmount.toStringAsFixed(2)} د.ل',
                      style: const TextStyle(color: Colors.orange),
                    ),
                    Text('فائدة سنوية: $interestRate%'),
                    Text('القسط الشهري: ${monthlyInstallment.toStringAsFixed(2)} د.ل'),
                    const SizedBox(height: 8),
                    Chip(
                      label: Text(status == 'active' ? 'نشط' : 'مكتمل'),
                      backgroundColor: status == 'active' ? Colors.red : Colors.green,
                      labelStyle: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // خيارات سريعة
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.payment),
                    label: const Text('سداد'),
                    onPressed: () {
                      Navigator.pop(context);
                      _showPaymentDialog(context);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.history),
                    label: const Text('السجل'),
                    onPressed: () {
                      Navigator.pop(context);
                      _showPaymentHistory(context);
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

  void _showPaymentDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _RecordPaymentDialog(loanId: loan['id'], onPaid: onRefresh),
    );
  }

  void _showPaymentHistory(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _PaymentHistoryDialog(loanId: loan['id']),
    );
  }
}

// ─── تسجيل السداد ────────────────────────────────────────────

class _RecordPaymentDialog extends ConsumerStatefulWidget {
  final String loanId;
  final VoidCallback onPaid;

  const _RecordPaymentDialog({
    required this.loanId,
    required this.onPaid,
  });

  @override
  ConsumerState<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends ConsumerState<_RecordPaymentDialog> {
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
        '/customer-loans/${widget.loanId}/payment',
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
      title: 'تسجيل سداد',
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

// ─── سجل السداد ────────────────────────────────────────────

class _PaymentHistoryDialog extends ConsumerStatefulWidget {
  final String loanId;

  const _PaymentHistoryDialog({required this.loanId});

  @override
  ConsumerState<_PaymentHistoryDialog> createState() => _PaymentHistoryDialogState();
}

class _PaymentHistoryDialogState extends ConsumerState<_PaymentHistoryDialog> {
  List<Map<String, dynamic>> _payments = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    setState(() => _loading = true);
    try {
      final response = await ApiClient.instance.dio.get(
        '/customer-loans/${widget.loanId}/payments',
      );
      if (mounted) {
        setState(() {
          _payments = (response.data as List).cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تحميل السجل: $e')),
        );
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveDialog(
      title: 'سجل السداد',
      maxWidth: 600,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _payments.isEmpty
              ? Center(
                  child: Text(
                    'لا توجد مدفوعات',
                    style: AppTextStyles.bodyMd(),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _payments.length,
                  itemBuilder: (context, index) {
                    final payment = _payments[index];
                    return ListTile(
                      leading: const Icon(Icons.check_circle, color: Colors.green),
                      title: Text('${payment['amount']?.toStringAsFixed(2) ?? '0'} د.ل'),
                      subtitle: Text(payment['paidDate'] ?? ''),
                      trailing: Text(payment['notes'] ?? ''),
                    );
                  },
                ),
    );
  }
}

// ─── إنشاء سلف جديد ────────────────────────────────────────

class _CreateLoanDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;

  const _CreateLoanDialog({required this.onCreated});

  @override
  ConsumerState<_CreateLoanDialog> createState() => _CreateLoanDialogState();
}

class _CreateLoanDialogState extends ConsumerState<_CreateLoanDialog> {
  late TextEditingController _amountController;
  late TextEditingController _interestRateController;
  late TextEditingController _monthlyInstallmentController;

  String? _selectedCustomerId;
  List<Map<String, dynamic>> _customers = [];
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    _interestRateController = TextEditingController(text: '5');
    _monthlyInstallmentController = TextEditingController();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    try {
      final response = await ApiClient.instance.dio.get('/customers');
      if (mounted) {
        final data = response.data;
        final List rawList;
        if (data is Map && data['items'] is List) {
          rawList = data['items'] as List;
        } else if (data is List) {
          rawList = data;
        } else {
          rawList = [];
        }

        setState(() {
          _customers = rawList.cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تحميل العملاء: $e')),
        );
      }
    }
  }

  Future<void> _createLoan() async {
    if (_selectedCustomerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر عميل')),
      );
      return;
    }

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
        '/customer-loans',
        data: {
          'customerId': _selectedCustomerId,
          'amount': amount,
          'interestRate': double.tryParse(_interestRateController.text) ?? 0,
          'monthlyInstallment': double.tryParse(_monthlyInstallmentController.text) ?? 0,
        },
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء السلف بنجاح')),
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
    _amountController.dispose();
    _interestRateController.dispose();
    _monthlyInstallmentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveDialog(
      title: 'إنشاء سلف جديد',
      maxWidth: 600,
      actions: [
        TextButton(
          onPressed: _processing ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _processing ? null : _createLoan,
          child: const Text('إنشاء'),
        ),
      ],
      body: SingleChildScrollView(
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: _selectedCustomerId,
              decoration: const InputDecoration(labelText: 'اختر العميل'),
              items: _customers
                  .map((c) => DropdownMenuItem(
                        value: c['id'] as String,
                        child: Text(c['fullName'] as String? ?? ''),
                      ))
                  .toList(),
              onChanged: _processing ? null : (value) => setState(() => _selectedCustomerId = value),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'المبلغ *'),
              enabled: !_processing,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _interestRateController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'الفائدة السنوية %'),
                    enabled: !_processing,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _monthlyInstallmentController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'القسط الشهري'),
                    enabled: !_processing,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_processing) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
