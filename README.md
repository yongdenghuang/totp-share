# TOTP-Share

自托管的 TOTP 验证码管理与分享。把账号的两步验证密钥存在自己的服务器上，
给每个账号生成一条分享链接，拿到链接的人只能看到当前的 6 位验证码，看不到密钥。

适合几个人共用一个账号、又不想把密钥发给每个人的场景。

## 功能

- **账号列表**：直接显示每个账号当前的验证码和倒计时，点一下复制
- **分享链接** `/t/<token>`：只显示验证码；可一键更换，旧链接立即失效
- **一键复制账号信息**：可选保存账号本身的登录密码（加密），按模板一键复制「分组、账号、密码、验证码链接」直接发给对方；模板可自定义
- **改密码与密码生成器**：一键生成随机强密码（长度、数字、符号可调，在浏览器本地生成），保存时自动复制，并保留上一个密码备查
- **分享密码**：全站统一密码，或给某条链接单独设密码
- **分组与搜索**：自建分组，每个分组一个颜色，账号名称前显示彩色分组标签；按分组筛选、按名称搜索，拖拽排序
- **访问记录**：谁（IP、地区、设备）在什么时候看过哪个账号的验证码，含输错密码的尝试
- **重名提示**：添加或改名时发现同名账号会提醒
- **加密备份**：每天自动备份数据库和密钥文件，AES-256 加密，自动清理旧备份
- **合租账本**：按月记录每个账号的续费日期、续费卡、每人收费、成本和利润，和验证码账号共用登录与分组（见下）

## 合租账本

后台导航里的「合租账本」（`/admin/hezu`）是一个按月记账的页面：

- **账号表**：AI 合租（按分组）、Netflix、Spotify、iCloud，可以自己加表。每行是账号、续费日期、续费卡、每人收费（或单价 × 人数）、续费成本，利润自动算
- **和验证码账号打通**：账本里的账号和某个验证码账号同名时自动关联，行内直接显示当前验证码（点一下复制），菜单里可以一键复制分享信息、跳去编辑验证码账号；名字不同的可以手动关联
- **分组共用一套**：账本里的分组就是验证码账号的分组，颜色一致；在账本里可以新建，改名、换颜色、删除在「分组管理」页
- **每月归档**：一个月一份，归档后只读，账号和金额自动带到下个月
- **支付卡**：先建卡种（名称 + 国家），卡种下挂卡号；账号表里下拉选择，汇总每种卡、每个卡号当月要花多少
- **总览**：当月收费 / 成本 / 利润、7 天内待续费、各类利润、历月利润
- **VPS**：主机、IP、密码、用途、流量、续费日期、价格
- **导入导出**：导入原来的 Excel；按月或按年导出 Excel；JSON 备份的导出和恢复
- **历史版本**：每天第一次保存前自动留一份上一版，保留 60 天，可在「更多 → 恢复到某天的版本」里恢复

账本整份数据压缩后用 `FERNET_KEY` 加密，存在数据库 `hezu_state` 表的一行里，
所以卡号、VPS 密码、账号、金额在数据库和每天的备份里都是密文。当前验证码只在页面上显示，不写进账本。

### 从单机版（hezu-manager）迁移

在单机版里「更多 → 导出数据备份（JSON）」，然后在这里「合租账本 → 更多 → 从 JSON 备份恢复」选这个文件。
备份里的分组会按名称对应到已有分组，没有的自动新建；账号和验证码账号同名的会自动关联。

## 安全设计

- TOTP 密钥和账号密码用 Fernet 加密后入库，密钥（`FERNET_KEY`）只放在环境文件里
- 账号密码不会出现在列表页的 HTML 和分享页里，只在管理员点「复制信息」或打开编辑页时下发
- 管理员密码和分享密码用 Argon2 哈希
- 分享页只下发验证码，密钥从不离开服务器
- 全部表单有 CSRF 保护；登录和分享密码有按访客 IP 的限流
- 管理员 30 分钟无操作自动退出
- 部署在 Cloudflare 隧道后面时，从 `CF-Connecting-IP` 取访客真实 IP（只在请求来自本机回环地址时才信任这个头）
- 合租账本整份加密入库；页面上的卡号平时只显示后四位，VPS 密码平时显示为圆点，点一下才显示

> 后台登录后能看到所有账号的验证码、已保存的密码，以及合租账本里的卡号和 VPS 密码，请使用足够强的管理员密码，并且只通过 HTTPS 访问。

## 技术栈

Python 3.11+ · Flask · SQLite · gunicorn · Bootstrap 5（CDN）。没有前端构建步骤；合租账本页面是不依赖第三方库的原生脚本。

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
| `hezu.py` | 合租账本的接口和加密存储 |
| `hezu_xlsx.py` | 解析原来的合租 Excel |
| `static/hezu/` | 合租账本的页面脚本和样式 |
| `backup.py` | 加密备份脚本 |
| `templates/` | 页面模板 |
| `deploy/` | systemd 单元和环境文件示例 |
| `tests/` | 自动化测试 |

## 许可证

[MIT](LICENSE)
