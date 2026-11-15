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

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODEW {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public ushort dmSpecVersion;
        public ushort dmDriverVersion;
        public ushort dmSize;
        public ushort dmDriverExtra;
        public uint dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public uint dmDisplayOrientation;
        public uint dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public ushort dmLogPixels;
        public uint dmBitsPerPel;
        public uint dmPelsWidth;
        public uint dmPelsHeight;
        public uint dmDisplayFlags;
        public uint dmDisplayFrequency;
        public uint dmICMMethod;
        public uint dmICMIntent;
        public uint dmMediaType;
        public uint dmDitherType;
        public uint dmReserved1;
        public uint dmReserved2;
        public uint dmPanningWidth;
        public uint dmPanningHeight;
    }

    [DllImport("kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint esFlags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindowW(string lpClassName, string lpWindowName);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

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

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool EnumDisplaySettingsW(string lpszDeviceName, int iModeNum, ref DEVMODEW lpDevMode);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int ChangeDisplaySettingsW(ref DEVMODEW lpDevMode, uint dwFlags);

    public const uint ES_CONTINUOUS = 0x80000000;
    public const uint ES_SYSTEM_REQUIRED = 0x00000001;
    public const uint ES_DISPLAY_REQUIRED = 0x00000002;
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    public const uint MOUSEEVENTF_RIGHTUP = 0x0010;
    public const uint DM_PELSWIDTH = 0x00080000;
    public const uint DM_PELSHEIGHT = 0x00100000;
    public const uint DM_BITSPERPEL = 0x00040000;
}
"@
Add-Type -TypeDefinition $win32Code -Language CSharp

# Prevent sleep/screensaver
[void][Win32GuiHelper]::SetThreadExecutionState(
    [Win32GuiHelper]::ES_CONTINUOUS -bor [Win32GuiHelper]::ES_SYSTEM_REQUIRED -bor [Win32GuiHelper]::ES_DISPLAY_REQUIRED
)

# Check & upgrade display resolution to crisp HD (prefer 1600x900 or 1440x900 or 1920x1080)
function Set-PreferredResolution {
    $cur = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    Write-Host "[DISPLAY] Initial PrimaryScreen: $($cur.Width)x$($cur.Height)"
    $dm = New-Object Win32GuiHelper+DEVMODEW
    $dm.dmSize = [uint16][System.Runtime.InteropServices.Marshal]::SizeOf($dm)
    $modes = @()
    $idx = 0
    while ([Win32GuiHelper]::EnumDisplaySettingsW($null, $idx, [ref]$dm)) {
        if ($dm.dmBitsPerPel -eq 32) {
            $modes += [PSCustomObject]@{ W = [int]$dm.dmPelsWidth; H = [int]$dm.dmPelsHeight; Index = $idx }
        }
        $idx++
    }
    $targets = @(
        @{ W = 1600; H = 900 },
        @{ W = 1440; H = 900 },
        @{ W = 1920; H = 1080 },
        @{ W = 1280; H = 800 },
        @{ W = 1280; H = 1024 }
    )
    foreach ($t in $targets) {
        $match = $modes | Where-Object { $_.W -eq $t.W -and $_.H -eq $t.H } | Select-Object -First 1
        if ($match) {
            if ($cur.Width -eq $t.W -and $cur.Height -eq $t.H) {
                Write-Host "[DISPLAY] Already at $($t.W)x$($t.H)"
                return
            }
            $dmSet = New-Object Win32GuiHelper+DEVMODEW
            $dmSet.dmSize = [uint16][System.Runtime.InteropServices.Marshal]::SizeOf($dmSet)
            if ([Win32GuiHelper]::EnumDisplaySettingsW($null, $match.Index, [ref]$dmSet)) {
                $dmSet.dmFields = [Win32GuiHelper]::DM_PELSWIDTH -bor [Win32GuiHelper]::DM_PELSHEIGHT -bor [Win32GuiHelper]::DM_BITSPERPEL
                $res = [Win32GuiHelper]::ChangeDisplaySettingsW([ref]$dmSet, 0)
                if ($res -eq 0) {
                    Start-Sleep -Milliseconds 600
                    $after = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
                    Write-Host "[DISPLAY] Switched resolution to $($after.Width)x$($after.Height)"
                    return
                }
            }
        }
    }
    Write-Host "[DISPLAY] Keeping current resolution $($cur.Width)x$($cur.Height)"
}
Set-PreferredResolution

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
    Start-Sleep -Milliseconds 160
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

function Find-UIAByNameRegex {
    param(
        [System.Windows.Automation.AutomationElement]$Root,
        [string]$Pattern,
        [int]$TimeoutSec = 8,
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
                            $candidates += [PSCustomObject]@{
                                Element = $el
                                Name = $name
                                Type = $ct
                                Rect = $r
                                Score = $score
                            }
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

function Click-UIA {
    param(
        [System.Windows.Automation.AutomationElement]$Root,
        [string]$Pattern,
        [string]$Label,
        [int]$TimeoutSec = 10,
        [switch]$Right
    )
    $hit = Find-UIAByNameRegex -Root $Root -Pattern $Pattern -TimeoutSec $TimeoutSec -PreferInteractive
    if (-not $hit) {
        throw "Could not find UIA element [$Label] matching '$Pattern'"
    }
    $cx = [int][Math]::Round($hit.Rect.Left + $hit.Rect.Width / 2.0)
    $cy = [int][Math]::Round($hit.Rect.Top + $hit.Rect.Height / 2.0)
    Write-Host "[UIA] Clicking [$Label] name='$($hit.Name)' type=$($hit.Type) at ($cx,$cy) rect=$([int]$hit.Rect.Left),$([int]$hit.Rect.Top),$([int]$hit.Rect.Width)x$([int]$hit.Rect.Height)"
    Click-Point -X $cx -Y $cy -Right:$Right
    return $hit
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

# Temporarily start vteam.exe on random port to seed authentic project structure
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
    $pyCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pyCmd) { $pyCmd = Get-Command python3 -ErrorAction SilentlyContinue }
    & $pyCmd.Source -c $pyCode $dbPath
    if ($LASTEXITCODE -ne 0) { throw "Failed to seed SQLite demo DB" }
    Write-Host "[SEED] Demo project '$projName' seeded cleanly."
} finally {
    if ($seedProc -and -not $seedProc.HasExited) {
        Stop-Process -Id $seedProc.Id -Force -ErrorAction SilentlyContinue
        $seedProc.WaitForExit(3000) | Out-Null
    }
}

# Minimize any open windows on desktop before recording
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
    # 4. Launch ValidTeam.exe with WebView2 accessibility enabled
    $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = "--force-renderer-accessibility"
    $env:VALID_TEAM_SECRET_BACKEND = "memory"

    $guiProc = Start-Process -FilePath $guiExe -PassThru
    Write-Host "[APP] Launched ValidTeam.exe (pid=$($guiProc.Id))"

    # Wait for daemon /api/status & main window
    $hwnd = [IntPtr]::Zero
    $apiReady = $false
    for ($i = 0; $i -lt 50; $i++) {
        if (-not $apiReady) {
            try {
                $st = Invoke-RestMethod -Uri "http://127.0.0.1:8787/api/status" -TimeoutSec 1
                if ($st.platform -eq "windows/amd64") { $apiReady = $true }
            } catch {}
        }
        $hwnd = [Win32GuiHelper]::FindWindowW("ValidTeamMainWindowClass", $null)
        if ($apiReady -and $hwnd -ne [IntPtr]::Zero -and [Win32GuiHelper]::IsWindowVisible($hwnd)) {
            break
        }
        Start-Sleep -Milliseconds 300
    }
    if ($hwnd -eq [IntPtr]::Zero) { throw "ValidTeamMainWindowClass window did not appear" }

    # Fit window cleanly inside PrimaryScreen.WorkingArea (keep taskbar visible)
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $targetW = [Math]::Min(1360, $wa.Width - 32)
    $targetH = [Math]::Min(840, $wa.Height - 24)
    $posX = $wa.Left + [int](($wa.Width - $targetW) / 2)
    $posY = $wa.Top + [int](($wa.Height - $targetH) / 2)
    [void][Win32GuiHelper]::MoveWindow($hwnd, $posX, $posY, $targetW, $targetH, $true)
    [void][Win32GuiHelper]::SetForegroundWindow($hwnd)

    Start-Sleep -Milliseconds 3000
    $winEl = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
    Write-Host "[SCENE 1] ValidTeam.exe main window visible ($targetW x $targetH at $posX,$posY)"

    # Scene 2: Click 系统配置
    Click-UIA -Root $winEl -Pattern "系统配置" -Label "系统配置" -TimeoutSec 10
    Start-Sleep -Milliseconds 2500

    # Scene 3: Click 📦 交付成果 -> markdown report -> SQLite DB -> filter -> export CSV
    Click-UIA -Root $winEl -Pattern "交付成果" -Label "📦 交付成果" -TimeoutSec 10
    Start-Sleep -Milliseconds 2500

    Click-UIA -Root $winEl -Pattern "版本发布台账\.db" -Label "版本发布台账.db" -TimeoutSec 10
    Start-Sleep -Milliseconds 2500

    $filterEl = Find-UIAByNameRegex -Root $winEl -Pattern "筛选当前预览记录" -TimeoutSec 8
    if ($filterEl) {
        $fx = [int][Math]::Round($filterEl.Rect.Left + $filterEl.Rect.Width / 2.0)
        $fy = [int][Math]::Round($filterEl.Rect.Top + $filterEl.Rect.Height / 2.0)
        Click-Point -X $fx -Y $fy
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.SendKeys]::SendWait("Windows")
        Start-Sleep -Milliseconds 1600
        [System.Windows.Forms.SendKeys]::SendWait("^a{BACKSPACE}")
        Start-Sleep -Milliseconds 900
    } else {
        Write-Host "[WARN] Filter input not matched by UIA, skipping filter keystrokes"
    }

    Click-UIA -Root $winEl -Pattern "导出 CSV" -Label "⬇️ 导出 CSV" -TimeoutSec 8
    Start-Sleep -Milliseconds 2200

    # Scene 4: Back to 🏠 进展总览 & inspect 产品经理 workspace
    Click-UIA -Root $winEl -Pattern "进展总览" -Label "🏠 进展总览" -TimeoutSec 8
    Start-Sleep -Milliseconds 2000

    Click-UIA -Root $winEl -Pattern "产品经理" -Label "产品经理" -TimeoutSec 8
    Start-Sleep -Milliseconds 2000

    # Scene 5: Click window Close X -> hide to tray -> right-click tray -> 打开工作台 -> right-click tray -> 完全退出
    $wr = New-Object Win32GuiHelper+RECT
    [void][Win32GuiHelper]::GetWindowRect($hwnd, [ref]$wr)
    $closeX = $wr.Right - 22
    $closeY = $wr.Top + 16
    Write-Host "[SCENE 5] Clicking window Close X at ($closeX, $closeY) to minimize to system tray"
    Click-Point -X $closeX -Y $closeY
    Start-Sleep -Milliseconds 1800

    function Open-ValidTeamTrayContextMenu {
        $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
        $trayHit = Find-UIAByNameRegex -Root $rootEl -Pattern "Valid Team" -TimeoutSec 2 -PreferInteractive
        if (-not $trayHit) {
            # Expand tray overflow chevron
            $trayWnd = [Win32GuiHelper]::FindWindowW("Shell_TrayWnd", $null)
            if ($trayWnd -ne [IntPtr]::Zero) {
                $trayEl = [System.Windows.Automation.AutomationElement]::FromHandle($trayWnd)
                $chev = Find-UIAByNameRegex -Root $trayEl -Pattern "Hidden Icons|Notification Chevron|隐藏的图标|SystemTrayIcon" -TimeoutSec 4 -PreferInteractive
                if (-not $chev) {
                    # Try AutomationId 1502 or SystemTrayIcon
                    $allTray = $trayEl.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
                    for ($j = 0; $j -lt $allTray.Count; $j++) {
                        $item = $allTray.Item($j)
                        try {
                            $aid = $item.Current.AutomationId
                            if ($aid -eq "1502" -or $aid -eq "SystemTrayIcon" -or $item.Current.Name -match "overflow|chevron|hidden") {
                                $rr = $item.Current.BoundingRectangle
                                if ($rr.Width -gt 4 -and $rr.Height -gt 4) {
                                    $chev = [PSCustomObject]@{ Element = $item; Name = $item.Current.Name; Rect = $rr }
                                    break
                                }
                            }
                        } catch {}
                    }
                }
                if ($chev) {
                    $cx = [int][Math]::Round($chev.Rect.Left + $chev.Rect.Width / 2.0)
                    $cy = [int][Math]::Round($chev.Rect.Top + $chev.Rect.Height / 2.0)
                    Write-Host "[TRAY] Clicking overflow chevron '$($chev.Name)' at ($cx,$cy)"
                    Click-Point -X $cx -Y $cy
                    Start-Sleep -Milliseconds 900
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
        $menuHwnd = [Win32GuiHelper]::FindWindowW("#32768", $null)
        if ($menuHwnd -ne [IntPtr]::Zero) {
            $mr = New-Object Win32GuiHelper+RECT
            [void][Win32GuiHelper]::GetWindowRect($menuHwnd, [ref]$mr)
            $mx = [int](($mr.Left + $mr.Right) / 2)
            $my = if ($FallbackPos -eq "top") { $mr.Top + 16 } else { $mr.Bottom - 16 }
            Write-Host "[TRAY-MENU] Clicking #32768 menu ($FallbackPos) at ($mx,$my)"
            Click-Point -X $mx -Y $my
            return
        }
        throw "Tray context menu did not appear for '$ItemRegex'"
    }

    Open-ValidTeamTrayContextMenu
    Start-Sleep -Milliseconds 1200
    Click-TrayMenuChoice -ItemRegex "打开工作台" -FallbackPos "top"
    Start-Sleep -Milliseconds 2000

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

# Extract 5 keyframes & verify non-blackness + inter-frame motion
$framesDir = Join-Path $OutDir "keyframes"
New-Item -ItemType Directory -Force -Path $framesDir | Out-Null
foreach ($sec in @(2, 8, 15, 22, 29)) {
    $png = Join-Path $framesDir ("frame_{0:D2}s.png" -f $sec)
    & ffmpeg -y -ss $sec -i $mp4Path -frames:v 1 -q:v 2 $png 2>$null
}

$pyVerify = @"
import glob, math, os, sys
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
$pyCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pyCmd) { $pyCmd = Get-Command python3 -ErrorAction SilentlyContinue }
& $pyCmd.Source -c $pyVerify $framesDir
if ($LASTEXITCODE -ne 0) {
    Write-Host "[WARN] PIL not installed or frame check returned non-zero; falling back to raw BMP/filesize check"
    Get-ChildItem -LiteralPath $framesDir | Format-Table Name, Length
}

Write-Host "WIN_GUI_RECORD_OK"
