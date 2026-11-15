param(
    [string]$VteamExe = ""
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [Console]::InputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"

if ([string]::IsNullOrWhiteSpace($VteamExe)) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $candidate1 = Join-Path $repoRoot "vteam\vteam.exe"
    $candidate2 = Join-Path $repoRoot "dist\windows\ValidTeam\vteam.exe"
    if (Test-Path -LiteralPath $candidate1) {
        $VteamExe = $candidate1
    } elseif (Test-Path -LiteralPath $candidate2) {
        $VteamExe = $candidate2
    } else {
        throw "Could not locate vteam.exe; pass -VteamExe <path>"
    }
}

$VteamExe = (Resolve-Path -LiteralPath $VteamExe).Path
Write-Host "[WIN-DEEP] Using vteam.exe: $VteamExe"

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = ($listener.LocalEndpoint).Port
$listener.Stop()
$addr = "127.0.0.1:$port"
$baseUrl = "http://$addr"

$tempBase = Join-Path $env:TEMP ("ValidTeam 中文验收 " + [System.Guid]::NewGuid().ToString("N").Substring(0, 8))
$projectsRoot = Join-Path $tempBase "Projects"
$secPath = Join-Path $tempBase "security.toml"
New-Item -ItemType Directory -Force -Path $projectsRoot | Out-Null

$secContent = @"
default_model = "test/mock-model"

[[api]]
name = "test"
format = "openai"
base_url = "http://127.0.0.1:9/v1"
key = "sk-test-verify"
models = ["mock-model"]
"@
[System.IO.File]::WriteAllText($secPath, $secContent, [System.Text.UTF8Encoding]::new($false))

$proc = $null
try {
    $env:VALID_TEAM_SECRET_BACKEND = "memory"
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $VteamExe
    $psi.Arguments = "-addr `"$addr`" -root `"$projectsRoot`" -security `"$secPath`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [System.Diagnostics.Process]::Start($psi)

    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        if ($proc.HasExited) {
            $errOut = $proc.StandardError.ReadToEnd()
            throw "vteam.exe exited early with code $($proc.ExitCode): $errOut"
        }
        try {
            $status = Invoke-RestMethod -Uri "$baseUrl/api/status" -TimeoutSec 2
            if ($status.platform -eq "windows/amd64") {
                $ready = $true
                break
            }
        } catch {
            Start-Sleep -Milliseconds 250
        }
    }
    if (-not $ready) {
        throw "vteam.exe did not become ready at $baseUrl/api/status"
    }
    Write-Host "[WIN-DEEP] /api/status OK on $baseUrl (platform=$($status.platform))"

    $projName = "中文Windows深度验收"
    $formBody = "name=" + [System.Uri]::EscapeDataString($projName)
    $null = Invoke-WebRequest -Uri "$baseUrl/projects" -Method Post -ContentType "application/x-www-form-urlencoded; charset=utf-8" -Body $formBody -MaximumRedirection 5 -UseBasicParsing

    $projDir = Join-Path $projectsRoot $projName
    $wsDir = Join-Path $projDir "workspace"
    $reportDir = Join-Path $wsDir "分析报告\深度验收"
    $dbDir = Join-Path $wsDir "数据仓库\深度验收"
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
    New-Item -ItemType Directory -Force -Path $dbDir | Out-Null

    $mdFile = Join-Path $reportDir "中文验收报告.md"
    [System.IO.File]::WriteAllText($mdFile, "# 中文黑盒验收`r`n内容：Windows UTF-8 正常`r`n", [System.Text.UTF8Encoding]::new($false))

    $dbFile = Join-Path $dbDir "台账.db"
    $pyScript = @"
import contextlib, sqlite3, sys
with contextlib.closing(sqlite3.connect(sys.argv[1], timeout=5.0)) as conn:
    conn.execute('CREATE TABLE "中文台账表" (id INTEGER PRIMARY KEY, title TEXT, remark TEXT)')
    conn.execute('INSERT INTO "中文台账表" (title, remark) VALUES (?, ?)', ('条目一', '你好Windows黑盒验收'))
    conn.commit()
"@
    $pyExe = $null
    foreach ($cand in @("python", "py", "python3")) {
        $cmd = Get-Command $cand -ErrorAction SilentlyContinue
        if ($cmd -and ($cmd.Source -notlike "*WindowsApps*")) {
            $pyExe = $cmd.Source
            break
        }
    }
    if (-not $pyExe) {
        throw "No usable Python interpreter found on Windows runner"
    }
    if ([System.IO.Path]::GetFileNameWithoutExtension($pyExe) -eq "py") {
        & $pyExe -3 -c $pyScript $dbFile
    } else {
        & $pyExe -c $pyScript $dbFile
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to seed SQLite test DB via Python"
    }

    $encProj = [System.Uri]::EscapeDataString($projName)
    $encFile = [System.Uri]::EscapeDataString("数据仓库/深度验收/台账.db")
    $encTable = [System.Uri]::EscapeDataString("中文台账表")

    $prevResp = Invoke-WebRequest -Uri "$baseUrl/projects/$encProj`?view=assets&file=$encFile" -UseBasicParsing
    if ($prevResp.StatusCode -ne 200) {
        throw "Asset preview HTTP $($prevResp.StatusCode)"
    }
    $prevHtml = [System.Text.Encoding]::UTF8.GetString($prevResp.RawContentStream.ToArray())
    if ($prevHtml -notmatch "你好Windows黑盒验收") {
        throw "SQLite preview missing expected Chinese content"
    }

    $csvResp = Invoke-WebRequest -Uri "$baseUrl/projects/$encProj/assets/db-csv?file=$encFile&table=$encTable" -UseBasicParsing
    if ($csvResp.StatusCode -ne 200) {
        throw "CSV export HTTP $($csvResp.StatusCode)"
    }
    $csvText = [System.Text.Encoding]::UTF8.GetString($csvResp.RawContentStream.ToArray())
    if ($csvText -notmatch "你好Windows黑盒验收") {
        throw "CSV export missing expected Chinese content"
    }
    Write-Host "[WIN-DEEP] Chinese SQLite preview & CSV export verified"

    # Verify SQLite file is unlocked immediately after preview/export.
    $renamedDb = "$dbFile.unlocked"
    Move-Item -LiteralPath $dbFile -Destination $renamedDb -Force
    Remove-Item -LiteralPath $renamedDb -Force
    Write-Host "[WIN-DEEP] Zero lingering SQLite file lock verified"
}
finally {
    if ($proc -and -not $proc.HasExited) {
        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            $proc.WaitForExit(5000) | Out-Null
        } catch {}
    }
    if (Test-Path -LiteralPath $tempBase) {
        Remove-Item -LiteralPath $tempBase -Recurse -Force
    }
}

Write-Host "WIN_DEEP_VERIFY_OK"
