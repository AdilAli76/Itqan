import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_text_styles.dart';
import 'customer_form_dialog.dart';
import 'customer_accounts_screen.dart';
import 'customer_loans_screen.dart';
import 'salary_management_screen.dart';
import 'card_balance_management_screen.dart';
import 'customer_categories_screen.dart';

class CustomerDashboard extends ConsumerStatefulWidget {
  const CustomerDashboard({super.key});

  @override
  ConsumerState<CustomerDashboard> createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends ConsumerState<CustomerDashboard> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _filteredCustomers = [];
  bool _loading = false;
  String _searchQuery = '';

  // إحصائيات
  int _totalCustomers = 0;
  double _totalLoans = 0;
  double _totalBalance = 0;
  int _totalCategories = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      await Future.wait([
        _loadCustomers(),
        _loadStatistics(),
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCustomers() async {
    try {
      final response = await ApiClient.instance.dio.get('/customers');
      if (!mounted) return;

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
        _applyFilter();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تحميل العملاء: $e')),
        );
      }
    }
  }

  Future<void> _loadStatistics() async {
    try {
      // تحميل الإحصائيات من API
      final statsResponse = await ApiClient.instance.dio.get('/customers/statistics');
      if (!mounted) return;

      final stats = statsResponse.data as Map<String, dynamic>;
      setState(() {
        _totalCustomers = stats['totalCustomers'] ?? 0;
        _totalLoans = (stats['totalLoans'] ?? 0).toDouble();
        _totalBalance = (stats['totalBalance'] ?? 0).toDouble();
        _totalCategories = stats['totalCategories'] ?? 0;
      });
    } catch (e) {
      // تجاهل أخطاء الإحصائيات
    }
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredCustomers = _customers;
    } else {
      _filteredCustomers = _customers
          .where((c) =>
              (c['fullName'] ?? '').toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (c['phone'] ?? '').contains(_searchQuery))
          .toList();
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _applyFilter();
    });
  }

  void _showCustomerForm({Map<String, dynamic>? customer}) {
    showDialog(
      context: context,
      builder: (context) => CustomerFormDialog(
        customer: customer,
        onSaved: _loadData,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة تحكم العملاء'),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'نظرة عامة'),
            Tab(text: 'قائمة العملاء'),
            Tab(text: 'الحسابات'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // التاب الأول: نظرة عامة
                _buildOverviewTab(),

                // التاب الثاني: قائمة العملاء
                _buildCustomersListTab(),

                // التاب الثالث: الحسابات
                const CustomerAccountsScreen(),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCustomerForm(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildOverviewTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // البطاقات الإحصائية
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              children: [
                _buildStatCard(
                  title: 'إجمالي العملاء',
                  value: _totalCustomers.toString(),
                  icon: Icons.people,
                  color: Colors.blue,
                ),
                _buildStatCard(
                  title: 'إجمالي السلف',
                  value: '${_totalLoans.toStringAsFixed(2)} د.ل',
                  icon: Icons.trending_down,
                  color: Colors.red,
                ),
                _buildStatCard(
                  title: 'إجمالي الأرصدة',
                  value: '${_totalBalance.toStringAsFixed(2)} د.ل',
                  icon: Icons.wallet,
                  color: Colors.green,
                ),
                _buildStatCard(
                  title: 'فئات العملاء',
                  value: '$_totalCategories',
                  icon: Icons.category,
                  color: Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 32),

            // العمليات السريعة
            Text('العمليات السريعة', style: AppTextStyles.headlineMd()),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 3,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.person_add),
                  label: const Text('عميل جديد'),
                  onPressed: () => _showCustomerForm(),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.category),
                  label: const Text('فئات العملاء'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CustomerCategoriesScreen()),
                    );
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.trending_down),
                  label: const Text('إدارة السلف'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CustomerLoansScreen()),
                    );
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.money),
                  label: const Text('إدارة المرتبات'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SalaryManagementScreen()),
                    );
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.account_balance_wallet),
                  label: const Text('إدارة الأرصدة'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CardBalanceManagementScreen()),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomersListTab() {
    return Column(
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
          child: _filteredCustomers.isEmpty
              ? Center(
                  child: Text(
                    _searchQuery.isEmpty ? 'لا توجد عملاء' : 'لم يتم العثور على نتائج',
                    style: AppTextStyles.bodyMd(),
                  ),
                )
              : ListView.builder(
                  itemCount: _filteredCustomers.length,
                  itemBuilder: (context, index) {
                    final customer = _filteredCustomers[index];
                    final category = customer['category']?['name'] ?? 'بدون فئة';

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text((customer['fullName'] ?? 'ع')[0]),
                        ),
                        title: Text(customer['fullName'] ?? 'عميل بلا اسم'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('الفئة: $category'),
                            Text('الهاتف: ${customer['phone'] ?? '-'}'),
                          ],
                        ),
                        trailing: PopupMenuButton(
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              onTap: () => _showCustomerForm(customer: customer),
                              child: const Row(
                                children: [
                                  Icon(Icons.edit),
                                  SizedBox(width: 8),
                                  Text('تعديل'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const CustomerAccountsScreen()),
                                );
                              },
                              child: const Row(
                                children: [
                                  Icon(Icons.account_balance),
                                  SizedBox(width: 8),
                                  Text('الحسابات'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const CustomerLoansScreen()),
                                );
                              },
                              child: const Row(
                                children: [
                                  Icon(Icons.trending_down),
                                  SizedBox(width: 8),
                                  Text('السلف'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const SalaryManagementScreen()),
                                );
                              },
                              child: const Row(
                                children: [
                                  Icon(Icons.money),
                                  SizedBox(width: 8),
                                  Text('المرتبات'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const CardBalanceManagementScreen()),
                                );
                              },
                              child: const Row(
                                children: [
                                  Icon(Icons.account_balance_wallet),
                                  SizedBox(width: 8),
                                  Text('الأرصدة'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 12),
            Text(title, style: AppTextStyles.bodySm()),
            const SizedBox(height: 4),
            Text(value, style: AppTextStyles.headlineSm()),
          ],
        ),
      ),
    );
  }
}
