/// نظير [readInstalledServer] على الويب — لا ملفّ تنفيذي ولا قرص.
///
/// الويب يشتقّ عنوانه من أصل الصفحة (راجع ApiClient.resolvedBaseUrl)، فلا
/// معنى لملفٍّ بجواره.
String? readInstalledServer() => null;
