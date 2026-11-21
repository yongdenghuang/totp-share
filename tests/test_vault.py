"""密码本和备忘录：登录保护、加密入库、列表不带密码、版本冲突、最近删除。全部是假数据。"""
from conftest import BASE_URL

API = "/admin/vault/api"
PW = "fake-pw-Zx81!q"
SECRET_ANSWER = "fake-answer-hugou"


def call(c, method, path, **kw):
    return getattr(c, method)(path, base_url=BASE_URL, **kw)


def new_item(c, **over):
    data = {"type": "apple", "title": "土区", "account": "demo05@example.com", "password": PW,
            "phone": "13800000000", "note": "已购 iPhone",
            "extras": [{"label": "生日", "value": "1999/9/9"},
                       {"label": "密保 1", "value": SECRET_ANSWER, "secret": True}]}
    data.update(over)
    r = call(c, "post", f"{API}/items", json={"data": data})
    assert r.status_code == 200, r.get_json()
    return r.get_json()["entry"]


def test_pages_and_api_require_login(ctx):
    c = ctx.client()
    for page in ("/admin/vault", "/admin/notes"):
        r = call(c, "get", page)
        assert r.status_code == 302 and "/admin/login" in r.headers["Location"]
    assert call(c, "get", f"{API}/items").status_code == 401
    assert call(c, "get", f"{API}/notes").status_code == 401
    assert call(c, "post", f"{API}/items", json={"data": {"account": "x"}}).status_code == 401
    assert call(c, "post", f"{API}/items/1/reveal", json={}).status_code == 401
    assert ctx.sql("SELECT COUNT(*) AS n FROM vault_entries")[0]["n"] == 0


def test_pages_render_with_shared_sidebar(ctx):
    c = ctx.admin()
    for page, active in (("/admin/vault", "密码本"), ("/admin/notes", "备忘录")):
        html = call(c, "get", page).get_data(as_text=True)
        assert 'class="side"' in html and "hezu/vault.js" in html and 'data-csrf="' in html
        assert html.split('class="nav on"', 1)[1].split("</a>", 1)[0].count(active) == 1
    dash = call(c, "get", "/admin/dashboard").get_data(as_text=True)
    assert 'href="/admin/vault"' in dash and 'href="/admin/notes"' in dash


def test_item_roundtrip_hides_secrets_in_list(ctx):
    c = ctx.admin()
    e = new_item(c)
    assert "password" not in e and e["hasPassword"] is True
    d = call(c, "get", f"{API}/items").get_json()
    assert [t["id"] for t in d["types"]][:2] == ["apple", "google"]
    item = d["entries"][0]
    assert item["account"] == "demo05@example.com" and item["hasPassword"] and "password" not in item
    assert item["extras"][0] == {"label": "生日", "value": "1999/9/9", "secret": False}
    assert item["extras"][1]["value"] == "" and item["extras"][1]["hasValue"]
    body = call(c, "get", f"{API}/items").get_data(as_text=True)
    assert PW not in body and SECRET_ANSWER not in body
    full = call(c, "post", f"{API}/items/{e['id']}/reveal", json={}).get_json()["entry"]
    assert full["password"] == PW and full["extras"][1]["value"] == SECRET_ANSWER


def test_entries_are_encrypted_at_rest(ctx):
    c = ctx.admin()
    new_item(c)
    call(c, "post", f"{API}/notes", json={"data": {"text": "备忘：fake-note-content-123"}})
    for r in ctx.sql("SELECT data_encrypted FROM vault_entries"):
        blob = bytes(r["data_encrypted"])
        for plain in (PW, SECRET_ANSWER, "demo05@example.com", "fake-note-content-123"):
            assert plain.encode() not in blob


def test_item_without_password_and_empty_item(ctx):
    c = ctx.admin()
    e = new_item(c, type="phone", title="移动主卡", account="13900000000", password="", extras=[])
    assert e["hasPassword"] is False
    r = call(c, "post", f"{API}/items", json={"data": {"type": "apple", "site": "https://x"}})
    assert r.status_code == 400


def test_update_conflict_and_force(ctx):
    c = ctx.admin()
    e = new_item(c)
    r = call(c, "put", f"{API}/items/{e['id']}", json={"rev": e["rev"], "data": {"type": "apple", "account": "a@example.com", "password": "p2"}})
    assert r.status_code == 200 and r.get_json()["entry"]["rev"] == e["rev"] + 1
    stale = call(c, "put", f"{API}/items/{e['id']}", json={"rev": e["rev"], "data": {"account": "b@example.com"}})
    assert stale.status_code == 409 and stale.get_json()["entry"]["account"] == "a@example.com"
    forced = call(c, "put", f"{API}/items/{e['id']}", json={"rev": e["rev"], "force": True, "data": {"account": "b@example.com"}})
    assert forced.status_code == 200
    # 没带密码字段时沿用原来的密码
    full = call(c, "post", f"{API}/items/{e['id']}/reveal", json={}).get_json()["entry"]
    assert full["account"] == "b@example.com" and full["password"] == "p2"


def test_trash_restore_and_purge(ctx):
    c = ctx.admin()
    e = new_item(c)
    assert call(c, "delete", f"{API}/items/{e['id']}?purge=1").status_code == 400   # 不在回收站里不能直接彻底删
    assert call(c, "delete", f"{API}/items/{e['id']}").get_json()["ok"]
    d = call(c, "get", f"{API}/items").get_json()
    assert d["entries"] == [] and d["trashCount"] == 1
    assert len(call(c, "get", f"{API}/items?trash=1").get_json()["entries"]) == 1
    assert call(c, "post", f"{API}/items/{e['id']}/restore", json={}).get_json()["ok"]
    assert len(call(c, "get", f"{API}/items").get_json()["entries"]) == 1
    call(c, "delete", f"{API}/items/{e['id']}")
    assert call(c, "delete", f"{API}/items/{e['id']}?purge=1").get_json()["ok"]
    assert ctx.sql("SELECT COUNT(*) AS n FROM vault_entries")[0]["n"] == 0


def test_old_trash_is_purged(ctx):
    c = ctx.admin()
    e = new_item(c)
    call(c, "delete", f"{API}/items/{e['id']}")
    ctx.sql("UPDATE vault_entries SET deleted_at='2000-01-01 00:00:00'")
    call(c, "get", f"{API}/items")
    assert ctx.sql("SELECT COUNT(*) AS n FROM vault_entries")[0]["n"] == 0


def test_notes_roundtrip_and_counts(ctx):
    c = ctx.admin()
    n = call(c, "post", f"{API}/notes", json={"data": {"text": "Apple 账号\n土区：…", "pinned": True}}).get_json()["entry"]
    assert n["text"].startswith("Apple 账号") and n["pinned"]
    r = call(c, "put", f"{API}/notes/{n['id']}", json={"rev": n["rev"], "data": {"text": "改过了"}})
    assert r.get_json()["entry"]["text"] == "改过了"
    assert call(c, "put", f"{API}/notes/{n['id']}", json={"rev": n["rev"], "data": {"text": "旧窗口"}}).status_code == 409
    new_item(c)
    side = call(c, "get", "/admin/notes").get_data(as_text=True).split('class="side"', 1)[1].split("</nav>", 1)[0]
    assert '密码本</span><span class="count">1<' in side and '备忘录</span><span class="count">1<' in side
    assert call(c, "get", f"{API}/hezu").status_code == 404


def test_types_save_with_revision(ctx):
    c = ctx.admin()
    types = call(c, "get", f"{API}/items").get_json()["types"]
    types.append({"id": "tg", "name": "Telegram", "color": "#0891b2", "site": "https://telegram.org"})
    r = call(c, "put", f"{API}/types", json={"rev": 0, "types": types})
    assert r.status_code == 200 and r.get_json()["typesRev"] == 1
    assert call(c, "put", f"{API}/types", json={"rev": 0, "types": types}).status_code == 409
    assert call(c, "put", f"{API}/types", json={"rev": 1, "types": []}).status_code == 400
    bad = [{"id": "x", "name": "X", "color": "red;background:url(x)"}]
    assert call(c, "put", f"{API}/types", json={"rev": 1, "types": bad}).get_json()["types"][0]["color"] == "#6c757d"
    assert call(c, "get", f"{API}/items").get_json()["types"][0]["name"] == "X"


def test_patch_changes_one_field_and_keeps_secrets(ctx):
    c = ctx.admin()
    e = new_item(c)
    r = call(c, "put", f"{API}/items/{e['id']}", json={"rev": 999, "patch": True, "force": True, "data": {"title": "新名字"}})
    assert r.status_code == 200
    full = call(c, "post", f"{API}/items/{e['id']}/reveal", json={}).get_json()["entry"]
    assert full["title"] == "新名字" and full["password"] == PW and full["extras"][1]["value"] == SECRET_ANSWER
    call(c, "put", f"{API}/items/{e['id']}", json={"rev": full["rev"], "patch": True, "data": {"password": "new-pw"}})
    full = call(c, "post", f"{API}/items/{e['id']}/reveal", json={}).get_json()["entry"]
    assert full["password"] == "new-pw" and full["account"] == "demo05@example.com"


def test_sidebar_order_is_saved_and_shared(ctx):
    c = ctx.admin()
    api = "/admin/hezu/api"

    def side(path):
        html = call(c, "get", path).get_data(as_text=True)
        return html.split('class="side"', 1)[1].split("</nav>", 1)[0]

    r = call(c, "post", f"{api}/nav-order", json={"sections": ["backup", "totp"], "items": {"backup": ["notes"], "totp": ["settings", "bogus"]}})
    order = r.get_json()["navOrder"]
    assert order["sections"] == ["backup", "totp", "accounts", "backend"]
    assert order["items"]["backup"] == ["notes", "vault"] and order["items"]["totp"] == ["settings", "dashboard", "logs"]
    s = side("/admin/vault")
    assert s.index('data-sec="backup"') < s.index('data-sec="totp"') < s.index('data-sec="accounts"')
    assert s.index('data-item="notes"') < s.index('data-item="vault"')
    assert call(c, "get", f"{api}/context").get_json()["navOrder"] == order      # 账本页也按这个顺序画
    # 拖动「账号」里的表：直接改账本里表的顺序
    call(c, "put", f"{api}/state", json={"rev": 0, "state": {"sheets": [{"id": "a", "name": "A"}, {"id": "b", "name": "B"}, {"id": "c", "name": "C"}], "months": {}, "vps": []}})
    assert call(c, "post", f"{api}/sheet-order", json={"order": ["c", "a"]}).get_json()["ok"]
    assert [x["id"] for x in call(c, "get", f"{api}/state").get_json()["state"]["sheets"]] == ["c", "a", "b"]
    s = side("/admin/dashboard")
    assert s.index('data-item="c"') < s.index('data-item="a"') < s.index('data-item="b"')


def test_sidebar_cross_section_and_rename(ctx):
    c = ctx.admin()
    api = "/admin/hezu/api"

    def side(path):
        html = call(c, "get", path).get_data(as_text=True)
        return html.split('class="side"', 1)[1].split("</nav>", 1)[0]

    def sec(html, name):
        return html.split(f'data-sec="{name}"', 1)[1].split('class="nav-sec"', 1)[0]

    call(c, "put", f"{api}/state", json={"rev": 0, "state": {"sheets": [{"id": "a", "name": "A"}, {"id": "b", "name": "B"}], "months": {}, "vps": []}})
    # 表 b 拖到「验证码」，支付卡拖到「账号」；只传了这两个分类，旧位置自动拿掉
    r = call(c, "post", f"{api}/nav-order", json={"items": {"totp": ["dashboard", "b", "logs", "settings"], "accounts": ["a", "cards"]}})
    o = r.get_json()["navOrder"]
    assert o["items"]["totp"] == ["dashboard", "b", "logs", "settings"]
    assert o["items"]["accounts"] == ["a", "cards"] and o["items"]["backend"] == ["vps", "gpt"]
    s = side("/admin/dashboard")
    assert 'data-item="b"' in sec(s, "totp") and 'data-item="cards"' in sec(s, "accounts")
    assert 'data-item="cards"' not in sec(s, "backend")
    # 改名；留空恢复默认；太长截断
    o = call(c, "post", f"{api}/nav-order", json={"labels": {"backend": "  我的 后台 ", "totp": "x" * 50, "bogus": "y"}}).get_json()["navOrder"]
    assert o["labels"]["backend"] == "我的 后台" and o["labels"]["totp"] == "x" * 20 and "bogus" not in o["labels"]
    assert "我的 后台" in side("/admin/vault")
    assert o["items"]["totp"] == ["dashboard", "b", "logs", "settings"]          # 改名不影响位置
    o = call(c, "post", f"{api}/nav-order", json={"labels": {"backend": ""}}).get_json()["navOrder"]
    assert o["labels"]["backend"] == "后台"
    assert call(c, "get", f"{api}/context").get_json()["navOrder"] == o
    # 表删掉以后不再出现，新表进「账号」
    st = call(c, "get", f"{api}/state").get_json()
    call(c, "put", f"{api}/state", json={"rev": st["rev"], "state": {"sheets": [{"id": "a", "name": "A"}, {"id": "n", "name": "N"}], "months": {}, "vps": []}})
    o = call(c, "get", f"{api}/context").get_json()["navOrder"]
    assert o["items"]["totp"] == ["dashboard", "logs", "settings"] and o["items"]["accounts"] == ["a", "cards", "n"]
