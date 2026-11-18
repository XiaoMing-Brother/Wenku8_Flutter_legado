# 源码快照与安装包

使用应用请下载 [GitHub Releases](https://github.com/mikufoxxx/Wenku8_Flutter/releases/latest) 中适合设备的安装包。Android 使用签名 APK，iOS 与 HarmonyOS 的未签名包需自行签名。

本仓库是部分实现的参考快照，保留了一些未提供模块的引用，不能独立构建或复现正式安装包。GitHub 自动生成的 Source code ZIP／tar.gz 是此快照的压缩文件，不是安装包。发行版功能以实际安装包及发布说明为准。

## 个人仓库发布

默认更新仓库为 `XiaoMing-Brother/Wenku8_Flutter`。需要在编译时覆盖时传入
`--dart-define=UPDATE_REPOSITORY=owner/repo`；该值是编译期常量，修改后必须重新构建。
自定义仓库必须公开，并且不会使用旧镜像，客户端会直接访问 GitHub API。

版本号采用 `主版本.次版本.修订号.YYMMDD.HHmm`，例如 `0.5.7.261118.1610`。
`pubspec.yaml` 仍需保留 Flutter 可解析的 `主版本.次版本.修订号+构建号`，
构建号必须小于 `2100000000`。构建时用 `--build-name` 写入完整版本名，确保
APK 的 `versionName` 与 Release Tag 一致：

```sh
flutter build apk --release --split-per-abi \
  --build-name=0.5.7.261118.1610 \
  --build-number=2026111816 \
  --dart-define=UPDATE_REPOSITORY=XiaoMing-Brother/Wenku8_Flutter
```

Release Tag 使用 `v<完整版本>`，附件上传到该 Release，不能使用外部下载链接。
Android 附件命名必须为 `wenku8-<完整版本>-<abi>.apk`，支持的 ABI 为
`arm64-v8a`、`armeabi-v7a`、`x86_64`，另可提供 `universal`。附件大小不能超过
300 MB；APK 的包名、`versionName`、`versionCode` 和签名必须与已安装版本兼容。

## 文件检查

```sh
python3 tools/check_public_source.py
```

该检查验证公开文件清单及已识别的敏感内容，不是 Flutter 编译或运行验证。公开 CI 只执行此检查，不创建、删除或更新 Release 和安装包。

## 许可

保留 LICENSE、NOTICE、assets/licenses/ 和第三方组件的声明。公开文件仍遵循对应许可；部分参考快照不等同于正式二进制的完整对应源码。
