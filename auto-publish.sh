#!/bin/bash
# ============================================================
# 按需发布：自动唤醒 Codespace → 发布 → 不再保持运行
# 节省每月 30 小时配额，只在需要时才启动
# ============================================================

set -e

# ===== 配置 =====
CODESPACE_NAME="zany-goggles-5g6qw5jw7p4j2v66j"
SERVER_URL="https://${CODESPACE_NAME}-3000.app.github.dev"
AUTH_TOKEN="${WECHAT_AUTH_TOKEN:-8f283c05d579}"
GH_TOKEN="${GH_TOKEN:-}"

# ===== 颜色 =====
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
err()  { echo -e "${RED}❌ $1${NC}"; exit 1; }
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }

auth_header() {
  if [ -n "$AUTH_TOKEN" ]; then
    echo "-H \"Authorization: Bearer $AUTH_TOKEN\""
  fi
}

# ===== 第一步：唤醒 Codespace =====
wake_codespace() {
  if [ -z "$GH_TOKEN" ]; then
    warn "未设置 GH_TOKEN，跳过自动唤醒"
    warn "请手动打开 Codespace 或设置 GH_TOKEN"
    warn "export GH_TOKEN=ghp_xxxx"
    return 1
  fi

  info "唤醒 Codespace: $CODESPACE_NAME"

  # 查询状态
  STATE=$(curl -s -H "Authorization: Bearer $GH_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/user/codespaces/$CODESPACE_NAME" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('state','unknown'))" 2>/dev/null)

  info "当前状态: $STATE"

  if [ "$STATE" = "Available" ] || [ "$STATE" = "Running" ]; then
    log "Codespace 已在运行"
    return 0
  fi

  # 启动 Codespace
  info "正在启动 Codespace..."
  HTTP_CODE=$(curl -s -o /tmp/cs_start.json -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/user/codespaces/$CODESPACE_NAME/start")

  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "202" ]; then
    log "启动指令已发送"
  else
    err "启动失败 (HTTP $HTTP_CODE): $(cat /tmp/cs_start.json)"
    return 1
  fi

  # 等待就绪（最多 90 秒）
  info "等待 Codespace 就绪..."
  for i in $(seq 1 18); do
    sleep 5
    STATE=$(curl -s -H "Authorization: Bearer $GH_TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/user/codespaces/$CODESPACE_NAME" \
      | python3 -c "import sys,json; print(json.load(sys.stdin).get('state','unknown'))" 2>/dev/null)
    
    if [ "$STATE" = "Available" ] || [ "$STATE" = "Running" ]; then
      log "Codespace 已就绪！"
      return 0
    fi
    info "状态: $STATE (${i}/18)"
  done

  err "Codespace 启动超时"
  return 1
}

# ===== 第二步：等待服务就绪 =====
wait_for_server() {
  info "等待 HTTP 服务启动（postStartCommand 需要时间）..."
  
  for i in $(seq 1 20); do
    RESP=$(curl -s --connect-timeout 5 "$SERVER_URL/api/health" 2>/dev/null)
    if echo "$RESP" | grep -q '"status":"ok"'; then
      log "HTTP 服务已就绪！"
      echo "$RESP" | python3 -m json.tool
      return 0
    fi
    sleep 3
  done

  warn "HTTP 服务未响应，尝试手动启动..."
  # 如果 postStartCommand 没起效，需要用户手动在 Codespace 终端启动
  err "请在 Codespace 终端运行: node dist/http-server.js"
  return 1
}

# ===== 第三步：健康检查 =====
health_check() {
  info "健康检查..."
  RESP=$(curl -s --connect-timeout 10 "$SERVER_URL/api/health")
  echo "$RESP" | python3 -m json.tool
  if echo "$RESP" | grep -q '"status":"ok"'; then
    log "服务正常"
  else
    err "服务异常"
  fi
}

# ===== 第四步：获取 access_token =====
get_token() {
  info "获取微信 access_token..."
  curl -s -X POST -H "Authorization: Bearer $AUTH_TOKEN" \
    "$SERVER_URL/api/token" | python3 -m json.tool
}

# ===== 第五步：上传封面图 =====
upload_image() {
  IMAGE_PATH="$1"
  [ -z "$IMAGE_PATH" ] && err "用法: auto-publish.sh upload-image <图片路径>"
  [ ! -f "$IMAGE_PATH" ] && err "文件不存在: $IMAGE_PATH"

  info "上传封面图: $IMAGE_PATH"
  RESULT=$(curl -s -X POST \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -F "file=@$IMAGE_PATH" \
    "$SERVER_URL/api/upload-image")

  echo "$RESULT" | python3 -m json.tool

  MEDIA_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('media_id',''))" 2>/dev/null)
  if [ -n "$MEDIA_ID" ]; then
    log "封面 media_id: $MEDIA_ID"
    echo "$MEDIA_ID" > /tmp/last_media_id.txt
  else
    err "上传失败"
  fi
}

# ===== 第六步：创建草稿 =====
create_draft() {
  TITLE="$1"
  CONTENT="$2"
  THUMB_ID="${3:-$(cat /tmp/last_media_id.txt 2>/dev/null)}"

  [ -z "$TITLE" ] && err "缺少标题"
  [ -z "$CONTENT" ] && err "缺少内容"
  [ -z "$THUMB_ID" ] && err "缺少封面 media_id，请先 upload-image"

  info "创建草稿: $TITLE"
  RESULT=$(curl -s -X POST \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"title\":$(echo "$TITLE" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))'),\"content\":$(echo "$CONTENT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))'),\"thumb_media_id\":\"$THUMB_ID\"}" \
    "$SERVER_URL/api/draft")

  echo "$RESULT" | python3 -m json.tool

  MEDIA_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('media_id',''))" 2>/dev/null)
  if [ -n "$MEDIA_ID" ]; then
    log "草稿 media_id: $MEDIA_ID"
    echo "$MEDIA_ID" > /tmp/last_draft_id.txt
  else
    err "创建草稿失败"
  fi
}

# ===== 第七步：发布 =====
publish() {
  MEDIA_ID="${1:-$(cat /tmp/last_draft_id.txt 2>/dev/null)}"
  [ -z "$MEDIA_ID" ] && err "缺少 media_id"

  info "发布文章: $MEDIA_ID"
  RESULT=$(curl -s -X POST \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"media_id\":\"$MEDIA_ID\"}" \
    "$SERVER_URL/api/publish")

  echo "$RESULT" | python3 -m json.tool
  log "发布完成！"
}

# ===== 一键完整流程 =====
full_publish() {
  TITLE="$1"
  CONTENT="$2"
  IMAGE_PATH="$3"

  [ -z "$TITLE" ] && err "用法: auto-publish.sh full <标题> <HTML内容> <封面图路径>"

  echo "========================================"
  echo "  🚀 微信公众号一键发布"
  echo "========================================"

  wake_codespace || true
  wait_for_server
  health_check

  if [ -n "$IMAGE_PATH" ]; then
    upload_image "$IMAGE_PATH"
  fi

  create_draft "$TITLE" "$CONTENT"
  publish

  echo ""
  log "✨ 全部完成！Codespace 将在闲置后自动休眠，不消耗配额。"
}

# ===== 主入口 =====
case "${1:-help}" in
  wake)          wake_codespace ;;
  wait)          wait_for_server ;;
  health)        health_check ;;
  token)         get_token ;;
  upload-image)  upload_image "$2" ;;
  draft)         create_draft "$2" "$3" "$4" ;;
  publish)       publish "$2" ;;
  full)          full_publish "$2" "$3" "$4" ;;
  help|*)
    cat << 'EOF'
🚀 微信公众号按需发布工具

用法:
  ./auto-publish.sh wake                           唤醒 Codespace
  ./auto-publish.sh health                         健康检查
  ./auto-publish.sh token                          获取 access_token
  ./auto-publish.sh upload-image <图片路径>         上传封面图
  ./auto-publish.sh draft "标题" "<HTML>" [media_id] 创建草稿
  ./auto-publish.sh publish [media_id]             发布草稿
  ./auto-publish.sh full "标题" "<HTML>" <封面图>   一键发布（唤醒+发布）

环境变量:
  GH_TOKEN         GitHub Personal Access Token (codespace 权限)
  WECHAT_AUTH_TOKEN API 认证 Token

流程:
  1. wake         → 唤醒 Codespace（按需启动，不浪费配额）
  2. wait         → 等待 HTTP 服务就绪
  3. upload-image → 上传封面图
  4. draft        → 创建草稿
  5. publish      → 发布

  或直接用 full 一键搞定。
EOF
    ;;
esac
