# TOTP-Share

自托管的 TOTP 验证码管理与分享。把账号的两步验证密钥存在自己的服务器上，
给每个账号生成一条分享链接，拿到链接的人只能看到当前的 6 位验证码，看不到密钥。

适合几个人共用一个账号、又不想把密钥发给每个人的场景。

## 功能

- **账号列表**：直接显示每个账号当前的验证码和倒计时，点一下复制
- **分享链接** `/t/<token>`：只显示验证码；可一键更换，旧链接立即失效
- **分享密码**：全站统一密码，或给某条链接单独设密码
- **分组与搜索**：自建分组，每个分组一个颜色，账号名称前显示彩色分组标签；按分组筛选、按名称搜索，拖拽排序
- **访问记录**：谁（IP、地区、设备）在什么时候看过哪个账号的验证码，含输错密码的尝试
- **重名提示**：添加或改名时发现同名账号会提醒
- **加密备份**：每天自动备份数据库和密钥文件，AES-256 加密，自动清理旧备份

## 安全设计

- TOTP 密钥用 Fernet 加密后入库，密钥（`FERNET_KEY`）只放在环境文件里
- 管理员密码和分享密码用 Argon2 哈希
- 分享页只下发验证码，密钥从不离开服务器
- 全部表单有 CSRF 保护；登录和分享密码有按访客 IP 的限流
- 管理员 30 分钟无操作自动退出
- 部署在 Cloudflare 隧道后面时，从 `CF-Connecting-IP` 取访客真实 IP（只在请求来自本机回环地址时才信任这个头）

> 后台登录后能看到所有账号的验证码，请使用足够强的管理员密码，并且只通过 HTTPS 访问。

## 技术栈

Python 3.11+ · Flask · SQLite · gunicorn · Bootstrap 5（CDN）。单文件应用，没有前端构建步骤。

## 部署

以下以 Debian/Ubuntu、安装到 `/opt/totp-share` 为例。

```bash
# 1. 代码和依赖
sudo useradd --system --home /opt/totp-share --shell /usr/sbin/nologin totp
sudo git clone <本仓库地址> /opt/totp-share
cd /opt/totp-share
sudo python3 -m venv venv
sudo venv/bin/pip install -r requirements.txt
sudo mkdir -p data && sudo chown -R totp:totp /opt/totp-share

# 2. 环境文件（按文件里的注释生成两个密钥）
sudo install -d -m 750 /etc/totp-share
sudo install -m 600 deploy/env.example /etc/totp-share/env
sudo nano /etc/totp-share/env

# 3. 创建管理员（密码至少 12 位；表结构在首次启动时自动建好）
sudo -u totp env $(sudo grep -v '^#' /etc/totp-share/env | xargs) venv/bin/python - <<'EOF'
import getpass, sqlite3, os
from argon2 import PasswordHasher
import app  # 导入即建表
db = sqlite3.connect(os.environ["DATABASE_PATH"])
db.execute("INSERT INTO admin(id, username, password_hash) VALUES (1, ?, ?)",
           (input("管理员用户名: "), PasswordHasher().hash(getpass.getpass("管理员密码: "))))
db.commit()
EOF

# 4. 服务
sudo cp deploy/totp-share.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now totp-share
```

应用默认只监听 `127.0.0.1:8765`，前面需要一个提供 HTTPS 的反向代理（Nginx、Caddy）或 Cloudflare 隧道。
会话 cookie 带 `Secure` 标记，不走 HTTPS 无法登录。

升级：更新代码后 `sudo systemctl restart totp-share` 即可。数据库结构由 `migrate.py` 在启动时自动补齐，只加表加列，不改已有数据。

## 备份与恢复

```bash
# 生成备份口令（只需一次）
sudo sh -c 'umask 077; head -c 32 /dev/urandom | base64 > /etc/totp-share/backup.pass'

# 安装备份脚本和定时器（每天北京时间 04:10 左右）
sudo install -m 700 -o root -g root backup.py /usr/local/sbin/totp-share-backup
sudo cp deploy/totp-share-backup.service deploy/totp-share-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now totp-share-backup.timer

# 立即备份一次 / 查看结果
sudo systemctl start totp-share-backup
sudo journalctl -u totp-share-backup -n 5
sudo ls -l /var/backups/totp-share
```

每份备份是一个 `totp-share-<时间>.tar.gpg`，里面有数据库快照 `totp.db` 和密钥文件 `env`。
默认保留 30 天，且不论多旧至少保留最新 7 份。

**请把 `/etc/totp-share/backup.pass` 里的口令另外抄到密码管理器。** 口令和备份都只在这台服务器上的话，
服务器丢了就都没了。建议再把 `/var/backups/totp-share` 定期同步到别处；备份文件已经加密，可以放心存到网盘或对象存储。

恢复：

```bash
gpg --decrypt totp-share-20261113-201000Z.tar.gpg | tar -x     # 会提示输入口令
# 把 totp.db 放回 DATABASE_PATH，env 放回 /etc/totp-share/env，然后重启服务
```

## 本地开发

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt pytest
.venv/bin/python -m pytest tests          # 全部用临时数据库和假数据
.venv/bin/python dev/run.py               # http://127.0.0.1:8767，假账号
```

`dev/run.py` 首次运行会生成 `dev/.env.dev`（随机密钥和本地管理员密码）和 `dev/dev.db`，两者都不会进 git。

## 目录

| 路径 | 说明 |
| --- | --- |
| `app.py` | 全部路由和业务逻辑 |
| `migrate.py` | 数据库结构迁移，启动时自动执行 |
| `backup.py` | 加密备份脚本 |
| `templates/` | 页面模板 |
| `deploy/` | systemd 单元和环境文件示例 |
| `tests/` | 自动化测试 |

## 许可证

[MIT](LICENSE)
