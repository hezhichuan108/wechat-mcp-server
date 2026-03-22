#!/bin/bash
# ============================================================
# 本地调用脚本 → GitHub Codespaces → 微信公众号 API
# 固定 IP 解决白名单问题
# ============================================================

set -e

# ===== 配置 =====
# Codespaces 地址（部署后替换为你的实际地址）
SERVER="${WECHAT_SERVER_URL:-https://your-codespace-name.github.dev}"
TOKEN="${WECHAT_AUTH_TOKEN:-}"

# ===== 颜色 =====
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ===== 辅助函数 =====
log()  { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
err()  { echo -e "${RED}❌ $1${NC}"; exit 1; }

auth_header() {
  if [ -n "$TOKEN" ]; then
    echo "-H" "Authorization: Bearer $TOKEN"
  fi
}

# ===== 命令 =====
case "${1:-help}" in

  health)
    echo "🔍 检查服务状态..."
    curl -s "$SERVER/api/health" | python3 -m json.tool || err "服务不可达"
    ;;

  token)
    echo "🔑 获取 access_token..."
    curl -s -X POST $(auth_header) "$SERVER/api/token" | python3 -m json.tool
    ;;

  upload-image)
    # Usage: ./publish.sh upload-image /path/to/image.jpg
    IMAGE_PATH="$2"
    [ -z "$IMAGE_PATH" ] && err "用法: $0 upload-image <图片路径>"
    [ ! -f "$IMAGE_PATH" ] && err "文件不存在: $IMAGE_PATH"
    
    echo "📤 上传图片: $IMAGE_PATH"
    RESULT=$(curl -s -X POST $(auth_header) \
      -F "file=@$IMAGE_PATH" \
      "$SERVER/api/upload-image")
    
    echo "$RESULT" | python3 -m json.tool
    
    # 提取 media_id
    MEDIA_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('media_id',''))" 2>/dev/null)
    if [ -n "$MEDIA_ID" ]; then
      log "media_id: $MEDIA_ID"
      echo "$MEDIA_ID" > /tmp/last_media_id.txt
    else
      warn "未获取到 media_id"
    fi
    ;;

  draft)
    # Usage: ./publish.sh draft "标题" "HTML内容" "thumb_media_id"
    TITLE="$2"
    CONTENT="$3"
    THUMB_ID="$4"
    
    [ -z "$TITLE" ] && err "用法: $0 draft <标题> <HTML内容> <thumb_media_id>"
    [ -z "$CONTENT" ] && err "缺少 HTML 内容"
    [ -z "$THUMB_ID" ] && {
      if [ -f /tmp/last_media_id.txt ]; then
        THUMB_ID=$(cat /tmp/last_media_id.txt)
        warn "使用上次上传的 media_id: $THUMB_ID"
      else
        err "缺少 thumb_media_id，请先上传封面图"
      fi
    }
    
    echo "📝 创建草稿: $TITLE"
    RESULT=$(curl -s -X POST $(auth_header) \
      -H "Content-Type: application/json" \
      -d "{\"title\":\"$TITLE\",\"content\":$(echo "$CONTENT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))'),\"thumb_media_id\":\"$THUMB_ID\"}" \
      "$SERVER/api/draft")
    
    echo "$RESULT" | python3 -m json.tool
    
    MEDIA_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('media_id',''))" 2>/dev/null)
    if [ -n "$MEDIA_ID" ]; then
      log "草稿 media_id: $MEDIA_ID"
      echo "$MEDIA_ID" > /tmp/last_draft_id.txt
    fi
    ;;

  draft-file)
    # Usage: ./publish.sh draft-file 文章.html thumb_media_id
    FILE="$2"
    THUMB_ID="$3"
    
    [ -z "$FILE" ] && err "用法: $0 draft-file <HTML文件> <thumb_media_id>"
    [ ! -f "$FILE" ] && err "文件不存在: $FILE"
    
    TITLE=$(head -20 "$FILE" | grep -oP '(?<=<title>|<h1[^>]*>)[^<]+' | head -1)
    [ -z "$TITLE" ] && TITLE="Untitled"
    
    CONTENT=$(cat "$FILE")
    
    echo "📝 从文件创建草稿: $TITLE"
    RESULT=$(curl -s -X POST $(auth_header) \
      -H "Content-Type: application/json" \
      -d "{\"title\":$(echo "$TITLE" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))'),\"content\":$(echo "$CONTENT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))'),\"thumb_media_id\":\"$THUMB_ID\"}" \
      "$SERVER/api/draft")
    
    echo "$RESULT" | python3 -m json.tool
    
    MEDIA_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('media_id',''))" 2>/dev/null)
    if [ -n "$MEDIA_ID" ]; then
      log "草稿 media_id: $MEDIA_ID"
      echo "$MEDIA_ID" > /tmp/last_draft_id.txt
    fi
    ;;

  publish)
    # Usage: ./publish.sh publish [media_id]
    MEDIA_ID="${2:-$(cat /tmp/last_draft_id.txt 2>/dev/null)}"
    [ -z "$MEDIA_ID" ] && err "用法: $0 publish <media_id>"
    
    echo "🚀 发布文章: $MEDIA_ID"
    RESULT=$(curl -s -X POST $(auth_header) \
      -H "Content-Type: application/json" \
      -d "{\"media_id\":\"$MEDIA_ID\"}" \
      "$SERVER/api/publish")
    
    echo "$RESULT" | python3 -m json.tool
    log "发布完成！"
    ;;

  help|*)
    cat << 'EOF'
📖 微信公众号发布工具 (GitHub Codespaces 代理)

用法:
  ./publish.sh health                        检查服务状态
  ./publish.sh token                         获取 access_token
  ./publish.sh upload-image <图片路径>        上传封面图
  ./publish.sh draft <标题> <HTML> <media_id>  创建草稿
  ./publish.sh draft-file <HTML文件> <id>     从文件创建草稿
  ./publish.sh publish [media_id]            发布文章

环境变量:
  WECHAT_SERVER_URL  Codespaces 服务地址
  WECHAT_AUTH_TOKEN  认证 Token

完整流程:
  1. ./publish.sh upload-image cover.jpg     # 上传封面 → 获得 media_id
  2. ./publish.sh draft "标题" "<h1>内容</h1>" <media_id>  # 创建草稿
  3. ./publish.sh publish                     # 发布
EOF
    ;;
esac
