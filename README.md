# ddns-script

基于 [NewFuture/DDNS](https://github.com/NewFuture/DDNS) 的 Cloudflare DNS 一键管理脚本。

## 一键安装/管理

在 Linux 服务器上执行下面的命令。脚本会保存到当前目录的 `ddns-manager.sh`，方便以后重复使用：

```bash
export LANG=C.UTF-8 LC_ALL=C.UTF-8; wget --no-cache -O ddns-manager.sh https://raw.githubusercontent.com/Chan110011/ddns-script/main/install.sh && chmod +x ddns-manager.sh && sudo -E bash ./ddns-manager.sh
```

后续再次管理 DDNS 时，不需要重新下载，直接运行：

```bash
export LANG=C.UTF-8 LC_ALL=C.UTF-8; sudo -E bash ./ddns-manager.sh
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
sudo -E bash ./ddns-manager.sh
```
