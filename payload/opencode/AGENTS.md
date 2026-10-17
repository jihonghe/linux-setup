# 全局环境约定

本文件对这台机器上的**所有** OpenCode 会话生效。

## ~/.alias.sh 的维护规则（重要）

`~/.alias.sh` 同时是「命令定义」和「命令速查表」的唯一来源。

**修改该文件时必须做到：**

1. 任何新增或修改的函数 / alias，必须在它**正上方**写结构化注释：

   ```bash
   # @cmd: 一句话说明
   # @usage: 命令用法
   # @example: 示例（可选，可多行）
   mycmd() { ... }
   ```

2. **绝对不要手写或另存速查表**。`alias-help`（短别名 `ah`）在运行时从
   `~/.alias.sh` 的 `@cmd` 注释生成。改完命令，速查表自动同步。

3. 新命令放进对应的 `# ==== 分节 ====` 里。分节名会作为速查表的分组标题。

4. 以下划线开头的函数是内部实现，不写 `@cmd`，也不会出现在速查表中。

5. 改完必须执行 `alias-lint`，**必须 0 错误**，再用 `alias-help` 确认输出正常。

6. 修改 `~/.alias.sh` 前先备份：`cp -a ~/.alias.sh ~/.alias.sh.bak.$(date +%Y%m%d-%H%M%S)`。

## ZeroOmega 分流规则

- 规则文件：`~/.config/zeroomega/rules.txt`
- 查看：`omega-rules-show`；编辑：`omega-rules`
- 规则格式：`[SwitchyOmega Conditions]` + `@with result`，每行 `*.域名 +proxy`，
  **最后一行必须是 `* +direct`**
- **不支持 `#` 注释**：这版解析器会把注释行当成规则并报错
- 改完必须在 ZeroOmega 选项里用「编辑源码」重新粘贴并点「应用选项」，否则不生效
- 代理客户端：MonoCloud（mihomo），mixed 端口 `127.0.0.1:10801`（HTTP + SOCKS5）
- `google.com` 会被重定向到 `google.com.hk`，所以规则里两个都要有

## 常用命令

```sh
ah                  # 命令速查表
ah -v dl            # 单个命令的完整说明
dl <url> [文件名]    # 下载大文件（16 连接，自动直连/代理）
proxy-status        # 代理状态 / 当前节点 / 已用流量
proxy-bench --watch # 换节点后自动测速
alias-lint          # 检查 alias 注释是否完整
```

## 环境要点

- 系统：Omarchy（Arch Linux）+ Hyprland（Wayland）
- Shell：zsh + oh-my-zsh，`~/.zshrc` 里 `source ~/.alias.sh`
- 下载大文件一律用 `dl`（aria2c 多连接）；浏览器单连接很慢
- 浏览器 Edge 通过 AUR 安装，可访问 `127.0.0.1:10801`
- `sudo` 需要密码，无法非交互执行
- Android/Flutter 工具链在 `~/dev/` 下
