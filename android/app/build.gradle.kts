import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeyFile = rootProject.file("key.properties")
val releaseKeys = Properties().apply {
    if (releaseKeyFile.isFile) releaseKeyFile.inputStream().use { load(it) }
}
val readerPreview = providers.gradleProperty("wenkuReaderPreview").orNull == "true"

android {
    namespace = "org.mewx.wenku8_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Keep the published package identity stable across releases.
        applicationId = "legado.wenku"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["wenkuAppLabel"] = "文库阅读"
        // AGP otherwise builds upstream desktop utilities too, including the
        // DRM tool whose encryption code is intentionally disabled in this app.
        externalNativeBuild.cmake.targets.addAll(listOf("mobi", "wenku_mobi"))
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    if (releaseKeyFile.isFile) {
        signingConfigs.create("distribution") {
            keyAlias = releaseKeys.getProperty("keyAlias")
            keyPassword = releaseKeys.getProperty("keyPassword")
            storeFile = rootProject.file(requireNotNull(releaseKeys.getProperty("storeFile")))
            storePassword = releaseKeys.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            proguardFile(file("document-import.pro"))
            if (readerPreview) {
                applicationIdSuffix = ".reader_preview"
            }
            // Local previews remain install-compatible. Public distributions
            // use an owner's untracked key.properties, never an embedded key.
            signingConfig = signingConfigs.getByName(
                if (releaseKeyFile.isFile && !readerPreview) "distribution" else "debug"
            )
        }
    }

    // Match native document import libraries to the selected Flutter targets.
    val targets = project.findProperty("target-platform")?.toString()
    if (targets != null && project.findProperty("split-per-abi")?.toString()?.toBoolean() != true) {
        val targetAbis = targets.split(",").map { platform ->
            when (platform) {
                "android-arm" -> "armeabi-v7a"
                "android-arm64" -> "arm64-v8a"
                "android-x64" -> "x86_64"
                else -> error("Unsupported Flutter target platform: $platform")
            }
        }
        buildTypes.configureEach {
            ndk.abiFilters.clear()
            ndk.abiFilters.addAll(targetAbis)
        }
    }

    packaging {
        // GitHub 分发的是独立 APK，压缩原生库可显著降低下载体积；
        // 安装时会解压到应用目录，安装后占用会相应增加。
        jniLibs {
            useLegacyPackaging = true
        }
        resources {
            // 阅读器只用 PDFBox 的常规加密与 POI 的 Word 读取路径，剔除
            // 未启用的抗量子算法参数表和演示文稿/表格资源。
            excludes += setOf(
                "org/bouncycastle/pqc/**",
                "org/apache/poi/sl/**",
                "org/apache/poi/hslf/**",
                "org/apache/poi/ss/**",
                // hutool-core 与 hutool-crypto 各自带一份 INDEX.LIST，打包时只需保留其一。
                "META-INF/INDEX.LIST"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.webkit:webkit:1.17.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    testImplementation("org.json:json:20250517")
    implementation("org.apache.poi:poi-scratchpad:5.5.1")
    implementation("com.github.albfernandez:juniversalchardet:2.0.4")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs_nio:2.1.5")
    implementation("org.jsoup:jsoup:1.23.2")
    implementation("org.commonmark:commonmark:0.30.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.jayway.jsonpath:json-path:2.9.0")
    implementation("org.mozilla:rhino:1.8.1")
    // 书源 java.unrarFile / un7zFile / getRarByteArrayContent 等接口依赖
    // libarchive；版本与上游 Legado 保持一致。
    implementation("me.zhanghai.android.libarchive:library:1.1.6")
    // 书源 jsLib 会通过 Packages.cn.hutool.* 直接调用，需保留在 classpath；
    // 版本与上游 Legado 基线一致，避免书源脚本兼容性回归。
    implementation("cn.hutool:hutool-crypto:5.8.22")
    implementation("com.tom-roush:pdfbox-android:2.0.27.0")
    // Keep the media host classes available to the app's shared-engine wiring.
    implementation("androidx.media:media:1.7.0")
}
