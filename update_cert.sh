#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# ==================服务器及Telegram 配置 ==================
HOST='FRONT_XXX'
TG_BOT_TOKEN="TG_TOKEN_XXX"
TG_CHAT_ID="TG_CHAT_ID_XXX"
TG_API="https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage"

# ================== 基础配置 ==================
RENEW_DIR="/etc/letsencrypt/renewal"
LOG_BASE_DIR="/root/logs/letsencrypt"
TODAY=$(date +%Y%m%d)
LOG_FILE="${LOG_BASE_DIR}/${TODAY}.log"

CERTBOT_BIN="/usr/bin/certbot"
NGINX_RELOAD_CMD="systemctl reload nginx"

# ================== 日志函数 ==================
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"
}

# ================== TG 发送函数（统一出口） ==================
tg_send() {
  local text="$1"
  # 不输出到屏幕/日志，避免泄露 token
  curl -s -X POST "$TG_API" \
    -d "chat_id=${TG_CHAT_ID}" \
    --data-urlencode "text=${text}" >/dev/null 2>&1
}

# ================== 初始化 ==================
mkdir -p "$LOG_BASE_DIR"

BROKEN_LIST=()
TOTAL_CERTS=0

log "=============================================="
log "开始执行 certbot 安全续期脚本"
log "host        : $HOST"
log "renewal 目录: $RENEW_DIR"
log "日志文件    : $LOG_FILE"
log "=============================================="

# ================== nginx 配置预检查 ==================
log "执行 nginx 配置检测: nginx -t"

if ! /usr/sbin/nginx -t >>"$LOG_FILE" 2>&1; then
  log "❌ nginx 配置检测失败，停止证书检测与续期（避免误判）"

  MSG=$(printf "[letsencrypt] %s %s\nnginx -t: FAILED\n\n已停止 certbot 检测与续期。\n请先修复 nginx 配置。\n\nlog: %s" \
    "$HOST" "$TODAY" "$LOG_FILE")

  tg_send "$MSG"
  exit 1
fi

log "✅ nginx -t 通过，继续证书检测"

# ================== 检测异常 renewal（不要误判 skipped） ==================
log "检查 renewal 配置是否存在异常..."

for conf in "$RENEW_DIR"/*.conf; do
  [ -e "$conf" ] || continue

  TOTAL_CERTS=$((TOTAL_CERTS + 1))
  cert_name=$(basename "$conf" .conf)
  log "检查证书: $cert_name"

  # 捕获输出用于判断：skipped / not due 不算异常
  OUTPUT=$($CERTBOT_BIN renew --dry-run --cert-name "$cert_name" 2>&1)
  echo "$OUTPUT" >>"$LOG_FILE"

  # 只有匹配这些“明确错误特征”才算异常
  if echo "$OUTPUT" | grep -Eqi \
    "broken|missing|required file|symlink|unauthorized|challenge failed|nginx.*failed|error"; then
    log "❌ 确认异常证书配置: $cert_name"
    BROKEN_LIST+=("$cert_name")
  else
    # skipped / not due / no renewals attempted 都归为正常
    log "✅ 证书正常（未到续期或已跳过）: $cert_name"
  fi
done

# ================== 正式续期 ==================
log "开始执行 certbot renew ..."

RENEW_OK=1
RENEW_OUTPUT=$($CERTBOT_BIN renew --deploy-hook "$NGINX_RELOAD_CMD" 2>&1)
echo "$RENEW_OUTPUT" >>"$LOG_FILE"

if echo "$RENEW_OUTPUT" | grep -Eqi "error|failed"; then
  RENEW_OK=0
  log "❌ certbot renew 执行过程中存在错误（详见日志）"
else
  log "🎉 certbot renew 执行完成"
fi

# ================== 统计与 Telegram 通知 ==================
STATUS_LINE="certbot renew: OK"
[ $RENEW_OK -eq 0 ] && STATUS_LINE="certbot renew: ERROR"

# 这里的 SUCCESS_CNT 表示“检查通过/正常”的数量（不是实际续期数量）
SUCCESS_CNT=$((TOTAL_CERTS - ${#BROKEN_LIST[@]}))

if [ ${#BROKEN_LIST[@]} -gt 0 ]; then
  BROKEN_TEXT=""
  for name in "${BROKEN_LIST[@]}"; do
    BROKEN_TEXT+="- ${name}"$'\n'
  done

  MSG=$(printf "[letsencrypt] %s %s\n%s\n\nabnormal certs:\n%s\nlog: %s" \
    "$HOST" "$TODAY" "$STATUS_LINE" "$BROKEN_TEXT" "$LOG_FILE")

  tg_send "$MSG"
  log "📣 已发送 Telegram 异常证书汇总通知（${#BROKEN_LIST[@]} 个）"
else
  log "证书检查/续期完成，正常证书 ${SUCCESS_CNT} 个（无异常）"

  # 你现在脚本最终会发 TG，我保留这个行为：成功也发一条
  MSG=$(printf "[letsencrypt] %s %s\n%s\n\n无异常证书。\n正常证书: %s 个\nlog: %s" \
    "$HOST" "$TODAY" "$STATUS_LINE" "$SUCCESS_CNT" "$LOG_FILE")
  tg_send "$MSG"
fi

log "=============================================="
log "certbot 安全续期脚本执行结束"
log "=============================================="
echo "" >>"$LOG_FILE"
