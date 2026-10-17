# ┌────────────────────────────────────────────────────────────────────┐
# │ 维护约定（人类与 AI 都必读）                                        │
# │                                                                    │
# │ 1. 新增 / 修改任何命令，必须在它正上方写：                          │
# │        # @cmd: 一句话说明                                          │
# │        # @usage: 命令用法                                          │
# │        # @example: 示例（可选，可多行）                             │
# │ 2. 速查表由 alias-help 运行时从本文件生成，禁止手写或另存副本。      │
# │ 3. 改完执行 alias-lint 自检，必须 0 错误。                          │
# │ 4. 新命令放进对应的 「# ==== 分节 ====」 里。                        │
# │ 5. 以下划线开头的函数视为内部实现，不会出现在速查表中。              │
# └────────────────────────────────────────────────────────────────────┘

# ==== 目录与杂项 ====

# @cmd: 长格式列出目录
# @usage: ll
alias ll="ls -l"

# @cmd: 列出目录（含隐藏文件）
# @usage: la
alias la="ls -la"

# @cmd: 启动 dsh web
# @usage: dsweb
alias dsweb="dsh web"

# ==== 代理核心（内部，不显示在速查表） ====

# monocloud (mihomo) 的 mixed 端口，同时支持 SOCKS5 和 HTTP CONNECT
export MONO_PROXY="${MONO_PROXY:-http://127.0.0.1:10801}"

# 只有命中这些域名才走代理；其余一律直连
MONO_PROXY_DOMAINS=(
  google.com googleapis.com gstatic.com gmail.com youtube.com googlevideo.com
  twitter.com x.com facebook.com instagram.com whatsapp.com
  telegram.org t.me telegraph.org
  openai.com chatgpt.com anthropic.com claude.ai
  huggingface.co docker.io registry-1.docker.io
  github.com raw.githubusercontent.com
  npmjs.org registry.npmjs.org pypi.org files.pythonhosted.org
  wikipedia.org reddit.com medium.com
)

# 判断命令参数里是否包含需要代理的域名
_mono_need_proxy() {
  local arg d
  for arg in "$@"; do
    for d in "${MONO_PROXY_DOMAINS[@]}"; do
      [[ "$arg" == *"$d"* ]] && return 0
    done
  done
  return 1
}

# ==== 代理命令 ====

# @cmd: 用 curl 访问，自动判断走代理还是直连
# @usage: curl <参数> <url>      # 加 --direct 可强制直连
# @example: curl -I https://github.com
# @example: curl --direct https://example.com
curl() {
  if [[ " $* " == *" --direct "* ]]; then
    local -a rest=()
    local a
    for a in "$@"; do
      [[ "$a" == "--direct" ]] && continue
      rest+=("$a")
    done
    command curl --noproxy '*' "${rest[@]}"
  elif _mono_need_proxy "$@"; then
    command curl -x "$MONO_PROXY" "$@"
  else
    command curl --noproxy '*' "$@"
  fi
}

# @cmd: 强制用代理执行 curl
# @usage: pcurl <curl 参数>
# @example: pcurl -I https://www.google.com
pcurl() { command curl -x "$MONO_PROXY" "$@"; }

# @cmd: 强制用代理执行 git
# @usage: pgit <git 子命令>
# @example: pgit clone https://github.com/user/repo.git
pgit()  { command git -c http.proxy="$MONO_PROXY" -c https.proxy="$MONO_PROXY" "$@"; }

# @cmd: 强制用代理执行 wget
# @usage: pwget <wget 参数>
pwget() { ALL_PROXY="$MONO_PROXY" command wget "$@"; }

# @cmd: 当前 shell 开启代理（影响所有子进程）
# @usage: proxy-on
proxy-on()  { export ALL_PROXY="$MONO_PROXY" HTTPS_PROXY="$MONO_PROXY" HTTP_PROXY="$MONO_PROXY"; echo "proxy ON  -> $MONO_PROXY"; }

# @cmd: 当前 shell 关闭代理，回到直连
# @usage: proxy-off
proxy-off() { unset ALL_PROXY HTTPS_PROXY HTTP_PROXY; echo "proxy OFF -> direct"; }

# @cmd: 查看代理状态、当前节点、已用流量
# @usage: proxy-status
proxy-status() {
  local json="$HOME/.Monocloud.json"
  if command ss -lnt 2>/dev/null | grep -q ':10801 '; then
    echo "端口 10801 : LISTEN ✅"
  else
    echo "端口 10801 : 未监听 ❌ (monocloud 未连接)"
  fi
  command jq -r '"当前节点  : \(.last_connection.node_alias // "unknown")  [\(.last_connection.node_type // "?")]"' "$json" 2>/dev/null
  command jq -r '"本月已用  : \((.plans[0].bandwidth.download|tonumber)/1048576|floor) MiB / \((.plans[0].bandwidth.allowance|tonumber)/1073741824) GiB"' "$json" 2>/dev/null
}

# ==== 下载 ====

# @cmd: 大文件下载，16 连接并行，自动判断走代理还是直连
# @usage: dl <url> [文件名]        # 用 DL_DIR=目录 可改保存位置
# @example: dl https://example.com/big.zip
# @example: dl https://example.com/big.zip backup.zip
# @example: DL_DIR=/tmp dl https://example.com/big.zip
dl() {
  local url="$1" out="${2:-}"
  local dir="${DL_DIR:-$HOME/Downloads}"
  local -a pargs

  if [ -z "$url" ]; then
    echo "用法: dl <url> [文件名]   （可选 DL_DIR=目录）" >&2
    return 1
  fi
  command -v aria2c >/dev/null || { echo "缺少 aria2c：sudo apt install aria2" >&2; return 1; }
  mkdir -p "$dir"

  [ -z "$out" ] && out="$(basename "${url%%\?*}")"
  if [ -z "$out" ] || [ "$out" = "/" ]; then
    out=""
  fi

  if _mono_need_proxy "$url"; then
    pargs=(--all-proxy="$MONO_PROXY")
    printf '→ 走代理 %s（该域名直连不通）\n' "$MONO_PROXY"
  else
    pargs=(--all-proxy="")
    printf '→ 直连，16 连接并行\n'
  fi

  aria2c -x16 -s16 -k1M -c --file-allocation=none \
         --console-log-level=warn --summary-interval=5 \
         -d "$dir" ${out:+-o "$out"} "${pargs[@]}" "$url"
}

# ==== 分流规则 ====

# ZeroOmega 规则文件（存放在隐藏目录）
export OMEGA_RULES="${XDG_CONFIG_HOME:-$HOME/.config}/zeroomega/rules.txt"

# @cmd: 查看 ZeroOmega 规则文件与条数
# @usage: omega-rules-show
omega-rules-show() {
  if [ ! -f "$OMEGA_RULES" ]; then
    echo "规则文件不存在: $OMEGA_RULES" >&2
    return 1
  fi
  printf '文件: %s\n规则: %s 条\n\n' "$OMEGA_RULES" "$(grep -c ' +proxy' "$OMEGA_RULES")"
  cat "$OMEGA_RULES"
}

# @cmd: 用默认编辑器修改 ZeroOmega 规则文件
# @usage: omega-rules
omega-rules() { "${EDITOR:-vi}" "$OMEGA_RULES"; }

# ==== 速查表 ====

# @cmd: 命令速查表（alias-help 的短别名）
# @usage: ah [-v] [关键词]
# @example: ah
# @example: ah -v dl
alias ah="alias-help"
