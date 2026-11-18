# Valid Team — Official Releases (macOS, Windows & Linux)

**Run AI like a real team.**
**Valid Team** is a local-first, multi-agent desktop workbench for **macOS, Windows 10/11, and Linux**. Describe your goal once—specialized AI roles plan, execute, review, and deliver finished files straight to your local workspace.

- **Website**: [valid-team.com](https://valid-team.com/) ([简体中文](https://valid-team.com/zh/)) · [Valid Studio](https://valid-studio.com/)
- **Community & Q&A**: [GitHub Discussions](https://github.com/valid-studio/valid-team-releases/discussions)
- **Bug Reports**: [GitHub Issues](https://github.com/valid-studio/valid-team-releases/issues)

> This repository (`valid-studio/valid-team-releases`) hosts official installers, macOS & Windows OTA manifests, checksums, and community discussions.

---

## macOS Desktop App (Latest: `v1.2.13`)

Universal Binary (**Apple Silicon `arm64`** + **Intel `x86_64`**), signed with **Apple Developer ID** and **Notarized**.

- **Installer**: [Download ValidTeam.dmg](https://github.com/valid-studio/valid-team-releases/releases/latest/download/ValidTeam.dmg)
- **OTA Manifest**: `https://github.com/valid-studio/valid-team-releases/releases/latest/download/latest-macos.json`
- **SHA-256 Checksums**: [`SHA256SUMS.txt`](https://github.com/valid-studio/valid-team-releases/releases/latest/download/SHA256SUMS.txt)

1. Open `ValidTeam.dmg` and drag **`Valid Team.app`** into **`Applications`**.
2. Launch `Valid Team`, enter your own API key (DeepSeek, OpenAI, Claude, Gemini, Qwen, Kimi, etc.), and create your first project.
3. Use **"Check for Updates…"** in the menu bar to update in-place without losing local data.

---

## Windows 10 / 11 Desktop App (x64 · Latest: `v1.2.13`)

Standalone desktop window built on system **WebView2** + system tray companion, no admin privileges or extra runtime required.

- **Recommended Installer**: [Download ValidTeam-Setup.exe](https://github.com/valid-studio/valid-team-releases/releases/latest/download/ValidTeam-Setup.exe)
- **Portable Archive**: [Download ValidTeam-windows-amd64.zip](https://github.com/valid-studio/valid-team-releases/releases/latest/download/ValidTeam-windows-amd64.zip)
- **OTA Manifest (`v1.2.1+`)**: `https://github.com/valid-studio/valid-team-releases/releases/latest/download/latest-windows.json`
- **SHA-256 Checksums**: [`SHA256SUMS-windows.txt`](https://github.com/valid-studio/valid-team-releases/releases/latest/download/SHA256SUMS-windows.txt)

> **Automatic Updates (`v1.2.1+`)**: Both Setup and Portable editions silently download & SHA-256 verify new releases in the background and restart cleanly in-place after a single confirmation (all local projects and keys in `%LOCALAPPDATA%\ValidTeam` are 100% preserved).
>
> **Windows SmartScreen Note**: Initial Windows releases do not yet carry a commercial code-signing certificate. If Microsoft Defender SmartScreen prompts on first launch, click **"More info"** → **"Run anyway"** to install and start. You can verify package integrity anytime against `SHA256SUMS-windows.txt`.

---

## Linux Standalone (CLI + Web UI)

- **Linux x86_64**: [ValidTeam-linux-amd64.tar.gz](https://github.com/valid-studio/valid-team-releases/releases/latest/download/ValidTeam-linux-amd64.tar.gz)
- **Linux ARM64**: [ValidTeam-linux-arm64.tar.gz](https://github.com/valid-studio/valid-team-releases/releases/latest/download/ValidTeam-linux-arm64.tar.gz)
- **SHA-256 Checksums**: [`SHA256SUMS-linux.txt`](https://github.com/valid-studio/valid-team-releases/releases/latest/download/SHA256SUMS-linux.txt)

```bash
tar -xzf ValidTeam-linux-amd64.tar.gz && cd ValidTeam-linux-amd64
./vteam

# Optional: bind LAN / server interface (use behind firewall or reverse proxy)
./vteam --addr 0.0.0.0:8787
```

---

## Editions (Free & Pro)

- **Free**: Ready out of the box with **3 AI agent seats** shared across all local projects, BYOK, zero background telemetry.
- **Pro**: Up to **99 AI agent seats** across all local projects, with a one-time online device slot check on activation inside **System Settings → Edition & Pro Key** using a `VTPRO-...` key, working 100% offline thereafter (no account required). Share feedback or a workflow in [GitHub Discussions](https://github.com/valid-studio/valid-team-releases/discussions) to request an early Pro Key.

---

## Signature & Checksum Verification

```bash
# macOS / Linux
shasum -a 256 -c SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS-linux.txt

codesign --verify --deep --strict --verbose=2 "/Applications/Valid Team.app"
xcrun stapler validate "/Applications/Valid Team.app"
spctl -a -t exec -v "/Applications/Valid Team.app"
```

```powershell
# Windows (PowerShell)
Get-FileHash ValidTeam-Setup.exe -Algorithm SHA256
# Compare with SHA256SUMS-windows.txt
```

---

<details>
<summary>简体中文说明（macOS / Windows / Linux 下载、安装与版本说明）</summary>

**Valid Team** 是一款纯本地优先的多智能体协作桌面端，支持 **macOS (Universal)**、**Windows 10/11 (`x64` 独立桌面窗口版)** 与 **Linux (`x86_64` / `ARM64`)**。用一句话描述目标，AI 团队即可自动分工协作、互相核验，并将最终报告、表格、图表和代码归档至本地目录。

- **中文官网**：[valid-team.com/zh/](https://valid-team.com/zh/) · [Valid Studio](https://valid-studio.com/zh/)
- **使用交流**：[GitHub Discussions](https://github.com/valid-studio/valid-team-releases/discussions)
- **问题反馈**：[GitHub Issues](https://github.com/valid-studio/valid-team-releases/issues)

### macOS 安装与更新（当前版本 `v1.2.13`）
1. 下载 [ValidTeam.dmg](https://github.com/valid-studio/valid-team-releases/releases/latest/download/ValidTeam.dmg)，将 **`Valid Team.app`** 拖入 **`Applications`（应用程序）**；
2. 安装包已通过 **Apple Developer ID 官方签名与 Notarization 公证**；
3. 旧版本用户可在菜单栏点击「检查更新…」直接热更新至 `v1.2.13`。

### Windows 10 / 11 安装与首次运行指引（x64 独立桌面窗口版）
- **推荐图形安装包**：[下载 ValidTeam-Setup.exe](https://github.com/valid-studio/valid-team-releases/releases/latest/download/ValidTeam-Setup.exe)（原生 WebView2 独立桌面窗口 + 系统托盘常驻、免管理员一键安装）
- **免安装便携包**：[下载 ValidTeam-windows-amd64.zip](https://github.com/valid-studio/valid-team-releases/releases/latest/download/ValidTeam-windows-amd64.zip)
- **OTA 自动热更清单（`v1.2.1+`）**：`https://github.com/valid-studio/valid-team-releases/releases/latest/download/latest-windows.json`（安装版与便携版均支持后台静默下载 SHA-256 校验，用户最多确认一次即可原地自动替换并重启，完整保留 `%LOCALAPPDATA%\ValidTeam` 项目与密钥数据）
- **SHA-256 校验清单**：[`SHA256SUMS-windows.txt`](https://github.com/valid-studio/valid-team-releases/releases/latest/download/SHA256SUMS-windows.txt)

> **SmartScreen 首次运行提示**：首发阶段暂未附加商业代码签名证书。Windows 10/11 首次运行安装包或程序时若弹出 Microsoft Defender SmartScreen 蓝框提示，点击 **「更多信息 (More info)」→「仍要运行 (Run anyway)」** 即可正常安装启动，并可通过 `SHA256SUMS-windows.txt` 校验官方安装包完整性。

### Linux 解压即用
```bash
tar -xzf ValidTeam-linux-amd64.tar.gz && cd ValidTeam-linux-amd64
./vteam
```

### Free 与 Pro 版本说明
- **Free 免费版**：开箱即用，支持全工作区 **跨项目共享 3 个 AI Agent 席位**，零后台遥测；
- **Pro 专业版**：支持全工作区 **跨项目高达 99 个 AI Agent 席位**，在软件内「⚙️ 系统配置 → 版本权益与 Pro Key 激活」粘贴 `VTPRO-...` 即可激活（首次激活联网核验设备名额，日常 100% 离线使用，无需注册账号；升级前的老版本存量项目与角色数据 100% 保留可正常使用）。欢迎在 [GitHub Discussions](https://github.com/valid-studio/valid-team-releases/discussions) 分享使用反馈或团队配置，联系获赠官方 Pro Key。

</details>
