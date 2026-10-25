# Gokapi Debian 12+ 一键安装

这是一个面向个人服务器的 **Gokapi 原生安装与管理脚本**。它不会修改旧的 `filebrowser` 仓库，也不使用 Docker。

Gokapi 适合“上传文件 → 生成分享链接 → 让其他人下载”的场景，支持链接过期、下载次数限制、密码、文件请求等功能。本仓库只提供安装脚本；Gokapi 本体由 [Forceu/Gokapi](https://github.com/Forceu/Gokapi) 维护。

## 一键安装

在 Debian 12 或更高版本的服务器上执行：

```bash
curl -fsSL https://raw.githubusercontent.com/brian952700/gokapi/main/gokapi.sh | bash -s -- install
```

安装完成后访问：

```text
http://服务器IP:53842/setup
```

请立即完成首次管理员配置。若服务器已开放到公网，推荐先用防火墙限制 53842 端口，并通过 Caddy、Nginx 等反向代理提供 HTTPS。

自定义首次启动端口：

```bash
curl -fsSL https://raw.githubusercontent.com/brian952700/gokapi/main/gokapi.sh | sudo env GOKAPI_PORT=12345 bash -s -- install
```

## 支持范围

- 操作系统：Debian 12 及以上版本（脚本会严格检查）
- 架构：`amd64`、`arm64`、`armhf`、`riscv64`
- Gokapi：固定并校验官方稳定版 `v2.2.4`
- 服务管理：systemd
- 运行用户：独立的无登录权限 `gokapi` 用户

发布包会使用写在脚本中的官方 SHA-256 摘要进行校验，校验失败时不会安装。

## 管理命令

下载脚本后也可以重复使用：

```bash
curl -fsSLO https://raw.githubusercontent.com/brian952700/gokapi/main/gokapi.sh
chmod +x gokapi.sh

sudo ./gokapi.sh status
sudo ./gokapi.sh update
sudo ./gokapi.sh uninstall
```

`uninstall` 会删除程序和 systemd 服务，但保留配置与上传文件。完全删除需要明确确认：

```bash
sudo ./gokapi.sh purge --yes
```

## 目录

| 用途 | 路径 |
| --- | --- |
| 程序 | `/usr/local/bin/gokapi` |
| systemd 服务 | `/etc/systemd/system/gokapi.service` |
| 环境变量 | `/etc/default/gokapi` |
| 配置 | `/etc/gokapi` |
| 数据与上传文件 | `/var/lib/gokapi` |

常用 systemd 命令：

```bash
sudo systemctl status gokapi
sudo systemctl restart gokapi
sudo journalctl -u gokapi -f
```

## 更新说明

运行 `update` 会重新下载并校验脚本固定的 Gokapi 版本，然后原子替换二进制并重启服务；现有配置和文件不会被覆盖。

当上游发布新版本时，需要先更新本仓库中的版本号和各架构 SHA-256，再运行更新命令。

## 安全说明

- Gokapi 初始配置页面在首次启动后可用，请不要长时间暴露未配置的实例。
- 公网分享建议使用 HTTPS 反向代理；大文件上传时应提高代理的请求体大小和超时时间。
- 脚本使用专用低权限用户，并为 systemd 服务启用基础沙箱保护。
- 加密功能的取舍与限制请阅读 [Gokapi 官方文档](https://gokapi.readthedocs.io/en/latest/setup.html)。

## 许可证

本安装脚本使用 MIT License。Gokapi 本体遵循其上游仓库的许可证。
