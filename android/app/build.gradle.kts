import java.util.Properties

plugins {
    id("com.android.application")
    // Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // google-services.json 을 읽어 Firebase 리소스를 만든다.
    //
    // **이게 없으면 파일이 있어도 아무 일도 일어나지 않는다.** 그동안
    // Firebase.initializeApp() 이 던지는 예외를 main.dart 의 try/catch 가 삼켜서,
    // 푸시는 조용히 죽어 있는데 앱은 멀쩡히 떴다.
    id("com.google.gms.google-services")
}

/**
 * 릴리스 서명 정보.
 *
 * `android/key.properties` 는 저장소에 넣지 않는다(.gitignore). 없으면 디버그
 * 키로 서명하고, 그건 개발용으로만 쓴다 — 스토어에 올릴 빌드는 반드시 이 파일이
 * 있어야 한다. 아래 buildTypes 에서 그 사실을 빌드 로그로 알린다.
 */
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

/**
 * 카카오 네이티브 앱 키를 매니페스트로 넘긴다.
 *
 * 카카오 로그인은 `kakao{네이티브키}://oauth` 로 돌아오는데, 그 스킴은 앱이
 * 매니페스트에 직접 선언해야 한다(SDK 가 대신 해 주지 않는다). 그동안 이게
 * 없어서 **안드로이드에서 카카오 로그인이 콜백을 받지 못했다** — 지금까지
 * 통과한 로그인이 전부 개발용 GUEST 였던 이유다.
 *
 * 값은 앱이 쓰는 것과 같은 `dart_defines.json` 에서 읽는다. 키를 두 곳에 적으면
 * 반드시 갈라진다. CI 처럼 그 파일이 없는 곳에서는 환경 변수로 준다.
 */
fun kakaoNativeAppKey(): String {
    val fromEnv = System.getenv("KAKAO_NATIVE_APP_KEY")
    if (!fromEnv.isNullOrBlank()) return fromEnv

    val defines = rootProject.file("../dart_defines.json")
    if (defines.exists()) {
        @Suppress("UNCHECKED_CAST")
        val parsed = groovy.json.JsonSlurper().parse(defines) as? Map<String, Any?>
        val key = parsed?.get("KAKAO_NATIVE_APP_KEY") as? String
        if (!key.isNullOrBlank()) return key
    }

    // 빈 값이어도 빌드는 된다. 카카오 로그인만 동작하지 않는다 —
    // 키 하나 때문에 빌드 전체를 막는 것보다 낫다.
    logger.warn("[로컬 퀘스트] KAKAO_NATIVE_APP_KEY 를 찾지 못했습니다. 카카오 로그인이 동작하지 않습니다.")
    return ""
}

android {
    namespace = "com.team.local_quest"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.team.local_quest"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        manifestPlaceholders["kakaoNativeAppKey"] = kakaoNativeAppKey()
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // 디버그 키로 서명된 빌드는 스토어가 받지 않는다.
                logger.warn(
                    "[로컬 퀘스트] android/key.properties 가 없어 디버그 키로 서명합니다. " +
                    "스토어 제출용 빌드가 아닙니다."
                )
                signingConfigs.getByName("debug")
            }

            // 코드 축소와 난독화.
            //
            // 릴리스에서만 켠다. 리플렉션으로 접근하는 클래스가 지워지면
            // 런타임에야 드러나므로, proguard-rules.pro 에 유지 규칙을 적어 뒀다.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
