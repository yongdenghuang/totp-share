"""数据库结构迁移（幂等，可重复执行）。

应用启动时会自动调用 ensure_schema()；也可以手动执行：
    DATABASE_PATH=/opt/totp-share/data/totp.db python migrate.py
只做"加表、加列、加索引"，不删除也不改写任何已有数据。
v2 时期的合租记账列（share_count、renewal_* 等）v3 不再使用，但原样保留在库里，
需要回滚到 v2 时数据还在。
"""
import os
import sqlite3

BASE_SCHEMA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "schema.sql")

# accounts 表在基础结构之外需要的列：(列名, 类型)。缺哪列补哪列。
ACCOUNT_COLUMNS = [
    ("sort_order", "INTEGER"),         # 拖拽排序（v2 线上是手工 ALTER 加的）
    ("group_name", "TEXT"),            # 分组；NULL = 未分组
    ("share_password_hash", "TEXT"),   # 此链接的单独密码；NULL = 跟随统一设置
]

GROUPS_SQL = """
CREATE TABLE IF NOT EXISTS account_groups (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL UNIQUE,
    created_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
"""

ACCESS_LOGS_SQL = """
CREATE TABLE IF NOT EXISTS access_logs (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id    INTEGER,
    account_name  TEXT NOT NULL,
    event         TEXT NOT NULL,
    ip            TEXT,
    country       TEXT,
    user_agent    TEXT,
    created_at    TEXT NOT NULL,
    last_seen_at  TEXT NOT NULL,
    hits          INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX IF NOT EXISTS idx_access_logs_account ON access_logs(account_id, last_seen_at);
CREATE INDEX IF NOT EXISTS idx_access_logs_seen ON access_logs(last_seen_at);
"""


def ensure_schema(db):
    """把数据库补齐到当前版本。返回本次实际执行的变更列表。"""
    changes = []
    tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}

    if "accounts" not in tables:
        with open(BASE_SCHEMA, encoding="utf-8") as f:
            db.executescript(f.read())
        changes.append("created base tables")

    existing = {r[1] for r in db.execute("PRAGMA table_info(accounts)")}
    for col, typ in ACCOUNT_COLUMNS:
        if col not in existing:
            db.execute(f"ALTER TABLE accounts ADD COLUMN {col} {typ}")
            changes.append(f"accounts.{col}")

    if "access_logs" not in tables:
        changes.append("access_logs")
    db.executescript(ACCESS_LOGS_SQL)

    if "account_groups" not in tables:
        changes.append("account_groups")
    db.executescript(GROUPS_SQL)
    # 账号上已经写了、但分组表里还没有的分组名，补登记进去
    db.execute("""INSERT OR IGNORE INTO account_groups(name)
                  SELECT DISTINCT group_name FROM accounts
                  WHERE group_name IS NOT NULL AND group_name <> ''""")

    db.commit()
    return changes


if __name__ == "__main__":
    path = os.environ["DATABASE_PATH"]
    conn = sqlite3.connect(path)
    try:
        done = ensure_schema(conn)
    finally:
        conn.close()
    print("已是最新结构，无需变更" if not done else "已执行变更: " + ", ".join(done))
