/// معالج أخطاء الطباعة.
///
/// يصنف الأخطاء ويوفر رسائل مفيدة للمستخدم والنظام.
class PrintErrorHandler {
  final String errorMessage;
  final PrintErrorType type;
  final Exception? originalException;

  PrintErrorHandler({
    required this.errorMessage,
    required this.type,
    this.originalException,
  });

  /// الرسالة المناسبة لعرضها على المستخدم (بالعربية).
  String get userMessage => switch (type) {
    PrintErrorType.noPrinter => 'لا توجد طابعة متصلة. تحقق من توصيل الطابعة.',
    PrintErrorType.printerOffline => 'الطابعة غير متصلة. تأكد من تشغيلها.',
    PrintErrorType.paperJam => 'الورق عالق في الطابعة.',
    PrintErrorType.lowPaper => 'الورق ناقص في الطابعة.',
    PrintErrorType.printerError => 'خطأ في الطابعة. جرب إعادة تشغيلها.',
    PrintErrorType.networkError => 'خطأ في الاتصال الشبكي. تحقق من الإنترنت.',
    PrintErrorType.networkTimeout => 'انقطع الاتصال بالخادم. حاول لاحقاً.',
    PrintErrorType.templateNotFound => 'لم يتم تحميل قالب الإيصال. حاول مجدداً.',
    PrintErrorType.logoNotFound => 'لم يتم تحميل الشعار. سيتم الطباعة بدونه.',
    PrintErrorType.unknown => 'خطأ في الطباعة: $errorMessage',
  };

  /// هل هذا الخطأ قابلٌ للإعادة؟ (أم أنه خطأ دائمي).
  bool get isRetryable => switch (type) {
    PrintErrorType.networkError || PrintErrorType.networkTimeout || PrintErrorType.printerOffline => true,
    _ => false,
  };

  /// هل يجب إبلاغ المستخدم عن هذا الخطأ؟
  bool get shouldNotifyUser => type != PrintErrorType.logoNotFound;

  @override
  String toString() => 'PrintError[$type]: $errorMessage';
}

enum PrintErrorType {
  noPrinter,
  printerOffline,
  paperJam,
  lowPaper,
  printerError,
  networkError,
  networkTimeout,
  templateNotFound,
  logoNotFound,
  unknown,
}

/// تصنيف الخطأ بناءً على رسالة الاستثناء.
PrintErrorHandler classifyError(Exception exception) {
  final message = exception.toString().toLowerCase();

  if (message.contains('timeout')) {
    return PrintErrorHandler(
      errorMessage: exception.toString(),
      type: PrintErrorType.networkTimeout,
      originalException: exception,
    );
  }
  if (message.contains('socket') || message.contains('connection failed')) {
    return PrintErrorHandler(
      errorMessage: exception.toString(),
      type: PrintErrorType.networkError,
      originalException: exception,
    );
  }
  if (message.contains('no printer')) {
    return PrintErrorHandler(
      errorMessage: exception.toString(),
      type: PrintErrorType.noPrinter,
      originalException: exception,
    );
  }
  if (message.contains('offline')) {
    return PrintErrorHandler(
      errorMessage: exception.toString(),
      type: PrintErrorType.printerOffline,
      originalException: exception,
    );
  }

  return PrintErrorHandler(
    errorMessage: exception.toString(),
    type: PrintErrorType.unknown,
    originalException: exception,
  );
}
