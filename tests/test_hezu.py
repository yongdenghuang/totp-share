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
    assert "hezu/app.js" in html and 'data-csrf="' in html
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
