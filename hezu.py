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

import hezu_xlsx

API_PREFIX = "/admin/hezu/api/"
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
    return {"groups": groups, "accounts": accounts}


def shell_nav():
    """验证码各页的左侧导航和账本页是同一套，这里给模板提供账本那几项的名字和数量。"""
    try:
        state = load_state()[1]
    except Exception:          # 账本读不出来也不能让验证码页面打不开
        state = default_state()
    months = sorted(k for k, v in state.get("months", {}).items() if isinstance(v, dict))
    rows = (state["months"][months[-1]].get("rows") or {}) if months else {}
    sheets = [{"id": str(s["id"]), "name": str(s.get("name") or ""), "grouped": bool(s.get("grouped")),
               "count": len(rows.get(s["id"]) or [])}
              for s in state.get("sheets", []) if isinstance(s, dict) and s.get("id")]
    accounts = _core.query_one("SELECT COUNT(*) AS n FROM accounts")["n"]
    return {"sheets": sheets, "cards": len(state.get("cards") or []),
            "vps": len(state.get("vps") or []), "accounts": accounts}


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
        state.pop("rev", None)
        state.pop("groups", None)   # 分组以验证码后台的为准，不随账本保存
        rev = save_state(state, data.get("rev"))
        if rev is None:
            return jsonify(ok=False, error="数据已在别处被修改"), 409
        return jsonify(ok=True, rev=rev, csrf=generate_csrf())

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
