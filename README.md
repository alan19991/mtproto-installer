# MTProto Proxy (Fake TLS) + Traefik

这个项目使用一个 443 端口提供 Telegram MTProto Proxy（Fake TLS），并通过 Traefik 按 SNI 转发到 Telemt。

## 默认配置（已更新）

- 默认伪装域名（SNI）：`www.microsoft.com`
- 默认监听端口：`443`
- `use_middle_proxy` 默认值：`true`
- `ad_tag`：安装时交互输入（可留空）

## GitHub 一键安装（推荐）

```bash
curl -sSL https://raw.githubusercontent.com/alan19991/mtproto-installer/main/install.sh | bash
```

安装脚本会从 GitHub `main` 分支下载所需配置文件。

安装脚本会自动：

1. 检查并安装 Docker（如未安装）
2. 下载 `docker-compose.yml`、Traefik 配置、Telemt 模板
3. 交互输入端口、SNI 域名、`ad_tag`
4. 生成 secret 并写入配置
5. 启动容器并输出 Telegram 代理链接

## 常用环境变量

- 指定安装目录：

```bash
INSTALL_DIR=/opt/mtproxy curl -sSL https://raw.githubusercontent.com/alan19991/mtproto-installer/main/install.sh | bash
```

- 非交互指定 SNI：

```bash
FAKE_DOMAIN=example.com curl -sSL https://raw.githubusercontent.com/alan19991/mtproto-installer/main/install.sh | bash
```

- 非交互指定 `ad_tag`：

```bash
AD_TAG=mytag curl -sSL https://raw.githubusercontent.com/alan19991/mtproto-installer/main/install.sh | bash
```

## 拉取代码后本地安装

```bash
git clone https://github.com/alan19991/mtproto-installer.git
cd mtproto-installer
./install.sh
```

## 手动部署（不走脚本）

1. 复制配置模板并编辑：

```bash
cp telemt.toml.example telemt.toml
```

2. 生成 secret：

```bash
openssl rand -hex 16
```

3. 把 secret 填到 `telemt.toml` 的 `[access.users]` 中。
4. 确保以下两处域名一致：
- `telemt.toml` 里的 `censorship.tls_domain`
- `traefik/dynamic/tcp.yml` 里的 `HostSNI(...)`

5. 启动：

```bash
docker compose up -d
```

## 排障

1. 查看容器状态：

```bash
docker compose ps
```

2. 查看日志：

```bash
docker compose logs -f
```

3. 检查 443 端口监听：

```bash
ss -tlnp | grep 443
```

4. 检查配置域名是否一致：

```bash
grep tls_domain telemt.toml
grep HostSNI traefik/dynamic/tcp.yml
```

## 卸载

一键卸载：

```bash
curl -sSL https://raw.githubusercontent.com/alan19991/mtproto-installer/main/uninstall.sh | bash
```

指定目录并跳过确认：

```bash
./uninstall.sh -y /path/to/mtproxy-data
```

## 目录结构

```text
mtproxy-data/
├── docker-compose.yml
├── telemt.toml
└── traefik/
    ├── dynamic/
    │   └── tcp.yml
    └── static/
```

## 安全建议

- 不要公开分享代理链接。
- 建议长期使用 443 端口。
- 定期更新镜像：

```bash
docker compose pull && docker compose up -d
```
