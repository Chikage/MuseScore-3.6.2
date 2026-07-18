# MuseScore 3.6.2 跨平台构建指南

本源码树基于 MuseScore 3.6.2，并合并同级 Linux、macOS 项目中保留的
MuseScore 4.7 Backport。

## 保留的 Backport

- 支持读取最高 MSC 470 的 MuseScore 4 谱面归档
- 支持 `score_style.mss`、`chordlist.xml` 和 `audiosettings.json`
- 安装 MS Basic SoundFont，并保留 FluidSynth 兼容修改
- 插件 `FileIO` 二进制读写辅助函数
- MuseScore 4 元素、连接线、和弦及旧谱面读取兼容修改
- 跨谱表 Ottava 和文本线布局修复
- macOS Apple Silicon 支持
- Linux AppImage 打包修复

## 根目录脚本

| 脚本 | 用途 |
| --- | --- |
| `build-linux.sh` | Linux x86_64/arm64 编译及 AppImage、DEB、TBZ2 打包 |
| `build-macos.sh` | macOS arm64/x86_64 编译、安装及本地 ad-hoc 签名 |
| `build-windows.bat` | Windows 日常一键构建入口 |
| `build_signed_dmg.sh` | macOS ARM64 正式签名及 DMG 打包 |
| `msvc_build.bat` | Windows 底层高级构建、安装、打包和清理脚本 |

## Linux：`build-linux.sh`

### 基本用法

```bash
./build-linux.sh [options]
```

无参数时构建当前主机架构，并在 `build.artifacts/linux` 下生成 TBZ2。

### 命令行参数

| 参数 | 可用值及说明 | 默认值 |
| --- | --- | --- |
| `-a LIST`, `--arch LIST` | 架构列表。支持 `host`、`all`、`x86_64`、`amd64`、`arm64`、`aarch64`；多个架构可用逗号分隔 | `host` |
| `-f LIST`, `--format LIST` | 输出格式。支持 `all`、`appimage`、`deb`、`tbz2`、`tar.bz2`；多个格式可用逗号分隔 | `tbz2` |
| `--deb` | 等价于 `--format deb` | 关闭 |
| `--docker` | 强制使用 Docker 构建 | 自动判断 |
| `--no-docker` | 在当前 Linux 系统直接构建 | 自动判断 |
| `--inside-container` | Docker 容器内部调用参数，不建议手动使用 | 关闭 |
| `--skip-deps` | 不自动安装 apt 构建依赖 | 关闭 |
| `--clean` | 构建前删除所选构建目录 | 关闭 |
| `--jobs N` | 并行编译任务数 | 主机 CPU 数或 `--docker-cpus` |
| `--ubuntu-image IMG` | Docker 基础镜像 | `ubuntu:20.04` |
| `--docker-builder-image IMG` | 指定并复用预装依赖的 Docker builder 镜像 | 自动命名 |
| `--no-docker-builder-image` | 禁用可复用 builder 镜像，每次在基础镜像中安装依赖 | 关闭 |
| `--rebuild-docker-builder-image` | 不使用 Docker layer cache，重新构建 builder 镜像 | 关闭 |
| `--docker-cpus N` | Docker 可使用的 CPU 数，例如 `8` | 不限制 |
| `--docker-memory SIZE` | Docker 内存限制，例如 `24g` | 不限制 |
| `--docker-memory-swap SIZE` | Docker 内存与 swap 总限制，例如 `32g` 或 `-1`；必须同时设置 `--docker-memory` | 不限制 |
| `--artifacts-dir DIR` | 输出文件目录 | `build.artifacts/linux` |
| `-h`, `--help` | 显示帮助并退出 | - |

### 环境变量

命令行参数优先于对应环境变量。

| 环境变量 | 说明 | 默认值 |
| --- | --- | --- |
| `ARCHES` | 等价于 `--arch` | `host` |
| `FORMATS` | 等价于 `--format` | `tbz2` |
| `SOURCE_DIR` | 源码根目录 | 当前仓库 |
| `ARTIFACTS_DIR` | 输出目录 | `build.artifacts/linux` |
| `USE_DOCKER` | `auto`、`1` 或 `0` | `auto` |
| `UBUNTU_IMAGE` | Docker 基础镜像 | `ubuntu:20.04` |
| `USE_DOCKER_BUILDER_IMAGE` | `1` 使用可复用 builder 镜像，`0` 禁用 | `1` |
| `DOCKER_BUILDER_IMAGE` | 自定义 builder 镜像名称 | 自动生成 |
| `DOCKER_REBUILD_BUILDER_IMAGE` | `1` 强制重建 builder 镜像 | `0` |
| `DOCKER_CPUS` | Docker CPU 限制 | 空 |
| `DOCKER_MEMORY` | Docker 内存限制 | 空 |
| `DOCKER_MEMORY_SWAP` | Docker 内存与 swap 总限制 | 空 |
| `INSTALL_DEPS` | `1` 安装依赖，`0` 跳过 | `1` |
| `CLEAN` | `1` 在构建前清理 | `0` |
| `JOBS` | 并行任务数 | 自动检测 |
| `BUILD_NUMBER` | 传给 CMake 和软件包的构建号 | `0` |
| `MUSESCORE_BUILD_CONFIG` | MuseScore 构建配置标识 | `release` |
| `MUSESCORE_REVISION` | 自定义版本修订字符串 | 空 |
| `TELEMETRY_TRACK_ID` | Telemetry Track ID | 空，禁用 Telemetry |
| `BUILD_LAME` | 启用 MP3/LAME 支持 | `ON` |
| `BUILD_PULSEAUDIO` | 启用 PulseAudio | `ON` |
| `BUILD_JACK` | 启用 JACK | `ON` |
| `BUILD_ALSA` | 启用 ALSA | `ON` |
| `BUILD_PORTAUDIO` | 启用 PortAudio | `ON` |
| `BUILD_PORTMIDI` | 启用 PortMidi | `ON` |
| `BUILD_WEBENGINE` | 启用 Qt WebEngine；目标环境缺失时可设为 `OFF` | `ON` |
| `BUILD_PCH` | 启用预编译头 | `OFF` |
| `USE_SYSTEM_FREETYPE` | 使用系统 FreeType | `ON` |
| `DOWNLOAD_SOUNDFONT` | 允许 CMake 更新内置 SoundFont | `OFF` |
| `USE_ZITA_REVERB` | 启用 Zita Reverb | `ON` |

### 示例

```bash
# 当前架构，生成 TBZ2
./build-linux.sh

# 同时构建 x86_64 和 arm64，并生成全部格式
./build-linux.sh --arch all --format all

# 使用 Docker，限制为 8 CPU / 24 GB 内存
./build-linux.sh --docker --docker-cpus 8 --docker-memory 24g

# 在本机直接构建 DEB，不安装依赖
./build-linux.sh --no-docker --deb --skip-deps

# 禁用 WebEngine 和 PCH
BUILD_WEBENGINE=OFF BUILD_PCH=OFF ./build-linux.sh
```

### 产物位置

构建完成后脚本会打印完整的产物摘要，并在输出目录中生成两个固定入口：

- 原始产物仍按架构和格式放在 `build.artifacts/linux/<arch>/appimage` 或
  `build.artifacts/linux/<arch>/package`
- `build.artifacts/linux/latest/` 保存指向本次可用产物的快捷链接，文件名带有
  架构和格式前缀，便于直接打开目录查找
- `build.artifacts/linux/manifest.txt` 记录每个 AppImage、DEB、TBZ2 的完整路径和大小

如果使用 `--artifacts-dir DIR` 或 `ARTIFACTS_DIR=DIR`，上述 `latest/` 和
`manifest.txt` 会生成在该自定义目录下；Docker 模式也会把该目录挂入容器作为统一输出目录。

### AppImage 运行时 FUSE 依赖

部分 Ubuntu 版本默认只安装 FUSE3，直接运行 AppImage 时可能提示缺少
`libfuse.so.2`。构建脚本会在实体机和 Docker builder 镜像中自动安装兼容包：
能找到 `libfuse2` 时安装 `libfuse2`，否则安装 `libfuse2t64`。

AppImage 的外层 runtime 必须在挂载 SquashFS 之前加载 FUSE，因此把
`libfuse.so.2` 放进 AppImage 本身不能改变标准 `.AppImage` 在缺少系统 FUSE
时的首次启动行为。现在每个 AppImage 同时包含两项兼容措施：

- AppDir 内含 `libfuse.so.2`，解包运行时不再依赖构建机的 FUSE 库；
- 旁边生成同名的 `.AppImage.run` 启动器。它检测到系统没有 FUSE 时自动解包
  并执行 `AppRun`，不需要安装系统包。

如果是在最终用户机器上运行已经生成的 AppImage，可手动安装：

```bash
# Ubuntu 20.04 / 22.04 / 23.10 等
sudo apt install libfuse2

# Ubuntu 24.04 及使用 t64 包名的版本
sudo apt install libfuse2t64
```

不能安装系统包时，推荐运行构建产物旁边的无 FUSE 启动器：

```bash
./MuseScore-*.AppImage.run
```

也可以直接使用 AppImage runtime 的环境变量绕过 FUSE 挂载：

```bash
APPIMAGE_EXTRACT_AND_RUN=1 ./MuseScore-*.AppImage
```

## macOS：`build-macos.sh`

### 基本用法

```bash
./build-macos.sh [options]
```

无参数时构建当前主机架构的 Release 版本，安装到
`build.artifacts/macos/<arch>/release/mscore.app`，并执行 ad-hoc 签名。

### 命令行参数

| 参数 | 可用值及说明 | 默认值 |
| --- | --- | --- |
| `--arch ARCH` | `host`、`arm64`、`x86_64`；同时接受别名 `aarch64` 和 `amd64` | `host` |
| `--debug` | 构建 Debug，而不是 Release | 关闭 |
| `--clean` | 删除当前架构和配置对应的构建、安装目录 | 关闭 |
| `--jobs N` | 并行编译任务数 | macOS 逻辑 CPU 数 |
| `--build-dir DIR` | 自定义 CMake 构建目录 | `build.macos-<arch>-<configuration>` |
| `--install-prefix DIR` | 自定义安装目录 | `build.artifacts/macos/<arch>/<configuration>` |
| `--deployment-target VER` | 设置 `CMAKE_OSX_DEPLOYMENT_TARGET` | arm64 为 `11.0`；x86_64 为 `10.10` |
| `--skip-sign` | 不对安装后的 `.app` 执行 ad-hoc 签名 | 关闭 |
| `-h`, `--help` | 显示帮助并退出 | - |

### 环境变量

| 环境变量 | 说明 | 默认值 |
| --- | --- | --- |
| `QT_PREFIX` | Qt 5 安装前缀，例如 `$(brew --prefix qt@5)` | 自动查找 Homebrew `qt@5` |
| `OSX_ARCHITECTURES` | 默认构建架构 | `uname -m` |
| `MUSESCORE_CONFIGURATION` | `release` 或 `debug` | `release` |
| `OSX_DEPLOYMENT_TARGET` | 默认 macOS Deployment Target | 按架构自动选择 |
| `OSX_SYSROOT` | macOS SDK 路径 | `xcrun --sdk macosx --show-sdk-path` |
| `JOBS` | 并行编译任务数 | 逻辑 CPU 数 |
| `CMAKE_PREFIX_PATH` | 额外 CMake 包搜索路径；脚本会自动追加 `QT_PREFIX` | 空 |

### 示例

```bash
# 当前 Mac 架构的 Release
./build-macos.sh

# Apple Silicon Release
./build-macos.sh --arch arm64

# Intel Debug，清理后重新构建
./build-macos.sh --arch x86_64 --debug --clean

# 自定义构建和安装目录
./build-macos.sh \
  --build-dir /tmp/musescore-build \
  --install-prefix /tmp/musescore-install

# 指定 Qt 和 Deployment Target
QT_PREFIX="$(brew --prefix qt@5)" \
  ./build-macos.sh --deployment-target 12.0
```

## Windows：`build-windows.bat`

### 基本用法

```bat
build-windows.bat [MODE] [ARCH]
```

该脚本是 `msvc_build.bat` 的简化入口。无参数时执行 64 位 Release 构建。

### 位置参数

| 位置 | 可用值及说明 | 默认值 |
| --- | --- | --- |
| `MODE` | `release`、`debug`、`relwithdebinfo`、`install`、`installdebug`、`installrelwithdebinfo`、`package`、`revision`、`clean`；包装脚本额外支持 `all` | `release` |
| `ARCH` | `64` 或 `32` | `64` |

`all` 会先执行 `release`，成功后再执行 `install`。它不会构建 Debug 或安装包。

### 示例

```bat
REM 64 位 Release
build-windows.bat

REM 64 位 Debug
build-windows.bat debug 64

REM 32 位 RelWithDebInfo
build-windows.bat relwithdebinfo 32

REM 构建并安装 64 位 Release
build-windows.bat all 64

REM 清理 msvc.* 和便携版目录
build-windows.bat clean
```

## Windows 高级脚本：`msvc_build.bat`

### 基本用法

```bat
msvc_build.bat MODE [ARCH] [BUILD_NUMBER]
```

脚本自动优先检测 Visual Studio 2022，然后依次尝试 2019 和 2017。要求安装
Desktop development with C++ 工作负载。

### 位置参数

| 位置 | 可用值及说明 | 默认值 |
| --- | --- | --- |
| `MODE` | 见下表 | 必填 |
| `ARCH` | `64` 或 `32` | `64` |
| `BUILD_NUMBER` | CI/自动更新使用的构建号；提供后会启用 `BUILD_AUTOUPDATE` | 空 |

### MODE

| MODE | 作用 |
| --- | --- |
| `release` | 构建 Release |
| `debug` | 构建 Debug |
| `relwithdebinfo` | 构建带大部分调试符号的优化版本 |
| `install` | 安装已经构建的 Release |
| `installdebug` | 安装已经构建的 Debug |
| `installrelwithdebinfo` | 安装已经构建的 RelWithDebInfo |
| `package` | 从已经构建和安装的 Release 创建 MSI |
| `revision` | 将当前短 Git revision 写入 `local_build_revision.env` |
| `clean` | 删除 `msvc.*` 和 `MuseScorePortable` 目录 |

### 环境变量

| 环境变量 | 说明 | 默认值 |
| --- | --- | --- |
| `GENERATOR_NAME` | 手动指定 CMake Visual Studio Generator；为空时自动检测 | 自动检测 |
| `BUILD_WIN_PORTABLE` | 设为 `ON` 时生成 PortableApps 目录结构 | 关闭 |
| `MUSESCORE_BUILD_CONFIG` | MuseScore 构建配置标识 | `dev` |
| `MUSESCORE_REVISION` | 自定义版本修订字符串 | 空 |
| `MSCORE_STABLE_BUILD` | 非空时启用稳定版专用配置判断 | 空 |
| `CRASH_LOG_SERVER_URL` | 稳定版 Crash Reporter 地址 | 空 |
| `TELEMETRY_TRACK_ID` | Telemetry Track ID | 空 |

### 示例

```bat
REM 带调试信息的 64 位构建
msvc_build.bat relwithdebinfo 64

REM 安装 32 位 Debug
msvc_build.bat installdebug 32

REM 生成 64 位 MSI
msvc_build.bat package 64

REM 生成 PortableApps 版本
set BUILD_WIN_PORTABLE=ON
msvc_build.bat release 64
msvc_build.bat install 64
```

## macOS 签名 DMG：`build_signed_dmg.sh`

### 基本用法

```bash
./build_signed_dmg.sh [options]
```

该脚本固定构建 ARM64，签名 `.app` 和最终 DMG。正式公开分发建议使用
`Developer ID Application` 证书，并在生成后继续执行 Apple notarization。

### 命令行参数

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `--sign-identity NAME` | 指定 codesign 证书名称；别名 `--sign_identity` 同样可用 | 自动依次查找 Developer ID、Apple Distribution、Apple Development |
| `--version VERSION` | DMG 包版本 | `3.6.2` |
| `--jobs N` | 并行编译任务数 | 逻辑 CPU 数 |
| `--clean` | 删除 `build.release` 和 `applebuild` 后重新构建 | 关闭 |
| `-h`, `--help` | 显示帮助并退出 | - |

### 环境变量

| 环境变量 | 说明 | 默认值 |
| --- | --- | --- |
| `MACOS_CODESIGN_IDENTITY` | 等价于 `--sign-identity` | 自动检测 |
| `MUSESCORE_PACKAGE_VERSION` | 等价于 `--version` | `3.6.2` |
| `OSX_DEPLOYMENT_TARGET` | ARM64 Deployment Target | `11.0` |

### 示例

```bash
# 自动选择签名证书
./build_signed_dmg.sh

# 指定 Developer ID 并清理重构建
./build_signed_dmg.sh --clean \
  --sign-identity "Developer ID Application: Your Name (TEAMID)"

# 自定义版本和并行数
./build_signed_dmg.sh --version 3.6.2-backport.1 --jobs 8
```

生成文件：

```text
applebuild/mscore.app
applebuild/MuseScore-<VERSION>.dmg
```
