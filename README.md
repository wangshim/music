# 音频分析助手（Audio Analyzer App）

Flutter 跨平台（Android / iOS）本地音频分析应用，支持**离线中文语音转写（ASR）**与**音频分析结果展示**（BPM / 调性为占位，待接入真实分析引擎）。

> 项目定位：本地自用工具，优先保证"选音频 → 分析 → 看结果"链路简单可用；非技术人员可直接安装 APK 使用。

## 文档导航

| 文档 | 内容 |
|---|---|
| [01-项目简介与功能清单.md](./docs/01-项目简介与功能清单.md) | 项目简介、功能清单（已实现 / 规划中）、每个功能的实现位置与涉及文件 |
| [02-环境要求与构建安装.md](./docs/02-环境要求与构建安装.md) | 开发环境要求、构建 APK、安装到手机的方法与常见问题 |
| [03-模型说明.md](./docs/03-模型说明.md) | ASR 模型说明、下载来源、打包位置与体积说明 |

## 快速开始

```bash
# 1. 准备 Flutter 环境（见 docs/02）
# 2. 进入项目
cd F:\audio_analyzer_app

# 3. 安装依赖
flutter pub get

# 4. 构建 release APK（按 ABI 拆分，推荐 arm64-v8a 包）
flutter build apk --release --split-per-abi

# 5. 安装到已连接手机
adb install -r build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
```

> 模型文件已随仓库分发（约 24MB，见 docs/03），克隆后无需额外下载即可构建。
