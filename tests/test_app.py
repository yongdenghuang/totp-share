import time

import pyotp

from conftest import BASE_URL

VISITOR = {"CF-Connecting-IP": "203.0.113.7", "CF-IPCountry": "CN",
           "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0) Safari/604.1"}


def get(c, path, **kw):
    return c.get(path, base_url=BASE_URL, **kw)


def post(c, path, **kw):
    return c.post(path, base_url=BASE_URL, **kw)


# ---------- 迁移 ----------
def test_migration_adds_columns_and_keeps_old_data(ctx):
    cols = {r["name"] for r in ctx.sql("PRAGMA table_info(accounts)")}
    assert {"group_name", "share_password_hash", "sort_order"} <= cols
    assert ctx.sql("SELECT name FROM sqlite_master WHERE name='access_logs'")
    # 旧的合租记账数据原样保留，方便回滚
    row = ctx.sql("SELECT share_count, renewal_amount, recharge_channel FROM accounts")[0]
    assert (row["share_count"], row["renewal_amount"], row["recharge_channel"]) == (3, "148", "支付宝")


def test_migration_is_idempotent(ctx):
    import sqlite3
    from migrate import ensure_schema
    db = sqlite3.connect(ctx.path)
    assert ensure_schema(db) == []
    db.close()


# ---------- 登录与列表 ----------
def test_admin_pages_require_login(ctx):
    c = ctx.client()
    for path in ("/admin/dashboard", "/admin/logs", "/admin/settings", "/admin/accounts/new"):
        r = get(c, path)
        assert r.status_code == 302 and "/admin/login" in r.headers["Location"]


def test_dashboard_has_no_rental_bookkeeping(ctx):
    html = get(ctx.admin(), "/admin/dashboard").get_data(as_text=True)
    assert "plus-01" in html and "pro20x-01" in html
    for gone in ("租金", "毛利", "合租", "续费", "充值渠道"):
        assert gone not in html


# ---------- 列表页实时验证码 ----------
def test_admin_codes_match_totp(ctx):
    r = get(ctx.admin(), "/admin/codes")
    assert r.status_code == 200 and "no-store" in r.headers["Cache-Control"]
    data = r.get_json()
    ids = {row["name"]: str(row["id"]) for row in ctx.sql("SELECT id, name FROM accounts")}
    for name, secret in ctx.secrets.items():
        totp = pyotp.TOTP(secret)
        assert data["codes"][ids[name]] in (totp.now(), totp.at(time.time() - 30))
    assert 1 <= data["remaining"] <= 30 and data["period"] == 30


def test_admin_codes_rejects_anonymous_with_json(ctx):
    r = get(ctx.client(), "/admin/codes")
    assert r.status_code == 401 and r.get_json()["ok"] is False


def test_code_polling_does_not_keep_session_alive(ctx):
    c = ctx.admin()
    with c.session_transaction(base_url=BASE_URL) as s:
        s["last_active"] = int(time.time()) - 29 * 60
    assert get(c, "/admin/codes").status_code == 200
    with c.session_transaction(base_url=BASE_URL) as s:
        assert time.time() - s["last_active"] > 28 * 60   # 轮询没有刷新活跃时间
        s["last_active"] = int(time.time()) - 31 * 60
    assert get(c, "/admin/codes").status_code == 401
    assert get(c, "/admin/dashboard").status_code == 302


# ---------- 一键换链接 ----------
def test_regen_replaces_link(ctx):
    c = ctx.admin()
    aid = ctx.sql("SELECT id FROM accounts WHERE name='plus-01'")[0]["id"]
    old = ctx.sql("SELECT url_token FROM accounts WHERE id=?", (aid,))[0]["url_token"]
    r = post(c, f"/admin/accounts/{aid}/regen", json={})
    body = r.get_json()
    assert r.status_code == 200 and body["ok"] and body["url_token"] != old
    assert body["url"] == f"{BASE_URL}/t/{body['url_token']}"
    anon = ctx.client()
    assert get(anon, f"/t/{old}").status_code == 404
    assert get(anon, f"/t/{old}/code").status_code == 404
    assert get(anon, f"/t/{body['url_token']}").status_code == 200


def test_regen_requires_login_and_existing_account(ctx):
    assert post(ctx.client(), "/admin/accounts/1/regen", json={}).status_code == 401
    assert post(ctx.admin(), "/admin/accounts/9999/regen", json={}).status_code == 404


# ---------- 重名提示 ----------
def test_duplicate_name_needs_confirmation(ctx):
    c = ctx.admin()
    form = {"name": "  PLUS-01 ", "secret": pyotp.random_base32()}
    r = post(c, "/admin/accounts/new", data=form)
    assert r.status_code == 200 and "已存在同名账号" in r.get_data(as_text=True)
    assert len(ctx.sql("SELECT id FROM accounts")) == 2
    r = post(c, "/admin/accounts/new", data={**form, "confirm_duplicate": "1"})
    assert r.status_code == 302
    assert len(ctx.sql("SELECT id FROM accounts")) == 3
    assert get(c, "/admin/dashboard").get_data(as_text=True).count(">重名<") == 2


def test_edit_only_warns_when_renaming_into_a_duplicate(ctx):
    c = ctx.admin()
    rows = {r["name"]: r["id"] for r in ctx.sql("SELECT id, name FROM accounts")}
    r = post(c, f"/admin/accounts/{rows['plus-01']}/edit", data={"name": "plus-01", "group_name": "plus"})
    assert r.status_code == 302
    r = post(c, f"/admin/accounts/{rows['plus-01']}/edit", data={"name": "pro20x-01"})
    assert r.status_code == 200 and "已存在同名账号" in r.get_data(as_text=True)
    assert ctx.sql("SELECT name FROM accounts WHERE id=?", (rows["plus-01"],))[0]["name"] == "plus-01"


# ---------- 分组 ----------
def test_group_inline_edit_and_field_whitelist(ctx):
    c = ctx.admin()
    r = post(c, "/admin/accounts/1/field", json={"field": "group_name", "value": "  plus  代充 "})
    assert r.get_json() == {"ok": True, "display": "plus 代充", "raw_value": "plus 代充"}
    r = post(c, "/admin/accounts/1/field", json={"field": "group_name", "value": ""})
    assert r.get_json()["raw_value"] == ""
    assert ctx.sql("SELECT group_name FROM accounts WHERE id=1")[0]["group_name"] is None
    for field in ("renewal_amount", "secret_encrypted", "url_token", "name"):
        assert post(c, "/admin/accounts/1/field", json={"field": field, "value": "x"}).status_code == 400


# ---------- 每条链接单独密码 ----------
def test_per_link_password(ctx):
    admin = ctx.admin()
    rows = {r["name"]: (r["id"], r["url_token"]) for r in ctx.sql("SELECT id, name, url_token FROM accounts")}
    aid, token = rows["plus-01"]
    _, other_token = rows["pro20x-01"]
    assert post(admin, f"/admin/accounts/{aid}/edit",
                data={"name": "plus-01", "link_password": "abc"}).status_code == 200   # 太短
    assert post(admin, f"/admin/accounts/{aid}/edit",
                data={"name": "plus-01", "link_password": "link-pass-1"}).status_code == 302

    v = ctx.client()
    assert "需要密码" in get(v, f"/t/{token}").get_data(as_text=True)
    assert get(v, f"/t/{token}/code").status_code == 403
    assert get(v, f"/t/{other_token}/code").status_code == 200       # 没设密码的链接不受影响

    assert "密码错误" in post(v, f"/t/{token}", data={"password": "nope"}, headers=VISITOR).get_data(as_text=True)
    assert post(v, f"/t/{token}", data={"password": "link-pass-1"}).status_code == 302
    assert get(v, f"/t/{token}/code").status_code == 200

    # 改密码后，之前解锁过的会话失效
    post(admin, f"/admin/accounts/{aid}/edit", data={"name": "plus-01", "link_password": "link-pass-2"})
    assert get(v, f"/t/{token}/code").status_code == 403

    # 清除单独密码 → 回到跟随统一设置（当前未开启）
    post(admin, f"/admin/accounts/{aid}/edit", data={"name": "plus-01", "clear_link_password": "1"})
    assert get(v, f"/t/{token}/code").status_code == 200


def test_global_password_applies_only_to_links_without_their_own(ctx):
    admin = ctx.admin()
    rows = {r["name"]: (r["id"], r["url_token"]) for r in ctx.sql("SELECT id, name, url_token FROM accounts")}
    aid, own_token = rows["plus-01"]
    _, plain_token = rows["pro20x-01"]
    post(admin, f"/admin/accounts/{aid}/edit", data={"name": "plus-01", "link_password": "own-pass"})
    post(admin, "/admin/settings", data={"action": "toggle", "share_password_enabled": "on",
                                         "share_password": "global-pass"})
    v = ctx.client()
    assert get(v, f"/t/{plain_token}/code").status_code == 403
    assert post(v, f"/t/{plain_token}", data={"password": "global-pass"}).status_code == 302
    assert get(v, f"/t/{plain_token}/code").status_code == 200
    # 统一密码打不开设了单独密码的链接
    assert "密码错误" in post(v, f"/t/{own_token}", data={"password": "global-pass"}).get_data(as_text=True)
    assert post(v, f"/t/{own_token}", data={"password": "own-pass"}).status_code == 302


def test_password_guessing_is_rate_limited(ctx):
    ctx.app_module.limiter.enabled = True
    admin = ctx.admin()
    aid, token = [(r["id"], r["url_token"]) for r in ctx.sql("SELECT id, url_token FROM accounts")][0]
    post(admin, f"/admin/accounts/{aid}/edit", data={"name": "plus-01", "link_password": "right-pass"})
    v = ctx.client()
    codes = [post(v, f"/t/{token}", data={"password": "guess"}, headers=VISITOR).status_code
             for _ in range(12)]
    assert codes[:10] == [200] * 10 and codes[10:] == [429, 429]


# ---------- 访问记录 ----------
def test_access_log_merges_polling_and_separates_visitors(ctx):
    token = ctx.sql("SELECT url_token FROM accounts WHERE name='plus-01'")[0]["url_token"]
    v = ctx.client()
    get(v, f"/t/{token}", headers=VISITOR)
    for _ in range(3):
        get(v, f"/t/{token}/code", headers=VISITOR)
    logs = ctx.sql("SELECT * FROM access_logs")
    assert len(logs) == 1
    assert (logs[0]["ip"], logs[0]["country"], logs[0]["event"], logs[0]["hits"]) == ("203.0.113.7", "CN", "view", 4)
    assert logs[0]["account_name"] == "plus-01"

    get(v, f"/t/{token}/code", headers={**VISITOR, "CF-Connecting-IP": "198.51.100.9"})
    assert len(ctx.sql("SELECT id FROM access_logs")) == 2

    # 超过合并窗口再来看 → 新的一条
    ctx.sql("UPDATE access_logs SET last_seen_at='2020-01-01 00:00:00', created_at='2020-01-01 00:00:00' "
            "WHERE ip='203.0.113.7'")
    get(v, f"/t/{token}/code", headers=VISITOR)
    assert len(ctx.sql("SELECT id FROM access_logs WHERE ip='203.0.113.7'")) == 2


def test_admin_preview_is_not_logged(ctx):
    token = ctx.sql("SELECT url_token FROM accounts")[0]["url_token"]
    admin = ctx.admin()
    get(admin, f"/t/{token}", headers=VISITOR)
    get(admin, f"/t/{token}/code", headers=VISITOR)
    assert ctx.sql("SELECT id FROM access_logs") == []


def test_forwarded_ip_only_trusted_from_loopback(ctx):
    token = ctx.sql("SELECT url_token FROM accounts")[0]["url_token"]
    get(ctx.client(), f"/t/{token}/code", headers=VISITOR,
        environ_base={"REMOTE_ADDR": "192.0.2.50"})   # 绕过隧道直连端口并伪造请求头
    assert ctx.sql("SELECT ip FROM access_logs")[0]["ip"] == "192.0.2.50"


def test_wrong_password_is_logged_and_logs_page_renders(ctx):
    admin = ctx.admin()
    aid, token = [(r["id"], r["url_token"]) for r in ctx.sql("SELECT id, url_token FROM accounts WHERE name='plus-01'")][0]
    post(admin, f"/admin/accounts/{aid}/edit", data={"name": "plus-01", "link_password": "right-pass"})
    v = ctx.client()
    post(v, f"/t/{token}", data={"password": "bad"}, headers=VISITOR)
    post(v, f"/t/{token}", data={"password": "right-pass"}, headers=VISITOR)
    get(v, f"/t/{token}", headers=VISITOR)
    events = sorted(r["event"] for r in ctx.sql("SELECT event FROM access_logs"))
    assert events == ["pw_fail", "view"]

    html = get(admin, "/admin/logs").get_data(as_text=True)
    assert "203.0.113.7" in html and "密码错误" in html and "iPhone · Safari" in html
    assert "plus-01" in get(admin, f"/admin/logs?account={aid}").get_data(as_text=True)
    assert "还没有访问记录" in get(admin, "/admin/logs?account=9999").get_data(as_text=True)

    # 账号删除后记录仍在（存了名称快照）
    post(admin, f"/admin/accounts/{aid}/delete")
    assert "plus-01" in get(admin, "/admin/logs").get_data(as_text=True)


def test_new_account_with_group_and_password(ctx):
    c = ctx.admin()
    r = post(c, "/admin/accounts/new", data={"name": "plus代充-01", "secret": pyotp.random_base32(),
                                             "group_name": "plus代充", "link_password": "secret-9"})
    assert r.status_code == 302
    row = ctx.sql("SELECT group_name, share_password_hash, url_token FROM accounts WHERE name='plus代充-01'")[0]
    assert row["group_name"] == "plus代充" and row["share_password_hash"].startswith("$argon2")
    assert get(ctx.client(), f"/t/{row['url_token']}/code").status_code == 403
