# 🎨 قوالب تحسين الشاشات - Copy & Paste Ready

**الهدف**: تحسين جميع شاشات التطبيق بمكونات احترافية موحدة

---

## 📋 قالب عام لأي شاشة قائمة

### الهيكل الأساسي:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/list_toolbar.dart';
import '../../../shared/widgets/custom_data_table.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/pagination_bar.dart';

class [ScreenName]Screen extends ConsumerStatefulWidget {
  const [ScreenName]Screen({super.key});

  @override
  ConsumerState<[ScreenName]Screen> createState() => _[ScreenName]ScreenState();
}

class _[ScreenName]ScreenState extends ConsumerState<[ScreenName]Screen> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read([screenName]SearchProvider.notifier).state = query;
      ref.read([screenName]PageProvider.notifier).state = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch([screenName]Provider);

    return AdaptiveScaffold(
      title: '[الاسم العربي]',
      activeRoute: '/[route]',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // شريط الأدوات المحسّن
          ListToolbar(
            searchPlaceholder: 'ابحث عن [شيء]...',
            onSearchChanged: _onSearch,
            onAddPressed: () => _openCreateDialog(context),
            onRefreshPressed: () => ref.invalidate([screenName]Provider),
            onExportPressed: () => _exportData(),
            filterOptions: [
              FilterOption(label: 'الكل', value: ''),
              FilterOption(label: 'نشط', value: 'active'),
              FilterOption(label: 'معطل', value: 'inactive'),
            ],
            onFilterChanged: (status) {
              ref.read([screenName]FilterProvider.notifier).state = status;
              ref.read([screenName]PageProvider.notifier).state = 1;
            },
            showActionButtons: true,
            showAddButton: true,
            addButtonLabel: '[اسم جديد]',
            isCompact: Breakpoints.isMobile(context),
          ),
          const SizedBox(height: 16),

          // محتوى البيانات
          dataAsync.when(
            loading: () => const TableSkeleton(),
            error: (err, _) => _buildErrorState(),
            data: (data) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomDataTable(
                  title: '[الاسم] (${data.totalCount})',
                  columns: ['العمود 1', 'العمود 2', 'العمود 3', 'الإجراءات'],
                  rows: data.items.map((item) => _buildRow(item)).toList(),
                  showRowNumbers: true,
                  alternateRowColors: true,
                ),
                PaginationBar(
                  page: data.page,
                  pageSize: data.pageSize,
                  totalCount: data.totalCount,
                  onPageChanged: (p) => 
                    ref.read([screenName]PageProvider.notifier).state = p,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRow(Map<String, dynamic> item) => [
    Text(item['field1'] as String? ?? ''),
    Text(item['field2'] as String? ?? ''),
    Text(item['field3'] as String? ?? ''),
    Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 18),
          onPressed: () => _openEditDialog(context, item),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 18),
          onPressed: () => _deleteItem(item['id']),
        ),
      ],
    ),
  ];

  Widget _buildErrorState() => Container(
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      children: [
        Text('تعذّر تحميل البيانات',
          style: TextStyle(color: AppColors.danger, fontSize: 14)),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => ref.invalidate([screenName]Provider),
          child: const Text('إعادة المحاولة'),
        ),
      ],
    ),
  );

  void _openCreateDialog(BuildContext context) {
    // فتح حوار الإضافة
  }

  void _openEditDialog(BuildContext context, Map<String, dynamic> item) {
    // فتح حوار التعديل
  }

  void _deleteItem(String id) {
    // حذف العنصر
  }

  void _exportData() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري تصدير البيانات...')),
    );
  }
}
```

---

## 🧾 Invoices Screen - محسّن

```dart
// الاستيراد الإضافي المطلوب:
// import '../../../shared/widgets/list_toolbar.dart';
// import '../../../core/responsive/breakpoints.dart';

// في الـ build method:

ListToolbar(
  searchPlaceholder: 'ابحث برقم الفاتورة أو اسم العميل...',
  onSearchChanged: (query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(invoiceSearchProvider.notifier).state = query;
      ref.read(invoicesPageProvider.notifier).state = 1;
    });
  },
  onAddPressed: () {
    // فتح شاشة إنشاء فاتورة جديدة
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('الانتقال لإنشاء فاتورة جديدة...')),
    );
  },
  onRefreshPressed: () => ref.invalidate(invoicesProvider),
  onPrintPressed: () {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري تحضير الطباعة...')),
    );
  },
  onExportPressed: () {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري تصدير البيانات...')),
    );
  },
  filterOptions: [
    FilterOption(label: 'الكل', value: ''),
    FilterOption(label: 'معلقة', value: 'pending'),
    FilterOption(label: 'مكتملة', value: 'completed'),
    FilterOption(label: 'مسترجعة', value: 'refunded'),
    FilterOption(label: 'ملغاة', value: 'cancelled'),
  ],
  onFilterChanged: (status) {
    ref.read(invoiceStatusFilterProvider.notifier).state =
        status?.isEmpty ?? true ? null : status;
    ref.read(invoicesPageProvider.notifier).state = 1;
  },
  showActionButtons: true,
  showAddButton: true,
  addButtonLabel: 'فاتورة جديدة',
  isCompact: Breakpoints.isMobile(context),
)
```

---

## 📦 Inventory Screen - محسّن

### للتبويب الأول (الأصناف):

```dart
ListToolbar(
  searchPlaceholder: 'ابحث عن منتج بالاسم أو الكود...',
  onSearchChanged: (query) {
    ref.read(productSearchProvider.notifier).state = query;
  },
  onAddPressed: () => _openProductDialog(context),
  onRefreshPressed: () => ref.invalidate(productsInventoryProvider),
  onPrintPressed: () {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري تحضير الطباعة...')),
    );
  },
  onExportPressed: () {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري تصدير المنتجات...')),
    );
  },
  filterOptions: [
    FilterOption(label: 'الكل', value: ''),
    FilterOption(label: 'متوفر', value: 'available'),
    FilterOption(label: 'منخفض المخزون', value: 'low_stock'),
    FilterOption(label: 'منتهي الصلاحية', value: 'expired'),
    FilterOption(label: 'موقوف', value: 'suspended'),
  ],
  onFilterChanged: (status) {
    ref.read(productFilterProvider.notifier).state = status;
  },
  showActionButtons: true,
  showAddButton: true,
  addButtonLabel: 'منتج جديد',
  isCompact: Breakpoints.isMobile(context),
)
```

### للتبويب الثاني (الموردون):

```dart
ListToolbar(
  searchPlaceholder: 'ابحث عن مورد بالاسم أو الرقم...',
  onSearchChanged: (query) {
    ref.read(supplierSearchProvider.notifier).state = query;
  },
  onAddPressed: () => _openSupplierDialog(context),
  onRefreshPressed: () => ref.invalidate(suppliersProvider),
  filterOptions: [
    FilterOption(label: 'الكل', value: ''),
    FilterOption(label: 'نشط', value: 'active'),
    FilterOption(label: 'معطل', value: 'inactive'),
    FilterOption(label: 'لديه أوامر معلقة', value: 'has_pending'),
  ],
  onFilterChanged: (status) {
    ref.read(supplierFilterProvider.notifier).state = status;
  },
  showActionButtons: true,
  showAddButton: true,
  addButtonLabel: 'مورد جديد',
  isCompact: Breakpoints.isMobile(context),
)
```

---

## 👥 Customers Screen - محسّن

```dart
ListToolbar(
  searchPlaceholder: 'ابحث عن عميل برقم أو اسم أو بريد...',
  onSearchChanged: (query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(customerSearchProvider.notifier).state = query;
      ref.read(customersPageProvider.notifier).state = 1;
    });
  },
  onAddPressed: () => _openCustomerDialog(context),
  onRefreshPressed: () => ref.invalidate(customersProvider),
  onPrintPressed: () {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري تحضير الطباعة...')),
    );
  },
  onExportPressed: () {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري تصدير البيانات...')),
    );
  },
  filterOptions: [
    FilterOption(label: 'الكل', value: ''),
    FilterOption(label: 'نشط', value: 'active'),
    FilterOption(label: 'معطل', value: 'inactive'),
    FilterOption(label: 'له رصيد', value: 'has_balance'),
    FilterOption(label: 'VIP', value: 'vip'),
  ],
  onFilterChanged: (status) {
    ref.read(customerStatusFilterProvider.notifier).state = status;
    ref.read(customersPageProvider.notifier).state = 1;
  },
  showActionButtons: true,
  showAddButton: true,
  addButtonLabel: 'عميل جديد',
  isCompact: Breakpoints.isMobile(context),
)
```

---

## 💰 Expenses Screen - محسّن

```dart
ListToolbar(
  searchPlaceholder: 'ابحث عن مصروف...',
  onSearchChanged: (query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(expenseSearchProvider.notifier).state = query;
    });
  },
  onAddPressed: () => _openExpenseDialog(context),
  onRefreshPressed: () => ref.invalidate(expensesProvider),
  onExportPressed: () {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري تصدير البيانات...')),
    );
  },
  filterOptions: [
    FilterOption(label: 'الكل', value: ''),
    FilterOption(label: 'غذاء', value: 'food'),
    FilterOption(label: 'نقل', value: 'transport'),
    FilterOption(label: 'صيانة', value: 'maintenance'),
    FilterOption(label: 'رواتب', value: 'salaries'),
    FilterOption(label: 'ديون', value: 'debts'),
    FilterOption(label: 'أخرى', value: 'other'),
  ],
  onFilterChanged: (category) {
    ref.read(expenseCategoryFilterProvider.notifier).state = category;
  },
  showActionButtons: true,
  showAddButton: true,
  addButtonLabel: 'مصروف جديد',
  isCompact: Breakpoints.isMobile(context),
)
```

---

## 👨‍💼 Users Screen - محسّن

```dart
ListToolbar(
  searchPlaceholder: 'ابحث عن موظف برقم أو اسم...',
  onSearchChanged: (query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(userSearchProvider.notifier).state = query;
      ref.read(usersPageProvider.notifier).state = 1;
    });
  },
  onAddPressed: () => _openUserDialog(context),
  onRefreshPressed: () => ref.invalidate(usersProvider),
  filterOptions: [
    FilterOption(label: 'الكل', value: ''),
    FilterOption(label: 'مدير', value: 'admin'),
    FilterOption(label: 'موظف', value: 'employee'),
    FilterOption(label: 'مراقب', value: 'monitor'),
    FilterOption(label: 'كاشير', value: 'cashier'),
    FilterOption(label: 'معطل', value: 'disabled'),
  ],
  onFilterChanged: (role) {
    ref.read(userRoleFilterProvider.notifier).state = role;
    ref.read(usersPageProvider.notifier).state = 1;
  },
  showActionButtons: true,
  showAddButton: true,
  addButtonLabel: 'موظف جديد',
  isCompact: Breakpoints.isMobile(context),
)
```

---

## 📦 Purchasing Screen - محسّن

```dart
ListToolbar(
  searchPlaceholder: 'ابحث عن أمر شراء...',
  onSearchChanged: (query) {
    ref.read(poSearchProvider.notifier).state = query;
  },
  onAddPressed: () => _openPurchaseOrder(context),
  onRefreshPressed: () => ref.invalidate(purchaseOrdersProvider),
  onPrintPressed: () => _printPOs(),
  onExportPressed: () => _exportPOs(),
  filterOptions: [
    FilterOption(label: 'الكل', value: ''),
    FilterOption(label: 'معلق', value: 'pending'),
    FilterOption(label: 'مستقبل', value: 'received'),
    FilterOption(label: 'مرفوع', value: 'submitted'),
  ],
  onFilterChanged: (status) {
    ref.read(poStatusFilterProvider.notifier).state = status;
  },
  showActionButtons: true,
  showAddButton: true,
  addButtonLabel: 'أمر شراء جديد',
  isCompact: Breakpoints.isMobile(context),
)
```

---

## 💰 Payroll Screen - محسّن

```dart
ListToolbar(
  searchPlaceholder: 'ابحث عن موظف...',
  onSearchChanged: (query) {
    ref.read(payrollSearchProvider.notifier).state = query;
  },
  onAddPressed: () => _openPayrollDialog(context),
  onRefreshPressed: () => ref.invalidate(payrollProvider),
  onExportPressed: () => _exportPayroll(),
  filterOptions: [
    FilterOption(label: 'الكل', value: ''),
    FilterOption(label: 'مسموح', value: 'approved'),
    FilterOption(label: 'مرفوع', value: 'submitted'),
    FilterOption(label: 'معلق', value: 'pending'),
  ],
  onFilterChanged: (status) {
    ref.read(payrollStatusFilterProvider.notifier).state = status;
  },
  showActionButtons: true,
  showAddButton: true,
  addButtonLabel: 'راتب جديد',
  isCompact: Breakpoints.isMobile(context),
)
```

---

## 📊 Dashboard - محسّن مع StatsCard

```dart
// الاستيراد:
// import '../../../shared/widgets/stats_card.dart';

GridView.count(
  crossAxisCount: Breakpoints.isDesktop(context) ? 4 : 
                 (Breakpoints.isTablet(context) ? 2 : 1),
  mainAxisSpacing: 16,
  crossAxisSpacing: 16,
  mainAxisExtent: 168,
  children: [
    StatsCardPresets.sales(
      value: (sales['totalRevenue'] as num?) ?? 0,
      changePercent: 12.5,
      isPositive: true,
    ),
    StatsCardPresets.pendingOrders(
      value: (sales['pendingOrders'] as num?) ?? 0,
      changePercent: -5,
    ),
    StatsCardPresets.activeCustomers(
      value: (inventory['activeCustomers'] as num?) ?? 0,
      changePercent: 8,
    ),
    StatsCardPresets.products(
      value: (inventory['totalProducts'] as num?) ?? 0,
      changePercent: 3.2,
    ),
  ],
)
```

---

## 📈 خطة التطبيق السريع

### اليوم:
- [ ] Invoices Screen
- [ ] Inventory Screen

### غداً:
- [ ] Customers Screen
- [ ] Dashboard

### اليوم بعد الغد:
- [ ] Expenses Screen
- [ ] Users Screen

### الأسبوع القادم:
- [ ] Purchasing
- [ ] Payroll
- [ ] Accounting
- [ ] باقي الشاشات

---

## ✅ قائمة التحقق لكل شاشة

- [ ] أضفت الاستيراات المطلوبة
- [ ] نسخت ListToolbar
- [ ] عدلت searchPlaceholder و filterOptions
- [ ] ربطت Providers الخاصة
- [ ] اختبرت البحث
- [ ] اختبرت الفلاتر
- [ ] اختبرت على الهاتف
- [ ] اختبرت الوضع الليلي
- [ ] ✅ جاهز للدمج

---

**كل هذه القوالب جاهزة للاستخدام الفوري - انسخ والصق فقط!**

