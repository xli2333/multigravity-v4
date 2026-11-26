# Multigravity v4 (Unofficial Custom Build)

[![Upstream](https://img.shields.io/badge/Upstream-GHSaiMo%2Fantigravity--mobile-2563EB?style=flat-square&logo=github)](https://github.com/GHSaiMo/antigravity-mobile)
[![License: MIT](https://img.shields.io/badge/License-MIT-10B981?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20Android%20%7C%20Web%20%7C%20Go-52525B?style=flat-square)](#)

> [!IMPORTANT]
> **上游项目致谢与非官方衍生声明（Upstream Attribution & Disclaimer）**
>
> - **上游出处**：本仓库是基于开源项目 **[GHSaiMo/antigravity-mobile (Multigravity)](https://github.com/GHSaiMo/antigravity-mobile)**（遵循 [MIT License](LICENSE)）进行的**个人 UI 重构与功能定制衍生版本**。
> - **诚挚致谢**：核心 Go 网关（`mgy`）、端到端加密传输协议（E2EE）、语言服务 RPC 桥接以及跨平台移动伴侣的基础架构均由原作者 **[@GHSaiMo](https://github.com/GHSaiMo)** 及上游贡献者设计与开源，特此致谢。
> - **官方渠道指路**：如果你需要 **官方稳定版、Apple App Store 正式版、TestFlight 公测或官方一键安装技术支持**，请直接访问上游官方仓库 **[GHSaiMo/antigravity-mobile](https://github.com/GHSaiMo/antigravity-mobile)** 或官方站点 **[mgy.jiuge.space](https://mgy.jiuge.space)**。
> - **问题反馈边界**：本仓库仅用于个人界面设计探索与自签构建测试，**与原作者及官方团队无隶属或代表关系**。因使用本衍生版本产生的任何问题，请勿前往上游仓库提交 Issue，以免给原作者增加额外维护负担。

---

## 本衍生版（v4）主要定制与改动

在保留上游网关与多端协议兼容性的基础上，本仓库主要围绕移动端交互体验与自用场景进行了以下定制修改：

### 1. v4 结构聚类与双轨视觉系统
- **四栏纯矢量信息架构**：将零散弹窗收敛为 `会话 (Sessions)` · `中枢 (Command Hub)` · `驾驶舱 (Cockpit)` · `连接 (System)` 四栏导航。
- **全域 0% Emoji 线性工程图标**：统一替换为线性 SVG 矢量图标，对齐 **Google Gemini 四芒星** 与 **Anthropic Claude 十二芒星** 官方矢量路径。
- **双主题光学对比度校准**：内置 **Antigravity 纯白**（`#FAFAFB` / `#FFFFFF`）与 **`claude cut` 黑曜深色**（`#16161A` / `#242629`，前景文字与填充色分轨提亮，满足 WCAG AAA 对比度）。

### 2. 对话工作台与配额驾驶舱增强
- **输入坞快捷能力常驻**：输入栏右侧常驻 `btw`（独立切片旁路快问，不污染主线上下文）、`Swarm`（`/swarm` 多智能体协同）与 `Goal` 胶囊。
- **双环配额表盘与自然倒计时**：支持 `5h` / `7d` 独立焦点切换、均速游标以及自然中文恢复倒计时（`X天Y小时后恢复` / `X小时Y分后恢复`）。
- **媒体与预览体验**：补齐全屏相册查看器、Windows `file:///c:/` 路径兼容归一，以及主机无关的图片/视频/文档持久化磁盘缓存与手动清理。

### 3. iOS 本机独立能力与系统扩展
- **免第三方推送保活与本地通知引擎**：支持在关闭外部 APNs 中转的自托管场景下，通过本机连接实现 1:1 本地通知、灵动岛实时活动推进与自动消警。
- **主屏幕「工作与额度」组合小组件**：新增支持 `4×2` 中号与 `4×4` 大号的合并桌面小组件，一屏展示实时双模型额度与最近工作进展，并支持动态解析重签后的 `embedded.mobileprovision` App Group 容器。
- **实验性 Apple Watch 伴侣端工程**：包含基于 `WatchConnectivity` 手机中转的 `MultigravityWatch` 与 `MultigravityWatchWidgets` 源码工程（需通过 Xcode 真机签名安装）。

---

## 构建与自用说明

### 1. 网关端（`mgy`）
本仓库客户端兼容上游 `mgy` 网关协议。可从源码自行编译网关：

```bash
go build -o mgy ./cmd/gateway
./mgy run -port 58900
```

> 若涉及敏感代码或私有环境，建议关闭外部推送中转（`APNS_ENABLED=0`）并搭配局域网、Tailscale 或自建隧道使用。

### 2. iOS 无签名包（GitHub Actions 自动构建）
本仓库通过 [.github/workflows/build_ios_ipa.yml](.github/workflows/build_ios_ipa.yml) 自动编译产出无签名测试包（发布于本仓库 [Releases](../../releases)），仅供个人自签或本地开发测试：
- `Multigravity-v4.0-ios-only-unsigned.ipa`：纯手机端 + 桌面小组件扩展（适用于常规个人证书自签工具导入安装）。
- `Multigravity-v4.0-unsigned.ipa`：完整包（额外内嵌 `MultigravityWatch.app` 手表端，需配合包含手表设备 UDID 的开发证书或 Mac Xcode 真机签名方可同步至 Apple Watch）。

---

## 开源协议与版权归属（License & Attribution）

本项目整体基于 **[MIT License](LICENSE)** 开源发布，完整保留上游项目的所有版权声明与许可条款，本仓库的新增与修改部分同样以 MIT 协议开放：

- **Upstream Repository**: [https://github.com/GHSaiMo/antigravity-mobile](https://github.com/GHSaiMo/antigravity-mobile)
- **Original Copyright**: `Copyright (c) 2026 Antigravity Mobile Contributors`
- **Modifications Copyright**: `Copyright (c) 2026 xli2333 (Modifications)`

### Attribution Notice (English)

> This repository (`xli2333/multigravity-v4`) is an **unofficial personal derivative work and UI redesign** based on **[GHSaiMo/antigravity-mobile (Multigravity)](https://github.com/GHSaiMo/antigravity-mobile)**, originally created by **[@GHSaiMo](https://github.com/GHSaiMo)** and contributors under the **[MIT License](LICENSE)**.
>
> All core gateway architecture, E2EE transport protocols, and foundational multi-platform client implementations credit the upstream project. For official releases, App Store / TestFlight builds, documentation, and upstream support, please visit **[github.com/GHSaiMo/antigravity-mobile](https://github.com/GHSaiMo/antigravity-mobile)**.
