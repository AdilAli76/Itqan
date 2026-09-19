import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/adaptive_dialog.dart';

class CardBalanceManagementScreen extends ConsumerStatefulWidget {
  const CardBalanceManagementScreen({super.key});

  @override
  ConsumerState<CardBalanceManagementScreen> createState() => _CardBalanceManagementScreenState();
}

class _CardBalanceManagementScreenState extends ConsumerState<CardBalanceManagementScreen> {
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _filteredAccounts = [];
  bool _loading = false;
  String _searchQuery = '';
  double _totalBalance = 0;
  double _totalCreditLimit = 0;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() => _loading = true);
    try {
      final response = await ApiClient.instance.dio.get('/customer-accounts');
      if (!mounted) return;

      var accounts = (response.data as List).cast<Map<String, dynamic>>();
      _totalBalance = accounts.fold(0.0, (sum, acc) => sum + (acc['balance'] ?? 0.0));
      _totalCreditLimit = accounts.fold(0.0, (sum, acc) => sum + (acc['creditLimit'] ?? 0.0));

      setState(() {
        _accounts = accounts;
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تحميل الأرصدة: $e')),
        );
        setState(() => _loading = false);
      }
    }
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredAccounts = _accounts;
    } else {
      _filteredAccounts = _accounts
          .where((acc) =>
              (acc['customer']?['fullName'] ?? '').toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (acc['accountNumber'] ?? '').contains(_searchQuery))
          .toList();
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _applyFilter();
    });
  }

  void _showAccountBalance(Map<String, dynamic> account) {
    showDialog(
      context: context,
      builder: (context) => _BalanceDetailsDialog(account: account, onRefresh: _loadAccounts),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة أرصدة البطاقات'),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // البطاقات الإحصائية
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.account_balance_wallet, color: Colors.blue),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text('إجمالي الأرصدة', style: TextStyle(fontSize: 12)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${_totalBalance.toStringAsFixed(2)} د.ل',
                                  style: AppTextStyles.headlineSm(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.credit_card, color: Colors.green),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text('سقف الائتمان', style: TextStyle(fontSize: 12)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${_totalCreditLimit.toStringAsFixed(2)} د.ل',
                                  style: AppTextStyles.headlineSm(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // البحث
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'ابحث عن عميل...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),

                // القائمة
                Expanded(
                  child: _filteredAccounts.isEmpty
                      ? Center(
                          child: Text(
                            _searchQuery.isEmpty ? 'لا توجد حسابات' : 'لم يتم العثور على نتائج',
                            style: AppTextStyles.bodyMd(),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredAccounts.length,
                          itemBuilder: (context, index) {
                            final account = _filteredAccounts[index];
                            final customer = account['customer'] as Map<String, dynamic>?;
                            final balance = account['balance'] ?? 0.0;
                            final creditLimit = account['creditLimit'] ?? 0.0;
                            final available = creditLimit - balance;
                            final utilization = creditLimit > 0 ? (balance / creditLimit) : 0.0;

                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text((customer?['fullName'] ?? 'ع')[0]),
                                ),
                                title: Text(customer?['fullName'] ?? 'عميل بلا اسم'),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('الرصيد: ${balance.toStringAsFixed(2)} د.ل'),
                                    Text(
                                      'المتاح: ${available.toStringAsFixed(2)} د.ل',
                                      style: TextStyle(
                                        color: available > 0 ? Colors.green : Colors.red,
                                      ),
                                    ),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: utilization.clamp(0.0, 1.0),
                                        minHeight: 6,
                                        backgroundColor: Colors.grey[300],
                                        valueColor: AlwaysStoppedAnimation(
                                          utilization > 0.8 ? Colors.red : Colors.green,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.arrow_forward),
                                  onPressed: () => _showAccountBalance(account),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

// ─── تفاصيل الرصيد ────────────────────────────────────────────

class _BalanceDetailsDialog extends ConsumerWidget {
  final Map<String, dynamic> account;
  final VoidCallback onRefresh;

  const _BalanceDetailsDialog({
    required this.account,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = account['customer'] as Map<String, dynamic>?;
    final balance = account['balance'] ?? 0.0;
    final creditLimit = account['creditLimit'] ?? 0.0;
    final available = creditLimit - balance;
    final utilization = creditLimit > 0 ? (balance / creditLimit) : 0.0;
    final accountNumber = account['accountNumber'] ?? '-';
    final bankName = account['bankName'] ?? '-';

    return AdaptiveDialog(
      title: 'تفاصيل رصيد البطاقة',
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
                    Text('البريد: ${customer?['email'] ?? '-'}'),
                    Text('الهاتف: ${customer?['phone'] ?? '-'}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // بيانات البطاقة
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('بيانات البطاقة', style: AppTextStyles.headlineMd()),
                    const SizedBox(height: 12),
                    Text('رقم الحساب: $accountNumber'),
                    Text('البنك: $bankName'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ملخص الرصيد
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ملخص الرصيد', style: AppTextStyles.headlineMd()),
                    const SizedBox(height: 16),

                    // الرصيد الحالي
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('الرصيد الحالي', style: TextStyle(fontSize: 12)),
                              Text(
                                '${balance.toStringAsFixed(2)} د.ل',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                          Icon(Icons.account_balance, color: Colors.blue, size: 32),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // سقف الائتمان
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('سقف الائتمان', style: TextStyle(fontSize: 12)),
                              Text(
                                '${creditLimit.toStringAsFixed(2)} د.ل',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                          Icon(Icons.credit_card, color: Colors.green, size: 32),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // المتاح
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: available > 0 ? Colors.orange[50] : Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('الرصيد المتاح', style: TextStyle(fontSize: 12)),
                              Text(
                                '${available.toStringAsFixed(2)} د.ل',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: available > 0 ? Colors.orange : Colors.red,
                                ),
                              ),
                            ],
                          ),
                          Icon(
                            available > 0 ? Icons.trending_up : Icons.trending_down,
                            color: available > 0 ? Colors.orange : Colors.red,
                            size: 32,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // نسبة الاستخدام
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('نسبة الاستخدام'),
                            Text(
                              '${(utilization * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: utilization.clamp(0.0, 1.0),
                            minHeight: 10,
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation(
                              utilization > 0.8 ? Colors.red : utilization > 0.5 ? Colors.orange : Colors.green,
                            ),
                          ),
                        ),
                      ],
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
                    icon: const Icon(Icons.add),
                    label: const Text('زيادة رصيد'),
                    onPressed: () {
                      Navigator.pop(context);
                      _showAddBalanceDialog(context);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.remove),
                    label: const Text('تنزيل رصيد'),
                    onPressed: () {
                      Navigator.pop(context);
                      _showReduceBalanceDialog(context);
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

  void _showAddBalanceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _AdjustBalanceDialog(
        accountId: account['id'],
        isAdding: true,
        onAdjusted: onRefresh,
      ),
    );
  }

  void _showReduceBalanceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _AdjustBalanceDialog(
        accountId: account['id'],
        isAdding: false,
        onAdjusted: onRefresh,
      ),
    );
  }
}

// ─── تعديل الرصيد ────────────────────────────────────────────

class _AdjustBalanceDialog extends ConsumerStatefulWidget {
  final String accountId;
  final bool isAdding;
  final VoidCallback onAdjusted;

  const _AdjustBalanceDialog({
    required this.accountId,
    required this.isAdding,
    required this.onAdjusted,
  });

  @override
  ConsumerState<_AdjustBalanceDialog> createState() => _AdjustBalanceDialogState();
}

class _AdjustBalanceDialogState extends ConsumerState<_AdjustBalanceDialog> {
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

  Future<void> _adjustBalance() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل مبلغاً صحيحاً')),
      );
      return;
    }

    setState(() => _processing = true);
    try {
      await ApiClient.instance.dio.patch(
        '/customer-accounts/${widget.accountId}/balance',
        data: {
          'amount': widget.isAdding ? amount : -amount,
          'notes': _notesController.text.isEmpty ? null : _notesController.text,
        },
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onAdjusted();
        final action = widget.isAdding ? 'زيادة' : 'تنزيل';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم $action الرصيد بنجاح')),
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
    final action = widget.isAdding ? 'زيادة' : 'تنزيل';
    return AdaptiveDialog(
      title: '$action الرصيد',
      maxWidth: 500,
      actions: [
        TextButton(
          onPressed: _processing ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _processing ? null : _adjustBalance,
          child: Text(action),
        ),
      ],
      body: SingleChildScrollView(
        child: Column(
          children: [
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'المبلغ *',
                prefixIcon: const Icon(Icons.money),
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
