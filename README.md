# Valid Team — Official Releases (macOS & Linux)

**Run AI like a real team.**  
**Valid Team** is a local-first, multi-agent desktop workbench. Describe your goal once—specialized AI roles plan, execute, review, and deliver ready-to-use files straight to your local workspace.

🌐 **Website**: [valid-team.com](https://valid-team.com/) ([简体中文](https://valid-team.com/zh/)) · [Valid Studio](https://valid-studio.com/)  
💬 **Community & Q&A**: [GitHub Discussions](https://github.com/valid-studio/valid-team-releases/discussions) · 🐛 **Bug Reports**: [GitHub Issues](https://github.com/valid-studio/valid-team-releases/issues)

> 🔒 **Public Distribution Notice**: This repository (`valid-studio/valid-team-releases`) hosts official signed installers, macOS OTA auto-update manifests, checksums, clean-VM E2E verification, and community feedback.

---

## 🍎 macOS Desktop App (Latest: `v1.1.9`)

Universal Binary supporting **Apple Silicon (`arm64`)** and **Intel (`x86_64`)** — officially signed with **Apple Developer ID** and **Notarized** with stapled Gatekeeper tickets.

- **Installer (`ValidTeam.dmg`)**: 👉 [**Download ValidTeam.dmg**](https://github.com/valid-studio/valid-team-releases/releases/latest/download/ValidTeam.dmg)
- **OTA Update Manifest**: `https://github.com/valid-studio/valid-team-releases/releases/latest/download/latest-macos.json`
- **SHA-256 Checksums**: [`SHA256SUMS.txt`](https://github.com/valid-studio/valid-team-releases/releases/latest/download/SHA256SUMS.txt)

### Install & Update
1. Download and open `ValidTeam.dmg`, then drag **`Valid Team.app`** into **`Applications`**.
2. Launch `Valid Team` from Applications or Spotlight, add your own API key (DeepSeek, OpenAI, Claude, Gemini, Qwen, Kimi, etc.), and start your first project.
3. Existing users can click **"Check for Updates…"** in the menu bar to update in-place without losing projects or keys.

---

## 🐧 Linux Standalone (CLI + Web UI · Zero Dependencies)

- **Linux x86_64 (`ValidTeam-linux-amd64.tar.gz`)**: 👉 [**Download amd64**](https://github.com/valid-studio/valid-team-releases/releases/latest/download/ValidTeam-linux-amd64.tar.gz)
- **Linux ARM64 (`ValidTeam-linux-arm64.tar.gz`)**: 👉 [**Download arm64**](https://github.com/valid-studio/valid-team-releases/releases/latest/download/ValidTeam-linux-arm64.tar.gz)
- **SHA-256 Checksums**: [`SHA256SUMS-linux.txt`](https://github.com/valid-studio/valid-team-releases/releases/latest/download/SHA256SUMS-linux.txt)

```bash
# Extract and run locally (defaults to 127.0.0.1:8787)
tar -xzf ValidTeam-linux-amd64.tar.gz && cd ValidTeam-linux-amd64
./vteam

# Or bind to LAN / server interface (use behind firewall or reverse proxy)
./vteam --addr 0.0.0.0:8787
```

---

## 🔐 Signature & Checksum Verification

```bash
shasum -a 256 -c SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS-linux.txt

codesign --verify --deep --strict --verbose=2 "/Applications/Valid Team.app"
xcrun stapler validate "/Applications/Valid Team.app"
spctl -a -t exec -v "/Applications/Valid Team.app"
```

---

<details>
<summary>🇨🇳 简体中文说明（点击展开下载、安装与社区反馈指引）</summary>

### 产品简介与官方入口
**Valid Team** 是一款开箱即用、纯本地优先的多智能体协作桌面端（支持 **macOS Universal** 与 **Linux x86_64 / ARM64**）。用一句话说清目标，AI 团队即可自动分工协作、互相核验，并将最终报告、表格、图表和代码归档至本地目录。

- **中文官网**：[valid-team.com/zh/](https://valid-team.com/zh/) · [Valid Studio 工作室](https://valid-studio.com/zh/)
- **使用交流 / 求助问答**：[GitHub Discussions](https://github.com/valid-studio/valid-team-releases/discussions)
- **Bug 反馈与功能建议**：[GitHub Issues](https://github.com/valid-studio/valid-team-releases/issues)

### macOS 安装与在线热更新（当前版本 `v1.1.9`）
1. 下载 [**ValidTeam.dmg**](https://github.com/valid-studio/valid-team-releases/releases/latest/download/ValidTeam.dmg) 并双击打开，将 **`Valid Team.app`** 拖入 **`Applications`（应用程序）**；
2. 安装包均已通过 **Apple Developer ID 官方签名与 Notarization 公证**并装订离线票据，下载即可直接打开；
3. 已安装旧版本的用户可在顶部菜单栏点击「检查更新…」一键自动热更新至 `v1.1.9`，历史项目与模型密钥原样保留。

### Linux 30 秒解压即跑
```bash
# x86_64 设备（ARM64 请替换为 ValidTeam-linux-arm64.tar.gz）
tar -xzf ValidTeam-linux-amd64.tar.gz && cd ValidTeam-linux-amd64

# 默认安全绑定本机 127.0.0.1:8787
./vteam

# 如需局域网 / 内网服务器供其他设备访问（请配合防火墙或反向代理使用）
./vteam --addr 0.0.0.0:8787
```

</details>
