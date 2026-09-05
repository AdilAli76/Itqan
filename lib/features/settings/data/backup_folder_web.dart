import 'dart:typed_data';

/// الويب لا مجلّدات فيه: المتصفّح لا يمنح التطبيق مساراً على القرص، والحفظ
/// يمرّ بنافذة التنزيل حتماً. فالميزة تُخفى هناك ولا تُعرَض معطَّلة — زرٌّ
/// رمادي بلا سبب مفهوم يولّد بلاغ دعم، والغياب لا يولّد شيئاً.
bool get supportsFolderSave => false;

Future<String> writeBackupFile(String folder, String fileName, Uint8List bytes) =>
    throw UnsupportedError('لا حفظ في مجلّد على الويب');

/// اسم المجلّد وحده للعرض — لا يُستدعى على الويب أصلاً.
String folderLabel(String path) => path;
