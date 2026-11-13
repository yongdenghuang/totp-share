"""本地开发用：用假数据起一个服务，方便在浏览器里看效果。不要在线上运行。

    .venv/bin/python dev/run.py        # http://127.0.0.1:8767

首次运行会在 dev/ 下生成 .env.dev（随机密钥 + 本地管理员密码，已被 .gitignore 忽略）
和 dev.db（线上 v2 的旧表结构 + 假账号，启动时由应用自动迁移到新结构）。
删掉这两个文件即可重置。
"""
import hashlib
import os
import secrets
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ENV_FILE = os.path.join(HERE, ".env.dev")
DB_FILE = os.path.join(HERE, "dev.db")
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, "tests"))


def load_env():
    if not os.path.exists(ENV_FILE):
        from cryptography.fernet import Fernet
        with open(ENV_FILE, "w", encoding="utf-8") as f:
            f.write("# 仅本地开发使用的随机值，与线上无关\n")
            f.write(f"SECRET_KEY={secrets.token_hex(32)}\n")
            f.write(f"FERNET_KEY={Fernet.generate_key().decode()}\n")
            f.write("DEV_ADMIN_USER=admin\n")
            f.write(f"DEV_ADMIN_PASSWORD={secrets.token_urlsafe(12)}\n")
        os.chmod(ENV_FILE, 0o600)
    with open(ENV_FILE, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                k, v = line.split("=", 1)
                os.environ[k] = v
    os.environ["DATABASE_PATH"] = DB_FILE


def seed():
    if os.path.exists(DB_FILE):
        return
    import pyotp
    from argon2 import PasswordHasher
    from cryptography.fernet import Fernet
    from conftest import V2_SCHEMA

    fernet = Fernet(os.environ["FERNET_KEY"].encode())
    db = sqlite3.connect(DB_FILE)
    db.executescript(V2_SCHEMA)
    db.execute("INSERT INTO admin(id, username, password_hash) VALUES (1,?,?)",
               (os.environ["DEV_ADMIN_USER"], PasswordHasher().hash(os.environ["DEV_ADMIN_PASSWORD"])))
    names = ["plus-01", "plus-02", "plus-03", "pro20x-01", "pro20x-02",
             "plus代充-01", "plus代充-02", "plus-02", "team-备用"]   # 故意放一个重名
    for i, name in enumerate(names):
        token = secrets.token_urlsafe(9)
        db.execute(
            """INSERT INTO accounts(name, secret_encrypted, url_token, url_token_hash,
                                    share_count, renewal_amount, currency, sort_order)
               VALUES (?,?,?,?, 3, '148', 'CNY', ?)""",
            (name, fernet.encrypt(pyotp.random_base32().encode()), token,
             hashlib.sha256(token.encode()).hexdigest(), i))
    db.commit()
    db.close()


if __name__ == "__main__":
    load_env()
    seed()
    from app import app
    app.config["TEMPLATES_AUTO_RELOAD"] = True   # 改模板后刷新页面即可看到
    app.run(host="127.0.0.1", port=8767, debug=False)
