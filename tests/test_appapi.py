"""iOS App 用的接口：会话、JSON 登录、验证码账号列表、删除。全部是假数据。"""
from conftest import ADMIN_PASSWORD, ADMIN_USER, BASE_URL

API = "/api/app"


def call(c, method, path, **kw):
    return getattr(c, method)(path, base_url=BASE_URL, **kw)


def test_session_and_json_login(ctx):
    c = ctx.client()
    d = call(c, "get", f"{API}/session").get_json()
    assert d["loggedIn"] is False and d["csrf"]
    assert call(c, "get", f"{API}/accounts").status_code == 401
    bad = call(c, "post", f"{API}/login", json={"username": ADMIN_USER, "password": "wrong"})
    assert bad.status_code == 401 and not bad.get_json()["ok"]
    r = call(c, "post", f"{API}/login", json={"username": ADMIN_USER, "password": ADMIN_PASSWORD, "remember": True})
    assert r.get_json()["ok"] and r.get_json()["user"] == ADMIN_USER
    assert "Expires=" in r.headers.get("Set-Cookie", "")          # 记住这台设备：带过期时间的 cookie
    d = call(c, "get", f"{API}/session").get_json()
    assert d["loggedIn"] and d["remember"]
    assert call(c, "post", f"{API}/logout", json={}).get_json()["ok"]
    assert call(c, "get", f"{API}/session").get_json()["loggedIn"] is False


def test_accounts_list_has_no_secrets_and_delete(ctx):
    c = ctx.admin()
    d = call(c, "get", f"{API}/accounts").get_json()
    names = {a["name"] for a in d["accounts"]}
    assert names == {"plus-01", "pro20x-01"}
    a = d["accounts"][0]
    assert a["shareUrl"].startswith("https://localhost/t/") and "secret" not in str(a).lower()
    for s in ctx.secrets.values():
        assert s not in call(c, "get", f"{API}/accounts").get_data(as_text=True)
    assert call(c, "delete", f"{API}/accounts/{a['id']}").get_json()["ok"]
    assert len(call(c, "get", f"{API}/accounts").get_json()["accounts"]) == 1
    assert call(c, "delete", f"{API}/accounts/{a['id']}").status_code == 404
