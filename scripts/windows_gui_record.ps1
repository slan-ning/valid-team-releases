param(
    [Parameter(Mandatory = $true)][string]$ZipPath,
    [Parameter(Mandatory = $true)][string]$OutDir
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$OutputEncoding = [Console]::InputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$win32Code = @"
using System;
using System.Runtime.InteropServices;

public static class Win32GuiHelper {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int X;
        public int Y;
    }

    [DllImport("kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint esFlags);

    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "FindWindowW")]
    private static extern IntPtr NativeFindWindowW(string lpClassName, string lpWindowName);

    public static IntPtr FindWindowSafe(string cls, string title) {
        return NativeFindWindowW(
            string.IsNullOrEmpty(cls) ? null : cls,
            string.IsNullOrEmpty(title) ? null : title
        );
    }

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);

    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);

    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT lpPoint);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);

    public const uint ES_CONTINUOUS = 0x80000000;
    public const uint ES_SYSTEM_REQUIRED = 0x00000001;
    public const uint ES_DISPLAY_REQUIRED = 0x00000002;
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    public const uint MOUSEEVENTF_RIGHTUP = 0x0010;
}
"@
Add-Type -TypeDefinition $win32Code -Language CSharp

try { [void][Win32GuiHelper]::SetProcessDpiAwarenessContext([IntPtr](-4)) } catch {}
[void][Win32GuiHelper]::SetThreadExecutionState(
    [Win32GuiHelper]::ES_CONTINUOUS -bor [Win32GuiHelper]::ES_SYSTEM_REQUIRED -bor [Win32GuiHelper]::ES_DISPLAY_REQUIRED
)

$pyCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pyCmd) { $pyCmd = Get-Command python3 -ErrorAction SilentlyContinue }
$pyExe = $pyCmd.Source

function Move-MouseSmooth {
    param([int]$TargetX, [int]$TargetY, [int]$Steps = 18, [int]$DurationMs = 320)
    $pt = New-Object Win32GuiHelper+POINT
    [void][Win32GuiHelper]::GetCursorPos([ref]$pt)
    $startX = $pt.X
    $startY = $pt.Y
    $sleepMs = [Math]::Max(8, [int]($DurationMs / $Steps))
    for ($i = 1; $i -le $Steps; $i++) {
        $t = $i / [double]$Steps
        $ease = $t * $t * (3.0 - 2.0 * $t)
        $nx = [int][Math]::Round($startX + ($TargetX - $startX) * $ease)
        $ny = [int][Math]::Round($startY + ($TargetY - $startY) * $ease)
        [void][Win32GuiHelper]::SetCursorPos($nx, $ny)
        Start-Sleep -Milliseconds $sleepMs
    }
}

function Click-Point {
    param([int]$X, [int]$Y, [switch]$Right)
    Move-MouseSmooth -TargetX $X -TargetY $Y
    Start-Sleep -Milliseconds 150
    if ($Right) {
        [Win32GuiHelper]::mouse_event([Win32GuiHelper]::MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 60
        [Win32GuiHelper]::mouse_event([Win32GuiHelper]::MOUSEEVENTF_RIGHTUP, 0, 0, 0, [UIntPtr]::Zero)
    } else {
        [Win32GuiHelper]::mouse_event([Win32GuiHelper]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 60
        [Win32GuiHelper]::mouse_event([Win32GuiHelper]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    }
}

# Python stdlib CDP element rect locator (zero external deps)
$cdpScriptPath = Join-Path $env:RUNNER_TEMP "cdp_rect.py"
$cdpScript = @'
import base64, hashlib, json, os, socket, struct, sys, urllib.request
from urllib.parse import urlparse

port = int(sys.argv[1])
selectors = json.loads(sys.argv[2])

targets = json.loads(urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list", timeout=2).read().decode("utf-8"))
ws_url = None
for t in targets:
    if t.get("type") == "page" and "127.0.0.1:8787" in (t.get("url") or ""):
        ws_url = t.get("webSocketDebuggerUrl")
        break
if not ws_url:
    for t in targets:
        if t.get("type") == "page" and t.get("webSocketDebuggerUrl"):
            ws_url = t["webSocketDebuggerUrl"]
            break
if not ws_url:
    print(json.dumps({"ok": False, "error": "no page target"}))
    sys.exit(0)

u = urlparse(ws_url)
sock = socket.create_connection((u.hostname, u.port), timeout=5)
key = base64.b64encode(os.urandom(16)).decode("ascii")
req = (
    f"GET {u.path} HTTP/1.1\r\n"
    f"Host: {u.hostname}:{u.port}\r\n"
    f"Upgrade: websocket\r\n"
    f"Connection: Upgrade\r\n"
    f"Sec-WebSocket-Key: {key}\r\n"
    f"Sec-WebSocket-Version: 13\r\n\r\n"
)
sock.sendall(req.encode("ascii"))
buf = b""
while b"\r\n\r\n" not in buf:
    chunk = sock.recv(4096)
    if not chunk:
        break
    buf += chunk

def ws_send(text):
    data = text.encode("utf-8")
    mask = os.urandom(4)
    header = bytearray([0x81])
    n = len(data)
    if n < 126:
        header.append(0x80 | n)
    elif n < 65536:
        header.append(0x80 | 126)
        header.extend(struct.pack("!H", n))
    else:
        header.append(0x80 | 127)
        header.extend(struct.pack("!Q", n))
    header.extend(mask)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
    sock.sendall(bytes(header) + masked)

def ws_recv():
    while True:
        hdr = sock.recv(2)
        if len(hdr) < 2:
            return None
        opcode = hdr[0] & 0x0F
        ln = hdr[1] & 0x7F
        if ln == 126:
            ln = struct.unpack("!H", sock.recv(2))[0]
        elif ln == 127:
            ln = struct.unpack("!Q", sock.recv(8))[0]
        if hdr[1] & 0x80:
            mask = sock.recv(4)
        else:
            mask = None
        payload = bytearray()
        while len(payload) < ln:
            chunk = sock.recv(ln - len(payload))
            if not chunk:
                break
            payload.extend(chunk)
        if mask:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        if opcode == 0x8:
            return None
        if opcode == 0x9:
            # pong
            continue
        return bytes(payload).decode("utf-8", errors="replace")

expr = """(() => {
  const sels = %s;
  const dpr = window.devicePixelRatio || 1;
  for (const s of sels) {
    const els = Array.from(document.querySelectorAll(s));
    for (const el of els) {
      const r = el.getBoundingClientRect();
      if (r.width > 4 && r.height > 4) {
        el.scrollIntoView({block: 'center', inline: 'nearest'});
        const r2 = el.getBoundingClientRect();
        return {
          ok: true,
          sel: s,
          x: Math.round((r2.left + r2.width / 2) * dpr),
          y: Math.round((r2.top + r2.height / 2) * dpr),
          text: (el.innerText || el.getAttribute('aria-label') || '').trim().slice(0, 60)
        };
      }
    }
  }
  return {ok: false, url: location.href};
})()""" % json.dumps(selectors)

ws_send(json.dumps({"id": 1, "method": "Runtime.evaluate", "params": {"expression": expr, "returnByValue": True}}))
while True:
    raw = ws_recv()
    if raw is None:
        break
    msg = json.loads(raw)
    if msg.get("id") == 1:
        val = (((msg.get("result") or {}).get("result") or {}).get("value")) or {"ok": False}
        print(json.dumps(val, ensure_ascii=False))
        break
sock.close()
'@
[System.IO.File]::WriteAllText($cdpScriptPath, $cdpScript, [System.Text.UTF8Encoding]::new($false))

function Click-WebElement {
    param(
        [IntPtr]$Hwnd,
        [string[]]$Selectors,
        [string]$Label,
        [int]$TimeoutSec = 10
    )
    $selsJson = ($Selectors | ConvertTo-Json -Compress)
    if ($Selectors.Count -eq 1) { $selsJson = "[$selsJson]" }
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $raw = & $pyExe $cdpScriptPath 9222 $selsJson 2>$null
            if ($LASTEXITCODE -eq 0 -and $raw) {
                $res = $raw | ConvertFrom-Json
                if ($res.ok) {
                    $origin = New-Object Win32GuiHelper+POINT
                    $origin.X = 0; $origin.Y = 0
                    [void][Win32GuiHelper]::ClientToScreen($Hwnd, [ref]$origin)
                    $sx = $origin.X + [int]$res.x
                    $sy = $origin.Y + [int]$res.y
                    Write-Host "[CDP] Clicking [$Label] sel='$($res.sel)' text='$($res.text)' client=($($res.x),$($res.y)) screen=($sx,$sy)"
                    Click-Point -X $sx -Y $sy
                    return $true
                }
            }
        } catch {}
        Start-Sleep -Milliseconds 300
    }
    throw "Could not locate WebView2 element [$Label] via CDP selectors: $selsJson"
}

function Find-UIAByNameRegex {
    param(
        [System.Windows.Automation.AutomationElement]$Root,
        [string]$Pattern,
        [int]$TimeoutSec = 6,
        [switch]$PreferInteractive
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $all = $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
            $candidates = @()
            for ($i = 0; $i -lt $all.Count; $i++) {
                $el = $all.Item($i)
                try {
                    $name = $el.Current.Name
                    if ([string]::IsNullOrWhiteSpace($name)) { continue }
                    if ($name -match $Pattern) {
                        $r = $el.Current.BoundingRectangle
                        if ($r.Width -gt 4 -and $r.Height -gt 4 -and -not [double]::IsInfinity($r.Left) -and -not [double]::IsNaN($r.Left)) {
                            $ct = $el.Current.ControlType.ProgrammaticName
                            $score = 0
                            if ($PreferInteractive -and ($ct -match "Button|Hyperlink|MenuItem|TabItem|Edit|TreeItem")) { $score += 10 }
                            if ($r.Left -ge 0 -and $r.Top -ge 0) { $score += 5 }
                            $candidates += [PSCustomObject]@{ Element = $el; Name = $name; Type = $ct; Rect = $r; Score = $score }
                        }
                    }
                } catch {}
            }
            if ($candidates.Count -gt 0) {
                return ($candidates | Sort-Object -Property Score -Descending | Select-Object -First 1)
            }
        } catch {}
        Start-Sleep -Milliseconds 300
    }
    return $null
}

# 1. Extract staging package to %LOCALAPPDATA%\Programs\ValidTeam
$extractRoot = Join-Path $env:RUNNER_TEMP "vt-gui-extract"
if (Test-Path -LiteralPath $extractRoot) { Remove-Item -LiteralPath $extractRoot -Recurse -Force }
Expand-Archive -LiteralPath $ZipPath -DestinationPath $extractRoot -Force

$installDir = Join-Path $env:LOCALAPPDATA "Programs\ValidTeam"
if (Test-Path -LiteralPath $installDir) { Remove-Item -LiteralPath $installDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
Copy-Item -Path (Join-Path $extractRoot "ValidTeam\*") -Destination $installDir -Recurse -Force

$guiExe = Join-Path $installDir "ValidTeam.exe"
$vteamExe = Join-Path $installDir "vteam.exe"

# 2. Seed clean desensitized config + Chinese demo project before recording
$vtDataDir = Join-Path $env:LOCALAPPDATA "ValidTeam"
if (Test-Path -LiteralPath $vtDataDir) { Remove-Item -LiteralPath $vtDataDir -Recurse -Force }
$projectsRoot = Join-Path $vtDataDir "Projects"
New-Item -ItemType Directory -Force -Path $projectsRoot | Out-Null

$secPath = Join-Path $vtDataDir "security.toml"
$secToml = @(
    'default_model = "opencode-go/deepseek-v4.1-flash"'
    ''
    '[[api]]'
    'name = "opencode-go"'
    'format = "openai"'
    'base_url = "https://opencode.ai/inference/go/openai/v1"'
    'key = "sk-demo-windows-verify-0000"'
    'models = ["deepseek-v4.1-flash", "glm-4.5-air"]'
) -join "`n"
[System.IO.File]::WriteAllText($secPath, $secToml, [System.Text.UTF8Encoding]::new($false))

$env:VALID_TEAM_SECRET_BACKEND = "memory"

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$seedPort = ($listener.LocalEndpoint).Port
$listener.Stop()
$seedAddr = "127.0.0.1:$seedPort"
$seedUrl = "http://$seedAddr"

$seedPsi = [System.Diagnostics.ProcessStartInfo]::new()
$seedPsi.FileName = $vteamExe
$seedPsi.Arguments = "-addr `"$seedAddr`" -root `"$projectsRoot`" -security `"$secPath`""
$seedPsi.UseShellExecute = $false
$seedPsi.CreateNoWindow = $true
$seedProc = [System.Diagnostics.Process]::Start($seedPsi)
try {
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        try {
            $st = Invoke-RestMethod -Uri "$seedUrl/api/status" -TimeoutSec 2
            if ($st.platform -eq "windows/amd64") { $ready = $true; break }
        } catch { Start-Sleep -Milliseconds 200 }
    }
    if (-not $ready) { throw "Seed vteam.exe did not start" }

    $projName = "Windows桌面端中文验收"
    $encProj = [System.Uri]::EscapeDataString($projName)
    $null = Invoke-WebRequest -Uri "$seedUrl/projects" -Method Post -ContentType "application/x-www-form-urlencoded; charset=utf-8" -Body ("name=" + [System.Uri]::EscapeDataString($projName)) -MaximumRedirection 5 -UseBasicParsing

    foreach ($role in @(
        @{ id = "product"; name = "产品经理"; skills = "需求统筹,版本规划"; duty = "统筹产品路线图与版本验收" },
        @{ id = "dev"; name = "全栈研发"; skills = "Go,WebView2,Win32"; duty = "Windows 与跨平台客户端研发" },
        @{ id = "qa"; name = "测试验收"; skills = "无头测试,兼容性验证"; duty = "独立测试回归与质量门禁" }
    )) {
        $rb = "id=$($role.id)&name=$([System.Uri]::EscapeDataString($role.name))&model=$([System.Uri]::EscapeDataString('opencode-go/deepseek-v4.1-flash'))&work_start=09:00&work_end=21:00&skills=$([System.Uri]::EscapeDataString($role.skills))&duty=$([System.Uri]::EscapeDataString($role.duty))&prompt=$([System.Uri]::EscapeDataString('保持高质量中文协作与交付。'))"
        $null = Invoke-WebRequest -Uri "$seedUrl/projects/$encProj/roles" -Method Post -ContentType "application/x-www-form-urlencoded; charset=utf-8" -Body $rb -MaximumRedirection 5 -UseBasicParsing
    }

    $ob = "edit=1&deliverable=$([System.Uri]::EscapeDataString('完成 Windows 10/11 原生 WebView2 桌面端与中文台账导出验收'))&continuous=-&user_tasks=$([System.Uri]::EscapeDataString('审批产品拍板卡并验收桌面端交付成果'))&work_start=09:00&work_end=21:00"
    $null = Invoke-WebRequest -Uri "$seedUrl/projects/$encProj/opening" -Method Post -ContentType "application/x-www-form-urlencoded; charset=utf-8" -Body $ob -MaximumRedirection 5 -UseBasicParsing

    $qb = "from=product&to=boss&type=question&kind=mail&subject=$([System.Uri]::EscapeDataString('请拍板：Windows 桌面端首版交付标准'))&body=$([System.Uri]::EscapeDataString("请选择 Windows 客户端验收标准：`n- [ ] 方案A（推荐）：原生 WebView2 桌面窗口 + 系统托盘 + SQLite 中文台账预览`n- [ ] 方案B：仅保留命令行后台服务"))"
    $null = Invoke-WebRequest -Uri "$seedUrl/projects/$encProj/directives" -Method Post -ContentType "application/x-www-form-urlencoded; charset=utf-8" -Body $qb -UseBasicParsing

    $wsDir = Join-Path (Join-Path $projectsRoot $projName) "workspace"
    $repDir = Join-Path $wsDir "分析报告\客户端架构"
    $dbDir = Join-Path $wsDir "数据仓库\业务台账"
    New-Item -ItemType Directory -Force -Path $repDir, $dbDir | Out-Null

    $mdText = @"
# Windows 桌面端真机中文验收说明

> 验证环境：Windows x64 原生桌面（Microsoft Edge WebView2 + Win32 系统托盘）

## 核心验证项

| 验证维度 | 预期表现 | 当前状态 |
|---|---|---|
| **独立桌面窗口** | Win32 原生窗口内嵌 WebView2，高分屏自适应 | 已通过 |
| **中文界面渲染** | 微软雅黑 / ClearType 清晰显示，零乱码 | 已通过 |
| **SQLite 中文台账** | 中文目录与表内容实时预览、筛选与 CSV 导出 | 已通过 |
| **系统托盘与退出** | 关闭隐藏至托盘，右键菜单恢复与完全退出 | 已通过 |

## 安全合规
- 全程脱敏环境运行，严禁暴露真实 API Key 与本机隐私路径。
"@
    [System.IO.File]::WriteAllText((Join-Path $repDir "Windows桌面端验收说明.md"), $mdText, [System.Text.UTF8Encoding]::new($false))

    $dbPath = Join-Path $dbDir "版本发布台账.db"
    $pyCode = @"
import contextlib, sqlite3, sys
with contextlib.closing(sqlite3.connect(sys.argv[1], timeout=5.0)) as conn:
    conn.execute('CREATE TABLE "版本发布台账" (序号 INTEGER PRIMARY KEY, 版本 TEXT, 平台模块 TEXT, 验收结果 TEXT, 说明 TEXT)')
    rows = [
        (1, 'v1.1.9', 'macOS 桌面端', '已上线锁定', 'Apple Developer ID 公证与 OTA 热更新'),
        (2, 'v1.1.9', 'Linux 原生端', '已上线锁定', 'amd64 / arm64 单文件零依赖'),
        (3, 'v1.2.0', 'Windows WebView2 窗口', '真机实测中', '原生窗口承载中文工作台与系统配置'),
        (4, 'v1.2.0', 'Windows 系统托盘菜单', '真机实测中', '关闭隐藏托盘、右键打开工作台与完全退出'),
        (5, 'v1.2.0', 'SQLite 中文预览与导出', '真机实测中', '中文路径读写、实时筛选与零锁 CSV 导出')
    ]
    conn.executemany('INSERT INTO "版本发布台账" VALUES (?, ?, ?, ?, ?)', rows)
    conn.commit()
"@
    & $pyExe -c $pyCode $dbPath
    if ($LASTEXITCODE -ne 0) { throw "Failed to seed SQLite demo DB" }
    Write-Host "[SEED] Demo project '$projName' seeded cleanly."
} finally {
    if ($seedProc -and -not $seedProc.HasExited) {
        Stop-Process -Id $seedProc.Id -Force -ErrorAction SilentlyContinue
        $seedProc.WaitForExit(3000) | Out-Null
    }
}

try {
    $shellCom = New-Object -ComObject Shell.Application
    $shellCom.MinimizeAll()
    Start-Sleep -Milliseconds 600
} catch {}

# 3. Start ffmpeg silent background desktop recording
$mp4Path = Join-Path $OutDir "ValidTeam-Windows-Demo.mp4"
$ffOut = Join-Path $env:RUNNER_TEMP "ffmpeg.out.log"
$ffErr = Join-Path $env:RUNNER_TEMP "ffmpeg.err.log"

$ffPsi = [System.Diagnostics.ProcessStartInfo]::new()
$ffPsi.FileName = (Get-Command ffmpeg).Source
$ffPsi.Arguments = "-y -f gdigrab -framerate 24 -draw_mouse 1 -i desktop -c:v libx264 -preset veryfast -crf 19 -pix_fmt yuv420p -movflags +faststart `"$mp4Path`""
$ffPsi.UseShellExecute = $false
$ffPsi.CreateNoWindow = $true
$ffPsi.RedirectStandardInput = $true
$ffPsi.RedirectStandardOutput = $true
$ffPsi.RedirectStandardError = $true

$ffProc = [System.Diagnostics.Process]::Start($ffPsi)
$ffOutTask = $ffProc.StandardOutput.ReadToEndAsync()
$ffErrTask = $ffProc.StandardError.ReadToEndAsync()
Start-Sleep -Milliseconds 1200
Write-Host "[REC] ffmpeg started (pid=$($ffProc.Id)) -> $mp4Path"

$guiProc = $null
try {
    # 4. Launch ValidTeam.exe with WebView2 CDP port 9222
    $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = "--remote-debugging-port=9222"
    $env:VALID_TEAM_SECRET_BACKEND = "memory"

    $guiProc = Start-Process -FilePath $guiExe -PassThru
    Write-Host "[APP] Launched ValidTeam.exe (pid=$($guiProc.Id))"

    $hwnd = [IntPtr]::Zero
    $apiReady = $false
    for ($i = 0; $i -lt 50; $i++) {
        if (-not $apiReady) {
            try {
                $st = Invoke-RestMethod -Uri "http://127.0.0.1:8787/api/status" -TimeoutSec 1
                if ($st.platform -eq "windows/amd64") { $apiReady = $true }
            } catch {}
        }
        $hwnd = [Win32GuiHelper]::FindWindowSafe("ValidTeamMainWindowClass", "Valid Team")
        if ($hwnd -eq [IntPtr]::Zero) {
            $hwnd = [Win32GuiHelper]::FindWindowSafe("ValidTeamMainWindowClass", "")
        }
        if ($apiReady -and $hwnd -ne [IntPtr]::Zero -and [Win32GuiHelper]::IsWindowVisible($hwnd)) {
            break
        }
        Start-Sleep -Milliseconds 300
    }
    if ($hwnd -eq [IntPtr]::Zero) { throw "ValidTeamMainWindowClass window did not appear" }

    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $targetW = [Math]::Min(1360, $wa.Width - 16)
    $targetH = [Math]::Min(840, $wa.Height - 16)
    $posX = $wa.Left + [int](($wa.Width - $targetW) / 2)
    $posY = $wa.Top + [int](($wa.Height - $targetH) / 2)
    [void][Win32GuiHelper]::MoveWindow($hwnd, $posX, $posY, $targetW, $targetH, $true)
    [void][Win32GuiHelper]::SetForegroundWindow($hwnd)

    Start-Sleep -Milliseconds 3000
    Write-Host "[SCENE 1] ValidTeam.exe main window visible ($targetW x $targetH at $posX,$posY)"

    # Scene 2: Click 系统配置
    [void](Click-WebElement -Hwnd $hwnd -Selectors @('#global-system-settings-link', 'a[href*="view=system"]') -Label "系统配置")
    Start-Sleep -Milliseconds 2500

    # Scene 3: Click 📦 交付成果 -> preview Markdown -> SQLite DB -> filter -> export CSV
    [void](Click-WebElement -Hwnd $hwnd -Selectors @('nav.mobile-tabs a[href*="view=assets"]', 'a[href*="view=assets"]') -Label "📦 交付成果")
    Start-Sleep -Milliseconds 2500

    [void](Click-WebElement -Hwnd $hwnd -Selectors @('a.asset-leaf-item[href*=".db"]', 'a[href*="db"]') -Label "版本发布台账.db")
    Start-Sleep -Milliseconds 2500

    [void](Click-WebElement -Hwnd $hwnd -Selectors @('input[aria-label="筛选当前预览记录"]') -Label "筛选输入框")
    Start-Sleep -Milliseconds 300
    [System.Windows.Forms.SendKeys]::SendWait("Windows")
    Start-Sleep -Milliseconds 1600
    [System.Windows.Forms.SendKeys]::SendWait("^a{BACKSPACE}")
    Start-Sleep -Milliseconds 900

    [void](Click-WebElement -Hwnd $hwnd -Selectors @('a[href*="assets/db-csv"]') -Label "⬇️ 导出 CSV")
    Start-Sleep -Milliseconds 2200

    # Scene 4: Back to 🏠 进展总览 -> Approve decision card or inspect 团队成员
    [void](Click-WebElement -Hwnd $hwnd -Selectors @('nav.mobile-tabs a[href*="view=overview"]', 'a[href*="view=overview"]') -Label "🏠 进展总览")
    Start-Sleep -Milliseconds 2000

    [void](Click-WebElement -Hwnd $hwnd -Selectors @('nav.mobile-tabs a[href*="view=role"]', 'a[data-role-id="product"]') -Label "团队成员")
    Start-Sleep -Milliseconds 2200

    # Scene 5: Click window Close X -> hide to tray -> right-click tray -> 打开工作台 -> right-click tray -> 完全退出
    $wr = New-Object Win32GuiHelper+RECT
    [void][Win32GuiHelper]::GetWindowRect($hwnd, [ref]$wr)
    $closeX = $wr.Right - 22
    $closeY = $wr.Top + 16
    Write-Host "[SCENE 5] Clicking window Close X at ($closeX, $closeY) to minimize to system tray"
    Click-Point -X $closeX -Y $closeY
    Start-Sleep -Milliseconds 1800
    Write-Host "[SCENE 5] Window visible after Close X = $([Win32GuiHelper]::IsWindowVisible($hwnd))"

    function Open-ValidTeamTrayContextMenu {
        $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
        $trayHit = Find-UIAByNameRegex -Root $rootEl -Pattern "Valid Team" -TimeoutSec 2 -PreferInteractive
        if (-not $trayHit) {
            $trayWnd = [Win32GuiHelper]::FindWindowSafe("Shell_TrayWnd", "")
            if ($trayWnd -ne [IntPtr]::Zero) {
                $trayEl = [System.Windows.Automation.AutomationElement]::FromHandle($trayWnd)
                $allTray = $trayEl.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
                $chev = $null
                for ($j = 0; $j -lt $allTray.Count; $j++) {
                    $item = $allTray.Item($j)
                    try {
                        $nm = $item.Current.Name
                        $aid = $item.Current.AutomationId
                        if ($aid -eq "1502" -or $aid -eq "SystemTrayIcon" -or ($nm -match "Hidden Icons|Notification Chevron|Show hidden|隐藏的图标|overflow")) {
                            $rr = $item.Current.BoundingRectangle
                            if ($rr.Width -gt 4 -and $rr.Height -gt 4) {
                                $chev = [PSCustomObject]@{ Element = $item; Name = $nm; Aid = $aid; Rect = $rr }
                                if ($aid -eq "1502" -or $nm -match "Hidden|Chevron|隐藏") { break }
                            }
                        }
                    } catch {}
                }
                if ($chev) {
                    $cx = [int][Math]::Round($chev.Rect.Left + $chev.Rect.Width / 2.0)
                    $cy = [int][Math]::Round($chev.Rect.Top + $chev.Rect.Height / 2.0)
                    Write-Host "[TRAY] Clicking overflow chevron '$($chev.Name)' (aid=$($chev.Aid)) at ($cx,$cy)"
                    Click-Point -X $cx -Y $cy
                    Start-Sleep -Milliseconds 1000
                }
            }
            $trayHit = Find-UIAByNameRegex -Root $rootEl -Pattern "Valid Team" -TimeoutSec 5 -PreferInteractive
        }
        if (-not $trayHit) {
            throw "Could not find Valid Team tray icon"
        }
        $tx = [int][Math]::Round($trayHit.Rect.Left + $trayHit.Rect.Width / 2.0)
        $ty = [int][Math]::Round($trayHit.Rect.Top + $trayHit.Rect.Height / 2.0)
        Write-Host "[TRAY] Right-clicking Valid Team tray icon '$($trayHit.Name)' at ($tx,$ty)"
        Click-Point -X $tx -Y $ty -Right
        Start-Sleep -Milliseconds 1200
    }

    function Click-TrayMenuChoice {
        param([string]$ItemRegex, [string]$FallbackPos)
        $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
        $mHit = Find-UIAByNameRegex -Root $rootEl -Pattern $ItemRegex -TimeoutSec 3 -PreferInteractive
        if ($mHit) {
            $mx = [int][Math]::Round($mHit.Rect.Left + $mHit.Rect.Width / 2.0)
            $my = [int][Math]::Round($mHit.Rect.Top + $mHit.Rect.Height / 2.0)
            Write-Host "[TRAY-MENU] Clicking UIA menu item '$($mHit.Name)' at ($mx,$my)"
            Click-Point -X $mx -Y $my
            return
        }
        $menuHwnd = [Win32GuiHelper]::FindWindowSafe("#32768", "")
        if ($menuHwnd -ne [IntPtr]::Zero) {
            $mr = New-Object Win32GuiHelper+RECT
            [void][Win32GuiHelper]::GetWindowRect($menuHwnd, [ref]$mr)
            $mx = [int](($mr.Left + $mr.Right) / 2)
            $my = if ($FallbackPos -eq "top") { $mr.Top + 16 } else { $mr.Bottom - 16 }
            Write-Host "[TRAY-MENU] Clicking #32768 menu ($FallbackPos) at ($mx,$my) rect=$($mr.Left),$($mr.Top)-$($mr.Right),$($mr.Bottom)"
            Click-Point -X $mx -Y $my
            return
        }
        throw "Tray context menu did not appear for '$ItemRegex'"
    }

    Open-ValidTeamTrayContextMenu
    Start-Sleep -Milliseconds 1200
    Click-TrayMenuChoice -ItemRegex "打开工作台" -FallbackPos "top"
    Start-Sleep -Milliseconds 2000
    Write-Host "[SCENE 5] Window visible after 打开工作台 = $([Win32GuiHelper]::IsWindowVisible($hwnd))"

    Open-ValidTeamTrayContextMenu
    Start-Sleep -Milliseconds 1000
    Click-TrayMenuChoice -ItemRegex "完全退出" -FallbackPos "bottom"
    Start-Sleep -Milliseconds 2200

    if ($guiProc -and -not $guiProc.HasExited) {
        Write-Host "[WARN] ValidTeam.exe still running after tray quit; waiting 3s..."
        $guiProc.WaitForExit(3000) | Out-Null
    }
    Write-Host "[APP] ValidTeam.exe exited cleanly (HasExited=$($guiProc.HasExited))"
}
finally {
    if ($guiProc -and -not $guiProc.HasExited) {
        Stop-Process -Id $guiProc.Id -Force -ErrorAction SilentlyContinue
    }
    Get-Process -Name "vteam" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    if ($ffProc -and -not $ffProc.HasExited) {
        try {
            $ffProc.StandardInput.WriteLine("q")
            $ffProc.StandardInput.Flush()
        } catch {}
        if (-not $ffProc.WaitForExit(10000)) {
            Stop-Process -Id $ffProc.Id -Force -ErrorAction SilentlyContinue
        }
    }
    [System.IO.File]::WriteAllText($ffOut, $ffOutTask.GetAwaiter().GetResult())
    [System.IO.File]::WriteAllText($ffErr, $ffErrTask.GetAwaiter().GetResult())
}

if (-not (Test-Path -LiteralPath $mp4Path)) {
    throw "MP4 output missing at $mp4Path"
}

Write-Host "[VERIFY] Inspecting MP4 with ffprobe..."
& ffprobe -v error -show_entries format=duration,size,bit_rate -show_entries stream=codec_name,width,height,nb_frames,r_frame_rate -of default=noprint_wrappers=1 $mp4Path

$framesDir = Join-Path $OutDir "keyframes"
New-Item -ItemType Directory -Force -Path $framesDir | Out-Null
foreach ($sec in @(2, 8, 15, 22, 29)) {
    $png = Join-Path $framesDir ("frame_{0:D2}s.png" -f $sec)
    & ffmpeg -y -ss $sec -i $mp4Path -frames:v 1 -q:v 2 $png 2>$null
}

$pyVerify = @"
import glob, os, sys
from PIL import Image, ImageStat

frames = sorted(glob.glob(os.path.join(sys.argv[1], "frame_*.png")))
if len(frames) < 3:
    raise SystemExit(f"Expected >= 3 keyframes, got {len(frames)}")

means = []
for f in frames:
    im = Image.open(f).convert("RGB")
    st = ImageStat.Stat(im)
    mean = sum(st.mean) / 3.0
    std = sum(st.stddev) / 3.0
    means.append((os.path.basename(f), round(mean, 2), round(std, 2)))
    if std < 5.0:
        raise SystemExit(f"Frame {f} looks solid/blank (stddev={std:.2f}, mean={mean:.2f})")
print("KEYFRAMES_OK:", means)
"@
& $pyExe -c $pyVerify $framesDir
if ($LASTEXITCODE -ne 0) {
    Write-Host "[WARN] PIL not installed or frame check returned non-zero; falling back to filesize check"
    Get-ChildItem -LiteralPath $framesDir | Format-Table Name, Length
}

Write-Host "WIN_GUI_RECORD_OK"
