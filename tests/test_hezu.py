"""合租账本：登录保护、加密入库、版本冲突、历史版本、备份恢复、和验证码后台共用分组。全部是假数据。"""
import io
import json
import zipfile

import hezu
from conftest import BASE_URL

API = "/admin/hezu/api"
CARD = "4000123412341234"          # 假卡号，用来检查数据库里有没有明文
VPS_PASSWORD = "not-a-real-vps-pw"


def call(c, method, path, **kw):
    return getattr(c, method)(path, base_url=BASE_URL, **kw)


def sample_state(note=""):
    return {
        "sheets": [{"id": "ai", "name": "AI 合租", "mode": "members", "grouped": True}],
        "months": {"2026-11": {"archived": False, "rows": {"ai": [
            {"id": "r1", "group": "", "account": "plus-01", "renew": "2026-11-15", "issuerId": "i1", "cardId": "c1",
             "members": [{"name": "", "amount": 35, "paid": True}], "cost": 105, "note": note}]}}},
        "issuers": [{"id": "i1", "name": "Wise", "country": ""}],
        "cards": [{"id": "c1", "issuerId": "i1", "number": CARD, "note": ""}],
        "vps": [{"id": "v1", "host": "demo", "password": VPS_PASSWORD}],
    }


def save(c, state, rev):
    return call(c, "put", f"{API}/state", json={"rev": rev, "state": state})


# ---------- 登录保护 ----------
def test_page_and_api_require_login(ctx):
    c = ctx.client()
    r = call(c, "get", "/admin/hezu")
    assert r.status_code == 302 and "/admin/login" in r.headers["Location"]
    assert call(c, "get", f"{API}/state").status_code == 401
    assert call(c, "get", f"{API}/context").status_code == 401
    assert call(c, "get", f"{API}/history").status_code == 401
    assert save(c, sample_state(), 0).status_code == 401
    assert call(c, "post", f"{API}/import", data=b"x").status_code == 401
    assert call(c, "post", f"{API}/restore", json={"state": sample_state()}).status_code == 401
    assert ctx.sql("SELECT COUNT(*) AS n FROM hezu_state")[0]["n"] == 0


def test_page_and_nav_link(ctx):
    c = ctx.admin()
    html = call(c, "get", "/admin/hezu").get_data(as_text=True)
    assert "hezu/app.js" in html and "hezu/fx.js" in html and 'data-csrf="' in html
    assert "/admin/hezu" in call(c, "get", "/admin/dashboard").get_data(as_text=True)


# ---------- 保存与读取 ----------
def test_empty_state_then_roundtrip(ctx):
    c = ctx.admin()
    d = call(c, "get", f"{API}/state").get_json()
    assert d["rev"] == 0 and d["state"]["months"] == {} and d["csrf"]
    assert [s["id"] for s in d["state"]["sheets"]] == ["ai", "netflix", "spotify", "icloud"]
    r = save(c, sample_state("你好"), 0)
    assert r.status_code == 200 and r.get_json()["rev"] == 1
    d = call(c, "get", f"{API}/state").get_json()
    assert d["rev"] == 1
    row = d["state"]["months"]["2026-11"]["rows"]["ai"][0]
    assert row["note"] == "你好" and d["state"]["cards"][0]["number"] == CARD


def test_stale_revision_is_rejected(ctx):
    c = ctx.admin()
    assert save(c, sample_state("first"), 0).status_code == 200
    r = save(c, sample_state("stale"), 0)          # 另一个窗口还拿着旧版本号
    assert r.status_code == 409
    assert call(c, "get", f"{API}/state").get_json()["state"]["months"]["2026-11"]["rows"]["ai"][0]["note"] == "first"


def test_rejects_malformed_state(ctx):
    c = ctx.admin()
    for bad in ({"rev": 0}, {"rev": 0, "state": []}, {"rev": 0, "state": {"sheets": [], "months": [], "vps": []}}):
        assert call(c, "put", f"{API}/state", json=bad).status_code == 400
    assert ctx.sql("SELECT COUNT(*) AS n FROM hezu_state")[0]["n"] == 0


def test_state_is_encrypted_at_rest(ctx):
    c = ctx.admin()
    save(c, sample_state("机密备注"), 0)
    with open(ctx.path, "rb") as f:
        raw = f.read()
    for wal in (ctx.path + "-wal",):
        try:
            with open(wal, "rb") as f:
                raw += f.read()
        except FileNotFoundError:
            pass
    for secret in (CARD, VPS_PASSWORD, "机密备注", "plus-01@"):
        assert secret.encode("utf-8") not in raw
    blob = ctx.sql("SELECT data_encrypted FROM hezu_state")[0]["data_encrypted"]
    assert bytes(blob).startswith(b"gAAAA")      # Fernet 密文


def test_large_ledger_fits_but_other_routes_keep_small_limit(ctx):
    c = ctx.admin()
    state = sample_state("x" * 200_000)           # 远超全站 64KB 的请求体上限
    assert save(c, state, 0).status_code == 200
    assert len(call(c, "get", f"{API}/state").get_json()["state"]["months"]["2026-11"]["rows"]["ai"][0]["note"]) == 200_000
    r = call(c, "post", "/admin/accounts/reorder", json={"order": list(range(30_000))})
    assert r.status_code == 413


def test_csrf_is_enforced(ctx):
    ctx.app.config["WTF_CSRF_ENABLED"] = True
    from conftest import ADMIN_PASSWORD, ADMIN_USER
    ref = {"Referer": BASE_URL + "/admin/hezu"}     # https 下 Flask-WTF 还会核对来源页
    c = ctx.client()
    page = call(c, "get", "/admin/login").get_data(as_text=True)
    token = page.split('name="csrf_token" value="')[1].split('"')[0]
    r = call(c, "post", "/admin/login", headers=ref,
             data={"username": ADMIN_USER, "password": ADMIN_PASSWORD, "csrf_token": token})
    assert r.status_code == 302
    fresh = call(c, "get", f"{API}/state").get_json()["csrf"]
    body = {"rev": 0, "state": sample_state()}
    assert call(c, "put", f"{API}/state", json=body, headers=ref).status_code == 400            # 没带令牌
    assert call(c, "put", f"{API}/state", json=body, headers=dict(ref, **{"X-CSRFToken": "bogus"})).status_code == 400
    assert call(c, "post", f"{API}/groups", json={"name": "x"}, headers=ref).status_code == 400
    r = call(c, "put", f"{API}/state", json=body, headers=dict(ref, **{"X-CSRFToken": fresh}))
    assert r.status_code == 200 and r.get_json()["csrf"]


# ---------- 历史版本 ----------
def test_daily_history_and_restore(ctx, monkeypatch):
    c = ctx.admin()
    monkeypatch.setattr(hezu, "today_cn", lambda: "2026-11-13")
    save(c, sample_state("day1-a"), 0)
    save(c, sample_state("day1-b"), 1)
    assert [d["day"] for d in call(c, "get", f"{API}/history").get_json()["days"]] == ["2026-11-13"]
    # 13 号这一份：13 号当天第一次覆盖旧数据之前的版本（day1-a）
    monkeypatch.setattr(hezu, "today_cn", lambda: "2026-11-14")
    save(c, sample_state("day2"), 2)
    days = [d["day"] for d in call(c, "get", f"{API}/history").get_json()["days"]]
    assert days == ["2026-11-14", "2026-11-13"]
    r = call(c, "post", f"{API}/history/2026-11-14/restore")
    d = r.get_json()
    assert r.status_code == 200 and d["rev"] == 4
    assert d["state"]["months"]["2026-11"]["rows"]["ai"][0]["note"] == "day1-b"   # 14 号开始前的样子
    assert call(c, "post", f"{API}/history/1999-01-01/restore").status_code == 404


def test_history_is_pruned(ctx, monkeypatch):
    c = ctx.admin()
    monkeypatch.setattr(hezu, "today_cn", lambda: "2026-01-01")
    save(c, sample_state(), 0)
    save(c, sample_state(), 1)
    monkeypatch.setattr(hezu, "today_cn", lambda: "2026-06-01")
    save(c, sample_state(), 2)
    assert [r["day"] for r in ctx.sql("SELECT day FROM hezu_history ORDER BY day")] == ["2026-06-01"]


# ---------- 和验证码后台共用的分组、账号 ----------
def test_context_lists_groups_and_accounts_without_secrets(ctx):
    c = ctx.admin()
    r = call(c, "post", f"{API}/groups", json={"name": "GPT  Plus"})
    assert r.status_code == 200 and r.get_json()["name"] == "GPT Plus"
    d = call(c, "get", f"{API}/context").get_json()
    g = d["groups"][0]
    assert g["name"] == "GPT Plus" and g["color"].startswith("#") and g["text"].startswith("#") and isinstance(g["id"], str)
    assert {a["name"] for a in d["accounts"]} == {"plus-01", "pro20x-01"}
    text = json.dumps(d, ensure_ascii=False)
    for name, secret in ctx.secrets.items():
        assert secret not in text
    assert "tok0-abcdefgh" not in text and "password" not in text.lower().replace("haspassword", "")
    # 同名分组不会建两个；验证码后台的分组页也能看到它
    assert call(c, "post", f"{API}/groups", json={"name": "gpt plus"}).get_json()["name"] == "GPT Plus"
    assert len(ctx.sql("SELECT 1 FROM account_groups")) == 1
    assert "GPT Plus" in call(c, "get", "/admin/groups").get_data(as_text=True)
    assert call(c, "post", f"{API}/groups", json={"name": "  "}).status_code == 400


def test_new_account_form_prefills_name(ctx):
    html = call(ctx.admin(), "get", "/admin/accounts/new?name=plus-09%40example.com").get_data(as_text=True)
    assert 'value="plus-09@example.com"' in html


# ---------- 从单机版备份迁移 ----------
def test_restore_standalone_backup_maps_groups_by_name(ctx):
    c = ctx.admin()
    call(c, "post", f"{API}/groups", json={"name": "GPT Plus"})
    backup = sample_state("来自单机版")
    backup["rev"] = 57
    backup["groups"] = [{"id": "g_plus", "name": "gpt plus", "color": "teal"},
                        {"id": "g_claude20", "name": "Claude 20x", "color": "amber"}]
    rows = backup["months"]["2026-11"]["rows"]["ai"]
    rows[0]["group"] = "g_plus"
    rows.append(dict(rows[0], id="r2", group="g_claude20"))
    rows.append(dict(rows[0], id="r3", group="g_deleted_long_ago"))
    save(c, sample_state("恢复前"), 0)
    r = call(c, "post", f"{API}/restore", json={"state": backup})
    d = r.get_json()
    assert r.status_code == 200 and d["rev"] == 2 and "groups" not in d["state"]
    by_name = {g["name"]: g["id"] for g in d["groups"]}
    assert set(by_name) == {"GPT Plus", "Claude 20x"}
    got = [x["group"] for x in d["state"]["months"]["2026-11"]["rows"]["ai"]]
    assert got == [by_name["GPT Plus"], by_name["Claude 20x"], ""]
    assert call(c, "post", f"{API}/restore", json={"state": {"nope": 1}}).status_code == 400


# ---------- Excel 导入 ----------
def tiny_xlsx(rows):
    def sheet(cells):
        by_row = {}
        for ref, v in cells.items():
            by_row.setdefault(int("".join(ch for ch in ref if ch.isdigit())), []).append((ref, v))
        xml = '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
        for r in sorted(by_row):
            xml += f'<row r="{r}">' + "".join(
                f'<c r="{ref}"><v>{v}</v></c>' if isinstance(v, (int, float))
                else f'<c r="{ref}" t="inlineStr"><is><t>{v}</t></is></c>' for ref, v in by_row[r]) + "</row>"
        return xml + "</sheetData></worksheet>"
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("xl/workbook.xml",
                   '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
                   'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
                   '<sheets><sheet name="GPT合租" sheetId="1" r:id="rId1"/></sheets></workbook>')
        z.writestr("xl/_rels/workbook.xml.rels",
                   '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                   '<Relationship Id="rId1" Type="t" Target="worksheets/sheet1.xml"/></Relationships>')
        z.writestr("xl/worksheets/sheet1.xml", sheet(rows))
    return buf.getvalue()


def test_excel_import_parses_without_saving(ctx):
    c = ctx.admin()
    data = tiny_xlsx({"B1": "序号", "C1": "账号", "D1": "续费日期", "F1": "卡信息", "G1": "卡号",
                      "J1": "收费人数", "O1": "收费", "P1": "成本",
                      "C2": "fake-01@example.com", "D2": "11.28", "F2": "wise", "G2": CARD,
                      "J2": 900, "K2": "50+30", "O2": 980, "P2": 1040})
    r = call(c, "post", f"{API}/import", data=data, content_type="application/octet-stream")
    d = r.get_json()
    assert r.status_code == 200 and len(d["ai"]) == 1
    row = d["ai"][0]
    assert row["account"] == "fake-01@example.com" and row["cardNo"] == CARD and row["cost"] == 1040
    assert [m["amount"] for m in row["members"]] == [900, 50, 30]
    assert ctx.sql("SELECT COUNT(*) AS n FROM hezu_state")[0]["n"] == 0
    assert call(c, "post", f"{API}/import", data=b"not a spreadsheet").status_code == 400


# ---------- 统一的「添加账号」入口 ----------
def test_add_account_creates_totp_account(ctx):
    import pyotp
    c = ctx.admin()
    call(c, "post", f"{API}/groups", json={"name": "GPT Plus"})
    secret = pyotp.random_base32()
    r = call(c, "post", f"{API}/accounts", json={"name": " new-01@example.com ", "secret": secret.lower(),
                                                 "password": "pw-123", "group": "gpt plus"})
    d = r.get_json()
    assert r.status_code == 200 and d["ok"] and isinstance(d["id"], int)
    mine = [a for a in d["accounts"] if a["id"] == d["id"]][0]
    assert mine == {"id": d["id"], "name": "new-01@example.com", "group": "GPT Plus", "hasPassword": True}
    assert secret not in r.get_data(as_text=True) and "pw-123" not in r.get_data(as_text=True)
    # 验证码立刻能用，分享链接也生成了，密钥和密码在库里是密文
    codes = call(c, "get", "/admin/codes").get_json()["codes"]
    assert codes[str(d["id"])] == pyotp.TOTP(secret).now()
    row = ctx.sql("SELECT * FROM accounts WHERE id=?", (d["id"],))[0]
    assert row["url_token"] and secret.encode() not in bytes(row["secret_encrypted"])
    assert b"pw-123" not in bytes(row["password_encrypted"])
    assert call(ctx.client(), "get", "/t/" + row["url_token"]).status_code == 200


def test_add_account_validation_and_duplicates(ctx):
    import pyotp
    c = ctx.admin()
    good = pyotp.random_base32()
    before = ctx.sql("SELECT COUNT(*) AS n FROM accounts")[0]["n"]
    for bad in ({"name": "", "secret": good}, {"name": "x", "secret": ""}, {"name": "x", "secret": "not base32!"},
                {"name": "x", "secret": good, "group": "没有这个分组"}, {"name": "x", "secret": good, "password": "p" * 300}):
        assert call(c, "post", f"{API}/accounts", json=bad).status_code == 400
    r = call(c, "post", f"{API}/accounts", json={"name": "PLUS-01", "secret": good})     # 夹具里已有 plus-01
    assert r.status_code == 409 and r.get_json()["duplicate"] is True
    assert ctx.sql("SELECT COUNT(*) AS n FROM accounts")[0]["n"] == before
    r = call(c, "post", f"{API}/accounts", json={"name": "PLUS-01", "secret": good, "confirmDuplicate": True})
    assert r.status_code == 200 and ctx.sql("SELECT COUNT(*) AS n FROM accounts")[0]["n"] == before + 1
    assert call(ctx.client(), "post", f"{API}/accounts", json={"name": "x", "secret": good}).status_code == 401


def test_dashboard_add_button_points_to_unified_entry(ctx):
    html = call(ctx.admin(), "get", "/admin/dashboard").get_data(as_text=True)
    assert 'href="/admin/hezu?add=1"' in html
    # 原来的添加表单还在：账本里给已有的行补建验证码账号时会用到
    assert call(ctx.admin(), "get", "/admin/accounts/new").status_code == 200


# ---------- 整个后台共用一个外壳 ----------
def test_totp_pages_share_the_ledger_sidebar(ctx):
    c = ctx.admin()
    state = sample_state()
    state["sheets"].append({"id": "s_<x>", "name": "油管 & 会员", "mode": "unit"})
    save(c, state, 0)
    for path, active in (("/admin/dashboard", "验证码账号"), ("/admin/logs", "访问记录"),
                         ("/admin/settings", "设置"), ("/admin/groups", "验证码账号"),
                         ("/admin/accounts/new", "验证码账号")):
        html = call(c, "get", path).get_data(as_text=True)
        assert 'class="side"' in html and "hezu/shell.css" in html and "navbar" not in html
        assert "hezu/fx.js" in html and "data-fx-toggle" in html          # 每个页面都能打开汇率计算器
        assert 'href="/admin/hezu#ai"' in html and 'href="/admin/hezu#cards"' in html
        assert "油管 &amp; 会员" in html and 'href="/admin/hezu#s_&lt;x&gt;"' in html      # 表名、编号都转义
        on = html.split('class="nav on"', 1)[1].split("</a>", 1)[0]
        assert active in on
        assert html.count('class="nav on"') == 1
    # 导航里的数量来自账本：这个月 AI 合租 1 个账号、1 张卡、1 台 VPS、2 个验证码账号
    html = call(c, "get", "/admin/dashboard").get_data(as_text=True)
    side = html.split('class="side"', 1)[1].split("</nav>", 1)[0]
    counts = [x.split("<")[0] for x in side.split('class="count">')[1:]]
    assert counts == ["1", "0", "1", "1", "2"]


def test_public_and_login_pages_have_no_sidebar(ctx):
    token = ctx.sql("SELECT url_token FROM accounts LIMIT 1")[0]["url_token"]
    c = ctx.client()
    for path in ("/admin/login", "/t/" + token):
        html = call(c, "get", path).get_data(as_text=True)
        assert 'class="side"' not in html and "/admin/hezu" not in html and "fx.js" not in html
    assert "hezu/shell.css" not in call(c, "get", "/t/" + token).get_data(as_text=True)   # 分享页样式不变


# ---------- 分组顺序（验证码列表和账本共用） ----------
def group_names(ctx):
    return [r["name"] for r in ctx.sql("SELECT name FROM account_groups ORDER BY COALESCE(sort_order, id), id")]


def test_group_order_is_shared_and_reorderable(ctx):
    c = ctx.admin()
    for n in ("A组", "B组", "C组"):
        call(c, "post", f"{API}/groups", json={"name": n})
    assert group_names(ctx) == ["A组", "B组", "C组"]
    r = call(c, "post", "/admin/groups/reorder", json={"order": ["c组", "A组", "没有这个", "C组"]})
    assert r.status_code == 200 and r.get_json()["groups"] == ["C组", "A组", "B组"]   # 没列到的排后面，不认识的忽略
    assert [g["name"] for g in call(c, "get", f"{API}/context").get_json()["groups"]] == ["C组", "A组", "B组"]
    html = call(c, "get", "/admin/dashboard").get_data(as_text=True)
    assert html.index('"C组"') < html.index('"A组"') < html.index('"B组"')       # 验证码列表的分组标签也按这个顺序
    call(c, "post", f"{API}/groups", json={"name": "D组"})
    assert group_names(ctx)[-1] == "D组"                                          # 新分组排在最后
    for bad in ({"order": "C组"}, {"order": [1, 2]}, {}):
        assert call(c, "post", "/admin/groups/reorder", json=bad).status_code == 400
    assert call(ctx.client(), "post", "/admin/groups/reorder", json={"order": []}).status_code == 401


def test_groups_page_move_buttons(ctx):
    c = ctx.admin()
    for n in ("A组", "B组", "C组"):
        call(c, "post", f"{API}/groups", json={"name": n})
    call(c, "post", "/admin/groups", data={"action": "move", "direction": "up", "old_name": "C组"})
    assert group_names(ctx) == ["A组", "C组", "B组"]
    call(c, "post", "/admin/groups", data={"action": "move", "direction": "down", "old_name": "A组"})
    assert group_names(ctx) == ["C组", "A组", "B组"]
    call(c, "post", "/admin/groups", data={"action": "move", "direction": "up", "old_name": "C组"})   # 已经是第一个
    assert group_names(ctx) == ["C组", "A组", "B组"]
    html = call(c, "get", "/admin/groups").get_data(as_text=True)
    assert html.index('value="C组"') < html.index('value="A组"') < html.index('value="B组"')


def test_old_groups_get_an_order_on_upgrade(ctx):
    import sqlite3
    from migrate import ensure_schema
    db = sqlite3.connect(ctx.path)
    db.execute("INSERT INTO account_groups(name, color) VALUES ('老分组甲', '#2563eb'), ('老分组乙', '#16a34a')")
    db.execute("UPDATE account_groups SET sort_order=NULL")
    db.commit()
    assert ensure_schema(db) == []          # 列已经在了，补顺序不算结构变更
    assert [r[0] for r in db.execute("SELECT name FROM account_groups ORDER BY sort_order")] == ["老分组甲", "老分组乙"]
    db.close()


# ---------- 汇率 ----------
FAKE_RATES = {"base": "USD", "rates": {"USD": 1.0, "CNY": 7.1, "PHP": 58.0, "NGN": 1500.0, "EUR": 0.9,
                                       "HKD": 7.8, "GBP": 0.78, "SGD": 1.34, "JPY": 150.0, "AUD": 1.5},
              "updated": 1794600000}


def reset_rates(monkeypatch, fake):
    import hezu as h
    monkeypatch.setattr(h, "_rates", {"data": None, "fetched": 0, "tried": 0})
    calls = []
    def fetch():
        calls.append(1)
        if isinstance(fake, Exception):
            raise fake
        return fake
    monkeypatch.setattr(h, "fetch_rates", fetch)
    return calls


def test_rates_require_login(ctx, monkeypatch):
    reset_rates(monkeypatch, FAKE_RATES)
    assert call(ctx.client(), "get", f"{API}/rates").status_code == 401


def test_rates_are_cached(ctx, monkeypatch):
    calls = reset_rates(monkeypatch, FAKE_RATES)
    c = ctx.admin()
    for _ in range(3):
        d = call(c, "get", f"{API}/rates").get_json()
        assert d["ok"] and d["rates"]["CNY"] == 7.1 and d["base"] == "USD" and d["stale"] is False
    assert len(calls) == 1                      # 一小时内只去数据源取一次


def test_rates_fall_back_to_cached_copy(ctx, monkeypatch):
    import hezu as h
    calls = reset_rates(monkeypatch, FAKE_RATES)
    c = ctx.admin()
    call(c, "get", f"{API}/rates")
    h._rates["fetched"] -= h.RATES_TTL + 1       # 缓存过期
    monkeypatch.setattr(h, "fetch_rates", lambda: (_ for _ in ()).throw(OSError("network down")))
    d = call(c, "get", f"{API}/rates").get_json()
    assert d["ok"] and d["stale"] is True and d["rates"]["PHP"] == 58.0
    assert len(calls) == 1


def test_rates_unavailable(ctx, monkeypatch):
    reset_rates(monkeypatch, OSError("network down"))
    r = call(ctx.admin(), "get", f"{API}/rates")
    assert r.status_code == 502 and r.get_json()["ok"] is False


def test_fetch_rates_validates_the_source(ctx, monkeypatch):
    import hezu as h

    class Resp:
        def __init__(self, body): self.body = body
        def __enter__(self): return self
        def __exit__(self, *a): return False
        def read(self, n): return self.body

    def serve(obj):
        monkeypatch.setattr(h.urllib.request, "urlopen", lambda req, timeout: Resp(json.dumps(obj).encode()))

    good = {"result": "success", "base_code": "USD", "time_last_update_unix": 5,
            "rates": dict(FAKE_RATES["rates"], bad="x", XX=1, ZZZ=-3, YYY=True)}
    serve(good)
    d = h.fetch_rates()
    assert d["updated"] == 5 and "XX" not in d["rates"] and "ZZZ" not in d["rates"] and "YYY" not in d["rates"]
    for bad in ({"result": "error"}, {"result": "success", "base_code": "USD", "rates": {"USD": 1}}):
        serve(bad)
        try:
            h.fetch_rates()
            assert False, "should have raised"
        except ValueError:
            pass


def test_rename_totp_account_from_ledger(ctx):
    c = ctx.admin()
    aid = ctx.sql("SELECT id FROM accounts WHERE name='plus-01'")[0]["id"]
    r = call(c, "post", f"/admin/accounts/{aid}/field", json={"field": "name", "value": "  mati@example.com "})
    assert r.status_code == 200 and r.get_json()["display"] == "mati@example.com"
    assert ctx.sql("SELECT name FROM accounts WHERE id=?", (aid,))[0]["name"] == "mati@example.com"
    names = {a["name"] for a in call(c, "get", f"{API}/context").get_json()["accounts"]}
    assert "mati@example.com" in names and "plus-01" not in names
    assert call(c, "post", f"/admin/accounts/{aid}/field", json={"field": "name", "value": "  "}).status_code == 400
    assert call(c, "post", f"/admin/accounts/{aid}/field", json={"field": "secret_encrypted", "value": "x"}).status_code == 400
