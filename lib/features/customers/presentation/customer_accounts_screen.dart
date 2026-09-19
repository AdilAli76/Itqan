import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/adaptive_dialog.dart';

class CustomerAccountsScreen extends ConsumerStatefulWidget {
  const CustomerAccountsScreen({super.key});

  @override
  ConsumerState<CustomerAccountsScreen> createState() => _CustomerAccountsScreenState();
}

class _CustomerAccountsScreenState extends ConsumerState<CustomerAccountsScreen> {
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _filteredAccounts = [];
  bool _loading = false;
  String _searchQuery = '';

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

      setState(() {
        _accounts = (response.data as List).cast<Map<String, dynamic>>();
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تحميل الحسابات: $e')),
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

  void _showAccountDetails(Map<String, dynamic> account) {
    showDialog(
      context: context,
      builder: (context) => _AccountDetailsDialog(account: account, onRefresh: _loadAccounts),
    );
  }

  void _showCreateAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => _CreateAccountDialog(onCreated: _loadAccounts),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة حسابات العملاء'),
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

                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: ListTile(
                                title: Text(customer?['fullName'] ?? 'عميل بلا اسم'),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('الرصيد: ${balance.toStringAsFixed(2)} دينار'),
                                    Text('سقف الائتمان: ${creditLimit.toStringAsFixed(2)} دينار'),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.arrow_forward),
                                  onPressed: () => _showAccountDetails(account),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateAccountDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ─── تفاصيل الحساب ────────────────────────────────────────────

class _AccountDetailsDialog extends ConsumerWidget {
  final Map<String, dynamic> account;
  final VoidCallback onRefresh;

  const _AccountDetailsDialog({
    required this.account,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = account['customer'] as Map<String, dynamic>?;
    final balance = account['balance'] ?? 0.0;
    final creditLimit = account['creditLimit'] ?? 0.0;
    final accountNumber = account['accountNumber'] ?? '-';
    final bankName = account['bankName'] ?? '-';

    return AdaptiveDialog(
      title: 'تفاصيل الحساب',
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

            // بيانات الحساب
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('بيانات الحساب', style: AppTextStyles.headlineMd()),
                    const SizedBox(height: 12),
                    Text('رقم الحساب: $accountNumber'),
                    Text('البنك: $bankName'),
                    Text('الرصيد الحالي: ${balance.toStringAsFixed(2)} دينار'),
                    Text('سقف الائتمان: ${creditLimit.toStringAsFixed(2)} دينار'),
                    Text(
                      'المتاح: ${(creditLimit - balance).toStringAsFixed(2)} دينار',
                      style: const TextStyle(color: Colors.green),
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
                    icon: const Icon(Icons.trending_down),
                    label: const Text('تنزيل رصيد'),
                    onPressed: () {
                      // تطبيق السلف
                      Navigator.pop(context);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.money),
                    label: const Text('المرتبات'),
                    onPressed: () {
                      // عرض المرتبات
                      Navigator.pop(context);
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
}

// ─── إنشاء حساب جديد ────────────────────────────────────────

class _CreateAccountDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;

  const _CreateAccountDialog({required this.onCreated});

  @override
  ConsumerState<_CreateAccountDialog> createState() => _CreateAccountDialogState();
}

class _CreateAccountDialogState extends ConsumerState<_CreateAccountDialog> {
  late TextEditingController _accountNumberController;
  late TextEditingController _bankNameController;
  late TextEditingController _creditLimitController;

  String? _selectedCustomerId;
  List<Map<String, dynamic>> _customers = [];

  @override
  void initState() {
    super.initState();
    _accountNumberController = TextEditingController();
    _bankNameController = TextEditingController();
    _creditLimitController = TextEditingController();
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

  Future<void> _createAccount() async {
    if (_selectedCustomerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر عميل')),
      );
      return;
    }

    try {
      await ApiClient.instance.dio.post(
        '/customer-accounts',
        data: {
          'customerId': _selectedCustomerId,
          'accountNumber': _accountNumberController.text,
          'bankName': _bankNameController.text,
          'creditLimit': double.tryParse(_creditLimitController.text) ?? 0,
        },
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء الحساب بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _accountNumberController.dispose();
    _bankNameController.dispose();
    _creditLimitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveDialog(
      title: 'إنشاء حساب عميل جديد',
      maxWidth: 600,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _createAccount,
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
              onChanged: (value) => setState(() => _selectedCustomerId = value),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _accountNumberController,
              decoration: const InputDecoration(labelText: 'رقم الحساب'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bankNameController,
              decoration: const InputDecoration(labelText: 'اسم البنك'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _creditLimitController,
              decoration: const InputDecoration(labelText: 'سقف الائتمان'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
    );
  }
}
