pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // ── AGP 8.x عمداً لا 9 ────────────────────────────────────────────────
    //
    // AGP 9 (وهو افتراضي قالب Flutter 3.44) يمنع الإضافات من تطبيق
    // org.jetbrains.kotlin.android بنفسها ويتولّى التصريف داخلياً. وأكثر
    // إضافات Flutter لم تلحق بعد: مع `builtInKotlin=false` لا تُصرَّف
    // مصادر Kotlin لبعضها إطلاقاً (package_info_plus)، ومع `true` تفشل
    // أخرى فوراً لأنها تطبّق الإضافة صراحةً (audioplayers). لا إعداد واحد
    // يُرضي الطرفين.
    //
    // فالتثبيت على 8.11.1 حيث تعمل المنظومة كلها. ويُراجَع حين تلحق
    // الإضافات — ملاحقتها إضافةً إضافةً معركة لا تنتهي في نظام يُباع.
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
