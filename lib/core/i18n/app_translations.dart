/// ترجمات التطبيق - العربية والإنجليزية
class AppTranslations {
  static const Map<String, Map<String, String>> translations = {
    // العربية
    'ar': {
      // العام
      'app_name': 'إتقان ERP',
      'settings': 'الإعدادات',
      'language': 'اللغة',
      'currency': 'العملة',
      'save': 'حفظ',
      'cancel': 'إلغاء',
      'delete': 'حذف',
      'edit': 'تعديل',
      'add': 'إضافة',
      'search': 'بحث',
      'close': 'إغلاق',
      'back': 'رجوع',
      'next': 'التالي',
      'previous': 'السابق',
      'loading': 'جاري التحميل...',
      'error': 'خطأ',
      'success': 'تم بنجاح',
      'confirm': 'تأكيد',
      'warning': 'تحذير',
      'info': 'معلومة',

      // الدخول والمصادقة
      'login': 'دخول',
      'logout': 'خروج',
      'email': 'البريد الإلكتروني',
      'password': 'كلمة المرور',
      'remember_me': 'تذكرني',
      'forgot_password': 'نسيت كلمة المرور؟',
      'sign_up': 'إنشاء حساب',
      'welcome': 'أهلاً وسهلاً',
      'enter_credentials': 'الرجاء إدخال بيانات الدخول',

      // نقطة البيع
      'pos': 'نقطة البيع',
      'sales': 'المبيعات',
      'cart': 'السلة',
      'total': 'الإجمالي',
      'subtotal': 'المجموع الجزئي',
      'tax': 'الضريبة',
      'discount': 'الخصم',
      'quantity': 'الكمية',
      'price': 'السعر',
      'product': 'المنتج',
      'products': 'المنتجات',
      'category': 'الفئة',
      'categories': 'الفئات',
      'checkout': 'الدفع',
      'payment': 'الدفع',
      'cash': 'نقداً',
      'card': 'بطاقة',
      'receipt': 'الإيصال',

      // الأرقام والمبيعات
      'dashboard': 'لوحة التحكم',
      'today_sales': 'مبيعات اليوم',
      'total_revenue': 'الإيراد الكلي',
      'transactions': 'المعاملات',
      'reports': 'التقارير',
      'analytics': 'التحليلات',
      'statistics': 'الإحصائيات',

      // المخزون
      'inventory': 'المخزون',
      'stock': 'المخزون',
      'add_product': 'إضافة منتج',
      'edit_product': 'تعديل منتج',
      'delete_product': 'حذف منتج',
      'product_name': 'اسم المنتج',
      'product_code': 'رمز المنتج',
      'barcode': 'الباركود',
      'quantity_on_hand': 'الكمية الحالية',
      'reorder_level': 'حد أعادة الطلب',
      'unit_cost': 'تكلفة الوحدة',
      'selling_price': 'سعر البيع',

      // العملاء والموردين
      'customers': 'العملاء',
      'customer': 'العميل',
      'suppliers': 'الموردين',
      'supplier': 'المورد',
      'name': 'الاسم',
      'phone': 'الهاتف',
      'address': 'العنوان',
      'city': 'المدينة',
      'country': 'الدولة',

      // الدعم والمساعدة
      'help': 'المساعدة',
      'support': 'الدعم',
      'about': 'حول',
      'contact_us': 'اتصل بنا',
      'terms': 'الشروط والأحكام',
      'privacy': 'سياسة الخصوصية',

      // الأخطاء
      'error_required_field': 'هذا الحقل مطلوب',
      'error_invalid_email': 'البريد الإلكتروني غير صحيح',
      'error_network': 'خطأ في الاتصال بالخادم',
      'error_unauthorized': 'غير مصرح لك بالدخول',
      'error_not_found': 'لم يتم العثور على المطلوب',
      'error_server': 'خطأ في الخادم',
    },

    // الإنجليزية
    'en': {
      // General
      'app_name': 'Kinetic ERP',
      'settings': 'Settings',
      'language': 'Language',
      'currency': 'Currency',
      'save': 'Save',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'edit': 'Edit',
      'add': 'Add',
      'search': 'Search',
      'close': 'Close',
      'back': 'Back',
      'next': 'Next',
      'previous': 'Previous',
      'loading': 'Loading...',
      'error': 'Error',
      'success': 'Success',
      'confirm': 'Confirm',
      'warning': 'Warning',
      'info': 'Information',

      // Login & Authentication
      'login': 'Login',
      'logout': 'Logout',
      'email': 'Email',
      'password': 'Password',
      'remember_me': 'Remember Me',
      'forgot_password': 'Forgot Password?',
      'sign_up': 'Sign Up',
      'welcome': 'Welcome',
      'enter_credentials': 'Please enter your credentials',

      // Point of Sale
      'pos': 'Point of Sale',
      'sales': 'Sales',
      'cart': 'Cart',
      'total': 'Total',
      'subtotal': 'Subtotal',
      'tax': 'Tax',
      'discount': 'Discount',
      'quantity': 'Quantity',
      'price': 'Price',
      'product': 'Product',
      'products': 'Products',
      'category': 'Category',
      'categories': 'Categories',
      'checkout': 'Checkout',
      'payment': 'Payment',
      'cash': 'Cash',
      'card': 'Card',
      'receipt': 'Receipt',

      // Numbers & Sales
      'dashboard': 'Dashboard',
      'today_sales': 'Today\'s Sales',
      'total_revenue': 'Total Revenue',
      'transactions': 'Transactions',
      'reports': 'Reports',
      'analytics': 'Analytics',
      'statistics': 'Statistics',

      // Inventory
      'inventory': 'Inventory',
      'stock': 'Stock',
      'add_product': 'Add Product',
      'edit_product': 'Edit Product',
      'delete_product': 'Delete Product',
      'product_name': 'Product Name',
      'product_code': 'Product Code',
      'barcode': 'Barcode',
      'quantity_on_hand': 'Quantity on Hand',
      'reorder_level': 'Reorder Level',
      'unit_cost': 'Unit Cost',
      'selling_price': 'Selling Price',

      // Customers & Suppliers
      'customers': 'Customers',
      'customer': 'Customer',
      'suppliers': 'Suppliers',
      'supplier': 'Supplier',
      'name': 'Name',
      'phone': 'Phone',
      'address': 'Address',
      'city': 'City',
      'country': 'Country',

      // Support & Help
      'help': 'Help',
      'support': 'Support',
      'about': 'About',
      'contact_us': 'Contact Us',
      'terms': 'Terms and Conditions',
      'privacy': 'Privacy Policy',

      // Errors
      'error_required_field': 'This field is required',
      'error_invalid_email': 'Invalid email address',
      'error_network': 'Network connection error',
      'error_unauthorized': 'Unauthorized access',
      'error_not_found': 'Not found',
      'error_server': 'Server error',
    },
  };

  /// الحصول على ترجمة
  static String translate(String key, String languageCode) {
    return translations[languageCode]?[key] ?? translations['en']?[key] ?? key;
  }

  /// جميع اللغات المتاحة
  static List<String> getAvailableLanguages() => translations.keys.toList();
}

/// Extension على String للترجمة السهلة
extension TranslationExtension on String {
  String tr(String languageCode) => AppTranslations.translate(this, languageCode);
}
