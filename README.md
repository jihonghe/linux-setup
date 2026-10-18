# linux-setup

Personal dotfiles and bootstrap scripts for **Arch Linux / Omarchy**.

> Opinionated, Arch-only setup: zsh + oh-my-zsh, my own `alias.sh` command
> system, OpenCode configs, Ghostty quick terminal, and a scripted
> Flutter / Android / Rust toolchain for [beeptype](https://github.com/jihonghe/beeptype).
>
> This repo contains **no secrets**. Regenerate SSH keys on the new machine.

---

## 目录

- [这是什么](#这是什么)
- [仓库结构](#仓库结构)
- [0. 抹盘前：备份与自检](#0-抹盘前备份与自检)
- [1. 安装 Omarchy](#1-安装-omarchy)
- [2. 首次开机：网络与代理](#2-首次开机网络与代理)
- [3. 连接 GitHub](#3-连接-github)
- [4. 运行 apply.sh](#4-运行-applysh)
- [5. 切换默认 shell](#5-切换默认-shell)
- [6. 运行 dev-setup.sh](#6-运行-dev-setsh)
- [7. 手动步骤](#7-手动步骤)
- [8. 故障排查](#8-故障排查)
- [9. 说明与约定](#9-说明与约定)

---

## 这是什么

一台机器从零到可开发状态的完整流程。三个脚本各司其职：

| 脚本 | 何时跑 | 作用 |
|---|---|---|
| `backup-check.sh` | 旧系统，抹盘前 | 自检仓库/配置/SSH，可选打包 secrets |
| `apply.sh` | 新系统 | 落地 dotfiles、zsh、oh-my-zsh、Ghostty 合并 |
| `dev-setup.sh` | 新系统，代理就绪后 | Flutter / Android SDK / Rust / tauri-cli |

**适用环境**：Arch Linux（开发与验证均在 Omarchy 4.x 上完成）。
其他发行版不保证，脚本会直接拒绝执行。

---

## 仓库结构

```
linux-setup/
├── README.md
├── apply.sh
├── dev-setup.sh
├── backup-check.sh
├── .gitignore
└── payload/
    ├── alias.sh              # 命令体系（@cmd 注释 + alias-lint）
    ├── zshrc                 # 带存在性判断的 zsh 配置
    ├── zshenv
    ├── bin/
    │   ├── alias-help        # 从 alias.sh 生成速查表
    │   ├── alias-lint        # 校验 @cmd 注释
    │   └── proxy-bench
    ├── opencode/
    │   ├── opencode.jsonc
    │   ├── cli.json
    │   ├── tui.json
    │   └── AGENTS.md
    ├── gitconfig
    ├── ghostty.config        # 下拉终端配置片段
    └── zeroomega-rules.txt   # 浏览器分流规则源文件
```

---

## 0. 抹盘前：备份与自检

在旧系统上执行（只读，不改系统）：

```bash
cd ~/linux-setup
bash backup-check.sh --backup-dir /media/usb/backup --pack
```

它会检查：

- 仓库是否干净、是否已推送
- `payload/` 与本机配置是否逐字节一致
- SSH 密钥是否存在、权限是否正确
- `~/Documents`、`~/Pictures` 是否还在
- 备份目录是否可写
- `--pack` 时把 `~/.ssh` 打成 `linux-setup-secrets-YYYYMMDD.tar.gz`（600 权限 + sha256）

**全部 `[ok]` 再抹盘。** 有 `[!!]` 就先处理。

> **Android 签名密钥（keystores）有意不迁移。**
> beeptype 目前只有自己一个用户，换机器时直接卸载重装即可，
> 需要发版时让 AI 重新生成一套密钥。

---

## 1. 安装 Omarchy

1. 下载 ISO（`omarchy-4.0.4.iso`）并写入 U 盘：

   ```bash
   sudo dd if=omarchy-4.0.4.iso of=/dev/sdX bs=4M status=progress oflag=sync conv=fsync
   ```

2. BIOS 里确认：
   - **Secure Boot：关闭**（Arch 系 ISO 未签名）
   - **Fast Boot：关闭**
   - **USB Boot：开启**

3. 开机按 `F12`/`F11` 选带 `UEFI:` 前缀的 U 盘。

4. 安装时：
   - 全盘安装，**启用 LUKS 加密**
   - 文件系统用 btrfs（Omarchy 默认带快照）
   - 记住 LUKS 口令，丢了数据就没了

---

## 2. 首次开机：网络与代理

打开终端：`Super + Return`。

```bash
# MonoCloud（AppImage 是静态运行时，无需 fuse2；若报缺 libfuse.so.2 再装）
#   sudo pacman -S --needed fuse2
mkdir -p ~/Applications
mv ~/Downloads/monocloud-*.AppImage ~/Applications/monocloud.AppImage
chmod +x ~/Applications/monocloud.AppImage
~/Applications/monocloud.AppImage &
```

登录后验证并临时开代理：

```bash
ss -lnt | grep 10801

export ALL_PROXY=http://127.0.0.1:10801
export HTTPS_PROXY=$ALL_PROXY HTTP_PROXY=$ALL_PROXY

curl -I https://github.com
```

> 这一份代理设置只对当前终端有效。`apply.sh` 之后可以用 `proxy-on` / `proxy-off`。

---

## 3. 连接 GitHub

选一条路线。

### A. 生成新密钥（推荐）

```bash
ssh-keygen -t ed25519 -C "omarchy@$(hostname)" -f ~/.ssh/id_ed25519 -N ""
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

gh auth login
# GitHub.com → SSH → Yes (upload your public key) → Login with a web browser

# 若上一步没自动上传：
gh ssh-key add ~/.ssh/id_ed25519.pub --title "omarchy-$(date +%F)"

ssh -T git@github.com
# 期望：Hi jihonghe! You've successfully authenticated...
```

### B. 恢复旧密钥

```bash
tar xzf /media/usb/backup/linux-setup-secrets-*.tar.gz -C ~/
chmod 600 ~/.ssh/id_ed25519
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519
ssh -T git@github.com
```

然后克隆：

```bash
git clone git@github.com:jihonghe/linux-setup.git ~/linux-setup
cd ~/linux-setup
```

> GitHub 连不上时，可临时用镜像前缀：
> `git clone https://gh-proxy.com/https://github.com/jihonghe/linux-setup.git`

---

## 4. 运行 apply.sh

```bash
bash apply.sh --dry-run   # 先看计划
bash apply.sh
```

> **先确认 MonoCloud 已连接**：脚本要从 GitHub 拉 oh-my-zsh。若当前 shell 没有
> `HTTPS_PROXY` 之类的环境变量，而 MonoCloud 监听在 `127.0.0.1:10801`，脚本会
> **自动借道**该代理克隆；两样都没有才会失败。

它会：

1. 检查并补装 `zsh`、`aria2`、`jq`（`dl` 用 aria2c；代理状态与配置合并用 jq）
2. 安装 oh-my-zsh（不存在时）
3. 备份现有配置到 `~/.linux-setup-backup-<时间戳>/`
4. 复制 `alias.sh`、`zshrc`、`zshenv`、bin 脚本、`gitconfig`（→ `~/.config/git/config`）、ZeroOmega 规则
5. 合并 OpenCode 配置（保留 Omarchy 自带的 `opencode.json`）
6. 向 Ghostty 配置追加下拉终端设置（不覆盖官方配置）
7. 运行环境检查

参数：

```bash
bash apply.sh --no-packages   # 只放配置
bash apply.sh --verify        # 只检查
```

---

## 5. 切换默认 shell

脚本不会自动改（`chsh` 需要密码，会打断自动化）：

```bash
chsh -s /usr/bin/zsh
exec zsh
```

> **改完要注销重登一次（或重启）**：`chsh` 只改 `/etc/passwd`，而当前图形会话
> （Hyprland / Ghostty）环境里 `SHELL` 仍是旧值，`Super+Return` 新开的终端
> 会**依旧进 bash**。临时救急：在当前终端 `exec zsh`。彻底生效：`omarchy logout`
> 后重新登录。

新终端里确认：

```bash
echo $SHELL
alias-lint
ah
```

---

## 6. 运行 dev-setup.sh

**先确认代理开着**（Android SDK 走 `dl.google.com`）。

```bash
bash dev-setup.sh --dry-run
bash dev-setup.sh
```

会安装：

| 组件 | 版本 / 说明 |
|---|---|
| 系统依赖 | base-devel、jdk21-openjdk、android-tools、rustup、webkit2gtk-4.1、libayatana-appindicator、librsvg、patchelf、openssl、unzip、wget、file、ffmpeg |
| Rust | rustup stable |
| tauri-cli | `cargo install tauri-cli`（首次编译 5–10 分钟） |
| Flutter | **3.47.4 stable** → `~/dev/flutter` |
| Android SDK | `~/dev/android-sdk` |
| platforms | android-34、android-36 |
| build-tools | 36.0.0 |
| NDK | 28.2.13676358 |
| cmake | 3.22.1 |

参数：

```bash
bash dev-setup.sh --skip-android
bash dev-setup.sh --skip-flutter
bash dev-setup.sh --skip-rust
bash dev-setup.sh --force-flutter
```

> 已完成 `flutter doctor` 的 licenses 接受。
> Linux 桌面工具链（clang/gtk3）不装，`flutter doctor` 里那一项红叉可以忽略。

---

## 7. 手动步骤

### 7.1 输入法

Omarchy 预装 fcitx5 + 中文引擎（本机拼音组已配好）。需要调整时：

```bash
fcitx5-configtool
```

1. 添加 **Pinyin**（拼音组）
2. 需要五笔就再加 **Wubi 98**
3. 切换键默认 `Ctrl + Space`（`Super + Space` 也可切换）

验证：

```bash
fcitx5-diagnose | head -30
```

### 7.2 浏览器与 ZeroOmega

```bash
yay -S microsoft-edge-stable-bin
```

1. Edge 登录账号（同步收藏/密码）
2. 安装 ZeroOmega 扩展
3. 打开扩展选项 → 左侧「情景模式」→ 选中 **`proxy`** → 代理协议选 `HTTP`（mixed 端口用 `SOCKS5` 也行）→ 服务器 `127.0.0.1` → 端口 `10801` → 「应用选项」
4. 选中 **`proxy-rules`**（自动切换情景）→ **编辑源码**
5. 粘贴 `payload/zeroomega-rules.txt` 的**全部**内容 → 「应用选项」
6. 点扩展图标，确认当前用的情景是 **`proxy-rules`**

> **关键**：规则里的 `+proxy` 指的是名为 `proxy` 的情景，它默认是占位值
> `proxy.example.com:8080`，**必须改成 `127.0.0.1:10801`**，否则所有命中代理的
> 域名都会请求失败。另外粘贴时别漏末尾的 `github.com` 等行。
> Edge 账号同步不会恢复扩展内部数据，这一步必须手动。

### 7.3 OpenCode

```bash
opencode            # 首次运行 /connect 登录 provider
omarchy default agent opencode
```

### 7.4 可选应用

```bash
yay -S tencent-wechat
yay -S xiaohongshu-pake
yay -S doubao-desktop-bin
```

### 7.5 硬件自检

```bash
hyprctl monitors
brightnessctl set 50%
speaker-test -t sine -f 440 -c 2 -l 1
bluetoothctl show
systemctl suspend
```

### 7.6 最终验收

```bash
alias-lint
ah
proxy-status
node -v                # 只有装了 Node 才有
flutter doctor -v
cargo tauri --version
adb version
tmux new -s t 'tdl c'
```

---

## 8. 故障排查

| 现象 | 处理 |
|---|---|
| `git clone` 卡住/超时 | 开代理；或用 `https://gh-proxy.com/https://github.com/...` |
| `yay` 拉 AUR 失败 | 同上是网络问题，确认 `ALL_PROXY` 生效 |
| `flutter doctor` 报 Android licenses | `flutter doctor --android-licenses` |
| `sdkmanager` 报 Java 错误 | 确认 `archlinux-java get` 有输出，JDK 21 已装 |
| `tdl: command not found` | 确认 `~/.zshrc` 里 source 了 `/usr/share/omarchy/default/bash/fns/tmux`；或 `exec zsh` |
| Ghostty 下拉快捷键无反应 | X11 不支持 quick terminal；Omarchy 是 Wayland，应可用。确认配置块已追加 |
| `alias-lint` 报错 | 按提示补 `@cmd` 注释，或 `ah` 查看格式 |
| 中文显示方块 | `sudo pacman -S noto-fonts-cjk`（Omarchy 默认已装） |

---

## 9. 说明与约定

- **`~/.alias.sh` 是唯一命令来源**：改命令必须写 `@cmd` / `@usage` 注释，改完跑 `alias-lint`。
- **配置即文档**：所有手动步骤都在本 README；脚本只输出状态，不重复教程。
- **不迁移的东西**（有意为之）：
  - Android 签名密钥（keystores）——换机器重新生成
  - 浏览器 profile / 书签——用账号同步
  - `~/Code` 源码——重要项目都在 GitHub
  - nvm / pnpm / bun——beeptype 是 Flutter + Tauri，不需要
  - Guake——用 Ghostty quick terminal 取代
- **版本锁定**：Flutter 3.47.4、platforms 34/36、build-tools 36.0.0、NDK 28.2.13676358。
- **代理端口**：`127.0.0.1:10801`（MonoCloud mixed）。

---

MIT
