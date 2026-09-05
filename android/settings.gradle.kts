pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            val localProps = file("local.properties")
            // `flutter build` 가 만들어 주는 파일이라 깨끗한 체크아웃에는 없다.
            // 없을 때 여기서 죽지 않고 환경 변수를 보게 한다.
            require(localProps.exists() || System.getenv("FLUTTER_ROOT") != null) {
                "local.properties 가 없습니다. `flutter build` 로 빌드하거나 FLUTTER_ROOT 를 설정하세요."
            }
            if (localProps.exists()) localProps.inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk") ?: System.getenv("FLUTTER_ROOT")
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
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    // google-services.json → Firebase 리소스 생성. 이게 없으면 파일이 있어도
    // 아무 일도 일어나지 않아 FCM 이 조용히 죽는다.
    id("com.google.gms.google-services") version "4.4.4" apply false
}

include(":app")
