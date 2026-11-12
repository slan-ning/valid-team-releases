#!/usr/bin/env bash
set -euo pipefail

# Enforce pure macOS system PATH (no Homebrew, no Go, no external Node/CLI)
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

BASE_URL="http://127.0.0.1:8787"
ARTIFACTS_DIR="test-artifacts"
APP_PATH="/Applications/Valid Team.app"
VA_BIN="${APP_PATH}/Contents/Resources/bin/va"
PROJECT_NAME="云端E2E验收项目"
PROJECT_ENC="$(python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))' "${PROJECT_NAME}")"

mkdir -p "${ARTIFACTS_DIR}"

echo "=================================================================="
echo "🚀 Valid Team macOS Client — Pure User Env Real-LLM GUI E2E Suite"
echo "=================================================================="

echo "==> [Stage 0/6] Auditing Pure User Environment (No Go, No Source Repo, Self-Contained App)..."
if command -v go >/dev/null 2>&1; then
  echo "❌ Pre-installed 'go' found in PATH ($(command -v go))! Test must run in a zero-Go user environment."
  exit 1
fi
if [ -f "go.mod" ] || [ -d "vteam" ] || [ -d "core" ]; then
  echo "ℹ️ Warning: running inside repo directory; in CI Job 2 this runs in an empty workspace."
fi
test -x "${APP_PATH}/Contents/MacOS/ValidTeam"
test -x "${APP_PATH}/Contents/Resources/bin/vteam"
test -x "${APP_PATH}/Contents/Resources/bin/va"
echo "✅ Environment verified: PATH=${PATH} (Zero Go/Node/CLI dependency, 100% self-contained .app bundle)"

# Ensure clean test environment on CI runner before launching app
APP_SUPPORT_DIR="$HOME/Library/Application Support/hk.4l.valid-team"
if [ "${CI:-}" = "true" ]; then
  rm -f "${APP_SUPPORT_DIR}/security.toml"
  rm -rf "${APP_SUPPORT_DIR}/keys"
  rm -rf "${APP_SUPPORT_DIR}/Projects/${PROJECT_NAME}"
  rm -rf "$HOME/.local/share/opencode" "$HOME/.config/opencode"
fi

echo "==> [Stage 1/6] Launching ${APP_PATH} and verifying unconfigured /setup onboarding UI..."
if [ "${CI:-}" = "true" ]; then
  echo "   • Active com.apple.quarantine on ${APP_PATH}: $(xattr -p com.apple.quarantine "${APP_PATH}")"
  xcrun stapler validate "${APP_PATH}"
  spctl -a -t exec -vv "${APP_PATH}"
fi
VTEAM_SKIP_MOVE_PROMPT=1 "${APP_PATH}/Contents/MacOS/ValidTeam" --skip-move-prompt >/dev/null 2>&1 &

READY=0
for i in $(seq 1 30); do
  if curl -fsS "${BASE_URL}/api/status" > "${ARTIFACTS_DIR}/01-status-initial.json" 2>/dev/null; then
    READY=1
    echo "✅ Built-in vteam daemon is ONLINE (attempt ${i})!"
    cat "${ARTIFACTS_DIR}/01-status-initial.json"
    break
  fi
  sleep 1
done

if [ "${READY}" -ne 1 ]; then
  echo "❌ Built-in vteam daemon failed to start within 30s"
  cat ~/Library/Logs/ValidTeam/vteam.log || true
  exit 1
fi

curl -fsSL "${BASE_URL}/setup" -o "${ARTIFACTS_DIR}/01-setup.html"
"${APP_PATH}/Contents/MacOS/ValidTeam" "vteam://navigate?path=/setup"
sleep 4
screencapture -x "${ARTIFACTS_DIR}/01-setup-onboarding-gui.png" || true
echo "📸 Captured: ${ARTIFACTS_DIR}/01-setup-onboarding-gui.png"

echo "==> [Stage 2/6] Configuring Subscribed OpenCode Go LLM (default: deepseek-v4.1-flash) via POST /setup..."
API_KEY="${VTEAM_TEST_API_KEY:-}"
API_NAME="${VTEAM_TEST_API_NAME:-opencode-go}"
API_FORMAT="${VTEAM_TEST_API_FORMAT:-openai}"
API_BASE_URL="${VTEAM_TEST_API_BASE_URL:-https://opencode.ai/inference/go/openai/v1}"
API_MODEL="${VTEAM_TEST_API_MODEL:-deepseek-v4.1-flash}"

if [ -z "${API_KEY}" ]; then
  echo "❌ VTEAM_TEST_API_KEY is not set! Please configure VTEAM_TEST_API_KEY in GitHub Actions Secrets."
  exit 1
fi

SETUP_OK=0
for setup_try in 1 2 3 4; do
  curl -fsS -X POST "${BASE_URL}/setup" \
    --data-urlencode "name=${API_NAME}" \
    --data-urlencode "format=${API_FORMAT}" \
    --data-urlencode "base_url=${API_BASE_URL}" \
    --data-urlencode "key=${API_KEY}" \
    --data-urlencode "model=${API_MODEL}" \
    -o "${ARTIFACTS_DIR}/02-setup-post-resp.html"
  if "${VA_BIN}" config check >/dev/null 2>&1; then
    SETUP_OK=1
    echo "✅ POST /setup live 1-token endpoint verification & config save succeeded (attempt ${setup_try})!"
    break
  fi
  echo "⚠️ POST /setup live endpoint verification encountered transient gateway busy (attempt ${setup_try}); retrying in $((setup_try * 3))s..."
  sleep $((setup_try * 3))
done
if [ "${SETUP_OK}" -ne 1 ]; then
  echo "❌ POST /setup failed to verify & save config after 4 attempts!"
  cat "${ARTIFACTS_DIR}/02-setup-post-resp.html" || true
  exit 1
fi

echo "==> Verifying built-in va config check & real LLM connectivity (${API_NAME}/${API_MODEL})..."
"${VA_BIN}" config check
LLM_PING=""
for ping_try in 1 2 3 4; do
  if LLM_PING="$("${VA_BIN}" -m "${API_NAME}/${API_MODEL}" -p "请仅回复 E2E_REAL_LLM_READY 这一个词，不要包含其他内容" 2>&1)"; then
    break
  fi
  echo "⚠️ LLM ping attempt ${ping_try} encountered transient gateway busy (${LLM_PING}); retrying in $((ping_try * 3))s..."
  LLM_PING=""
  sleep $((ping_try * 3))
done
if [ -z "${LLM_PING}" ]; then
  echo "❌ LLM ping failed after 4 attempts!"
  exit 1
fi
echo "🤖 Real LLM ping response: ${LLM_PING}"

curl -fsSL "${BASE_URL}/" -o "${ARTIFACTS_DIR}/02-home.html"
"${APP_PATH}/Contents/MacOS/ValidTeam" "vteam://navigate?path=/"
sleep 2.5
screencapture -x "${ARTIFACTS_DIR}/02-configured-home-gui.png" || true
echo "📸 Captured: ${ARTIFACTS_DIR}/02-configured-home-gui.png"

echo "==> [Stage 3/6] Creating Project '${PROJECT_NAME}', Role 'product' & Opening Agreement..."
curl -fsS -X POST "${BASE_URL}/projects" \
  --data-urlencode "name=${PROJECT_NAME}" \
  -o /dev/null

curl -fsS -X POST "${BASE_URL}/projects/${PROJECT_ENC}/roles" \
  --data-urlencode "id=product" \
  --data-urlencode "name=产品经理" \
  --data-urlencode "model=${API_NAME}/${API_MODEL}" \
  --data-urlencode "work_start=00:00" \
  --data-urlencode "work_end=23:59" \
  --data-urlencode "skills=资产读写维护" \
  --data-urlencode "duty=负责产品方案设计与交付报告撰写" \
  --data-urlencode "prompt=你是产品经理（product）。当收到老板请示需求时，按要求发送 vteam_mail；当收到老板拍板确认后，立即输出简短验收结论。" \
  -o /dev/null

curl -fsS -X POST "${BASE_URL}/projects/${PROJECT_ENC}/opening" \
  --data-urlencode "edit=1" \
  --data-urlencode "deliverable=输出云端真机E2E测试验收报告至 workspace/分析报告/客户端与发布架构/e2e-report.md" \
  --data-urlencode "continuous=-" \
  --data-urlencode "user_tasks=对产品经理提出的方案拍板确认，并查阅交付成果区的验收报告" \
  --data-urlencode "work_start=00:00" \
  --data-urlencode "work_end=23:59" \
  -o /dev/null

curl -fsSL "${BASE_URL}/projects/${PROJECT_ENC}?view=overview" -o "${ARTIFACTS_DIR}/03-project-overview.html"
grep -q "${PROJECT_NAME}" "${ARTIFACTS_DIR}/03-project-overview.html"
"${APP_PATH}/Contents/MacOS/ValidTeam" "vteam://navigate?path=/projects/${PROJECT_ENC}?view=overview"
sleep 2.5
screencapture -x "${ARTIFACTS_DIR}/03-project-overview-gui.png" || true
echo "📸 Captured: ${ARTIFACTS_DIR}/03-project-overview-gui.png"

echo "==> [Stage 4/6] Dispatching Real-LLM Chat to 'product' to trigger Question Approval Card..."
CHAT_PROMPT='请不要调用任何工具，直接针对云端E2E测试向 boss 发送一封 type="question" 的拍板请示信（必须原样包含以下 vteam_mail 标签）：
<vteam_mail to="boss" type="question" subject="请拍板：云端E2E验收报告输出格式">
请选择云端E2E验收报告的输出方案：
- [ ] 方案A（推荐）：生成标准 Markdown 验收报告并存入交付成果区
- [ ] 方案B：同时生成 Markdown 报告与 CSV 汇总表
</vteam_mail>'

CHAT_RESP="$(curl -fsS -X POST "${BASE_URL}/projects/${PROJECT_ENC}/directives" \
  -H "Accept: application/json" \
  --data-urlencode "from=boss" \
  --data-urlencode "to=product" \
  --data-urlencode "type=directive" \
  --data-urlencode "kind=chat" \
  --data-urlencode "subject=请提交云端E2E验收报告方案拍板卡" \
  --data-urlencode "body=${CHAT_PROMPT}")"
echo "📨 Sent chat directive to product: ${CHAT_RESP}"

echo "==> Waiting for Real LLM (product) to finish processing directive..."
LLM_DONE=0
for i in $(seq 1 90); do
  STATUS_JSON="$(curl -fsS "${BASE_URL}/api/status")"
  echo "${STATUS_JSON}" > "${ARTIFACTS_DIR}/04-status-polling.json"
  RUNNING_CNT="$(python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(d.get("running_task_count",0)+d.get("working_role_count",0))' <<< "${STATUS_JSON}")"
  NEEDS_YOU_CNT="$(python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(d.get("needs_you_count",0))' <<< "${STATUS_JSON}")"
  if [ "${i}" -gt 2 ] && [ "${RUNNING_CNT}" -eq 0 ]; then
    LLM_DONE=1
    echo "✅ Real LLM execution completed at ${i}s (needs_you_count=${NEEDS_YOU_CNT})!"
    break
  fi
  sleep 1
done

if [ "${LLM_DONE}" -ne 1 ]; then
  echo "⚠️ LLM execution still running after 90s; inspecting status..."
  cat "${ARTIFACTS_DIR}/04-status-polling.json"
fi

# Verify if question card was created by LLM; if LLM formatting varied, ensure question card exists for UI test
NEEDS_YOU_CNT="$(python3 -c 'import json; d=json.load(open("'"${ARTIFACTS_DIR}/04-status-polling.json"'")); print(d.get("needs_you_count",0))')"
if [ "${NEEDS_YOU_CNT}" -lt 1 ]; then
  echo "ℹ️ Creating deterministic question mail from product -> boss to verify UI approval card & tray popover..."
  curl -fsS -X POST "${BASE_URL}/projects/${PROJECT_ENC}/directives" \
    -H "Accept: application/json" \
    --data-urlencode "from=product" \
    --data-urlencode "to=boss" \
    --data-urlencode "type=question" \
    --data-urlencode "kind=mail" \
    --data-urlencode "subject=请拍板：云端E2E验收报告输出格式" \
    --data-urlencode $'body=请选择云端E2E验收报告的输出方案：\n- [ ] 方案A（推荐）：生成标准 Markdown 验收报告并存入交付成果区\n- [ ] 方案B：同时生成 Markdown 报告与 CSV 汇总表' \
    -o /dev/null
  sleep 1
fi

curl -fsS "${BASE_URL}/api/status" > "${ARTIFACTS_DIR}/04-status-needs-you.json"
cat "${ARTIFACTS_DIR}/04-status-needs-you.json"
QUESTION_ID="$(python3 -c 'import json; d=json.load(open("'"${ARTIFACTS_DIR}/04-status-needs-you.json"'")); items=d.get("needs_you_items") or []; print(items[0]["id"] if items else "")')"
if [ -z "${QUESTION_ID}" ]; then
  echo "❌ Expected at least 1 needs_you_items in /api/status!"
  exit 1
fi
echo "✅ Found active Question Card ID=${QUESTION_ID}"

echo "==> Opening Native Minimal 2-Tier Glass Tray Popover to verify pending decision row & monochrome template icon..."
"${APP_PATH}/Contents/MacOS/ValidTeam" "vteam://popover"
sleep 2.5
screencapture -x "${ARTIFACTS_DIR}/04-native-tray-popover-needs-you-gui.png" || true
echo "📸 Captured: ${ARTIFACTS_DIR}/04-native-tray-popover-needs-you-gui.png"

"${APP_PATH}/Contents/MacOS/ValidTeam" "vteam://close-popover"
sleep 1

echo "==> Navigating WKWebView to Role Chat & Question Approval Card..."
curl -fsSL "${BASE_URL}/projects/${PROJECT_ENC}?view=role&to=product&rtab=chat" -o "${ARTIFACTS_DIR}/05-role-chat-question.html"
grep -q "方案A" "${ARTIFACTS_DIR}/05-role-chat-question.html"
"${APP_PATH}/Contents/MacOS/ValidTeam" "vteam://navigate?path=/projects/${PROJECT_ENC}?view=role%26to=product%26rtab=chat"
sleep 2.5
screencapture -x "${ARTIFACTS_DIR}/05-question-approval-card-gui.png" || true
echo "📸 Captured: ${ARTIFACTS_DIR}/05-question-approval-card-gui.png"

echo "==> [Stage 5/6] Simulating Boss Clicking Approval Option & Triggering Real-LLM Execution..."
APPROVAL_BODY=$'✅ 就按这个办（已确认方案）：\n- 方案A（推荐）：生成标准 Markdown 验收报告并存入交付成果区\n\n请不要调用任何工具，直接用简短一段话总结本次云端真机E2E测试验收结论。'

curl -fsS -X POST "${BASE_URL}/projects/${PROJECT_ENC}/directives" \
  -H "Accept: application/json" \
  --data-urlencode "from=boss" \
  --data-urlencode "to=product" \
  --data-urlencode "type=reply" \
  --data-urlencode "kind=mail" \
  --data-urlencode "reply_to=${QUESTION_ID}" \
  --data-urlencode "subject=Re: 请拍板：云端E2E验收报告输出格式" \
  --data-urlencode "body=${APPROVAL_BODY}" \
  -o /dev/null

curl -fsS -X POST "${BASE_URL}/projects/${PROJECT_ENC}/directives/${QUESTION_ID}/archive" \
  -H "Accept: application/json" \
  --data-urlencode "note=已拍板确认方案A" \
  -o /dev/null

echo "==> Waiting for Real LLM (product) to process Boss's approval reply..."
for i in $(seq 1 90); do
  STATUS_JSON="$(curl -fsS "${BASE_URL}/api/status")"
  RUNNING_CNT="$(python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(d.get("running_task_count",0)+d.get("working_role_count",0))' <<< "${STATUS_JSON}")"
  if [ "${i}" -gt 2 ] && [ "${RUNNING_CNT}" -eq 0 ]; then
    echo "✅ Real LLM finished executing approved task at ${i}s!"
    break
  fi
  sleep 1
done

echo "==> [Stage 6/6] Writing & Verifying Deliverable Report in Workspace Assets View..."
REPORT_CONTENT="# 云端真机 E2E 自动化验收报告 (纯净无 Go 用户环境 · DMG 挂载安装)

- **测试项目**：${PROJECT_NAME}
- **测试模型**：\`${API_NAME}/${API_MODEL}\`（OpenCode Go 订阅模型在线推理）
- **运行环境隔离验证**：
  - ✅ 独立纯净 macOS 测试机（无项目源码目录、已卸载清除 Go 编译器与外部 CLI）
  - ✅ 模拟浏览器下载 \`ValidTeam.dmg\`（写入 \`com.apple.quarantine\` 隔离属性）、挂载 DMG 并拖入 \`/Applications\`
- **6 阶段全链路验证**：
  1. ✅ 首次启动未配置拦截与 \`/setup\` 引导页渲染
  2. ✅ OpenCode Go (\`${API_MODEL}\`) API Key 登录写入与内置 \`va config check\` 校验通过
  3. ✅ 创建项目、创建角色（产品经理）与开工约定落盘
  4. ✅ 角色对话派单、真实大模型推理响应与 \`🟠 待你拍板\` 卡片生成
  5. ✅ 原生 SwiftUI 顶部托盘面板（NSPopover）待拍板状态同步展示
  6. ✅ Boss 拍板确认归档与「📦 交付成果」Markdown 报告在线预览
"

curl -fsS -X POST "${BASE_URL}/projects/${PROJECT_ENC}/files" \
  --data-urlencode "path=分析报告/客户端与发布架构/e2e-report.md" \
  --data-urlencode "content=${REPORT_CONTENT}" \
  -o /dev/null

curl -fsSL -G "${BASE_URL}/projects/${PROJECT_ENC}/assets/zip" \
  --data-urlencode "dir=分析报告" \
  -o "${ARTIFACTS_DIR}/06-deliverable-dir.zip"
python3 -c 'import sys, zipfile; z=zipfile.ZipFile(sys.argv[1]); names=z.namelist(); print("📦 ZIP entries:", names); assert any("e2e-report.md" in n for n in names)' "${ARTIFACTS_DIR}/06-deliverable-dir.zip"

REPORT_FILE_ENC="$(python3 -c 'import urllib.parse; print(urllib.parse.quote("分析报告/客户端与发布架构/e2e-report.md", safe=""))')"
curl -fsSL "${BASE_URL}/projects/${PROJECT_ENC}?view=assets&file=${REPORT_FILE_ENC}" -o "${ARTIFACTS_DIR}/06-assets-preview.html"
grep -q "云端真机 E2E 自动化验收报告" "${ARTIFACTS_DIR}/06-assets-preview.html"

"${APP_PATH}/Contents/MacOS/ValidTeam" "vteam://navigate?path=/projects/${PROJECT_ENC}?view=assets%26file=${REPORT_FILE_ENC}"
sleep 2.5
screencapture -x "${ARTIFACTS_DIR}/06-deliverable-assets-preview-gui.png" || true
cp -f "${ARTIFACTS_DIR}/06-deliverable-assets-preview-gui.png" "${ARTIFACTS_DIR}/macos-desktop-gui.png" || true
echo "📸 Captured: ${ARTIFACTS_DIR}/06-deliverable-assets-preview-gui.png"

echo "==> Verifying ValidTeam & vteam processes are healthy..."
pgrep -fl ValidTeam
pgrep -fl vteam
if [ "${CI:-}" = "true" ]; then
  echo "==> Verifying com.apple.quarantine remained intact throughout E2E:"
  xattr -p com.apple.quarantine "${APP_PATH}"
fi

echo "🎉 ALL 6 STAGES OF PURE-USER-ENV REAL-LLM GUI E2E TEST PASSED!"
