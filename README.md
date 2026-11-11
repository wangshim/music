---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 5c96509d255f4e87c60df81df97919d9_9c00b0059c6e11f1b930525400e6dd8f
    ReservedCode1: z7jrq2atgiT398lxMbzhswzblmY/eCMDnHErTxxzLMNK/Vp2w8TYsXUUtI9yANH3L/KUw3sttGkhOxRxfQV60xkSBhZ0M7D+5DosHtFWK2NuOpQiXFonYGEBrriyMedMEypsYQKXkn4N0KYa1HGrP53dJuHyG+gOTkTvK/5dNf0LRNHBDe7cZdTGbgA=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 5c96509d255f4e87c60df81df97919d9_9c00b0059c6e11f1b930525400e6dd8f
    ReservedCode2: z7jrq2atgiT398lxMbzhswzblmY/eCMDnHErTxxzLMNK/Vp2w8TYsXUUtI9yANH3L/KUw3sttGkhOxRxfQV60xkSBhZ0M7D+5DosHtFWK2NuOpQiXFonYGEBrriyMedMEypsYQKXkn4N0KYa1HGrP53dJuHyG+gOTkTvK/5dNf0LRNHBDe7cZdTGbgA=
---

# 音频分析助手（Audio Analyzer App）

Flutter 跨平台（Android / iOS）本地音频工具，支持**导入音频直接识别纯文本歌词**（识曲 + 在线歌词匹配，不展示歌曲信息），识曲失败时自动回退**离线中文语音转写（ASR）**。

> 项目定位：本地自用工具，优先保证"选音频 → 识别歌词 → 复制/查看"链路简单可用；非技术人员可直接安装 APK 使用。

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

> ASR 模型（SenseVoice-Small int8，约 228MB）超过 GitHub 单文件 100MB 限制，**未随仓库分发**，克隆后请按 [docs/03-模型说明.md](docs/03-模型说明.md) 下载放到 `assets/models/` 对应目录后再构建。
*（内容由AI生成，仅供参考）*
