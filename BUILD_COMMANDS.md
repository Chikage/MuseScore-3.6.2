# MuseScore 3.6.2 三端编译命令示例

本文给出当前源码树在 Windows、Linux 和 macOS 上的常用编译命令。命令均以
源码根目录为当前目录；`<N>` 表示并行任务数，可按 CPU 核数调整。

完整参数说明和 CI/签名流程请参阅 [BUILDING.md](BUILDING.md)。本文优先使用仓库
根目录的构建脚本；旧版 `Makefile` 入口只作为本地开发的补充。

## 快速对照

| 平台 | 推荐入口 | 默认/示例产物 |
| --- | --- | --- |
| Linux | `./build-linux.sh --no-docker --format tbz2 --jobs <N>` | `build.artifacts/linux/` 下的 TBZ2；也可生成 AppImage、DEB |
| macOS | `./build-macos.sh --jobs <N>` | `build.artifacts/macos/<arch>/release/mscore.app` |
| Windows | `build-windows.bat release 64` | `msvc.build_x64`；安装后位于 `msvc.install_x64` |

## 通用准备

1. 获取源码并进入根目录：

   ```bash
   git clone <仓库地址> MuseScore-3.6.2
   cd MuseScore-3.6.2
   ```

2. 项目使用 Qt 5（最低 5.8）和 CMake（最低 3.5），还需要对应平台的 C/C++
   编译器、`make`/MSBuild 及 Git。各平台脚本会继续检查 `qmake`、CMake 和其余
   平台工具。

3. 切换架构或 Debug/Release 配置时，建议使用脚本的 `--clean`（Windows 使用
   `build-windows.bat clean`），避免旧的 CMake 缓存带入新配置。

## Linux

### 环境

`build-linux.sh` 支持 x86_64 和 arm64。Debian/Ubuntu 主机可以让脚本通过 `apt`
自动安装依赖；如果依赖已经准备好，可加 `--skip-deps`。也可以使用 Docker，脚本
默认使用 `ubuntu:20.04` 构建环境。

### Release 和打包

```bash
cd /path/to/MuseScore-3.6.2
chmod +x build-linux.sh

# 当前主机架构，生成 TBZ2（会按需安装 Debian/Ubuntu 依赖）
./build-linux.sh --no-docker --format tbz2 --jobs 8

# 依赖已经安装时，跳过 apt；生成 AppImage 和 DEB
./build-linux.sh --no-docker --skip-deps \
  --arch x86_64 --format appimage,deb --jobs 8

# 使用 Docker 同时构建 x86_64/arm64 的全部格式
./build-linux.sh --docker --arch all --format all \
  --docker-cpus 8 --docker-memory 24g
```

常用开关：

```bash
# 目标发行版没有 Qt WebEngine 时关闭 WebEngine，并清理后重建
BUILD_WEBENGINE=OFF ./build-linux.sh --no-docker --clean

# 将产物写入自定义目录
./build-linux.sh --artifacts-dir /tmp/musescore-artifacts
```

产物会放在 `build.artifacts/linux/<arch>/appimage` 或
`build.artifacts/linux/<arch>/package`；`latest/` 和 `manifest.txt` 便于查找本次
构建结果。运行 AppImage 时若提示缺少 `libfuse.so.2`，在 Ubuntu 上安装
`libfuse2`（Ubuntu 24.04 也可能使用 `libfuse2t64`），或临时使用：

```bash
APPIMAGE_EXTRACT_AND_RUN=1 ./build.artifacts/linux/latest/*.AppImage
```

### 本地快速编译

只需要开发版可执行文件时仍可使用传统 Makefile：

```bash
make release
./build.release/mscore/mscore

make debug
./build.debug/mscore/mscore

# 安装到默认前缀（需要管理员权限）
sudo make install

# 清理旧的 Release/Debug 构建目录
make clean
```

## macOS

### 环境

先安装 Xcode 或 Command Line Tools、Homebrew，以及 Qt 5 和 CMake。Apple Silicon
可以直接执行仓库提供的依赖脚本：

```bash
cd /path/to/MuseScore-3.6.2
scripts/setup_macos_arm64.sh
```

该脚本会安装 `cmake`、`qt@5`、`pkgconf`、音频库和打包工具。Intel Mac 也可以用
Homebrew 手动安装同名依赖。

### Release/Debug 编译

```bash
# 当前 Mac 架构的 Release；默认执行本地 ad-hoc 签名
./build-macos.sh --jobs 8

# Apple Silicon Release
./build-macos.sh --arch arm64 --jobs 8

# Intel Debug，清理后重建
./build-macos.sh --arch x86_64 --debug --clean --jobs 8

# 显式指定 Qt 5 和最低部署版本
QT_PREFIX="$(brew --prefix qt@5)" \
  ./build-macos.sh --deployment-target 12.0
```

默认安装结果为
`build.artifacts/macos/<arch>/<configuration>/mscore.app`，可以直接打开：

```bash
open build.artifacts/macos/arm64/release/mscore.app
```

临时跳过本地签名：

```bash
./build-macos.sh --skip-sign
```

### Apple Silicon app/DMG

需要使用专用 ARM64 流程时：

```bash
# 只生成 app，不生成 DMG（脚本仍会为本地启动执行 ad-hoc 签名）
scripts/build_macos_arm64.sh --skip-package

# 默认生成 app 和 DMG；正式发布时指定 Developer ID
scripts/build_macos_arm64.sh \
  --sign-identity "Developer ID Application: Your Name (TEAMID)"
```

对应产物为 `applebuild/mscore.app` 和
`applebuild/MuseScore-3.6.2.dmg`。正式发布前还需要按 Apple 要求完成公证；本地
调试不应把示例证书名称当作真实签名身份。

## Windows

### 环境

请安装 Visual Studio 2017 或更高版本（脚本会自动尝试检测已安装版本），并勾选
`Desktop development with C++` 和 Windows SDK；同时安装 CMake、Git 以及与目标
架构匹配的 Qt 5 MSVC kit。建议在 `cmd.exe` 或 Visual Studio Developer Command
Prompt 中执行 `.bat` 命令。

如果使用 Visual Studio 2026 generator，脚本要求 CMake 4.2 或更高版本；其他版本
可使用 Visual Studio 自带或 PATH 中兼容的 CMake。

如果 Qt 不在 `PATH`，可显式指定 Qt 根目录（目录下应有 `bin\qmake.exe`）：

```bat
set "QT_PATH=C:\Qt\5.15.2\msvc2019_64"
```

注意：当前源码树不携带 `dependencies` 目录。完整的 MSVC 功能构建还需要与目标
架构匹配的第三方依赖包，至少应能提供 `dependencies/include`、
`dependencies/libx64` 或 `dependencies/libx86` 中的头文件和库（例如 LAME、
PortAudio、Vorbis、zlib）。仓库中的 `build/ci/windows/setup.bat` 展示了 CI 使用的
依赖归档准备流程；请使用项目认可的依赖归档，不要把临时下载目录直接提交到源码。

### 日常构建

```bat
cd /d C:\src\MuseScore-3.6.2

REM 64 位 Release（默认模式）
build-windows.bat release 64

REM 64 位 Debug
build-windows.bat debug 64

REM 32 位 RelWithDebInfo
build-windows.bat relwithdebinfo 32

REM 构建 Release 并安装到 msvc.install_x64
build-windows.bat all 64

REM 清理 msvc.* 和便携版目录
build-windows.bat clean
```

`build-windows.bat` 是简化入口，底层由 `msvc_build.bat` 调用 CMake 和 MSBuild。
默认构建目录为 `msvc.build_x64`（32 位为 `msvc.build_x86`），安装目录为
`msvc.install_x64` 或 `msvc.install_x86`。

完成 `install` 后可直接运行安装树中的程序：

```bat
msvc.install_x64\bin\mscore.exe
```

### 安装、MSI 和 Portable

`package` 使用 CPack 的 WiX generator；如果要生成 MSI，还需安装 WiX Toolset
v3.11，并让它位于脚本期望的 `C:\Program Files\WiX Toolset v3.11`。仅编译或执行
`install` 不需要 WiX。

```bat
REM 分步构建和安装 64 位 Release
msvc_build.bat release 64
msvc_build.bat install 64

REM 安装已经构建好的 Debug
msvc_build.bat installdebug 64

REM 从已安装内容生成 MSI
msvc_build.bat package 64

REM 生成 PortableApps 目录结构
set "BUILD_WIN_PORTABLE=ON"
msvc_build.bat release 64
msvc_build.bat install 64
```

构建号可作为第三个参数传入，例如 `msvc_build.bat release 64 123`。脚本会自动
通过 `vswhere` 定位 Visual Studio，并检查 CMake generator、`cl.exe`、MSBuild 和
Qt kit；出现架构不匹配时，应改用对应的 `msvc*_64` 或 `msvc*` Qt 安装。

## 常见问题

| 现象 | 处理方式 |
| --- | --- |
| `qmake was not found` / 找不到 Qt | Linux 检查 `qmake -query`；macOS 设置 `QT_PREFIX`；Windows 设置 `QT_PATH`，并确认使用 Qt 5 MSVC kit |
| 修改架构或配置后结果异常 | Linux/macOS 加 `--clean`；Windows 执行 `build-windows.bat clean` 后重新构建 |
| Linux AppImage 无法启动 | 安装 `libfuse2`/`libfuse2t64`，或使用 `APPIMAGE_EXTRACT_AND_RUN=1` |
| macOS 启动时报签名错误 | 本地构建保留默认 ad-hoc 签名；必要时不要删除签名步骤，或仅用 `--skip-sign` 做无签名调试 |
| Windows 找不到 generator | 更新 CMake，或设置 `GENERATOR_NAME`/`VS_INSTALL_PATH` 后重试 |

更多参数、环境变量、CI 和正式发布签名流程见 [BUILDING.md](BUILDING.md)；macOS
ARM64 的 Xcode 流程见 [MACOS_ARM64_README.md](MACOS_ARM64_README.md)。
