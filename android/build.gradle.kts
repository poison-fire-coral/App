allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// kakao_map_plugin 등 일부 플러그인이 compileSdk 35로 고정돼 있어,
// compileSdk 36을 요구하는 webview_flutter_android와 AAR 메타데이터 검사에서 충돌한다.
// 모든 안드로이드 서브프로젝트의 compileSdk를 앱과 동일한 36으로 맞춘다.
// 주의: 아래 evaluationDependsOn(":app") 보다 반드시 먼저 등록되어야 한다.
val forcedCompileSdk = 36

fun Project.alignCompileSdk() {
    val androidExt = extensions.findByName("android") ?: return
    runCatching {
        val setter =
            androidExt.javaClass.methods.firstOrNull {
                it.name == "setCompileSdk" && it.parameterTypes.size == 1
            }
        if (setter != null) {
            setter.invoke(androidExt, forcedCompileSdk)
        } else {
            androidExt.javaClass.methods
                .firstOrNull {
                    it.name == "compileSdkVersion" &&
                        it.parameterTypes.size == 1 &&
                        it.parameterTypes[0] == Int::class.javaPrimitiveType
                }
                ?.invoke(androidExt, forcedCompileSdk)
        }
    }
}

subprojects {
    if (state.executed) {
        alignCompileSdk()
    } else {
        afterEvaluate { alignCompileSdk() }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
