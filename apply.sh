#!/usr/bin/env bash
# apply.sh — 把 linux-setup 的配置落地到 Arch / Omarchy
#
# 用法:
#   bash apply.sh --dry-run      # 只打印计划，不改任何东西
#   bash apply.sh                # 正式执行
#   bash apply.sh --no-packages  # 只放配置，不装包
#   bash apply.sh --verify       # 只做环境检查
#
# 这个脚本不做的事：改默认 shell、装 AUR 应用、配代理、碰分区。
# 手动步骤见仓库 README。

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD="$REPO_DIR/payload"

DRY_RUN=0
NO_PACKAGES=0
VERIFY_ONLY=0
BACKUP_DIR="$HOME/.linux-setup-backup-$(date +%Y%m%d-%H%M%S)"

if [[ -t 1 ]]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'
  C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_OK=''; C_WARN=''; C_ERR=''; C_DIM=''; C_OFF=''
fi

log()  { printf '%s==>%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_WARN" "$C_OFF" "$*" >&2; }
die()  { printf '%s[x]%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }
plan() { printf '%s  ·%s %s\n' "$C_DIM" "$C_OFF" "$*"; }

run() {
  if (( DRY_RUN )); then
    plan "$*"
  else
    "$@"
  fi
}

usage() {
  sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

while (( $# )); do
  case "$1" in
    --dry-run)     DRY_RUN=1 ;;
    --no-packages) NO_PACKAGES=1 ;;
    --verify)      VERIFY_ONLY=1 ;;
    -h|--help)     usage ;;
    *)             die "未知参数: $1" ;;
  esac
  shift
done

is_arch() {
  [[ -f /etc/arch-release ]] || command -v pacman >/dev/null 2>&1
}

backup_path() {
  local target="$1"
  [[ -e "$target" ]] || return 0
  if (( DRY_RUN )); then
    plan "备份 $target → $BACKUP_DIR/"
    return 0
  fi
  mkdir -p "$BACKUP_DIR"
  cp -a "$target" "$BACKUP_DIR/$(basename "$target")"
}

install_file() {
  local src="$1" dst="$2" mode="${3:-644}"
  [[ -f "$src" ]] || { warn "缺少源文件: $src"; return 0; }
  backup_path "$dst"
  if (( DRY_RUN )); then
    plan "安装 $dst"
    return 0
  fi
  install -Dm"$mode" "$src" "$dst"
}

# ---------- 只检查 ----------
verify() {
  local failed=0

  log "环境检查"

  if command -v zsh >/dev/null 2>&1; then
    printf '  %s[ok]%s zsh %s\n' "$C_OK" "$C_OFF" "$(zsh --version | awk '{print $2}')"
  else
    printf '  %s[--]%s zsh 未安装（跑 apply.sh 会装，或 sudo pacman -S zsh）\n' "$C_ERR" "$C_OFF"
    failed=1
  fi

  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    printf '  %s[ok]%s oh-my-zsh\n' "$C_OK" "$C_OFF"
  else
    printf '  %s[--]%s oh-my-zsh 未安装\n' "$C_WARN" "$C_OFF"
    failed=1
  fi

  if [[ -x "$HOME/.local/bin/alias-lint" ]]; then
    if "$HOME/.local/bin/alias-lint" --quiet; then
      printf '  %s[ok]%s alias-lint 通过\n' "$C_OK" "$C_OFF"
    else
      printf '  %s[--]%s alias-lint 报错\n' "$C_ERR" "$C_OFF"
      failed=1
    fi
  else
    printf '  %s[--]%s alias-lint 缺失\n' "$C_ERR" "$C_OFF"
    failed=1
  fi

  if [[ -x "$HOME/.local/bin/alias-help" ]]; then
    printf '  %s[ok]%s alias-help 可执行\n' "$C_OK" "$C_OFF"
  else
    printf '  %s[--]%s alias-help 缺失\n' "$C_ERR" "$C_OFF"
    failed=1
  fi

  if command -v mise >/dev/null 2>&1; then
    printf '  %s[ok]%s mise %s\n' "$C_OK" "$C_OFF" "$(mise --version 2>/dev/null | awk '{print $1}')"
  else
    printf '  %s[--]%s mise 未安装（Omarchy 默认自带）\n' "$C_WARN" "$C_OFF"
  fi

  if command -v opencode >/dev/null 2>&1; then
    printf '  %s[ok]%s opencode %s\n' "$C_OK" "$C_OFF" "$(opencode --version 2>/dev/null | head -1)"
  else
    printf '  %s[--]%s opencode 未安装\n' "$C_WARN" "$C_OFF"
  fi

  printf '\n'
  if (( failed )); then
    warn "有检查项未通过"
    return 1
  fi
  log "全部通过"
}

if (( VERIFY_ONLY )); then
  verify
  exit $?
fi

# ---------- 前置检查 ----------
if ! is_arch; then
  if (( DRY_RUN )); then
    warn "当前不是 Arch 系统：只展示计划，不会执行任何安装"
  else
    die "此脚本仅支持 Arch / Omarchy（未检测到 pacman）"
  fi
fi

log "仓库: $REPO_DIR"
(( DRY_RUN )) && warn "DRY RUN 模式：不会修改任何文件"

# ---------- 1. 依赖 ----------
if (( ! NO_PACKAGES )); then
  log "检查基础依赖"
  pkgs=()
  command -v zsh >/dev/null 2>&1 || pkgs+=(zsh)
  if command -v pacman >/dev/null 2>&1 && ! pacman -Qq fuse2 >/dev/null 2>&1; then
    pkgs+=(fuse2)
  fi

  if (( ${#pkgs[@]} )); then
    log "安装: ${pkgs[*]}"
    run sudo pacman -S --needed --noconfirm "${pkgs[@]}"
  else
    log "依赖已齐（zsh / fuse2）"
  fi
fi

# ---------- 2. oh-my-zsh ----------
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  if command -v git >/dev/null 2>&1; then
    log "安装 oh-my-zsh"
    run git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
  else
    warn "git 未安装，跳过 oh-my-zsh"
  fi
else
  log "oh-my-zsh 已存在，跳过"
fi

# ---------- 3. 复制配置 ----------
log "落地配置"
install_file "$PAYLOAD/zshrc"   "$HOME/.zshrc"  644
install_file "$PAYLOAD/zshenv"  "$HOME/.zshenv" 644
install_file "$PAYLOAD/alias.sh" "$HOME/.alias.sh" 644
install_file "$PAYLOAD/gitconfig" "$HOME/.gitconfig" 644
install_file "$PAYLOAD/zeroomega-rules.txt" "$HOME/.config/zeroomega/rules.txt" 644

for f in alias-help alias-lint proxy-bench; do
  install_file "$PAYLOAD/bin/$f" "$HOME/.local/bin/$f" 755
done

# opencode：保留 Omarchy 自带的 opencode.json（主题同步），做深合并
OC_DIR="$HOME/.config/opencode"
for f in cli.json tui.json AGENTS.md; do
  install_file "$PAYLOAD/opencode/$f" "$OC_DIR/$f" 644
done

if [[ -f "$OC_DIR/opencode.json" && -f "$PAYLOAD/opencode/opencode.jsonc" ]] && command -v jq >/dev/null 2>&1; then
  backup_path "$OC_DIR/opencode.json"
  if (( DRY_RUN )); then
    plan "合并 $OC_DIR/opencode.json ← payload/opencode/opencode.jsonc"
  else
    tmp="$(mktemp)"
    jq -s '.[0] * .[1]' "$OC_DIR/opencode.json" "$PAYLOAD/opencode/opencode.jsonc" > "$tmp"
    mv "$tmp" "$OC_DIR/opencode.json"
  fi
else
  install_file "$PAYLOAD/opencode/opencode.jsonc" "$OC_DIR/opencode.jsonc" 644
fi

# ---------- 4. Ghostty：追加而不是覆盖 ----------
GHOSTTY_DIR="$HOME/.config/ghostty"
GHOSTTY_CFG="$GHOSTTY_DIR/config"
if [[ -f "$GHOSTTY_CFG" ]]; then
  if grep -q '^# >>> linux-setup >>>' "$GHOSTTY_CFG" 2>/dev/null; then
    log "Ghostty 已含 linux-setup 配置块，跳过"
  else
    backup_path "$GHOSTTY_CFG"
    if (( DRY_RUN )); then
      plan "向 $GHOSTTY_CFG 追加下拉终端配置"
    else
      {
        printf '\n# >>> linux-setup >>>\n'
        sed -n '/^keybind = ctrl+backquote/,$p' "$PAYLOAD/ghostty.config"
        printf '# <<< linux-setup <<<\n'
      } >> "$GHOSTTY_CFG"
    fi
  fi
else
  install_file "$PAYLOAD/ghostty.config" "$GHOSTTY_CFG" 644
fi

# ---------- 5. 检查 ----------
verify || true

printf '\n'
log "完成。"
cat <<'EOF'

⚠️  还需要手动完成的事情（详见 README）：
   1. chsh -s /usr/bin/zsh && exec zsh
   2. 配代理、登录 GitHub（README §5）
   3. bash dev-setup.sh（Flutter / Android / Rust）
   4. 输入法、浏览器、ZeroOmega（README §7）

EOF
