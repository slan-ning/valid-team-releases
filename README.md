# Valid Team (Official Releases — macOS & Linux)

**Valid Team** 是一款开箱即用的本地多智能体团队协作工作台，原生提供 **macOS 桌面客户端（Universal Binary：Apple Silicon `arm64` + Intel `x86_64`）** 与 **Linux 独立运行版（CLI + Web 纯静态零依赖：`x86_64` + `arm64`）**。

> 🔒 **双仓安全架构说明**：本仓库（`slan-ning/valid-team-releases`）为官方公开安装包分发、macOS OTA 自动热更新与纯净虚拟机 E2E 验收仓库（不含业务源码与内部设计文档）。

---

## 🍎 macOS 桌面客户端下载与安装（Latest Release: `v1.0.2`）

- **macOS 拖拽安装包 (`ValidTeam.dmg`)**：  
  👉 [**直接下载 ValidTeam.dmg**](https://github.com/slan-ning/valid-team-releases/releases/latest/download/ValidTeam.dmg)
- **在线 OTA 热更清单 (`latest-macos.json`)**：  
  `https://github.com/slan-ning/valid-team-releases/releases/latest/download/latest-macos.json`
- **macOS SHA-256 校验清单 (`SHA256SUMS.txt`)**：  
  `https://github.com/slan-ning/valid-team-releases/releases/latest/download/SHA256SUMS.txt`

### 安装与升级步骤
1. 下载并双击打开 `ValidTeam.dmg`，将 **`Valid Team.app`** 拖入右侧 **`Applications`（应用程序）** 文件夹；
2. 从「应用程序」或 Spotlight 启动 `Valid Team` 即可直接开始使用；
3. 已安装历史版本（如 `v1.0.0`）的用户可在菜单栏点击「检查更新…」一键原子热更新至 `v1.0.2`。

---

## 🐧 Linux 命令行 + 网页版快速上手（纯静态零依赖）

- **Linux x86_64 (`ValidTeam-linux-amd64.tar.gz`)**：  
  👉 [**下载 ValidTeam-linux-amd64.tar.gz**](https://github.com/slan-ning/valid-team-releases/releases/latest/download/ValidTeam-linux-amd64.tar.gz)
- **Linux ARM64 (`ValidTeam-linux-arm64.tar.gz`)**：  
  👉 [**下载 ValidTeam-linux-arm64.tar.gz**](https://github.com/slan-ning/valid-team-releases/releases/latest/download/ValidTeam-linux-arm64.tar.gz)
- **Linux SHA-256 校验清单 (`SHA256SUMS-linux.txt`)**：  
  `https://github.com/slan-ning/valid-team-releases/releases/latest/download/SHA256SUMS-linux.txt`

### 30 秒解压即跑与自定义监听绑定
```bash
# 1. 解压对应架构发行包（支持 Ubuntu / Debian / CentOS / Rocky / Alpine / NAS / 云服务器）
tar -xzf ValidTeam-linux-amd64.tar.gz && cd ValidTeam-linux-amd64
# ARM64 设备请使用：tar -xzf ValidTeam-linux-arm64.tar.gz && cd ValidTeam-linux-arm64

# 2. 启动方式 A：本机桌面或 SSH 端口转发（默认安全绑定 127.0.0.1:8787，仅本机可访问）
./vteam

# 3. 启动方式 B：局域网 / 内网服务器供其他设备浏览器访问（自定义监听绑定地址）
./vteam --addr 0.0.0.0:8787
# 或分别指定主机与端口（亦可通过环境变量 VTEAM_ADDR=0.0.0.0:9000 指定）：
./vteam --host 0.0.0.0 --port 9000
```

> ⚠️ **内网安全提示**：开启 `0.0.0.0` 或非本机网卡 IP 监听后，同一网络内的设备可直接访问工作台，请确保运行在受信任内网或配合防火墙 / 反向代理鉴权使用。

---

## 🔐 开发者签名、Apple 官方公证与双端完整性校验

macOS 官方安装包均由 **Apple Developer ID Application** 官方签名，并通过 **Apple 官方公证（Notarized Developer ID）与票据装订（Stapled Ticket）**，任何新 Mac 下载拖入 `/Applications` 均可零拦截直接打开：

```bash
# 校验 macOS / Linux 安装包 SHA-256 摘要
shasum -a 256 -c SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS-linux.txt

# 校验 macOS Apple Developer ID 签名与公证票据装订 (Stapler & Gatekeeper)
codesign --verify --deep --strict --verbose=2 "/Applications/Valid Team.app"
xcrun stapler validate "/Applications/Valid Team.app"
spctl -a -t exec -v "/Applications/Valid Team.app"
```
