import 'package:flutter_riverpod/flutter_riverpod.dart';

/// حسابات الاختبار المدمجة
final _demoCredentials = {
  'admin': 'admin123',
  'cashier': 'cashier123',
  'manager': 'manager123',
};

final _demoRoles = {
  'admin': 'ADMIN',
  'cashier': 'CASHIER',
  'manager': 'MANAGER',
};

/// محاولة الدخول بحساب اختبار
Future<Map<String, dynamic>?> tryDemoLogin(
  String username,
  String password,
) async {
  // تحقق من الحساب
  if (!_demoCredentials.containsKey(username)) {
    return null;
  }

  // تحقق من كلمة المرور
  if (_demoCredentials[username] != password) {
    return null;
  }

  // نجح الدخول
  return {
    'id': 'DEMO_${username.toUpperCase()}',
    'username': username,
    'fullName': _getFullName(username),
    'role': _demoRoles[username],
    'isLoggedIn': true,
  };
}

String _getFullName(String username) {
  switch (username) {
    case 'admin':
      return 'مدير النظام';
    case 'cashier':
      return 'أحمد الكاشير';
    case 'manager':
      return 'محمد المدير';
    default:
      return username;
  }
}

/// State للدخول
class DemoLoginState {
  final bool isLoading;
  final String? error;
  final String? username;
  final String? role;
  final bool isLoggedIn;

  const DemoLoginState({
    this.isLoading = false,
    this.error,
    this.username,
    this.role,
    this.isLoggedIn = false,
  });

  DemoLoginState copyWith({
    bool? isLoading,
    String? error,
    String? username,
    String? role,
    bool? isLoggedIn,
  }) {
    return DemoLoginState(
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      username: username ?? this.username,
      role: role ?? this.role,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
    );
  }
}

/// Notifier للدخول
class DemoLoginNotifier extends StateNotifier<DemoLoginState> {
  DemoLoginNotifier() : super(const DemoLoginState());

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await Future.delayed(const Duration(milliseconds: 500)); // محاكاة تأخير

      final result = await tryDemoLogin(username, password);

      if (result == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'اسم المستخدم أو كلمة المرور غير صحيحة',
        );
        return false;
      }

      state = DemoLoginState(
        isLoading: false,
        username: result['username'],
        role: result['role'],
        isLoggedIn: true,
      );

      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'حدث خطأ: $e',
      );
      return false;
    }
  }

  Future<void> logout() async {
    state = const DemoLoginState();
  }
}

/// Provider للدخول
final demoLoginProvider =
    StateNotifierProvider<DemoLoginNotifier, DemoLoginState>((ref) {
  return DemoLoginNotifier();
});

/// Provider لحالة تسجيل الدخول
final isLoggedInProvider = Provider<bool>((ref) {
  return ref.watch(demoLoginProvider).isLoggedIn;
});

/// Provider لاسم المستخدم الحالي
final currentUsernameProvider = Provider<String?>((ref) {
  return ref.watch(demoLoginProvider).username;
});

/// Provider لدور المستخدم
final currentRoleProvider = Provider<String?>((ref) {
  return ref.watch(demoLoginProvider).role;
});
