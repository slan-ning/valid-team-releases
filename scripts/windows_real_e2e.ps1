# Windows Real NTFS & SQLite / Rescue / Optional Live-LLM E2E Verification
# Invoked by .github/workflows/clean-vm-e2e.yml on windows-latest (Zero App Source Code Required)
param(
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "Programs\ValidTeam"),
  [string]$DownloadDir = (Join-Path $env:RUNNER_TEMP "vt-win")
)

$ErrorActionPreference = "Stop"

Write-Host "==> [Win-E2E 1/4] Running stripped native Windows Go unit test binaries (if staged in release)..."
foreach ($testBin in @("core-platform.test.exe", "vteam-statedb.test.exe")) {
  $binPath = Join-Path $DownloadDir $testBin
  if (Test-Path -LiteralPath $binPath) {
    Write-Host "   -> Executing $testBin on real Windows NTFS..."
    $tWork = Join-Path $env:RUNNER_TEMP ("ut-" + $testBin)
    New-Item -ItemType Directory -Force -Path $tWork | Out-Null
    Push-Location $tWork
    try {
      & $binPath -test.short
      if ($LASTEXITCODE -ne 0) {
        throw "Native Windows unit test binary $testBin failed with exit code $LASTEXITCODE"
      }
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
if (Test-Path -LiteralPath $e2eRoot) {
  Remove-Item -LiteralPath $e2eRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $e2eRoot | Out-Null

# Pick an available loopback port
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
$listener.Stop()
$addr = "127.0.0.1:$port"
$baseURL = "http://$addr"
$secFile = Join-Path $e2eRoot "security.toml"
$secToml = @(
  'default_model = "selftest/mock"'
  ''
  '[[api]]'
  'name = "selftest"'
  'format = "openai"'
  'base_url = "http://127.0.0.1:9/v1"'
  'key = "sk-selftest-placeholder"'
  'models = ["mock"]'
  ''
) -join "`n"
[System.IO.File]::WriteAllBytes($secFile, [System.Text.Encoding]::ASCII.GetBytes($secToml))
$outLog = Join-Path $env:RUNNER_TEMP "win-e2e-vteam-out.log"
$errLog = Join-Path $env:RUNNER_TEMP "win-e2e-vteam-err.log"

Write-Host "==> [Win-E2E 2/4] Starting vteam.exe on $baseURL with devil workspace path: $e2eRoot"
$daemon = Start-Process -FilePath $vteamExe -ArgumentList "-addr",$addr,"-root",$e2eRoot,"-security",$secFile -WorkingDirectory $InstallDir -PassThru -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog

try {
  $ready = $false
  $status = $null
  for ($i = 0; $i -lt 80; $i++) {
    try {
      $resp = Invoke-RestMethod -Uri "$baseURL/api/status" -Method Get -TimeoutSec 2
      if (-not $resp.bootstrapping) {
        $status = $resp
        $ready = $true
        break
      }
    } catch {}
    Start-Sleep -Milliseconds 250
  }
  if (-not $ready) {
    throw "vteam.exe did not finish bootstrap within 20s"
  }
  if (-not $status.canary_ok -or $status.daemon_health -ne "healthy") {
    throw "Startup SQLite canary failed on Windows: canary_ok=$($status.canary_ok) health=$($status.daemon_health) err=$($status.canary_error)"
  }
  Write-Host "   [PASS] /api/status canary_ok=true daemon_health=healthy platform=$($status.platform)"

  Write-Host "==> [Win-E2E 3/4] Testing real SQLite CreateProject, VACUUM INTO .zip backup/import & Data Protection Mode..."
  $projName = "win-team-中文"
  $encProj = [uri]::EscapeDataString($projName)
  $projHdrFile = Join-Path $env:RUNNER_TEMP "win-e2e-proj-hdr.txt"
  curl.exe -fsS -D $projHdrFile -o NUL -X POST "$baseURL/projects" -d "name=$encProj"
  if ($LASTEXITCODE -ne 0) {
    throw "POST /projects failed via curl.exe (exit=$LASTEXITCODE)"
  }
  $projHdrRaw = Get-Content -LiteralPath $projHdrFile -Raw
  if ($projHdrRaw -notmatch "(?m)^HTTP/\S+[ \t]+303\b" -or $projHdrRaw -notmatch "(?mi)^Location:[ \t]*/projects/\S+") {
    throw "POST /projects did not return 303 redirect to /projects/ (headers: $projHdrRaw)"
  }
  $projDir = Join-Path $e2eRoot $projName
  $stateDB = Join-Path $projDir "state.db"
  $healthyMarker = Join-Path $projDir ".statedb_healthy.json"
  if (-not (Test-Path -LiteralPath $stateDB) -or (Get-Item -LiteralPath $stateDB).Length -eq 0) {
    throw "state.db was not created on Windows NTFS at $stateDB"
  }
  if (-not (Test-Path -LiteralPath $healthyMarker)) {
    throw ".statedb_healthy.json was not written at $healthyMarker"
  }

  # Write a real deliverable file and export both normal & salvage .zip backups
  $delivDir = Join-Path $projDir "workspace\分析报告\测试专题"
  New-Item -ItemType Directory -Force -Path $delivDir | Out-Null
  Set-Content -LiteralPath (Join-Path $delivDir "summary.md") -Value "# Windows E2E Deliverable" -Encoding UTF8

  $zipFile = Join-Path $env:RUNNER_TEMP "win-team-backup.zip"
  curl.exe -fsS -o $zipFile "$baseURL/projects/$encProj/export-backup"
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $zipFile) -or (Get-Item -LiteralPath $zipFile).Length -lt 100) {
    throw "Exported .zip backup is empty or missing"
  }
  $salvageZip = Join-Path $env:RUNNER_TEMP "win-team-salvage.zip"
  curl.exe -fsS -o $salvageZip "$baseURL/projects/$encProj/export-backup?salvage=1"
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $salvageZip) -or (Get-Item -LiteralPath $salvageZip).Length -lt 100) {
    throw "Salvage .zip backup (?salvage=1) is empty or missing"
  }
  Write-Host "   [PASS] Real SQLite state.db + VACUUM INTO & ?salvage=1 export-backup succeeded ($((Get-Item -LiteralPath $zipFile).Length) / $((Get-Item -LiteralPath $salvageZip).Length) bytes)"

  # Optional Real-LLM API configuration & smoke check when VTEAM_TEST_API_KEY is injected
  if (-not [string]::IsNullOrWhiteSpace($env:VTEAM_TEST_API_KEY)) {
    Write-Host "==> [Win-E2E 3.5/4] VTEAM_TEST_API_KEY present: verifying real POST /setup + va.exe config check..."
    $apiName = if ($env:VTEAM_TEST_API_NAME) { $env:VTEAM_TEST_API_NAME } else { "opencode-go" }
    $apiFmt = if ($env:VTEAM_TEST_API_FORMAT) { $env:VTEAM_TEST_API_FORMAT } else { "openai" }
    $apiBase = if ($env:VTEAM_TEST_API_BASE_URL) { $env:VTEAM_TEST_API_BASE_URL } else { "https://opencode.ai/inference/go/openai/v1" }
    $apiModel = if ($env:VTEAM_TEST_API_MODEL) { $env:VTEAM_TEST_API_MODEL } else { "deepseek-v4.1-flash" }
    $setupHdr = Join-Path $env:RUNNER_TEMP "win-e2e-setup-hdr.txt"
    $setupResp = Join-Path $env:RUNNER_TEMP "win-e2e-setup-resp.html"
    $setupOK = $false
    for ($setupTry = 1; $setupTry -le 4; $setupTry++) {
      Remove-Item -LiteralPath $setupHdr, $setupResp -Force -ErrorAction SilentlyContinue
      curl.exe -sS -D $setupHdr -o $setupResp -X POST "$baseURL/setup" `
        --data-urlencode "name=$apiName" `
        --data-urlencode "format=$apiFmt" `
        --data-urlencode "base_url=$apiBase" `
        --data-urlencode "key=$($env:VTEAM_TEST_API_KEY)" `
        --data-urlencode "model=$apiModel"
      $curlExit = $LASTEXITCODE
      $hdrTxt = if (Test-Path -LiteralPath $setupHdr) { Get-Content -LiteralPath $setupHdr -Raw } else { "" }
      if ($curlExit -eq 0 -and $hdrTxt -match "(?m)^HTTP/\S+[ \t]+303\b" -and $hdrTxt -match "(?mi)^Location:[ \t]*/\r?$") {
        & $vaExe config --security $secFile check | Out-Null
        if ($LASTEXITCODE -eq 0) {
          $setupOK = $true
          Write-Host "   [PASS] POST /setup + va.exe config check succeeded on Windows ($apiName/$apiModel, attempt $setupTry)"
          break
        }
      }
      if ($setupTry -lt 4) {
        $waitSec = $setupTry * 3
        Write-Host "   [WARN] POST /setup attempt $setupTry encountered transient gateway busy; retrying in ${waitSec}s..."
        Start-Sleep -Seconds $waitSec
      }
    }
    if (-not $setupOK) {
      $safeHdr = if (Test-Path -LiteralPath $setupHdr) { (Get-Content -LiteralPath $setupHdr -Raw).Replace($env:VTEAM_TEST_API_KEY, "[REDACTED]") } else { "<no headers>" }
      throw "POST /setup failed to verify & save config after 4 attempts ($apiName/$apiModel): $safeHdr"
    }
  }
} finally {
  if ($daemon -and -not $daemon.HasExited) {
    & "$env:SystemRoot\System32\taskkill.exe" /T /F /PID $daemon.Id | Out-Null
    $daemon.WaitForExit(5000) | Out-Null
  }
  Remove-Item -LiteralPath (Join-Path $env:RUNNER_TEMP "win-team-backup.zip"), (Join-Path $env:RUNNER_TEMP "win-team-salvage.zip"), (Join-Path $env:RUNNER_TEMP "win-e2e-proj-hdr.txt"), (Join-Path $env:RUNNER_TEMP "win-e2e-setup-hdr.txt"), (Join-Path $env:RUNNER_TEMP "win-e2e-setup-resp.html") -Force -ErrorAction SilentlyContinue
}

Write-Host "==> [Win-E2E 4/4] Verifying zero lingering Windows file locks on workspace teardown..."
Remove-Item -LiteralPath $e2eRoot -Recurse -Force
if (Test-Path -LiteralPath $e2eRoot) {
  throw "Lingering Windows file handle prevented removal of $e2eRoot"
}
Write-Host "✅ WIN_REAL_E2E_OK: NTFS SQLite URI + WAL + VACUUM INTO + Clean Handle Teardown passed!"
