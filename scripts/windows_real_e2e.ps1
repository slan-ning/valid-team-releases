# Windows Real NTFS & SQLite / Legacy Migration / Portable+Subst / Edge Headless UI E2E Verification
# Invoked by .github/workflows/clean-vm-e2e.yml on windows-latest (Zero App Source Code Required)
param(
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "Programs\ValidTeam"),
  [string]$DownloadDir = (Join-Path $env:RUNNER_TEMP "vt-win"),
  [string]$PortableDir = ""
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom([string]$TargetPath, [string]$Text) {
  $parent = Split-Path -Parent $TargetPath
  if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  [System.IO.File]::WriteAllBytes($TargetPath, [System.Text.UTF8Encoding]::new($false).GetBytes($Text))
}

function Get-FreeLoopbackPort {
  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
  $listener.Start()
  $p = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
  $listener.Stop()
  return $p
}

function Read-RedactedLog([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return "<empty>" }
  try {
    $fs = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8, $true)
    try { $txt = $sr.ReadToEnd() } finally { $sr.Dispose(); $fs.Dispose() }
    if ([string]::IsNullOrWhiteSpace($txt)) { return "<empty>" }
    if (-not [string]::IsNullOrWhiteSpace($env:VTEAM_TEST_API_KEY)) {
      $txt = $txt.Replace($env:VTEAM_TEST_API_KEY, "[REDACTED]")
    }
    return $txt.Trim()
  } catch {
    return "<unreadable: $($_.Exception.Message)>"
  }
}

function Wait-VteamReady([System.Diagnostics.Process]$Proc, [string]$BaseURL, [string]$OutLog, [string]$ErrLog, [string]$Label) {
  for ($i = 0; $i -lt 80; $i++) {
    if ($Proc.HasExited) { break }
    try {
      $resp = Invoke-RestMethod -Uri "$BaseURL/api/status" -Method Get -TimeoutSec 2
      if (-not $resp.bootstrapping) { return $resp }
    } catch {}
    Start-Sleep -Milliseconds 250
  }
  $exitInfo = if ($Proc.HasExited) { "exited early with code $($Proc.ExitCode)" } else { "did not finish bootstrap within 20s" }
  throw "$Label vteam.exe $exitInfo (stdout: $(Read-RedactedLog $OutLog) | stderr: $(Read-RedactedLog $ErrLog))"
}

function Remove-DirectoryWithRetry([string]$DirPath, [int]$MaxAttempts = 10) {
  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    if (-not (Test-Path -LiteralPath $DirPath)) { return }
    Remove-Item -LiteralPath $DirPath -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $DirPath)) { return }
    Start-Sleep -Milliseconds 250
  }
}

function Assert-CreateProject([string]$BaseURL, [string]$RootDir, [string]$ProjName, [string]$Tag) {
  $enc = [uri]::EscapeDataString($ProjName)
  $hdrFile = Join-Path $env:RUNNER_TEMP "win-e2e-$Tag-hdr.txt"
  $respFile = Join-Path $env:RUNNER_TEMP "win-e2e-$Tag-resp.html"
  try {
    curl.exe -fsS -D "$hdrFile" -o "$respFile" -X POST "$BaseURL/projects" -d "name=$enc"
    if ($LASTEXITCODE -ne 0) { throw "POST /projects ($ProjName) failed via curl.exe (exit=$LASTEXITCODE)" }
    $hdrRaw = Get-Content -LiteralPath $hdrFile -Raw
    if ($hdrRaw -notmatch "(?m)^HTTP/\S+[ \t]+303\b" -or $hdrRaw -notmatch "(?mi)^Location:[ \t]*/projects/\S+") {
      throw "POST /projects ($ProjName) did not return 303 redirect (headers: $hdrRaw)"
    }
  } finally {
    Remove-Item -LiteralPath $hdrFile, $respFile -Force -ErrorAction SilentlyContinue
  }
  $projDir = Join-Path $RootDir $ProjName
  $stateDB = Join-Path $projDir "state.db"
  $healthyMarker = Join-Path $projDir ".statedb_healthy.json"
  if (-not (Test-Path -LiteralPath $stateDB) -or (Get-Item -LiteralPath $stateDB).Length -eq 0) {
    throw "state.db was not created at $stateDB"
  }
  if (-not (Test-Path -LiteralPath $healthyMarker)) {
    throw ".statedb_healthy.json was not written at $healthyMarker"
  }
  return $projDir
}

function Assert-ZipExport([string]$Url, [string]$OutZip, [string]$Label) {
  curl.exe -fsS -o "$OutZip" "$Url"
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $OutZip) -or (Get-Item -LiteralPath $OutZip).Length -lt 100) {
    throw "$Label .zip export is empty or missing ($Url)"
  }
  return (Get-Item -LiteralPath $OutZip).Length
}

Write-Host "==> [Win-E2E 1/6] Running stripped native Windows Go unit test binaries (if staged in release)..."
foreach ($testBin in @("core-platform.test.exe", "vteam-statedb.test.exe", "windows-app.test.exe", "va-sdk.test.exe")) {
  $binPath = Join-Path $DownloadDir $testBin
  if (Test-Path -LiteralPath $binPath) {
    Write-Host "   -> Executing $testBin on real Windows NTFS (clean empty workdir)..."
    $tWork = Join-Path $env:RUNNER_TEMP ("ut-" + $testBin)
    if (Test-Path -LiteralPath $tWork) { Remove-Item -LiteralPath $tWork -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $tWork | Out-Null
    Push-Location $tWork
    try {
      & $binPath "-test.short"
      if ($LASTEXITCODE -ne 0) { throw "Native Windows unit test binary $testBin failed with exit code $LASTEXITCODE" }
      Write-Host "   [PASS] $testBin passed on real Windows NTFS!"
    } finally {
      Pop-Location
      Remove-Item -LiteralPath $tWork -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

$vteamExe = Join-Path $InstallDir "vteam.exe"
$vaExe = Join-Path $InstallDir "va.exe"
if (-not (Test-Path -LiteralPath $vteamExe)) { throw "Missing $vteamExe" }
if (-not (Test-Path -LiteralPath $vaExe)) { throw "Missing $vaExe" }

$e2eRoot = Join-Path $env:RUNNER_TEMP "Valid Team 中文工作区 #1"
if (Test-Path -LiteralPath $e2eRoot) { Remove-Item -LiteralPath $e2eRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $e2eRoot | Out-Null

# Pre-seed v1.2.11 pure-Markdown legacy project (no opening.json, no state.db)
$legacyName = "legacy-v1211-中文"
$legacyEnc = [uri]::EscapeDataString($legacyName)
$legacyDir = Join-Path $e2eRoot $legacyName
Write-Utf8NoBom (Join-Path $legacyDir "project.toml") ("name = `"旧版升级项目`"`nwork_start = `"09:00`"`nwork_end = `"18:30`"`n")
Write-Utf8NoBom (Join-Path $legacyDir "NOTES.md") "# 旧版笔记`n"
Write-Utf8NoBom (Join-Path $legacyDir "roles\system\ROLE.md") "# 总办职责`n"
Write-Utf8NoBom (Join-Path $legacyDir "directives\20261101T100000-leg01.md") (@(
  'id: 20261101T100000-leg01', 'from: boss', 'to: system', 'subject: 历史冷迁移任务',
  'kind: task', 'status: done', 'created_at: 2026-11-01T10:00:00Z', 'finished_at: 2026-11-01T10:05:00Z',
  '---', '历史冷迁移正文', '---result---', '历史冷迁移已完成', ''
) -join "`n")

$port = Get-FreeLoopbackPort
$addr = "127.0.0.1:$port"
$baseURL = "http://$addr"
$secFile = Join-Path $e2eRoot "security.toml"
$secToml = "default_model = `"selftest/mock`"`n`n[[api]]`nname = `"selftest`"`nformat = `"openai`"`nbase_url = `"http://127.0.0.1:9/v1`"`nkey = `"sk-selftest-placeholder`"`nmodels = [`"mock`"]`n"
[System.IO.File]::WriteAllBytes($secFile, [System.Text.Encoding]::ASCII.GetBytes($secToml))

$outLog = Join-Path $env:RUNNER_TEMP "win-e2e-vteam-out.log"
$errLog = Join-Path $env:RUNNER_TEMP "win-e2e-vteam-err.log"
$portOutLog = Join-Path $env:RUNNER_TEMP "win-e2e-portable-out.log"
$portErrLog = Join-Path $env:RUNNER_TEMP "win-e2e-portable-err.log"
Remove-Item -LiteralPath $outLog, $errLog, $portOutLog, $portErrLog -Force -ErrorAction SilentlyContinue

$daemon = $null
$portDaemon = $null
$edgeProc = $null
$cdpSocket = $null
$edgeUserDataDir = Join-Path $env:RUNNER_TEMP "vt-edge-profile"
$substDrv = $null
$substMounted = $false
$substBacking = Join-Path $env:RUNNER_TEMP "vt-subst-backing"
$substRoot = $null
$hadPrimaryError = $false

Write-Host "==> [Win-E2E 2/6] Starting Instance #1 vteam.exe on $baseURL (legacy v1.2.11 cold migration + devil path: $e2eRoot)..."
$daemon = Start-Process -FilePath $vteamExe -ArgumentList @("-addr", $addr, "-root", "`"$e2eRoot`"", "-security", "`"$secFile`"") -WorkingDirectory $InstallDir -PassThru -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog

try {
  $status = Wait-VteamReady $daemon $baseURL $outLog $errLog "Instance#1"
  if (-not $status.canary_ok -or $status.daemon_health -ne "healthy" -or [int]$status.isolated_project_count -ne 0) {
    throw "Instance#1 /api/status unexpected: canary_ok=$($status.canary_ok) health=$($status.daemon_health) isolated=$($status.isolated_project_count) err=$($status.canary_error)"
  }
  $legacyDB = Join-Path $legacyDir "state.db"
  if (-not (Test-Path -LiteralPath $legacyDB) -or (Get-Item -LiteralPath $legacyDB).Length -eq 0 -or -not (Test-Path -LiteralPath (Join-Path $legacyDir ".statedb_healthy.json"))) {
    throw "Legacy cold migration did not materialize state.db + .statedb_healthy.json under $legacyDir"
  }
  Write-Host "   [PASS] /api/status canary_ok=true daemon_health=healthy isolated=0 & v1.2.11 legacy directives/*.md migrated cleanly!"

  Write-Host "==> [Win-E2E 3/6] Testing real SQLite CreateProject, VACUUM INTO .zip backup & ?salvage=1..."
  $projName = "win-team-中文"
  $encProj = [uri]::EscapeDataString($projName)
  $projDir = Assert-CreateProject $baseURL $e2eRoot $projName "inst1"
  Write-Utf8NoBom (Join-Path $projDir "workspace\分析报告\测试专题\summary.md") "# Windows E2E Deliverable`n"

  $zipLen = Assert-ZipExport "$baseURL/projects/$encProj/export-backup" (Join-Path $env:RUNNER_TEMP "win-team-backup.zip") "Instance#1 normal"
  $salvLen = Assert-ZipExport "$baseURL/projects/$encProj/export-backup?salvage=1" (Join-Path $env:RUNNER_TEMP "win-team-salvage.zip") "Instance#1 salvage"
  Write-Host "   [PASS] Real SQLite state.db + VACUUM INTO & ?salvage=1 export-backup succeeded ($zipLen / $salvLen bytes)"

  if (-not [string]::IsNullOrWhiteSpace($env:VTEAM_TEST_API_KEY)) {
    Write-Host "==> [Win-E2E 3.5/6] VTEAM_TEST_API_KEY present: verifying real POST /setup + va.exe config check..."
    $apiName = if ($env:VTEAM_TEST_API_NAME) { $env:VTEAM_TEST_API_NAME } else { "opencode-go" }
    $apiFmt = if ($env:VTEAM_TEST_API_FORMAT) { $env:VTEAM_TEST_API_FORMAT } else { "openai" }
    $apiBase = if ($env:VTEAM_TEST_API_BASE_URL) { $env:VTEAM_TEST_API_BASE_URL } else { "https://opencode.ai/inference/go/openai/v1" }
    $apiModel = if ($env:VTEAM_TEST_API_MODEL) { $env:VTEAM_TEST_API_MODEL } else { "deepseek-v4.1-flash" }
    $setupHdr = Join-Path $env:RUNNER_TEMP "win-e2e-setup-hdr.txt"
    $setupResp = Join-Path $env:RUNNER_TEMP "win-e2e-setup-resp.html"
    $setupOK = $false
    for ($setupTry = 1; $setupTry -le 4; $setupTry++) {
      Remove-Item -LiteralPath $setupHdr, $setupResp -Force -ErrorAction SilentlyContinue
      curl.exe -sS -D "$setupHdr" -o "$setupResp" -X POST "$baseURL/setup" `
        --data-urlencode "name=$apiName" --data-urlencode "format=$apiFmt" `
        --data-urlencode "base_url=$apiBase" --data-urlencode "key=$($env:VTEAM_TEST_API_KEY)" --data-urlencode "model=$apiModel"
      $hdrTxt = if (Test-Path -LiteralPath $setupHdr) { Get-Content -LiteralPath $setupHdr -Raw } else { "" }
      if ($LASTEXITCODE -eq 0 -and $hdrTxt -match "(?m)^HTTP/\S+[ \t]+303\b" -and $hdrTxt -match "(?mi)^Location:[ \t]*/\r?$") {
        & $vaExe "config" "--security" "$secFile" "check" | Out-Null
        if ($LASTEXITCODE -eq 0) {
          $setupOK = $true
          Write-Host "   [PASS] POST /setup + va.exe config check succeeded on Windows ($apiName/$apiModel, attempt $setupTry)"
          break
        }
      }
      if ($setupTry -lt 4) { Start-Sleep -Seconds ($setupTry * 3) }
    }
    if (-not $setupOK) {
      $safeHdr = if (Test-Path -LiteralPath $setupHdr) { (Get-Content -LiteralPath $setupHdr -Raw).Replace($env:VTEAM_TEST_API_KEY, "[REDACTED]") } else { "<no headers>" }
      throw "POST /setup failed after 4 attempts ($apiName/$apiModel): $safeHdr"
    }
  }

  # Stage 4/6: Portable vteam.exe + subst Cross-Drive Workspace + broken-isolated Data Protection Mode
  $requirePortable = -not [string]::IsNullOrWhiteSpace($PortableDir)
  $resolvedPortDir = $PortableDir
  if ([string]::IsNullOrWhiteSpace($resolvedPortDir)) {
    $fallbackPortDir = Join-Path $env:RUNNER_TEMP "vt-win-portable"
    if (Test-Path -LiteralPath $fallbackPortDir) { $resolvedPortDir = $fallbackPortDir }
  }
  $baseURL2 = $null
  if (-not [string]::IsNullOrWhiteSpace($resolvedPortDir)) {
    Write-Host "==> [Win-E2E 4/6] Starting Instance #2 (Portable vteam.exe + subst cross-drive workspace + broken-isolated fault isolation)..."
    $portVteamItem = Get-ChildItem -LiteralPath $resolvedPortDir -Filter "vteam.exe" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $portVteamItem) { throw "PortableDir '$resolvedPortDir' does not contain vteam.exe" }
    $portableExePath = $portVteamItem.FullName
    $portableExeDir = $portVteamItem.DirectoryName

    foreach ($drv in @('V', 'W', 'X', 'Y', 'Z')) {
      if (-not (Test-Path "${drv}:\")) { $substDrv = $drv; break }
    }
    if (-not $substDrv) { throw "No free drive letter among V..Z available for subst cross-drive test" }
    if (Test-Path -LiteralPath $substBacking) { Remove-Item -LiteralPath $substBacking -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $substBacking | Out-Null
    & subst.exe "${substDrv}:" "$substBacking"
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path "${substDrv}:\")) { throw "subst ${substDrv}: -> $substBacking failed (exit=$LASTEXITCODE)" }
    $substMounted = $true

    $substRoot = "${substDrv}:\Valid Team 跨盘工作区"
    New-Item -ItemType Directory -Force -Path $substRoot | Out-Null
    $substSecFile = Join-Path $substRoot "security.toml"
    [System.IO.File]::WriteAllBytes($substSecFile, [System.Text.Encoding]::ASCII.GetBytes($secToml))

    $brokenDir = Join-Path $substRoot "broken-isolated"
    Write-Utf8NoBom (Join-Path $brokenDir "project.toml") ("name = `"损坏隔离测试`"`nwork_start = `"09:00`"`nwork_end = `"18:30`"`n")
    Write-Utf8NoBom (Join-Path $brokenDir "workspace\分析报告\抢救说明.md") "# 抢救说明`n损坏库隔离模式下成果完好。`n"
    [System.IO.File]::WriteAllBytes((Join-Path $brokenDir "state.db"), [System.Text.Encoding]::ASCII.GetBytes("corrupted-not-a-sqlite-file"))

    $port2 = Get-FreeLoopbackPort
    $addr2 = "127.0.0.1:$port2"
    $baseURL2 = "http://$addr2"
    # WorkingDirectory MUST stay on C: ($portableExeDir), never on ${substDrv}:\ so subst /D can unmount cleanly!
    $portDaemon = Start-Process -FilePath $portableExePath -ArgumentList @("-addr", $addr2, "-root", "`"$substRoot`"", "-security", "`"$substSecFile`"") -WorkingDirectory $portableExeDir -PassThru -WindowStyle Hidden -RedirectStandardOutput $portOutLog -RedirectStandardError $portErrLog

    $status2 = Wait-VteamReady $portDaemon $baseURL2 $portOutLog $portErrLog "Instance#2(Portable+Subst)"
    if (-not $status2.canary_ok -or [int]$status2.isolated_project_count -ne 1) {
      throw "Instance#2 /api/status expected canary_ok=true & isolated_project_count=1, got canary_ok=$($status2.canary_ok) isolated=$($status2.isolated_project_count)"
    }

    $portProjName = "portable-跨盘项目"
    $encPortProj = [uri]::EscapeDataString($portProjName)
    Assert-CreateProject $baseURL2 $substRoot $portProjName "inst2" | Out-Null
    Assert-ZipExport "$baseURL2/projects/$encPortProj/export-backup" (Join-Path $env:RUNNER_TEMP "win-portable-backup.zip") "Instance#2 portable" | Out-Null
    Assert-ZipExport "$baseURL2/projects/broken-isolated/export-backup?salvage=1" (Join-Path $env:RUNNER_TEMP "win-broken-salvage.zip") "Instance#2 broken-salvage" | Out-Null
    Write-Host "   [PASS] Portable vteam.exe + subst ${substDrv}: cross-drive SQLite + isolated_project_count=1 + ?salvage=1 passed!"
  } elseif ($requirePortable) {
    throw "PortableDir was requested ('$PortableDir') but could not be resolved"
  }

  # Stage 5/6: Native .NET ClientWebSocket -> msedge.exe --headless=new Real UI Inspection (0 npm/pip)
  Write-Host "==> [Win-E2E 5/6] Running headless Microsoft Edge CDP real browser UI & viewport inspection..."
  $edgeCandidates = @()
  $edgeCmd = Get-Command "msedge.exe" -ErrorAction SilentlyContinue
  if ($edgeCmd -and $edgeCmd.Source) { $edgeCandidates += $edgeCmd.Source }
  $edgeCandidates += @("C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe", "C:\Program Files\Microsoft\Edge\Application\msedge.exe")
  $edgeExe = $edgeCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
  if (-not $edgeExe) { throw "msedge.exe not found on Windows runner" }

  $cdpPort = Get-FreeLoopbackPort
  if (Test-Path -LiteralPath $edgeUserDataDir) { Remove-Item -LiteralPath $edgeUserDataDir -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $edgeUserDataDir | Out-Null
  $edgeProc = Start-Process -FilePath $edgeExe -ArgumentList @("--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check", "--remote-debugging-port=$cdpPort", "--user-data-dir=`"$edgeUserDataDir`"", "about:blank") -WorkingDirectory $env:RUNNER_TEMP -PassThru -WindowStyle Hidden

  $wsUrl = $null
  for ($i = 0; $i -lt 60; $i++) {
    if ($edgeProc.HasExited) { throw "msedge.exe exited prematurely with code $($edgeProc.ExitCode)" }
    try {
      $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$cdpPort/json/list" -Method Get -TimeoutSec 2
      $pageTarget = @($targets) | Where-Object { $_.type -eq "page" -and $_.webSocketDebuggerUrl } | Select-Object -First 1
      if ($pageTarget) { $wsUrl = [string]$pageTarget.webSocketDebuggerUrl; break }
    } catch {}
    Start-Sleep -Milliseconds 200
  }
  if (-not $wsUrl) { throw "Timed out waiting for Edge CDP webSocketDebuggerUrl on 127.0.0.1:$cdpPort" }

  $cdpSocket = [System.Net.WebSockets.ClientWebSocket]::new()
  $connCts = [System.Threading.CancellationTokenSource]::new(15000)
  try { $cdpSocket.ConnectAsync([Uri]$wsUrl, $connCts.Token).GetAwaiter().GetResult() } finally { $connCts.Dispose() }

  $script:cdpNextId = 1
  $script:cdpPageErrors = [System.Collections.Generic.List[string]]::new()
  $script:cdpConsoleErrors = [System.Collections.Generic.List[string]]::new()

  function Handle-CdpEvent($Msg) {
    if (-not $Msg -or -not $Msg.method) { return }
    if ($Msg.method -eq "Runtime.exceptionThrown") {
      $desc = ""
      if ($Msg.params -and $Msg.params.exceptionDetails) {
        $desc = [string]$Msg.params.exceptionDetails.text
        if ($Msg.params.exceptionDetails.exception -and $Msg.params.exceptionDetails.exception.description) {
          $desc = "$desc $($Msg.params.exceptionDetails.exception.description)"
        }
      }
      $script:cdpPageErrors.Add($desc.Trim())
    } elseif ($Msg.method -eq "Runtime.consoleAPICalled" -and $Msg.params -and $Msg.params.type -eq "error") {
      $parts = foreach ($a in @($Msg.params.args)) {
        if ($null -ne $a.value) { [string]$a.value } elseif ($a.description) { [string]$a.description }
      }
      $joined = ($parts -join " ").Trim()
      if ($joined -notmatch "favicon\.ico") { $script:cdpConsoleErrors.Add("console.error: $joined") }
    } elseif ($Msg.method -eq "Log.entryAdded" -and $Msg.params -and $Msg.params.entry -and $Msg.params.entry.level -eq "error") {
      $u = [string]$Msg.params.entry.url
      $t = [string]$Msg.params.entry.text
      if ($u -notmatch "favicon\.ico" -and $t -notmatch "favicon\.ico") { $script:cdpConsoleErrors.Add("log.error: $t ($u)") }
    }
  }

  function Receive-CdpJson([System.Net.WebSockets.ClientWebSocket]$Sock, [int]$TimeoutMs = 15000) {
    $ms = [System.IO.MemoryStream]::new()
    $buf = [byte[]]::new(16384)
    $seg = [System.ArraySegment[byte]]::new($buf)
    $rCts = [System.Threading.CancellationTokenSource]::new($TimeoutMs)
    try {
      do {
        $res = $Sock.ReceiveAsync($seg, $rCts.Token).GetAwaiter().GetResult()
        if ($res.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { throw "Edge CDP WebSocket closed unexpectedly" }
        if ($res.Count -gt 0) { $ms.Write($buf, 0, $res.Count) }
      } while (-not $res.EndOfMessage)
      return ([System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json)
    } finally {
      $rCts.Dispose()
      $ms.Dispose()
    }
  }

  function Invoke-CdpCommand([string]$Method, [hashtable]$Params = @{}) {
    $id = $script:cdpNextId
    $script:cdpNextId = $id + 1
    $bytes = [System.Text.Encoding]::UTF8.GetBytes((@{ id = $id; method = $Method; params = $Params } | ConvertTo-Json -Depth 10 -Compress))
    $sCts = [System.Threading.CancellationTokenSource]::new(10000)
    try {
      $cdpSocket.SendAsync([System.ArraySegment[byte]]::new($bytes), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $sCts.Token).GetAwaiter().GetResult()
    } finally {
      $sCts.Dispose()
    }
    while ($true) {
      $msg = Receive-CdpJson $cdpSocket 15000
      if ($null -ne $msg.id -and [int]$msg.id -eq $id) {
        if ($msg.error) { throw "CDP $Method error: $($msg.error.message)" }
        return $msg.result
      }
      Handle-CdpEvent $msg
    }
  }

  function Invoke-CdpEval([string]$Expression) {
    $res = Invoke-CdpCommand "Runtime.evaluate" @{ expression = $Expression; returnByValue = $true; awaitPromise = $true }
    if ($res.exceptionDetails) { throw "JS evaluation threw exception: $($res.exceptionDetails.text) | expr=$Expression" }
    return $res.result.value
  }

  function Navigate-CdpAndWait([string]$TargetUrl) {
    try { Invoke-CdpEval "window.__vt_nav_seq = 1; true" | Out-Null } catch {}
    Invoke-CdpCommand "Page.navigate" @{ url = $TargetUrl } | Out-Null
    for ($w = 0; $w -lt 60; $w++) {
      try {
        if ((Invoke-CdpEval "(!window.__vt_nav_seq && document.readyState === 'complete')") -eq $true) { return }
      } catch {}
      Start-Sleep -Milliseconds 150
    }
    throw "Timed out waiting for Edge navigation readyState=complete on $TargetUrl"
  }

  function Reload-CdpAndWait {
    Invoke-CdpEval "window.__vt_reload_seq = 1; true" | Out-Null
    Invoke-CdpCommand "Page.reload" @{ ignoreCache = $false } | Out-Null
    for ($w = 0; $w -lt 60; $w++) {
      try {
        if ((Invoke-CdpEval "(!window.__vt_reload_seq && document.readyState === 'complete')") -eq $true) { return }
      } catch {}
      Start-Sleep -Milliseconds 150
    }
    throw "Timed out waiting for Edge Page.reload readyState=complete"
  }

  function Assert-ZeroHorizontalOverflow([string]$PageLabel) {
    foreach ($vp in @(@{ width = 1440; height = 900; mobile = $false }, @{ width = 375; height = 812; mobile = $true })) {
      Invoke-CdpCommand "Emulation.setDeviceMetricsOverride" @{ width = [int]$vp.width; height = [int]$vp.height; deviceScaleFactor = 1; mobile = [bool]$vp.mobile } | Out-Null
      Start-Sleep -Milliseconds 80
      $dims = Invoke-CdpEval "JSON.stringify({ sw: document.documentElement.scrollWidth, iw: window.innerWidth })" | ConvertFrom-Json
      if ([int]$dims.sw -gt [int]$dims.iw) {
        throw "Horizontal overflow on $PageLabel at $($vp.width)x$($vp.height): scrollWidth=$($dims.sw) > innerWidth=$($dims.iw)"
      }
    }
    Invoke-CdpCommand "Emulation.clearDeviceMetricsOverride" @{} | Out-Null
  }

  Invoke-CdpCommand "Page.enable" @{} | Out-Null
  Invoke-CdpCommand "Runtime.enable" @{} | Out-Null
  Invoke-CdpCommand "Log.enable" @{} | Out-Null

  # UI Check 1: Home / Workspace Rail
  Navigate-CdpAndWait "$baseURL/"
  $homeCheck = Invoke-CdpEval "JSON.stringify({ rail: !!document.querySelector('.ws-rail'), badTokens: /\b(undefined|NaN)\b/.test(document.body ? document.body.innerText : '') })" | ConvertFrom-Json
  if (-not $homeCheck.rail -or $homeCheck.badTokens) {
    throw "Edge UI Check 1 (/) failed: ws-rail=$($homeCheck.rail) badTokens=$($homeCheck.badTokens)"
  }
  Write-Host "   [PASS] Edge UI Check 1 (/): .ws-rail rendered & zero undefined/NaN text"

  # UI Check 2: Cold-migrated legacy project overview & task detail drawer
  Navigate-CdpAndWait "$baseURL/projects/$legacyEnc"
  if (-not (Invoke-CdpEval "!!document.querySelector('#task-row-20261101T100000-leg01')")) {
    throw "Edge UI Check 2 (/projects/$legacyName) missing #task-row-20261101T100000-leg01"
  }
  Invoke-CdpEval "openTaskDetail('20261101T100000-leg01'); true" | Out-Null
  $drawerLoaded = $false
  for ($d = 0; $d -lt 25; $d++) {
    if (Invoke-CdpEval "(function(){ var el = document.querySelector('#task-detail-drawer'); return !!(el && el.textContent && el.textContent.indexOf('历史冷迁移任务') !== -1); })()") {
      $drawerLoaded = $true; break
    }
    Start-Sleep -Milliseconds 120
  }
  if (-not $drawerLoaded) { throw "Edge UI Check 2: #task-detail-drawer did not render '历史冷迁移任务' within 3s" }
  Write-Host "   [PASS] Edge UI Check 2 (/projects/$legacyName): #task-row-20261101T100000-leg01 + openTaskDetail drawer verified"

  # UI Check 3: Role chat draft persistence, sidebar badge, reload survival & dual-viewport zero overflow
  Navigate-CdpAndWait "$baseURL/projects/$encProj?view=role&to=system"
  if (-not (Invoke-CdpEval "!!(document.querySelector('#directive-form') && document.querySelector('#directive-body'))")) {
    throw "Edge UI Check 3: #directive-form or #directive-body missing on role chat page"
  }
  $draftSavedJson = Invoke-CdpEval @'
(function(){
  var ta = document.querySelector('#directive-body');
  ta.value = 'Windows Edge 草稿持久化实测';
  ta.dispatchEvent(new Event('input', { bubbles: true }));
  return JSON.stringify({
    stored: localStorage.getItem('vteam.draft.chat:win-team-中文:system'),
    badge: !!document.querySelector('.nav-draft-badge')
  });
})()
'@
  $draftSaved = $draftSavedJson | ConvertFrom-Json
  if ($draftSaved.stored -ne "Windows Edge 草稿持久化实测" -or -not $draftSaved.badge) {
    throw "Edge UI Check 3 draft save failed: stored='$($draftSaved.stored)' badge=$($draftSaved.badge)"
  }
  Reload-CdpAndWait
  $restoredVal = Invoke-CdpEval "document.querySelector('#directive-body') ? document.querySelector('#directive-body').value : ''"
  if ($restoredVal -ne "Windows Edge 草稿持久化实测") {
    throw "Edge UI Check 3 draft reload restore failed: got '$restoredVal'"
  }
  $clearedNull = Invoke-CdpEval @'
(function(){
  var ta = document.querySelector('#directive-body');
  ta.value = '';
  ta.dispatchEvent(new Event('input', { bubbles: true }));
  return localStorage.getItem('vteam.draft.chat:win-team-中文:system') === null;
})()
'@
  if (-not $clearedNull) { throw "Edge UI Check 3 draft clear failed: localStorage key was not removed" }
  Assert-ZeroHorizontalOverflow "role-chat(win-team-中文)"
  Write-Host "   [PASS] Edge UI Check 3 (role chat): draft save/badge/reload/clear + 1440x900 & 375x812 zero overflow verified"

  # UI Check 4: Instance #2 Data Protection Mode page & dual-viewport zero overflow
  if ($baseURL2) {
    Navigate-CdpAndWait "$baseURL2/projects/broken-isolated"
    $protCheckJson = Invoke-CdpEval @'
(function(){
  var bodyTxt = document.body ? document.body.innerText : '';
  var btn = document.querySelector('#protection-salvage-export-btn');
  var href = btn ? (btn.getAttribute('href') || '') : '';
  return JSON.stringify({
    hasBanner: bodyTxt.indexOf('已为项目开启数据保护模式') !== -1,
    hasSalvageBtn: !!(btn && href.indexOf('/export-backup?salvage=1') !== -1)
  });
})()
'@
    $protCheck = $protCheckJson | ConvertFrom-Json
    if (-not $protCheck.hasBanner -or -not $protCheck.hasSalvageBtn) {
      throw "Edge UI Check 4 (/projects/broken-isolated) failed: hasBanner=$($protCheck.hasBanner) hasSalvageBtn=$($protCheck.hasSalvageBtn)"
    }
    Assert-ZeroHorizontalOverflow "protection-panel(broken-isolated)"
    Write-Host "   [PASS] Edge UI Check 4 (/projects/broken-isolated): Data Protection Mode banner + salvage button + dual-viewport zero overflow verified"
  }

  Invoke-CdpEval "true" | Out-Null
  if ($script:cdpPageErrors.Count -gt 0 -or $script:cdpConsoleErrors.Count -gt 0) {
    throw "Edge headless UI detected runtime errors! pageerror($($script:cdpPageErrors.Count)): [$($script:cdpPageErrors -join ' | ')] console/log error($($script:cdpConsoleErrors.Count)): [$($script:cdpConsoleErrors -join ' | ')]"
  }
  Write-Host "   [PASS] Edge CDP global error gate: pageerror=0 & console/log error=0!"
} catch {
  $hadPrimaryError = $true
  throw
} finally {
  Write-Host "==> [Win-E2E 6/6] Executing strict 4-step teardown & verifying zero lingering Windows/subst locks..."

  # Step 1: Close CDP WebSocket, terminate Edge process tree, remove & verify $edgeUserDataDir
  if ($cdpSocket) {
    try {
      if ($cdpSocket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        $closeCts = [System.Threading.CancellationTokenSource]::new(2000)
        try { $cdpSocket.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "done", $closeCts.Token).GetAwaiter().GetResult() } finally { $closeCts.Dispose() }
      }
    } catch {} finally { $cdpSocket.Dispose() }
  }
  if ($edgeProc) {
    if (-not $edgeProc.HasExited) {
      & "$env:SystemRoot\System32\taskkill.exe" /T /F /PID $edgeProc.Id 2>$null | Out-Null
      $edgeProc.WaitForExit(5000) | Out-Null
    }
    Remove-DirectoryWithRetry $edgeUserDataDir 12
    if (-not $hadPrimaryError -and (Test-Path -LiteralPath $edgeUserDataDir)) {
      throw "Lingering Edge file lock prevented removal of $edgeUserDataDir"
    }
  }

  # Step 2: Terminate Instance #2 (portable daemon)
  if ($portDaemon -and -not $portDaemon.HasExited) {
    & "$env:SystemRoot\System32\taskkill.exe" /T /F /PID $portDaemon.Id 2>$null | Out-Null
    $portDaemon.WaitForExit(5000) | Out-Null
  }

  # Step 3: Remove cross-drive workspace $substRoot & assert zero lingering SQLite -wal/-shm locks
  if ($substRoot -and (Test-Path -LiteralPath $substRoot)) {
    Remove-DirectoryWithRetry $substRoot 10
    if (-not $hadPrimaryError -and (Test-Path -LiteralPath $substRoot)) {
      throw "Lingering cross-drive SQLite file lock prevented removal of $substRoot"
    }
  }

  # Step 4: Unmount subst drive letter & remove backing directory
  if ($substMounted -and $substDrv) {
    & subst.exe "${substDrv}:" /D 2>$null | Out-Null
    if (-not $hadPrimaryError -and (Test-Path "${substDrv}:\")) {
      throw "subst ${substDrv}: /D failed to unmount virtual drive"
    }
  }
  if (Test-Path -LiteralPath $substBacking) { Remove-DirectoryWithRetry $substBacking 10 }

  # Terminate Instance #1 daemon & clean temp logs/zips
  if ($daemon -and -not $daemon.HasExited) {
    & "$env:SystemRoot\System32\taskkill.exe" /T /F /PID $daemon.Id 2>$null | Out-Null
    $daemon.WaitForExit(5000) | Out-Null
  }
  Remove-Item -LiteralPath @(
    (Join-Path $env:RUNNER_TEMP "win-team-backup.zip"),
    (Join-Path $env:RUNNER_TEMP "win-team-salvage.zip"),
    (Join-Path $env:RUNNER_TEMP "win-portable-backup.zip"),
    (Join-Path $env:RUNNER_TEMP "win-broken-salvage.zip"),
    (Join-Path $env:RUNNER_TEMP "win-e2e-setup-hdr.txt"),
    (Join-Path $env:RUNNER_TEMP "win-e2e-setup-resp.html"),
    $outLog, $errLog, $portOutLog, $portErrLog
  ) -Force -ErrorAction SilentlyContinue
}

Remove-DirectoryWithRetry $e2eRoot 10
if (Test-Path -LiteralPath $e2eRoot) { throw "Lingering Windows file handle prevented removal of $e2eRoot" }
Write-Host "✅ WIN_REAL_E2E_OK: 4x Native Go Test Bins + Legacy Migration + Portable/Subst/Protection + Edge Headless UI + Clean Teardown passed!"
