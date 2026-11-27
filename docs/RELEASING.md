# 源码快照与安装包

使用应用请下载 [GitHub Releases](https://github.com/XiaoMing-Brother/Wenku8_Flutter_legado/releases/latest) 中适合设备的安装包。Android 使用签名 APK，iOS 与 HarmonyOS 的未签名包需自行签名。

本仓库是部分实现的参考快照，保留了一些未提供模块的引用，不能独立构建或复现正式安装包。GitHub 自动生成的 Source code ZIP／tar.gz 是此快照的压缩文件，不是安装包。发行版功能以实际安装包及发布说明为准。

## 个人仓库发布

默认更新仓库为 `XiaoMing-Brother/Wenku8_Flutter_legado`。需要在编译时覆盖时传入
`--dart-define=UPDATE_REPOSITORY=owner/repo`；该值是编译期常量，修改后必须重新构建。
自定义仓库必须公开，并且不会使用旧镜像，客户端会直接访问 GitHub API。

版本号采用 `主版本.次版本.修订号.YYMMDD.HHmm`，例如 `0.5.7.261118.1707`。
`pubspec.yaml` 仍需保留 Flutter 可解析的 `主版本.次版本.修订号+构建号`，
构建号必须小于 `2100000000`。构建时用 `--build-name` 写入完整版本名，确保
APK 的 `versionName` 与 Release Tag 一致：

```sh
flutter build apk --release --split-per-abi \
  --target-platform=android-arm64 \
  --split-debug-info=build/symbols/0.5.7.261118.1707 \
  --build-name=0.5.7.261118.1707 \
  --build-number=2026111817 \
  --dart-define=UPDATE_REPOSITORY=XiaoMing-Brother/Wenku8_Flutter_legado
```

`--split-debug-info` 会剥离 Dart AOT 调试信息并生成
`build/symbols/<完整版本>/app.android-arm64.symbols`，用于还原崩溃栈；
该符号文件单独归档，不要打进 APK。

`--build-number` 使用 `pubspec.yaml` 和 `currentAppBuild` 的基数；
`--split-per-abi` 会为 arm64 产物追加 ABI 偏移，最终 `versionCode`
以 `aapt dump badging` 的输出为准，不要把偏移后的值写回构建号。

Release Tag 使用 `v<完整版本>`，附件上传到该 Release，不能使用外部下载链接。
Android 默认只构建 `arm64-v8a`，将输出文件
`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` 重命名为
`legado-wenku8-<完整版本>-arm64-v8a.apk` 后上传。只有明确需要老款 32 位设备、
模拟器或通用包时，才额外构建 `armeabi-v7a`、`x86_64` 或 `universal`。
附件大小不能超过 300 MB；APK 的包名、`versionName`、`versionCode` 和签名
必须与已安装版本兼容。

原生库在 `android/app/build.gradle.kts` 中通过
`packaging.jniLibs.useLegacyPackaging = true` 压缩，以减小 GitHub 下载体积；
安装时 Android 会解压这些 `.so`，因此安装后占用会高于压缩前的 APK。

客户端只接受 `legado-wenku8-` 附件前缀。仍在识别旧 `wenku8-` 前缀的
旧版客户端无法通过应用内更新获取本版，需要手动安装一次新版，后续版本
即可继续自动更新。

七猫段评的签名密钥只在构建时通过
`--dart-define-from-file=<本地密钥文件>` 注入 `QIMAO_REVIEW_SECRET`，
不得写入仓库；未提供时该来源的段评会自动跳过，不影响正文阅读。

Android 的 `applicationId` 固定为 `legado.wenku`，Kotlin 源码命名空间仍为
`org.mewx.wenku8_flutter`。从旧的 `org.mewx.wenku8_flutter.source_preview`
迁移时属于独立应用，需要先备份数据再手动安装；之后才能通过应用内更新覆盖升级。

## 文件检查

```sh
python3 tools/check_public_source.py
```

该检查验证公开文件清单及已识别的敏感内容，不是 Flutter 编译或运行验证。公开 CI 只执行此检查，不创建、删除或更新 Release 和安装包。

## 许可

保留 LICENSE、NOTICE、assets/licenses/ 和第三方组件的声明。公开文件仍遵循对应许可；部分参考快照不等同于正式二进制的完整对应源码。
