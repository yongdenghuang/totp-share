"""合租账本：每月的账号续费、每人收费、支付卡、VPS。

和验证码账号共用同一个后台登录和同一套分组。账本整份数据（JSON）压缩后用 Fernet
加密，存在 hezu_state 表的一行里——卡号、VPS 密码、账号、金额在数据库里都是密文，
也会跟着每天的加密备份走。每天第一次保存前，把上一版留一份到 hezu_history。

由 app.py 末尾调用 install() 接入；这里不直接 import app，避免循环引用。
"""
import json
import os
import re
import threading
import time
import urllib.request
import zlib
from datetime import datetime, timedelta

import pyotp
from flask import jsonify, render_template, request, url_for
from flask_wtf.csrf import generate_csrf

import hezu_export
import hezu_xlsx

API_PREFIX = "/admin/hezu/api/"
WEB_CLIENT_MIN = 2   # 网页 app.js 里的 CLIENT_VERSION；改了同步规则时调高，旧页面就存不进来


def _int(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return 0

MAX_BODY = 8 * 1024 * 1024       # 账本和导入的 Excel 都比全站 64KB 的上限大
HISTORY_DAYS = 60
UNGROUPED_COLOR = "#6c757d"

# 汇率：ExchangeRate-API 的免费接口（不需要密钥，每天更新一次）。页面的安全策略不允许浏览器直接
# 访问外部网站，所以由服务器去取，并在内存里缓存一小时。
RATES_URL = "https://open.er-api.com/v6/latest/USD"
RATES_TTL = 3600            # 缓存多久（秒）
RATES_RETRY = 300           # 取失败后，至少隔多久再去试
_rates = {"data": None, "fetched": 0, "tried": 0}
_rates_lock = threading.Lock()

_core = None   # app 模块，install() 时填入


def default_state():
    return {
        "sheets": [
            {"id": "ai", "name": "AI 合租", "mode": "members", "grouped": True},
            {"id": "netflix", "name": "Netflix", "mode": "unit"},
            {"id": "spotify", "name": "Spotify", "mode": "unit"},
            {"id": "icloud", "name": "iCloud", "mode": "unit"},
        ],
        "months": {},
        "vps": [],
    }


def valid_state(s):
    return (isinstance(s, dict) and isinstance(s.get("sheets"), list)
            and isinstance(s.get("months"), dict) and isinstance(s.get("vps"), list)
            and all(isinstance(m, dict) for m in s["months"].values()))


def today_cn():
    """北京时间的今天，决定“每天留一份历史”按哪一天算。"""
    return datetime.now(_core.TZ_DISPLAY).strftime("%Y-%m-%d")


def pack(state):
    raw = json.dumps(state, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return _core.FERNET.encrypt(zlib.compress(raw))


def unpack(blob):
    return json.loads(zlib.decompress(_core.FERNET.decrypt(bytes(blob))).decode("utf-8"))


def load_state():
    """返回 (版本号, 账本)。还没存过时是 (0, 空账本)。"""
    row = _core.query_one("SELECT rev, data_encrypted FROM hezu_state WHERE id=1")
    if not row:
        return 0, default_state()
    return row["rev"], unpack(row["data_encrypted"])


def save_state(state, expected_rev):
    """保存账本。expected_rev 和库里的版本号不一致（别处先改过）时不保存，返回 None。"""
    db = _core.get_db()
    db.execute("BEGIN IMMEDIATE")
    try:
        row = db.execute("SELECT rev, data_encrypted FROM hezu_state WHERE id=1").fetchone()
        current = row["rev"] if row else 0
        if expected_rev != current:
            db.rollback()
            return None
        now, day = _core.utc_now_str(), today_cn()
        if row and not db.execute("SELECT 1 FROM hezu_history WHERE day=?", (day,)).fetchone():
            db.execute("INSERT INTO hezu_history(day, rev, data_encrypted, saved_at) VALUES (?,?,?,?)",
                       (day, current, row["data_encrypted"], now))
            cutoff = (datetime.strptime(day, "%Y-%m-%d") - timedelta(days=HISTORY_DAYS)).strftime("%Y-%m-%d")
            db.execute("DELETE FROM hezu_history WHERE day<?", (cutoff,))
        db.execute(
            """INSERT INTO hezu_state(id, rev, data_encrypted, updated_at) VALUES (1,?,?,?)
               ON CONFLICT(id) DO UPDATE SET rev=excluded.rev,
                   data_encrypted=excluded.data_encrypted, updated_at=excluded.updated_at""",
            (current + 1, pack(state), now))
        db.commit()
    except Exception:
        db.rollback()
        raise
    return current + 1


def context():
    """账本页面要用到的验证码后台数据：分组（共用一套）和账号名单。不含任何密钥、密码。"""
    groups = []
    for r in _core.query_all("SELECT id, name, color FROM account_groups ORDER BY COALESCE(sort_order, id), id"):
        color = r["color"] or UNGROUPED_COLOR
        groups.append({"id": str(r["id"]), "name": r["name"], "color": color,
                       "text": _core.text_color_on(color)})
    accounts = [{"id": r["id"], "name": r["name"], "group": r["group_name"] or "",
                 "hasPassword": bool(r["has_password"])}
                for r in _core.query_all(
                    """SELECT id, name, group_name, password_encrypted IS NOT NULL AS has_password
                       FROM accounts ORDER BY COALESCE(sort_order, 999999), created_at DESC""")]
    import vault   # 左侧导航上密码本、备忘录的数量和各项的顺序（账本页的导航由 app.js 画）
    return {"groups": groups, "accounts": accounts, "vault": vault.counts(), "navOrder": nav_order()}


# 左侧导航：四个大分类，名字可以改，小项可以拖到任意分类、调整顺序。存在 settings 表（nav_order）：
# {"sections": [分类], "items": {分类: [小项 id]}, "labels": {分类: 自定义名字}}。
# 小项有两种：固定的页面（支付卡、VPS…）和账本里的表（id 是表的 id）。没放到任何分类里的，固定页面回到默认分类，
# 表进「账号」并按账本里 sheets 的顺序。验证码各页、账本页、密码本页共用。
NAV_SECTIONS = [("accounts", "账号"), ("backend", "后台"), ("backup", "备份"), ("totp", "验证码")]
NAV_ITEMS = {"accounts": [], "backend": ["cards", "vps", "gpt"], "backup": ["vault", "notes"], "totp": ["dashboard", "logs", "settings"]}
NAV_LABEL_MAX = 20
# 每个板块的颜色（左栏的板块名、图标、选中时的底色都用它），可以自己换
NAV_COLORS = ["purple", "blue", "teal", "amber", "pink", "green", "red", "gray"]
NAV_DEFAULT_COLORS = {"accounts": "purple", "backend": "blue", "backup": "amber", "totp": "teal"}
NAV_FIXED = {i for lst in NAV_ITEMS.values() for i in lst}   # 固定页面的小项，名字可以改（存在 names 里）；表的名字就是账本里表的名字


def _ordered(saved, known):
    """按保存的顺序排，没保存过的（新加的）按默认顺序接在后面；不认识的丢掉。"""
    saved = [x for x in saved if x in known] if isinstance(saved, list) else []
    out = []
    for x in saved + list(known):
        if x not in out:
            out.append(x)
    return out


def _sheet_ids(state=None):
    if state is None:
        try:
            state = load_state()[1]
        except Exception:
            state = default_state()
    return [str(s["id"]) for s in state.get("sheets", []) if isinstance(s, dict) and s.get("id")]


def _resolve(sections, items, sheets):
    """每个小项只出现在一个分类里：先按保存的位置放，剩下的固定页面回默认分类，剩下的表接在「账号」后面。"""
    fixed = {i: sec for sec, lst in NAV_ITEMS.items() for i in lst}
    known = set(fixed) | set(sheets)
    used, out = set(), {}
    for sec in sections:
        lst = []
        saved = items.get(sec) if isinstance(items.get(sec), list) else []
        for x in saved:
            if isinstance(x, str) and x in known and x not in used:
                used.add(x)
                lst.append(x)
        out[sec] = lst
    for i, sec in fixed.items():
        if i not in used:
            out[sec].append(i)
    out["accounts"] += [x for x in sheets if x not in used]
    return out


def _labels(raw):
    raw = raw if isinstance(raw, dict) else {}
    out = {}
    for k, default in NAV_SECTIONS:
        v = raw.get(k)
        v = " ".join(str(v).split())[:NAV_LABEL_MAX] if isinstance(v, str) else ""
        out[k] = v or default
    return out


def _names(raw):
    """固定小项的自定义名字（只存改过的）"""
    out = {}
    for k, v in (raw if isinstance(raw, dict) else {}).items():
        v = " ".join(str(v).split())[:NAV_LABEL_MAX] if isinstance(v, str) else ""
        if k in NAV_FIXED and v:
            out[k] = v
    return out


def nav_order(sheets=None):
    try:
        raw = json.loads(_core.get_setting("nav_order", "") or "{}")
    except ValueError:
        raw = {}
    if not isinstance(raw, dict):
        raw = {}
    sections = _ordered(raw.get("sections"), [k for k, _ in NAV_SECTIONS])
    items = raw.get("items") if isinstance(raw.get("items"), dict) else {}
    sheets = _sheet_ids() if sheets is None else sheets
    collapsed = [k for k in raw.get("collapsed") or [] if k in NAV_ITEMS] if isinstance(raw.get("collapsed"), list) else []
    rc = raw.get("colors") if isinstance(raw.get("colors"), dict) else {}
    colors = {k: rc[k] if rc.get(k) in NAV_COLORS else NAV_DEFAULT_COLORS[k] for k in NAV_ITEMS}
    return {"sections": sections, "items": _resolve(sections, items, sheets), "labels": _labels(raw.get("labels")),
            "names": _names(raw.get("names")), "collapsed": list(dict.fromkeys(collapsed)), "colors": colors}


def save_nav_order(data):
    if not isinstance(data, dict):
        raise ValueError("参数错误")
    sheets = _sheet_ids()
    cur = nav_order(sheets)
    if "sections" in data:
        cur["sections"] = _ordered(data["sections"], [k for k, _ in NAV_SECTIONS])
    if isinstance(data.get("items"), dict):
        merged = dict(cur["items"])
        moved = set()
        for k, v in data["items"].items():
            if k in NAV_ITEMS and isinstance(v, list):
                merged[k] = [x for x in v if isinstance(x, str)][:500]
                moved.update(merged[k])
        for k in NAV_ITEMS:           # 拖到新分类的小项，从没一起传上来的旧分类里拿掉
            if k not in data["items"]:
                merged[k] = [x for x in merged[k] if x not in moved]
        cur["items"] = _resolve(cur["sections"], merged, sheets)
    if isinstance(data.get("labels"), dict):
        labels = dict(cur["labels"])
        labels.update({k: v for k, v in data["labels"].items() if k in NAV_ITEMS and isinstance(v, str)})
        cur["labels"] = _labels(labels)
    if isinstance(data.get("colors"), dict):
        cur["colors"] = dict(cur["colors"], **{k: v for k, v in data["colors"].items() if k in NAV_ITEMS and v in NAV_COLORS})
    if isinstance(data.get("collapsed"), list):    # 折叠起来的板块（只显示板块名和当前打开的那一项）
        cur["collapsed"] = list(dict.fromkeys(k for k in data["collapsed"] if k in NAV_ITEMS))
    if isinstance(data.get("names"), dict):        # 留空 = 恢复默认名字
        names = dict(cur["names"])
        names.update({k: v for k, v in data["names"].items() if isinstance(v, str)})
        cur["names"] = _names(names)
    # 名字和默认一样的就不存，以后默认名改了也跟着变
    defaults = dict(NAV_SECTIONS)
    stored = dict(cur, labels={k: v for k, v in cur["labels"].items() if v != defaults[k]})
    _core.set_setting("nav_order", json.dumps(stored, ensure_ascii=False, separators=(",", ":")))
    return cur


def shell_nav():
    """验证码各页、密码本、备忘录的左侧导航（服务器画）。账本页的导航由 app.js 按同样的顺序画。"""
    try:
        state = load_state()[1]
    except Exception:          # 账本读不出来也不能让验证码页面打不开
        state = default_state()
    months = sorted(k for k, v in state.get("months", {}).items() if isinstance(v, dict))
    rows = (state["months"][months[-1]].get("rows") or {}) if months else {}
    ledger = url_for("hezu_page")
    import vault
    vc = vault.counts()
    accounts = _core.query_one("SELECT COUNT(*) AS n FROM accounts")["n"]
    sheets = [{"id": str(s["id"]), "sheet": True, "text": str(s.get("name") or ""), "href": ledger + "#" + str(s["id"]),
               "icon": "users" if s.get("grouped") else "bolt" if s.get("mode") == "resale" else "play",
               "count": len(rows.get(s["id"]) or [])}
              for s in state.get("sheets", []) if isinstance(s, dict) and s.get("id")]
    items = {
        "cards": {"text": "支付卡", "href": ledger + "#cards", "icon": "card", "count": len(state.get("cards") or [])},
        "vps": {"text": "VPS", "href": ledger + "#vps", "icon": "server", "count": len(state.get("vps") or [])},
        "gpt": {"text": "GPT 账号", "href": url_for("gpt_page"), "icon": "brain", "on": ["gpt_page"]},
        "vault": {"text": "密码本", "href": url_for("vault_page"), "icon": "lock", "count": vc["items"], "on": ["vault_page"]},
        "notes": {"text": "备忘录", "href": url_for("notes_page"), "icon": "note", "count": vc["notes"], "on": ["notes_page"]},
        "dashboard": {"text": "验证码账号", "href": url_for("dashboard"), "icon": "key", "count": accounts,
                      "on": ["dashboard", "account_new", "account_edit", "groups_page"]},
        "logs": {"text": "访问记录", "href": url_for("access_logs"), "icon": "list", "on": ["access_logs"]},
        "settings": {"text": "设置", "href": url_for("settings"), "icon": "gear", "on": ["settings"]},
    }
    by_id = {x["id"]: x for x in sheets}
    order = nav_order(list(by_id))
    sections = []
    for sec in order["sections"]:
        its = [by_id[i] if i in by_id else dict(items[i], id=i, default=items[i]["text"], text=order["names"].get(i, items[i]["text"]))
               for i in order["items"][sec]]
        sections.append({"id": sec, "label": order["labels"][sec], "items": its, "newSheet": sec == "accounts",
                         "collapsed": sec in order["collapsed"], "color": order["colors"][sec]})
    return {"sections": sections}


def static_url(filename):
    """静态文件地址带上修改时间，更新代码后浏览器不会继续用旧的脚本和样式。"""
    path = os.path.join(_core.app.static_folder, filename)
    try:
        version = int(os.path.getmtime(path))
    except OSError:
        version = 0
    return url_for("static", filename=filename, v=version)


def fetch_rates():
    """去数据源取一次汇率，返回 {"base", "rates", "updated"}；任何问题都抛异常。"""
    req = urllib.request.Request(RATES_URL, headers={"User-Agent": "totp-share/hezu"})
    with urllib.request.urlopen(req, timeout=8) as r:
        raw = r.read(512 * 1024)
    d = json.loads(raw.decode("utf-8"))
    if d.get("result") != "success" or not isinstance(d.get("rates"), dict):
        raise ValueError("数据源返回的内容不对")
    rates = {k: float(v) for k, v in d["rates"].items()
             if isinstance(k, str) and re.fullmatch(r"[A-Z]{3}", k)
             and isinstance(v, (int, float)) and not isinstance(v, bool) and v > 0}
    base = d.get("base_code") or "USD"
    if rates.get(base) != 1 or len(rates) < 10:
        raise ValueError("数据源返回的内容不对")
    return {"base": base, "rates": rates, "updated": int(d.get("time_last_update_unix") or 0)}


def get_rates():
    """返回 (数据, 是否是过期的旧数据)；一次都没取到过时返回 (None, False)。"""
    now = time.time()
    with _rates_lock:
        fresh = bool(_rates["data"]) and now - _rates["fetched"] < RATES_TTL
        # 已经有旧数据时，失败后隔 5 分钟再试；一次都没取到过时，隔 30 秒就可以再试
        wait = RATES_RETRY if _rates["data"] else 30
        if not fresh and now - _rates["tried"] >= wait:
            _rates["tried"] = now
            try:
                _rates["data"] = fetch_rates()
                _rates["fetched"] = now
                fresh = True
            except Exception:
                _core.app.logger.warning("取汇率失败", exc_info=True)
        return _rates["data"], bool(_rates["data"]) and not fresh


def payload(rev, state):
    return dict(ok=True, rev=rev, state=state, csrf=generate_csrf(), **context())


def adopt_groups(state):
    """导入单机版的备份时：把备份里自带的分组按名称对应到共用的分组（没有就新建），
    并把每一行里的旧分组编号换成新的。"""
    old = state.pop("groups", None)
    if not isinstance(old, list):
        return
    mapping = {}
    for g in old:
        if not isinstance(g, dict) or not g.get("id"):
            continue
        try:
            name = _core.create_group(str(g.get("name") or ""))
        except ValueError:
            continue
        row = _core.query_one("SELECT id FROM account_groups WHERE name=?", (name,))
        mapping[str(g["id"])] = str(row["id"])
    for month in state["months"].values():
        for rows in (month.get("rows") or {}).values():
            for r in rows if isinstance(rows, list) else []:
                if isinstance(r, dict) and r.get("group"):
                    r["group"] = mapping.get(str(r["group"]), "")


def install(core):
    """把账本的页面和接口挂到 app 上。"""
    global _core
    _core = core
    app, limiter, login_required = core.app, core.limiter, core.login_required
    @app.context_processor
    def shell_helpers():
        # 用 context_processor 而不是直接改 jinja_env：后者会过早创建模板环境，
        # dev/run.py 里之后才设置的 TEMPLATES_AUTO_RELOAD 就不生效了
        return {"hz_nav": shell_nav, "hz_static": static_url}

    api_limit = limiter.limit("240 per minute")   # 账本边改边自动保存，不能用全站默认的每小时 300 次

    def raise_body_limit():
        # 必须排在 CSRF 检查之前：那一步会碰请求体，超过全站上限就直接 413 了
        if request.path.startswith(API_PREFIX):
            request.max_content_length = MAX_BODY
    app.before_request_funcs.setdefault(None, []).insert(0, raise_body_limit)

    def read_json():
        data = request.get_json(silent=True)
        return data if isinstance(data, dict) else None

    @app.route("/admin/hezu")
    @login_required
    def hezu_page():
        return render_template("hezu.html")

    @app.route(API_PREFIX + "state", methods=["GET"])
    @api_limit
    @login_required
    def hezu_state_get():
        return jsonify(payload(*load_state()))

    @app.route(API_PREFIX + "state", methods=["PUT"])
    @api_limit
    @login_required
    def hezu_state_put():
        data = read_json()
        state = data.get("state") if data else None
        if not valid_state(state):
            return jsonify(ok=False, error="数据结构不对"), 400
        # 浏览器里开着的旧页面（规则旧了，比如不认「分组不同步」）：不让它保存，提示刷新。
        # App 自己的请求（不是浏览器）不受影响。
        if "Mozilla" in (request.headers.get("User-Agent") or "") and _int(data.get("client")) < WEB_CLIENT_MIN:
            return jsonify(ok=False, stale=True, error="这个页面是旧版本，请刷新后再改"), 409
        state.pop("rev", None)
        state.pop("groups", None)   # 分组以验证码后台的为准，不随账本保存
        rev = save_state(state, data.get("rev"))
        if rev is None:
            return jsonify(ok=False, error="数据已在别处被修改"), 409
        return jsonify(ok=True, rev=rev, csrf=generate_csrf())

    @app.route(API_PREFIX + "export")
    @api_limit
    @login_required
    def hezu_export_xlsx():
        """导出 Excel（App 用；网页在浏览器里自己生成同样的文件）。?month=2026-11 或 ?year=2026"""
        state = load_state()[1]
        keys = sorted(k for k, v in (state.get("months") or {}).items() if isinstance(v, dict))
        year, month = request.args.get("year", ""), request.args.get("month", "")
        if year:
            months, name = [k for k in keys if k.startswith(year + "-")], f"合租管理-{year}年.xlsx"
        else:
            month = month or (keys[-1] if keys else "")
            months, name = [k for k in keys if k == month], f"合租管理-{hezu_export.ym_label(month).replace(' ', '')}.xlsx" if month else "合租管理.xlsx"
        if not months:
            return jsonify(ok=False, error="这个时间段没有数据"), 404
        data = hezu_export.build(state, context()["groups"], months, bool(year))
        from urllib.parse import quote
        return app.response_class(data, mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                                  headers={"Content-Disposition": f"attachment; filename*=UTF-8''{quote(name)}",
                                           "Cache-Control": "no-store"})

    @app.route(API_PREFIX + "rates")
    @api_limit
    @login_required
    def hezu_rates():
        data, stale = get_rates()
        if not data:
            return jsonify(ok=False, error="暂时取不到汇率，请稍后再试"), 502
        return jsonify(ok=True, stale=stale, source="ExchangeRate-API",
                       sourceUrl="https://www.exchangerate-api.com", **data)

    @app.route(API_PREFIX + "context")
    @api_limit
    @login_required
    def hezu_context():
        return jsonify(ok=True, csrf=generate_csrf(), **context())

    @app.route(API_PREFIX + "nav-order", methods=["POST"])
    @api_limit
    @login_required
    def hezu_nav_order():
        """拖动左侧导航的大分类或「后台」「备份」「验证码」里的小项。"""
        try:
            return jsonify(ok=True, navOrder=save_nav_order(read_json()))
        except ValueError as e:
            return jsonify(ok=False, error=str(e)), 400

    @app.route(API_PREFIX + "sheet-order", methods=["POST"])
    @api_limit
    @login_required
    def hezu_sheet_order():
        """在验证码各页、密码本页拖动「账号」里的表：直接改账本里表的顺序（账本页自己改 sheets 再保存）。"""
        order = (read_json() or {}).get("order")
        if not isinstance(order, list) or not all(isinstance(x, str) for x in order):
            return jsonify(ok=False, error="参数错误"), 400
        for _ in range(5):            # 恰好有别处在保存时重试
            rev, state = load_state()
            pos = {sid: i for i, sid in enumerate(order)}
            state["sheets"].sort(key=lambda s: pos.get(str(s.get("id")), len(pos)))
            if save_state(state, rev) is not None:
                return jsonify(ok=True)
        return jsonify(ok=False, error="账本正忙，请稍后再试"), 409

    @app.route(API_PREFIX + "sheet-rename", methods=["POST"])
    @api_limit
    @login_required
    def hezu_sheet_rename():
        """在验证码各页、密码本页的左侧导航给表改名：直接改账本里表的名字（账本页自己改再保存）。"""
        data = read_json() or {}
        sid, name = data.get("id"), " ".join(str(data.get("name") or "").split())[:40]
        if not isinstance(sid, str) or not name:
            return jsonify(ok=False, error="参数错误"), 400
        for _ in range(5):
            rev, state = load_state()
            sh = next((x for x in state.get("sheets", []) if isinstance(x, dict) and str(x.get("id")) == sid), None)
            if sh is None:
                return jsonify(ok=False, error="找不到这张表"), 404
            sh["name"] = name
            if save_state(state, rev) is not None:
                return jsonify(ok=True, name=name)
        return jsonify(ok=False, error="账本正忙，请稍后再试"), 409

    @app.route(API_PREFIX + "share-links", methods=["POST"])
    @api_limit
    @login_required
    def hezu_share_links():
        """「只存账号」表要显示验证码分享链接（和验证码账号页一样）。链接不放进账本数据里，打开这张表时单独取。"""
        ids = (read_json() or {}).get("ids")
        if not isinstance(ids, list) or len(ids) > 500 or not all(isinstance(x, int) for x in ids):
            return jsonify(ok=False, error="参数错误"), 400
        if not ids:
            return jsonify(ok=True, links={})
        rows = _core.query_all(f"SELECT id, url_token FROM accounts WHERE id IN ({','.join('?' * len(ids))})", ids)
        return jsonify(ok=True, links={str(r["id"]): r["url_token"] for r in rows})

    @app.route(API_PREFIX + "groups", methods=["POST"])
    @api_limit
    @login_required
    def hezu_group_create():
        data = read_json() or {}
        try:
            name = core.create_group(str(data.get("name") or ""))
        except ValueError as e:
            return jsonify(ok=False, error=str(e)), 400
        return jsonify(ok=True, name=name, **context())

    @app.route(API_PREFIX + "accounts", methods=["POST"])
    @api_limit
    @login_required
    def hezu_account_create():
        """统一的「添加账号」入口填了 TOTP 密钥时，在这里建验证码账号。
        校验规则和验证码后台原来的添加表单一致；账本那一行由页面随后自己保存。"""
        data = read_json() or {}
        name = str(data.get("name") or "").strip()[:100]
        if not name:
            return jsonify(ok=False, error="请填写账号名称"), 400
        try:
            secret = core.validate_base32(str(data.get("secret") or ""))
            pyotp.TOTP(secret).now()
            password = core.parse_account_password(str(data.get("password") or ""))
            group = core.resolve_group(str(data.get("group") or ""))
        except ValueError as e:
            return jsonify(ok=False, error=str(e)), 400
        dups = core.find_same_name(name)
        if dups and not data.get("confirmDuplicate"):
            return jsonify(ok=False, duplicate=True,
                           error=f"验证码账号里已经有 {len(dups)} 个叫「{dups[0]['name']}」的账号。"), 409
        token = core.new_token()
        aid = core.execute(
            """INSERT INTO accounts(name, secret_encrypted, url_token, url_token_hash,
                                    group_name, password_encrypted) VALUES (?,?,?,?,?,?)""",
            (name, core.encrypt_secret(secret), token, core.hash_token(token), group, password))
        return jsonify(ok=True, id=aid, **context())

    @app.route(API_PREFIX + "import", methods=["POST"])
    @api_limit
    @login_required
    def hezu_import():
        """把原来的 Excel 解析成账本数据交给页面预览，这一步不保存任何东西。"""
        try:
            return jsonify(hezu_xlsx.parse(request.get_data()))
        except Exception as e:   # 不是合法的 xlsx、结构认不出来等
            return jsonify(ok=False, error=f"读不了这个文件：{e}"), 400

    @app.route(API_PREFIX + "restore", methods=["POST"])
    @api_limit
    @login_required
    def hezu_restore():
        """用一份 JSON 备份（单机版或本系统导出的）整体替换当前账本。"""
        data = read_json()
        state = data.get("state") if data else None
        if not valid_state(state):
            return jsonify(ok=False, error="这不是合租账本的备份文件"), 400
        state.pop("rev", None)
        adopt_groups(state)
        rev = save_state(state, load_state()[0])
        if rev is None:
            return jsonify(ok=False, error="数据刚被别处修改，请重试"), 409
        return jsonify(payload(rev, state))

    @app.route(API_PREFIX + "history")
    @api_limit
    @login_required
    def hezu_history():
        rows = core.query_all("SELECT day, saved_at FROM hezu_history ORDER BY day DESC")
        return jsonify(ok=True, days=[{"day": r["day"], "savedAt": core.cn_time(r["saved_at"], "%m-%d %H:%M")}
                                      for r in rows])

    @app.route(API_PREFIX + "history/<day>/restore", methods=["POST"])
    @api_limit
    @login_required
    def hezu_history_restore(day):
        row = core.query_one("SELECT data_encrypted FROM hezu_history WHERE day=?", (day,))
        if not row:
            return jsonify(ok=False, error="没有这一天的历史版本"), 404
        state = unpack(row["data_encrypted"])
        rev = save_state(state, load_state()[0])
        if rev is None:
            return jsonify(ok=False, error="数据刚被别处修改，请重试"), 409
        return jsonify(payload(rev, state))
