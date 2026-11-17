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


def test_settings_share_password_and_template(ctx):
    c = ctx.admin()
    d = call(c, "get", f"{API}/settings").get_json()
    assert d["shareTemplateDefault"] and not d["sharePasswordEnabled"]
    assert call(c, "post", f"{API}/settings/share-password", json={"enabled": True}).status_code == 400   # 首次开启要设密码
    assert call(c, "post", f"{API}/settings/share-password", json={"enabled": True, "password": "abc"}).status_code == 400
    assert call(c, "post", f"{API}/settings/share-password", json={"enabled": True, "password": "abcd"}).get_json()["ok"]
    assert call(c, "get", f"{API}/settings").get_json()["sharePasswordEnabled"]
    assert call(c, "post", f"{API}/settings/share-template", json={"template": "账号：{account}"}).get_json()["ok"]
    assert call(c, "get", f"{API}/settings").get_json()["shareTemplate"] == "账号：{account}"


def test_admin_password_change_logs_out_others(ctx):
    c, other = ctx.admin(), ctx.admin()
    assert call(c, "post", f"{API}/settings/admin-password", json={"old": "wrong", "new": "x" * 12}).status_code == 400
    assert call(c, "post", f"{API}/settings/admin-password", json={"old": ADMIN_PASSWORD, "new": "short"}).status_code == 400
    r = call(c, "post", f"{API}/settings/admin-password", json={"old": ADMIN_PASSWORD, "new": "new-test-password-456"})
    assert r.get_json()["ok"]
    assert call(c, "get", f"{API}/session").get_json()["loggedIn"]
    assert call(other, "get", f"{API}/session").get_json()["loggedIn"] is False


def test_groups_rename_color_delete(ctx):
    c = ctx.admin()
    assert call(c, "post", f"{API}/groups", json={"name": "测试组"}).get_json()["ok"]
    assert call(c, "post", f"{API}/groups", json={"name": "测试组"}).status_code == 400
    r = call(c, "post", f"{API}/groups/update", json={"old": "测试组", "name": "新名字", "color": "#16a34a"}).get_json()
    g = next(x for x in r["groups"] if x["name"] == "新名字")
    assert g["color"] == "#16a34a" and g["count"] == 0
    assert call(c, "post", f"{API}/groups/update", json={"old": "新名字", "name": "x", "color": "red"}).status_code == 400
    assert call(c, "post", f"{API}/groups/delete", json={"name": "新名字"}).get_json()["ok"]
    assert not any(x["name"] == "新名字" for x in call(c, "get", f"{API}/groups").get_json()["groups"])


def test_logs_api(ctx):
    c = ctx.admin()
    d = call(c, "get", f"{API}/logs").get_json()
    assert d["ok"] and d["page"] == 1 and isinstance(d["logs"], list) and len(d["accounts"]) == 2


def test_excel_export(ctx):
    import io, zipfile, re
    c = ctx.admin()
    state = {"sheets": [{"id": "ai", "name": "AI 合租", "mode": "members", "grouped": True},
                        {"id": "nf", "name": "Netflix", "mode": "unit"}],
             "months": {"2026-10": {"archived": True, "rows": {"ai": [], "nf": []}},
                        "2026-11": {"archived": False, "rows": {
                            "ai": [{"id": "r1", "group": "", "account": "plus-01", "renew": "2026-11-15", "issuerId": "i1", "cardId": "c1",
                                    "members": [{"name": "小王", "amount": 35, "paid": True}, {"name": "", "amount": 40, "paid": False}], "cost": 50, "note": ""}],
                            "nf": [{"id": "r2", "account": "nf-1", "unitPrice": 20, "count": 4, "cost": 60}]}}},
             "issuers": [{"id": "i1", "name": "Wise", "country": "美国"}],
             "cards": [{"id": "c1", "issuerId": "i1", "number": "4000123412341234", "note": "", "expiry": "12/28", "cvc": "123"}],
             "vps": [{"id": "v1", "host": "demo", "renew": "2026-12-01", "tags": [{"name": "xui", "url": ""}]}]}
    assert call(c, "put", "/admin/hezu/api/state", json={"rev": 0, "state": state}).status_code == 200
    r = call(c, "get", "/admin/hezu/api/export?month=2026-11")
    assert r.status_code == 200 and "attachment" in r.headers["Content-Disposition"]
    z = zipfile.ZipFile(io.BytesIO(r.data))
    wb = z.read("xl/workbook.xml").decode()
    assert re.findall(r'name="([^"]+)"', wb) == ["利润汇总", "AI 合租", "Netflix", "按卡统计", "支付卡", "VPS"]
    text = "".join(z.read(n).decode() for n in z.namelist() if n.startswith("xl/worksheets/"))
    for want in ("plus-01", "小王35 + 40", "4000123412341234", "12/28", "<v>75</v>", "<v>25</v>", "<v>80</v>", "<v>20</v>", "全部合计"):
        assert want in text, want
    y = zipfile.ZipFile(io.BytesIO(call(c, "get", "/admin/hezu/api/export?year=2026").data))
    assert "年度汇总" in y.read("xl/workbook.xml").decode()
    assert call(c, "get", "/admin/hezu/api/export?year=1999").status_code == 404
