#!/usr/bin/env bash
# backup-check.sh — 抹盘/重装前的自检（只读，不会改动系统）
#
# 用法:
#   bash backup-check.sh
#   bash backup-check.sh --backup-dir /media/usb/backup
#   bash backup-check.sh --pack --backup-dir /media/usb/backup
#
# --pack 只打包 SSH 密钥（secrets）。Android 签名密钥有意不迁移。

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD="$REPO_DIR/payload"

BACKUP_DIR=""
PACK=0
FAILED=0
WARNED=0

if [[ -t 1 ]]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'
  C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_OK=''; C_WARN=''; C_ERR=''; C_DIM=''; C_OFF=''
fi

ok()   { printf '  %s[ok]%s %s\n'   "$C_OK"   "$C_OFF" "$*"; }
bad()  { printf '  %s[!!]%s %s\n'   "$C_ERR"  "$C_OFF" "$*"; FAILED=$((FAILED+1)); }
note() { printf '  %s[--]%s %s\n'   "$C_WARN" "$C_OFF" "$*"; WARNED=$((WARNED+1)); }
step() { printf '\n%s==>%s %s\n'    "$C_OK"   "$C_OFF" "$*"; }

usage() {
  sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

while (( $# )); do
  case "$1" in
    --backup-dir) BACKUP_DIR="${2:-}"; shift 2 ;;
    --pack)       PACK=1; shift ;;
    -h|--help)    usage ;;
    *)            printf '未知参数: %s\n' "$1" >&2; exit 2 ;;
  esac
done

# ---------- 仓库 ----------
step "仓库"
if [[ -d "$REPO_DIR/.git" ]]; then
  ok "git 仓库: $REPO_DIR"

  if [[ -z "$(git -C "$REPO_DIR" status --porcelain)" ]]; then
    ok "工作区干净"
  else
    bad "有未提交的改动（先 git commit）"
  fi

  if git -C "$REPO_DIR" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    ahead="$(git -C "$REPO_DIR" rev-list --count '@{u}..HEAD')"
    if [[ "$ahead" == "0" ]]; then
      ok "已推送到远程"
    else
      bad "有 $ahead 个提交未推送（git push）"
    fi
  else
    bad "没有远程分支（先 gh repo create / git push -u origin main）"
  fi
else
  bad "这里不是 git 仓库，或还没有 git init"
fi

# ---------- payload 与本地配置是否一致 ----------
step "配置同步（payload ↔ 本机）"

compare() {
  local local_file="$1" payload_file="$2" label="$3"
  if [[ ! -f "$local_file" ]]; then
    note "$label 不存在: $local_file"
  elif [[ ! -f "$payload_file" ]]; then
    bad "$label 未放入 payload: $payload_file"
  elif cmp -s "$local_file" "$payload_file"; then
    ok "$label"
  else
    bad "$label 与 payload 不一致（重新复制到 payload/）"
  fi
}

compare "$HOME/.alias.sh"                    "$PAYLOAD/alias.sh"                    "alias.sh"
compare "$HOME/.local/bin/alias-help"        "$PAYLOAD/bin/alias-help"              "alias-help"
compare "$HOME/.local/bin/alias-lint"        "$PAYLOAD/bin/alias-lint"              "alias-lint"
compare "$HOME/.local/bin/proxy-bench"       "$PAYLOAD/bin/proxy-bench"             "proxy-bench"
compare "$HOME/.config/opencode/cli.json"    "$PAYLOAD/opencode/cli.json"           "opencode/cli.json"
compare "$HOME/.config/opencode/tui.json"    "$PAYLOAD/opencode/tui.json"           "opencode/tui.json"
compare "$HOME/.config/git/config"           "$PAYLOAD/gitconfig"                   "gitconfig"
compare "$HOME/.config/zeroomega/rules.txt"  "$PAYLOAD/zeroomega-rules.txt"         "zeroomega 规则"
compare "$HOME/.config/microsoft-edge-stable-flags.conf" "$PAYLOAD/edge-flags.conf"   "Edge flags"

note "zshrc / ghostty / AGENTS.md 是模板化或人工整理过的，不做逐字节比较"
note "Edge 配色策略（/etc/opt/edge/policies/managed/color.json）由 apply.sh 按主题生成，不比较"

# ---------- SSH ----------
step "SSH"
if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
  perms="$(stat -c '%a' "$HOME/.ssh/id_ed25519" 2>/dev/null || echo '?')"
  if [[ "$perms" == "600" || "$perms" == "400" ]]; then
    ok "id_ed25519 存在（权限 $perms）"
  else
    note "id_ed25519 权限是 $perms，建议 chmod 600"
  fi
else
  note "没有 id_ed25519（如果打算新机器重新生成，可以忽略）"
fi

# ---------- 其他数据 ----------
step "其他数据"
for d in "$HOME/Documents" "$HOME/Pictures"; do
  if [[ -d "$d" ]]; then
    printf '  %s[--]%s %s (%s)\n' "$C_DIM" "$C_OFF" "$d" "$(du -sh "$d" 2>/dev/null | cut -f1)"
  else
    note "$d 不存在"
  fi
done

if [[ -f "$HOME/Downloads/flutter_linux_3.47.4-stable.tar.xz" ]]; then
  ok "Flutter tarball 已有（可复用，省一次下载）"
else
  note "Flutter tarball 不在 ~/Downloads（dev-setup 会重新下载）"
fi

# ---------- 备份目录 ----------
if [[ -n "$BACKUP_DIR" ]]; then
  step "备份目录"
  if mkdir -p "$BACKUP_DIR" 2>/dev/null; then
    ok "可写: $BACKUP_DIR"
  else
    bad "无法写入: $BACKUP_DIR"
    BACKUP_DIR=""
  fi
fi

# ---------- 打包 secrets ----------
if (( PACK )); then
  step "打包 secrets"
  if [[ -z "$BACKUP_DIR" ]]; then
    bad "--pack 需要 --backup-dir"
  elif [[ ! -d "$HOME/.ssh" ]]; then
    note "没有 ~/.ssh，跳过打包"
  else
    archive="$BACKUP_DIR/linux-setup-secrets-$(date +%Y%m%d).tar.gz"
    if tar czf "$archive" -C "$HOME" .ssh 2>/dev/null; then
      chmod 600 "$archive"
      ( cd "$BACKUP_DIR" && sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256" )
      ok "已生成: $archive"
      printf '      %s\n' "$(du -h "$archive" | cut -f1)"
    else
      bad "打包失败"
    fi
  fi
fi

# ---------- 汇总 ----------
step "结果"
printf '  失败 %d 项，提醒 %d 项\n' "$FAILED" "$WARNED"

if (( FAILED > 0 )); then
  printf '\n%s不建议现在抹盘。先把上面标 [!!] 的处理掉。%s\n' "$C_ERR" "$C_OFF"
  exit 1
fi

printf '\n%s可以抹盘了。%s\n' "$C_OK" "$C_OFF"
printf '安装完成后按 README 的步骤恢复。\n'
