# Flutter نفسه يتعامل مع كوده عبر AOT، هذه القواعد للمكتبات الأصلية (native) فقط.

# printing / pdf — تعتمد على PdfDocument و PrintManager عبر الانعكاس
-keep class net.nfet.flutter.printing.** { *; }

# flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# SignalR (signalr_netcore) يستخدم Gson/الانعكاس على أسماء الحقول
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }

# إبقاء أسماء الاستثناءات مفهومة في تقارير الأعطال
-keepattributes SourceFile,LineNumberTable
