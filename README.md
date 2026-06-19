# ddns-script

基于 [NewFuture/DDNS](https://github.com/NewFuture/DDNS) 的 Cloudflare DNS 一键管理脚本。

## 一键安装/管理

在 Linux 服务器上执行：

```bash
curl -fsSL -o /tmp/ddns-manager.sh https://raw.githubusercontent.com/Chan110011/ddns-script/main/install.sh && sudo bash /tmp/ddns-manager.sh
```

如果系统没有 `curl`，可以使用：

```bash
wget -O /tmp/ddns-manager.sh https://raw.githubusercontent.com/Chan110011/ddns-script/main/install.sh && sudo bash /tmp/ddns-manager.sh
```

## 功能

- 安装/更新 NewFuture/DDNS 二进制程序
- 快速写入 Cloudflare API Token 配置
- 查看配置，默认隐藏 Token
- 修改配置
- systemd 启动、停止、重启、状态查看
- 查看日志
- 卸载 DDNS

## 生产环境路径

脚本在 Linux 服务器上会写入：

- `/opt/ddns`
- `/etc/ddns/config.json`
- `/etc/systemd/system/ddns.service`

## 手动使用

```bash
chmod +x ddns-manager.sh
sudo ./ddns-manager.sh
```

