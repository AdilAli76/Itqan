# 🔧 Providers و Helper Functions - جاهزة للاستخدام

---

## 📝 Providers Template لأي شاشة

```dart
// في ملف providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';

// ===== State Providers =====

final [screenName]SearchProvider = StateProvider<String>((ref) => '');
final [screenName]PageProvider = StateProvider<int>((ref) => 1);
final [screenName]FilterProvider = StateProvider<String?>((ref) => null);

// ===== Async Providers =====

final [screenName]Provider = FutureProvider.autoDispose((ref) async {
  final search = ref.watch([screenName]SearchProvider);
  final page = ref.watch([screenName]PageProvider);
  final filter = ref.watch([screenName]FilterProvider);

  final params = {
    'search': search,
    'page': page,
    'filter': filter,
    'pageSize': 20,
  };

  final response = await ApiClient.instance.dio.get(
    '/[endpoint]',
    queryParameters: params,
  );
  
  return response.data; // تحويل إلى نموذج
});

// ===== تفاصيل العنصر =====

final [screenName]DetailProvider = 
  FutureProvider.autoDispose.family((ref, String id) async {
  final response = await ApiClient.instance.dio.get('/[endpoint]/$id');
  return response.data;
});
```

---

## 🎨 Helper Class للألوان والحالات

```dart
// في ملف helpers.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class StatusHelper {
  /// احصل على لون الحالة
  static Color getStatusColor(String status) {
    return AppColors.getStatusColor(status);
  }

  /// احصل على خلفية الحالة
  static Color getStatusBackground(String status) {
    return AppColors.getStatusBackgroundColor(status);
  }

  /// بناء Chip للحالة
  static Widget buildStatusChip(String status) {
    final color = getStatusColor(status);
    final bgColor = getStatusBackground(status);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// احصل على أيقونة الحالة
  static IconData getStatusIcon(String status) {
    return switch (status.toLowerCase()) {
      'completed' || 'مكتملة' => Icons.check_circle_outline,
      'pending' || 'معلقة' => Icons.schedule_outlined,
      'rejected' || 'مرفوضة' => Icons.cancel_outlined,
      'active' || 'نشط' => Icons.check_circle_outline,
      'inactive' || 'معطل' => Icons.block_outlined,
      _ => Icons.info_outline,
    };
  }
}

/// Helper لصيغة الأرقام
class FormatHelper {
  static String currency(double amount) {
    final format = NumberFormat('#,##0.00', 'en');
    return format.format(amount);
  }

  static String integer(int number) {
    final format = NumberFormat('#,##0', 'en');
    return format.format(number);
  }

  static String date(DateTime? date) {
    if (date == null) return '-';
    return DateFormat('yyyy-MM-dd').format(date);
  }

  static String dateTime(DateTime? date) {
    if (date == null) return '-';
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  }
}

/// Helper لـ API errors
class ApiErrorHelper {
  static String getErrorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
      
      return switch (error.type) {
        DioExceptionType.connectionTimeout => 'انقطع الاتصال',
        DioExceptionType.sendTimeout => 'انقطع الاتصال',
        DioExceptionType.receiveTimeout => 'انقطع الاتصال',
        DioExceptionType.badResponse => 'خطأ من الخادم',
        _ => 'حدث خطأ غير متوقع',
      };
    }
    return 'حدث خطأ غير متوقع';
  }
}
```

---

## 🧪 Model Classes لـ API Responses

```dart
// في ملف models.dart

class PaginatedResponse<T> {
  final List<T> items;
  final int totalCount;
  final int page;
  final int pageSize;
  final int totalPages;

  PaginatedResponse({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    return PaginatedResponse(
      items: (json['items'] as List).map((e) => fromJsonT(e)).toList(),
      totalCount: json['totalCount'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      pageSize: json['pageSize'] as int? ?? 20,
      totalPages: json['totalPages'] as int? ?? 1,
    );
  }
}

class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? message;
  final String? error;

  ApiResponse({
    required this.success,
    this.data,
    this.message,
    this.error,
  });

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>)? fromJsonT,
  ) {
    return ApiResponse(
      success: json['success'] as bool? ?? false,
      data: fromJsonT != null && json['data'] != null
          ? fromJsonT(json['data'] as Map<String, dynamic>)
          : null,
      message: json['message'] as String?,
      error: json['error'] as String?,
    );
  }
}
```

---

## 🎪 Dialog Helper

```dart
// في ملف dialog_helper.dart

class DialogHelper {
  /// عرض رسالة تأكيد
  static Future<bool> showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    String positiveLabel = 'نعم',
    String negativeLabel = 'لا',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(negativeLabel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(positiveLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// عرض رسالة خطأ
  static void showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('خطأ'),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  /// عرض رسالة نجاح
  static void showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// عرض رسالة تحذير
  static void showWarningSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.warning,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
```

---

## 🔄 Debounce Helper

```dart
// في ملف debounce_helper.dart

import 'dart:async';

class DebounceHelper {
  static Timer? _debounce;

  /// تنفيذ دالة مع تأخير (debounce)
  static void run(
    Function() callback, {
    Duration duration = const Duration(milliseconds: 350),
  }) {
    _debounce?.cancel();
    _debounce = Timer(duration, callback);
  }

  /// الإلغاء
  static void cancel() {
    _debounce?.cancel();
  }
}

// الاستخدام:
// DebounceHelper.run(
//   () => ref.read(searchProvider.notifier).state = query,
//   duration: const Duration(milliseconds: 350),
// );
```

---

## 📋 Form Validator Helper

```dart
// في ملف validators.dart

class FormValidators {
  static String? validateRequired(String? value) {
    if (value == null || value.isEmpty) {
      return 'هذا الحقل مطلوب';
    }
    return null;
  }

  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'البريد الإلكتروني مطلوب';
    }
    
    final regex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!regex.hasMatch(value)) {
      return 'البريد الإلكتروني غير صحيح';
    }
    return null;
  }

  static String? validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'رقم الهاتف مطلوب';
    }
    
    if (!value.contains(RegExp(r'[0-9]'))) {
      return 'رقم الهاتف غير صحيح';
    }
    return null;
  }

  static String? validateMinLength(String? value, int min) {
    if (value == null || value.length < min) {
      return 'يجب أن يكون الطول $min أحرف على الأقل';
    }
    return null;
  }

  static String? validateAmount(String? value) {
    if (value == null || value.isEmpty) {
      return 'المبلغ مطلوب';
    }
    
    final amount = double.tryParse(value);
    if (amount == null || amount <= 0) {
      return 'المبلغ يجب أن يكون أكبر من صفر';
    }
    return null;
  }
}
```

---

## 🎯 Export Helper - Snippet جاهز

```dart
// في ملف export_helper.dart

class ExportHelper {
  /// تصدير إلى Excel (محاكاة)
  static Future<void> exportToExcel(
    List<List<dynamic>> data, {
    required String fileName,
  }) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('جاري تصدير $fileName...'),
        duration: const Duration(seconds: 2),
      ),
    );
    
    // يمكن استخدام مكتبة excel مثل excel أو csv
    // مثال:
    // final excel = Excel.createExcel();
    // excel.appendRow(data[0]);
    // ...
  }

  /// تصدير إلى PDF
  static Future<void> exportToPdf(
    List<List<String>> data, {
    required String fileName,
  }) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('جاري تصدير $fileName...'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// طباعة البيانات
  static Future<void> print(
    List<List<String>> data, {
    required String title,
  }) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('جاري تحضير الطباعة...'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
```

---

## 🛠️ استخدام جميع الـ Helpers

### مثال عملي في شاشة:

```dart
class MyScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends ConsumerState<MyScreen> {
  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(myProvider);

    return Scaffold(
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) {
          // استخدم ApiErrorHelper
          final message = ApiErrorHelper.getErrorMessage(err);
          DialogHelper.showErrorDialog(context, message);
          return const SizedBox();
        },
        data: (data) => CustomDataTable(
          columns: ['الحالة', 'المبلغ', 'التاريخ'],
          rows: data.map((item) => [
            // استخدم StatusHelper
            StatusHelper.buildStatusChip(item['status']),
            // استخدم FormatHelper
            Text(FormatHelper.currency(item['amount'])),
            Text(FormatHelper.date(DateTime.parse(item['date']))),
          ]).toList(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          // استخدم DialogHelper للتأكيد
          final confirm = await DialogHelper.showConfirmDialog(
            context,
            title: 'تأكيد',
            message: 'هل تريد حفظ التغييرات؟',
          );
          
          if (confirm) {
            DialogHelper.showSuccessSnackBar(
              context,
              'تم الحفظ بنجاح',
            );
            ref.invalidate(myProvider);
          }
        },
        label: const Text('حفظ'),
        icon: const Icon(Icons.save),
      ),
    );
  }
}
```

---

## ✅ قائمة الاستخدام السريع

- [ ] انسخ Providers Template
- [ ] عدّل endpoint والحقول
- [ ] استخدم StatusHelper للحالات
- [ ] استخدم FormatHelper للأرقام والتواريخ
- [ ] استخدم DialogHelper للـ dialogs
- [ ] استخدم FormValidators للتحقق من الفرم
- [ ] استخدم ApiErrorHelper لمعالجة الأخطاء
- [ ] استخدم ExportHelper للتصدير

---

**جميع الـ Helpers جاهزة للاستخدام الفوري - نسخ والصق فقط!**

