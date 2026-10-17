#!/usr/bin/env bash
# dev-setup.sh — 为 beeptype 重装开发环境（Flutter / Android / Rust / Tauri）
#
# 用法:
#   bash dev-setup.sh --dry-run
#   bash dev-setup.sh
#   bash dev-setup.sh --skip-android
#   bash dev-setup.sh --force-flutter   # 已存在时重新解压
#
# 只支持 Arch / Omarchy。不 clone 项目、不构建项目。

set -euo pipefail

FLUTTER_VERSION="3.47.4"
FLUTTER_TARBALL="$HOME/Downloads/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_URL="https://storage.flutter-io.cn/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
ANDROID_HOME="$HOME/dev/android-sdk"
CMDLINE_ZIP_URL="https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip"

ANDROID_PKGS=(
  "platform-tools"
  "platforms;android-36"
  "platforms;android-34"
  "build-tools;36.0.0"
  "ndk;28.2.13676358"
  "cmake;3.22.1"
)

DRY_RUN=0
SKIP_FLUTTER=0
SKIP_ANDROID=0
SKIP_RUST=0
FORCE_FLUTTER=0

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
  sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

while (( $# )); do
  case "$1" in
    --dry-run)       DRY_RUN=1 ;;
    --skip-flutter)  SKIP_FLUTTER=1 ;;
    --skip-android)  SKIP_ANDROID=1 ;;
    --skip-rust)     SKIP_RUST=1 ;;
    --force-flutter) FORCE_FLUTTER=1 ;;
    -h|--help)       usage ;;
    *)               die "未知参数: $1" ;;
  esac
  shift
done

is_arch() {
  [[ -f /etc/arch-release ]] || command -v pacman >/dev/null 2>&1
}

if ! is_arch; then
  if (( DRY_RUN )); then
    warn "当前不是 Arch：只展示计划"
  else
    die "此脚本仅支持 Arch / Omarchy（未检测到 pacman）"
  fi
fi

# ---------- 磁盘空间 ----------
free_gb="$(df -Pk "$HOME" | awk 'NR==2 {printf "%d", $4/1024/1024}')"
if (( free_gb < 10 )); then
  warn "家目录剩余 ${free_gb}G，建议至少 10G（Flutter + Android SDK）"
fi

# ---------- 代理提示 ----------
if (( ! DRY_RUN )) && command -v curl >/dev/null 2>&1; then
  if ! curl -sI --max-time 8 https://dl.google.com >/dev/null 2>&1; then
    warn "连不上 dl.google.com：Android SDK 下载可能失败，请先开代理"
  fi
fi

# ---------- 1. 系统依赖 ----------
log "安装系统依赖"
PKGS=(
  base-devel jdk21-openjdk android-tools rustup
  webkit2gtk-4.1 libayatana-appindicator librsvg patchelf openssl
  unzip wget file ffmpeg
)
run sudo pacman -S --needed --noconfirm "${PKGS[@]}"

# ---------- 2. Rust / tauri-cli ----------
if (( ! SKIP_RUST )); then
  log "配置 Rust"
  if command -v rustup >/dev/null 2>&1; then
    if ! rustup toolchain list 2>/dev/null | grep -q '^stable'; then
      run rustup default stable
    else
      log "Rust stable 已存在"
    fi
  else
    warn "rustup 未安装（pacman 应该已经装上）"
  fi

  CARGO_BIN="$HOME/.cargo/bin/cargo"
  [[ -x "$CARGO_BIN" ]] || CARGO_BIN="$(command -v cargo || true)"

  if [[ -n "$CARGO_BIN" && -x "$CARGO_BIN" ]]; then
    if "$CARGO_BIN" tauri --version >/dev/null 2>&1; then
      log "tauri-cli 已安装"
    else
      log "安装 tauri-cli（需要编译，约 5–10 分钟）"
      run "$CARGO_BIN" install tauri-cli --locked
    fi
  else
    warn "找不到 cargo，跳过 tauri-cli"
  fi
fi

# ---------- 3. Flutter ----------
if (( ! SKIP_FLUTTER )); then
  log "Flutter $FLUTTER_VERSION"

  if [[ -d "$HOME/dev/flutter" && ! $FORCE_FLUTTER -eq 1 ]]; then
    log "$HOME/dev/flutter 已存在，跳过（想重装加 --force-flutter）"
  elif (( DRY_RUN )); then
    plan "下载并解压 Flutter 到 ~/dev/flutter"
  else
    mkdir -p "$HOME/dev"

    if [[ -f "$FLUTTER_TARBALL" ]]; then
      log "使用本地包: $FLUTTER_TARBALL"
    else
      log "下载: $FLUTTER_URL"
      curl -fL --retry 3 -o "$FLUTTER_TARBALL" "$FLUTTER_URL"
    fi

    if [[ -d "$HOME/dev/flutter" ]]; then
      mv "$HOME/dev/flutter" "$HOME/dev/flutter.bak.$(date +%Y%m%d-%H%M%S)"
    fi

    tar -xf "$FLUTTER_TARBALL" -C "$HOME/dev"
    "$HOME/dev/flutter/bin/flutter" --version
    "$HOME/dev/flutter/bin/flutter" config --no-analytics >/dev/null 2>&1 || true
  fi
fi

# ---------- 4. Android SDK ----------
if (( ! SKIP_ANDROID )); then
  log "Android SDK → $ANDROID_HOME"

  SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"

  if [[ -x "$SDKMANAGER" ]]; then
    log "cmdline-tools 已存在，跳过下载"
  elif (( DRY_RUN )); then
    plan "下载 cmdline-tools 并解压到 $ANDROID_HOME"
  else
    mkdir -p "$ANDROID_HOME/cmdline-tools"
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    curl -fL --retry 3 -o "$tmpdir/cmdline-tools.zip" "$CMDLINE_ZIP_URL"
    unzip -q "$tmpdir/cmdline-tools.zip" -d "$tmpdir"
    rm -rf "$ANDROID_HOME/cmdline-tools/latest"
    mv "$tmpdir/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
  fi

  if (( DRY_RUN )); then
    plan "接受 licenses 并安装: ${ANDROID_PKGS[*]}"
  else
    export ANDROID_HOME ANDROID_SDK_ROOT="$ANDROID_HOME"
    if command -v archlinux-java >/dev/null 2>&1; then
      JAVA_HOME="/usr/lib/jvm/$(archlinux-java get)"
      export JAVA_HOME
    fi

    yes | "$SDKMANAGER" --sdk_root="$ANDROID_HOME" --licenses >/dev/null 2>&1 || true
    "$SDKMANAGER" --sdk_root="$ANDROID_HOME" "${ANDROID_PKGS[@]}"
  fi
fi

# ---------- 5. 验证 ----------
log "验证"

if [[ -x "$HOME/dev/flutter/bin/flutter" && ! $SKIP_FLUTTER -eq 1 ]] && (( ! DRY_RUN )); then
  "$HOME/dev/flutter/bin/flutter" doctor || true
fi

if (( ! DRY_RUN )); then
  command -v java >/dev/null 2>&1 && java -version 2>&1 | head -1
  command -v adb  >/dev/null 2>&1 && adb version | head -1
  if [[ -x "$HOME/.cargo/bin/cargo" ]]; then
    "$HOME/.cargo/bin/cargo" tauri --version || true
  fi
fi

printf '\n'
log "dev-setup 完成。"
cat <<'EOF'

提示：
  · Flutter 已在 ~/dev/flutter，zshrc 会自动加进 PATH
  · Android SDK 在 ~/dev/android-sdk，licenses 已接受
  · 新开终端后跑 flutter doctor 复核
  · beeptype 首次构建（可选）：
      git clone git@github.com:jihonghe/beeptype.git ~/Code/beeptype
      cd ~/Code/beeptype/app && flutter pub get
      cd ../desktop && cargo build

EOF
