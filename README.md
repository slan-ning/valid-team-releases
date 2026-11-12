# Valid Team for macOS (Official Releases)

**Valid Team** 是一款开箱即用的多智能体团队协作桌面客户端（macOS Universal Binary，原生支持 Apple Silicon `arm64` 与 Intel `x86_64`）。

> 🔒 **双仓安全架构说明**：本仓库（`slan-ning/valid-team-releases`）为官方公开安装包分发、OTA 自动热更新与纯净 macOS 虚拟机 E2E 验收仓库（不含业务源码与内部设计文档）。

---

## 📥 一键下载安装（Latest Release: `v1.0.0`）

- **macOS 拖拽安装包 (`ValidTeam.dmg`)**：  
  👉 [**直接下载 ValidTeam.dmg**](https://github.com/slan-ning/valid-team-releases/releases/latest/download/ValidTeam.dmg)
- **在线 OTA 热更清单 (`latest-macos.json`)**：  
  `https://github.com/slan-ning/valid-team-releases/releases/latest/download/latest-macos.json`
- **SHA-256 校验清单 (`SHA256SUMS.txt`)**：  
  `https://github.com/slan-ning/valid-team-releases/releases/latest/download/SHA256SUMS.txt`

### 安装步聚
1. 下载并双击打开 `ValidTeam.dmg`；
2. 将 **`Valid Team.app`** 拖入右侧 **`Applications`（应用程序）** 文件夹；
3. 从「应用程序」或 Spotlight 启动 `Valid Team` 即可直接开始使用（客户端内置零依赖原子 OTA 自动更新器）。

---

## 🔐 开发者签名、Apple 官方公证与完整性校验

所有官方发布的安装包均由 **Apple Developer ID Application (`J9ZH8HRHH9`)** 正式签名，并通过 **Apple 官方公证（Notarized Developer ID）与票据装订（Stapled Ticket）**，任何新 Mac 下载拖入 `/Applications` 均可零拦截直接打开：

```bash
# 校验 SHA-256 摘要
shasum -a 256 -c SHA256SUMS.txt

# 校验 Apple Developer ID 签名与公证票据装订 (Stapler & Gatekeeper)
codesign --verify --deep --strict --verbose=2 "/Applications/Valid Team.app"
xcrun stapler validate "/Applications/Valid Team.app"
spctl -a -t exec -vv "/Applications/Valid Team.app"
```
