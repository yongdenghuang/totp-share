"""测试夹具：每个测试用一份全新的临时数据库，结构是线上 v2 的旧结构，
这样每次跑测试都顺带验证了"旧库 → 新版本"的自动迁移。全部是假数据。"""
import importlib
import os
import sqlite3
import sys

import pyotp
import pytest
from argon2 import PasswordHasher
from cryptography.fernet import Fernet

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

# 线上数据库当前（v2.7）的真实结构
V2_SCHEMA = """
CREATE TABLE accounts (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    name              TEXT NOT NULL,
    secret_encrypted  BLOB NOT NULL,
    url_token         TEXT NOT NULL UNIQUE,
    url_token_hash    TEXT NOT NULL UNIQUE,
    created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
, share_count INTEGER, renewal_period INTEGER, renewal_date TEXT, renewal_amount TEXT,
  currency TEXT, recharge_channel TEXT, sort_order INTEGER);
CREATE TABLE admin (
    id             INTEGER PRIMARY KEY,
    username       TEXT NOT NULL UNIQUE,
    password_hash  TEXT NOT NULL,
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE settings (
    key    TEXT PRIMARY KEY,
    value  TEXT NOT NULL
);
CREATE INDEX idx_accounts_token_hash ON accounts(url_token_hash);
"""

ADMIN_USER = "tester"
ADMIN_PASSWORD = "test-only-password-123"
BASE_URL = "https://localhost"   # 会话 cookie 带 Secure 标记，测试也走 https


def seed_v2_db(path, fernet_key):
    """建一份旧结构的库，放两个带合租记账数据的假账号。返回 {名称: 密钥}。"""
    import hashlib
    f = Fernet(fernet_key)
    secrets_by_name = {}
    db = sqlite3.connect(path)
    db.executescript(V2_SCHEMA)
    db.execute("INSERT INTO admin(id, username, password_hash) VALUES (1,?,?)",
               (ADMIN_USER, PasswordHasher().hash(ADMIN_PASSWORD)))
    for i, name in enumerate(["plus-01", "pro20x-01"]):
        secret = pyotp.random_base32()
        token = f"tok{i}-abcdefgh"
        secrets_by_name[name] = secret
        db.execute(
            """INSERT INTO accounts(name, secret_encrypted, url_token, url_token_hash,
                                    share_count, renewal_period, renewal_date,
                                    renewal_amount, currency, recharge_channel, sort_order)
               VALUES (?,?,?,?, 3, 1, '2026-12-01', '148', 'CNY', '支付宝', ?)""",
            (name, f.encrypt(secret.encode()), token,
             hashlib.sha256(token.encode()).hexdigest(), i))
    db.commit()
    db.close()
    return secrets_by_name


@pytest.fixture
def ctx(tmp_path, monkeypatch):
    db_path = str(tmp_path / "totp.db")
    fernet_key = Fernet.generate_key()
    secrets_by_name = seed_v2_db(db_path, fernet_key)
    monkeypatch.setenv("SECRET_KEY", "test-secret-key")
    monkeypatch.setenv("FERNET_KEY", fernet_key.decode())
    monkeypatch.setenv("DATABASE_PATH", db_path)
    sys.modules.pop("app", None)
    mod = importlib.import_module("app")
    mod.app.config.update(TESTING=True, WTF_CSRF_ENABLED=False)
    mod.limiter.enabled = False

    class Ctx:
        app_module = mod
        app = mod.app
        path = db_path
        secrets = secrets_by_name

        def client(self):
            return mod.app.test_client()

        def admin(self):
            c = self.client()
            r = c.post("/admin/login", base_url=BASE_URL,
                       data={"username": ADMIN_USER, "password": ADMIN_PASSWORD})
            assert r.status_code == 302
            return c

        def sql(self, query, args=()):
            db = sqlite3.connect(db_path)
            db.row_factory = sqlite3.Row
            try:
                rows = db.execute(query, args).fetchall()
                db.commit()
                return rows
            finally:
                db.close()

    yield Ctx()
    sys.modules.pop("app", None)
