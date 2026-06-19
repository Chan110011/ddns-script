# DDNS Cloudflare 一键管理脚本设计

日期：2026-06-19

## 背景

基于 NewFuture/DDNS 项目，为 Linux 服务器制作一个单文件交互式管理脚本。目标用户主要使用 Cloudflare DNS，并通过 Cloudflare API Token 更新 DNS 记录。

当前工作区为空且不是 git 仓库。本设计先定义脚本行为、文件路径、菜单、配置生成和安全策略。

## 目标

创建一个 Linux 单文件交互式脚本，例如：

```bash
sudo bash ddns-manager.sh
```

脚本用于管理 NewFuture/DDNS 的二进制安装、Cloudflare 配置、systemd 服务、日志查看和卸载。

## 非目标

- 不做 Web 面板。
- 不做多 DNS 服务商通用向导。
- 不做 Docker 管理。
- 不做 Windows PowerShell 版本。
- 不内置 Cloudflare Token 创建功能，用户需要自行在 Cloudflare 后台创建 Token。

## 安装与文件布局

采用 NewFuture/DDNS 官方 Release 二进制。

计划路径：

- 安装目录：`/opt/ddns`
- 主程序：`/opt/ddns/ddns`
- 配置目录：`/etc/ddns`
- 配置文件：`/etc/ddns/config.json`
- systemd 服务：`/etc/systemd/system/ddns.service`

安装或更新流程：

1. 检查是否以 root 权限运行。
2. 检查系统是否有 systemd。
3. 检测系统架构，例如 `x86_64`、`aarch64`。
4. 检查下载工具 `curl` 或 `wget`。
5. 从 GitHub Release 下载匹配的 Linux 二进制包。
6. 解压并安装到 `/opt/ddns/ddns`。
7. 设置可执行权限。
8. 创建或覆盖 systemd 服务文件。
9. 执行 `systemctl daemon-reload`。
10. 提示是否立即进入 Cloudflare 配置向导。

## 交互菜单

主菜单包含：

1. 安装/更新 DDNS
2. 快速写入 Cloudflare 配置
3. 查看当前配置
4. 修改配置
5. 启动 DDNS
6. 停止 DDNS
7. 重启 DDNS
8. 查看运行状态
9. 查看日志
10. 卸载 DDNS
0. 退出

无参数运行脚本时显示该菜单。脚本第一版不提供命令行子命令。

## Cloudflare 配置向导

配置向导专用于 Cloudflare API Token。

询问字段：

- Cloudflare API Token，必填。
- IPv4 域名列表，逗号分隔，至少需要 IPv4 或 IPv6 之一非空。
- 是否启用 IPv6。
- IPv6 域名列表，启用 IPv6 时填写。
- TTL，默认 `600`。
- Cloudflare 代理开关，默认 `false`。

生成配置示例：

```json
{
  "$schema": "https://ddns.newfuture.cc/schema/v4.0.json",
  "dns": "cloudflare",
  "id": "",
  "token": "<Cloudflare API Token>",
  "index4": "default",
  "index6": "default",
  "ipv4": ["a.example.com"],
  "ipv6": [],
  "ttl": 600,
  "proxy": false
}
```

实现前需要再次核对 NewFuture/DDNS 当前文档或示例，确认 Cloudflare 在 API Token 模式下 `id` 字段是否应为空、邮箱、账号 ID 或其他值；以官方项目文档为准。

## 查看与修改配置

查看配置：

- 默认隐藏 `token` 值，只显示前后少量字符。
- 提供二次确认后显示完整配置。

修改配置：

1. 重新运行 Cloudflare 配置向导并覆盖 `/etc/ddns/config.json`。
2. 使用编辑器编辑完整配置：优先 `$EDITOR`，其次 `nano`；若编辑器不存在则提示用户安装。

配置文件写入后执行：

- `chown root:root /etc/ddns/config.json`
- `chmod 600 /etc/ddns/config.json`

## systemd 服务设计

服务文件内容核心为：

```ini
[Unit]
Description=NewFuture DDNS Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/ddns/ddns -c /etc/ddns/config.json
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

菜单中的启动、停止、重启、状态和日志查看分别调用：

- `systemctl enable --now ddns`
- `systemctl stop ddns`
- `systemctl restart ddns`
- `systemctl status ddns --no-pager`
- `journalctl -u ddns -f`

## 卸载流程

卸载时：

1. 二次确认。
2. 停止并禁用 systemd 服务。
3. 删除 `/etc/systemd/system/ddns.service`。
4. 执行 `systemctl daemon-reload`。
5. 删除 `/opt/ddns`。
6. 询问是否保留 `/etc/ddns/config.json`。
7. 若用户选择不保留，删除 `/etc/ddns`。

## 错误处理

脚本需要明确检查并提示：

- 非 root 运行。
- 缺少 systemd。
- 缺少 `curl`/`wget`。
- 缺少解压工具。
- 系统架构不受支持。
- GitHub Release 下载失败。
- 二进制安装后不可执行。
- 配置字段为空或域名列表为空。
- systemctl 操作失败。

## 测试与验证

实现后至少验证：

1. Shell 语法检查：`bash -n ddns-manager.sh`。
2. 静态检查：如可用则运行 `shellcheck ddns-manager.sh`。
3. 本地 dry-run 或临时目录模拟生成配置。
4. 人工检查生成的 JSON 可被 Python `json` 模块解析。
5. 在 Linux 环境中验证 systemd 服务文件内容合理。

## 后续扩展

脚本函数边界预留扩展空间，但第一版不实现：

- 其他 DNS 服务商向导。
- 命令行子命令模式。
- Docker 模式。
- 自动创建 Cloudflare API Token。
