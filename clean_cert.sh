#!/bin/bash

DOMAINS=(
  xxx.com
  yyy.com
  zzz.com
)

BASE="/etc/letsencrypt"

echo "===== 将要删除的 letsencrypt 文件 ====="

for d in "${DOMAINS[@]}"; do
  echo "--- $d ---"
  find "$BASE" -type f -name "${d}.conf"
  find "$BASE" -type d -name "$d"
done

echo
read -p "确认删除以上文件？输入 YES 继续: " confirm
[ "$confirm" != "YES" ] && echo "已取消" && exit 1

echo
echo "===== 开始删除 ====="

for d in "${DOMAINS[@]}"; do
  rm -rf "$BASE/renewal/${d}.conf"
  rm -rf "$BASE/archive/${d}"
  rm -rf "$BASE/live/${d}"
done

echo "===== 删除完成 ====="
