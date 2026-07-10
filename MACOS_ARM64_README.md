# MuseScore 3.6.2 macOS ARM64 构建说明

本仓库是统一的 MuseScore 3.6.2 跨平台源码树；其中 macOS 构建保留了原 ARM64 工程的 Apple Silicon 原生支持，并与 Windows、Linux 共用同一套源码。

## 包含内容

- MuseScore 3.6.2 源码、资源、thirdparty 代码和 CMake 构建文件
- 已适配 macOS ARM64 的 CMake/Makefile/打包脚本
- `scripts/setup_macos_arm64.sh`：安装 Homebrew 依赖
- `scripts/build_macos_arm64.sh`：编译并可选打包
- `scripts/xcode_macos_arm64.sh`：供 Xcode target 调用的 ARM64 构建包装脚本
- `scripts/package_macos_arm64.sh`：对已编译 app 打包/签名
- `scripts/verify_macos_arm64.sh`：校验 app 二进制架构
- `build_signed_dmg.sh`：根目录一键编译、签名 app、签名 DMG
- `MuseScoreARM64.xcodeproj`：可直接用 Xcode 打开的构建项目

不包含 `.git`、历史构建目录、CodeGraph 索引和旧 DMG/app 输出。

## 系统要求

- Apple Silicon Mac
- Xcode 或 Xcode Command Line Tools
- Homebrew
- `qt@5`、`cmake`、`pkgconf`、`jack`、`lame`、`libogg`、`libvorbis`、`flac`、`libsndfile`、`portaudio`

安装依赖：

```bash
cd /path/to/MuseScore-3.6.2
scripts/setup_macos_arm64.sh
```

## 用 Xcode 编译

打开项目：

```bash
open MuseScoreARM64.xcodeproj
```

在 Xcode 里选择 `MuseScore ARM64` scheme，然后按 `Cmd+B` 编译。该 target 会调用现有的 ARM64 CMake/Makefile 构建流程，产物仍然输出到：

- `applebuild/mscore.app`

需要生成 DMG 时，在 Xcode 左侧 target 列表选择 `Package DMG` 构建，或继续使用下面的命令行打包方式。需要清理 CMake 构建目录和 app 产物时，选择 `Clean Build` target。

说明：这里没有使用 CMake 的 `-G Xcode` 生成原生 CMake Xcode target。Xcode 26 的 new build system 会拒绝 MuseScore 3.6.2 旧 CMake/Qt `AUTOMOC` 生成图里的重复 custom command，所以本项目提供的是 Xcode 外部构建 target：能在 Xcode 中打开、编辑源码并启动 ARM64 编译，同时保持底层构建与已验证的命令行流程一致。

## 命令行编译

```bash
cd /path/to/MuseScore-3.6.2
scripts/build_macos_arm64.sh --skip-sign
```

产物：

- `applebuild/mscore.app`
- `applebuild/MuseScore-3.6.2.dmg`

只编译 app、不打 DMG：

```bash
scripts/build_macos_arm64.sh --skip-package
```

## 签名打包

一键编译并生成已签名 DMG：

```bash
./build_signed_dmg.sh --sign-identity "Developer ID Application: Your Name (TEAMID)"
```

先查看可用证书：

```bash
security find-identity -v -p codesigning
```

然后使用 Developer ID Application 证书：

```bash
scripts/build_macos_arm64.sh \
  --sign-identity "Developer ID Application: Your Name (TEAMID)"
```

如果 app 已经编译好，只重新打包签名：

```bash
scripts/package_macos_arm64.sh \
  --sign-identity "Developer ID Application: Your Name (TEAMID)"
```

## 公证

正式分发 DMG 还需要 Apple notarization：

```bash
xcrun notarytool submit applebuild/MuseScore-3.6.2.dmg \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password" \
  --wait

xcrun stapler staple applebuild/MuseScore-3.6.2.dmg
```

## 说明

命令行和 Xcode target 都使用 Xcode 提供的 AppleClang 工具链，并通过 CMake `Unix Makefiles` 构建。
