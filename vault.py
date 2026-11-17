"""密码本和备忘录：自己的各类账号密码、只有号码没有密码的信息（电话卡等）、纯文本笔记。

每一条单独存一行（vault_entries），内容整条用 Fernet 加密——账号、密码、备注、笔记正文在数据库里
全是密文，也跟着每天的加密备份走。一条一行而不是整份一个大块：两个窗口同时改不同的条目互不影响；
同一条在别处先改过时（版本号对不上）返回 409，由页面决定怎么处理。

密码本的列表接口不带密码和标了「保密」的附加信息，点复制或编辑时再单独取（…/reveal）。
删除先进「最近删除」，30 天后才真正删掉，期间可以恢复。

由 app.py 末尾调用 install() 接入；这里不直接 import app，避免循环引用。
"""
import json
import zlib
from datetime import datetime, timedelta, timezone

from flask import jsonify, render_template, request
from flask_wtf.csrf import generate_csrf

API_PREFIX = "/admin/vault/api/"
TRASH_DAYS = 30
MAX_BODY = 1024 * 1024          # 一条笔记最长 20 万字，留足余量
KINDS = ("item", "note")

# 第一次打开时的默认类型；之后在页面上增删改、调顺序
DEFAULT_TYPES = [
    {"id": "apple", "name": "Apple", "color": "#57534e", "site": "https://account.apple.com"},
    {"id": "google", "name": "Google", "color": "#2563eb", "site": "https://myaccount.google.com"},
    {"id": "mail", "name": "邮箱", "color": "#0891b2", "site": ""},
    {"id": "phone", "name": "电话卡", "color": "#16a34a", "site": ""},
    {"id": "bank", "name": "银行 / 支付", "color": "#a16207", "site": ""},
    {"id": "social", "name": "社交", "color": "#db2777", "site": ""},
    {"id": "other", "name": "其他", "color": "#6c757d", "site": ""},
]

_core = None


def pack(obj):
    raw = json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return _core.FERNET.encrypt(zlib.compress(raw))


def unpack(blob):
    return json.loads(zlib.decompress(_core.FERNET.decrypt(bytes(blob))).decode("utf-8"))


def _s(v, limit):
    return str(v if v is not None else "").strip()[:limit]


def clean_item(d):
    """密码本的一条。只留认识的字段并截断长度；没有任何内容时返回 None。"""
    extras = []
    for x in (d.get("extras") or [])[:30]:
        if isinstance(x, dict) and (_s(x.get("label"), 60) or _s(x.get("value"), 1000)):
            extras.append({"label": _s(x.get("label"), 60), "value": _s(x.get("value"), 1000),
                           "secret": bool(x.get("secret"))})
    item = {
        "type": _s(d.get("type"), 40),
        "title": _s(d.get("title"), 100),
        "account": _s(d.get("account"), 300),
        "password": str(d.get("password") or "")[:500],   # 密码不去首尾空格，原样保存
        "phone": _s(d.get("phone"), 60),
        "site": _s(d.get("site"), 500),
        "note": str(d.get("note") or "")[:5000],
        "extras": extras,
    }
    if not any(item[k] for k in ("title", "account", "password", "phone", "note")) and not extras:
        return None
    return item


def clean_note(d):
    return {"text": str(d.get("text") or "")[:200000], "pinned": bool(d.get("pinned"))}


def clean_types(types):
    out, seen = [], set()
    for t in types if isinstance(types, list) else []:
        if not isinstance(t, dict):
            continue
        tid, name = _s(t.get("id"), 40), _s(t.get("name"), 40)
        if not tid or not name or tid in seen:
            continue
        seen.add(tid)
        color = _s(t.get("color"), 7)
        if not (len(color) == 7 and color[0] == "#" and all(c in "0123456789abcdefABCDEF" for c in color[1:])):
            color = "#6c757d"
        out.append({"id": tid, "name": name, "color": color, "site": _s(t.get("site"), 500)})
    return out[:60]


def public_item(item):
    """列表里给页面的样子：没有密码，标了保密的附加信息也不带内容。"""
    out = dict(item)
    out["hasPassword"] = bool(out.pop("password", ""))
    out["extras"] = [{"label": x["label"], "secret": True, "value": "", "hasValue": bool(x["value"])}
                     if x.get("secret") else dict(x) for x in item.get("extras") or []]
    return out


def entry_json(row, data, kind, full=False):
    body = data if (kind == "note" or full) else public_item(data)
    return dict(body, id=row["id"], rev=row["rev"],
                created=_core.cn_time(row["created_at"], "%Y-%m-%d %H:%M"),
                updated=_core.cn_time(row["updated_at"], "%Y-%m-%d %H:%M"),
                updatedRaw=row["updated_at"],
                deleted=_core.cn_time(row["deleted_at"], "%m-%d %H:%M") if row["deleted_at"] else "")


def get_row(kind, eid):
    return _core.query_one("SELECT * FROM vault_entries WHERE id=? AND kind=?", (eid, kind))


def purge_trash():
    cutoff = (datetime.now(timezone.utc) - timedelta(days=TRASH_DAYS)).strftime(_core.TS_FORMAT)
    _core.execute("DELETE FROM vault_entries WHERE deleted_at IS NOT NULL AND deleted_at < ?", (cutoff,))


def load_types():
    row = _core.query_one("SELECT rev, data_encrypted FROM vault_meta WHERE key='types'")
    if not row:
        return 0, [dict(t) for t in DEFAULT_TYPES]
    return row["rev"], unpack(row["data_encrypted"])


def counts():
    """左侧导航上的数量。"""
    try:
        rows = _core.query_all("SELECT kind, COUNT(*) AS n FROM vault_entries WHERE deleted_at IS NULL GROUP BY kind")
    except Exception:
        return {"items": 0, "notes": 0}
    d = {r["kind"]: r["n"] for r in rows}
    return {"items": d.get("item", 0), "notes": d.get("note", 0)}


def install(core):
    global _core
    _core = core
    app, limiter, login_required = core.app, core.limiter, core.login_required
    api_limit = limiter.limit("240 per minute")   # 笔记边打字边自动保存

    def raise_body_limit():
        if request.path.startswith(API_PREFIX):
            request.max_content_length = MAX_BODY
    app.before_request_funcs.setdefault(None, []).insert(0, raise_body_limit)

    @app.context_processor
    def vault_helpers():
        return {"vault_counts": counts}

    def body():
        d = request.get_json(silent=True)
        return d if isinstance(d, dict) else {}

    def kind_of(name):
        k = name[:-1] if name.endswith("s") else name
        return k if k in KINDS else None

    @app.route("/admin/vault")
    @login_required
    def vault_page():
        return render_template("vault.html", page="vault")

    @app.route("/admin/notes")
    @login_required
    def notes_page():
        return render_template("vault.html", page="notes")

    @app.route(API_PREFIX + "context")
    @api_limit
    @login_required
    def vault_context():
        return jsonify(ok=True, csrf=generate_csrf())

    @app.route(API_PREFIX + "<kinds>", methods=["GET"])
    @api_limit
    @login_required
    def vault_list(kinds):
        kind = kind_of(kinds)
        if not kind:
            return jsonify(ok=False, error="没有这一类"), 404
        purge_trash()
        trash = request.args.get("trash") == "1"
        rows = core.query_all(
            "SELECT * FROM vault_entries WHERE kind=? AND deleted_at IS " + ("NOT NULL" if trash else "NULL")
            + " ORDER BY " + ("deleted_at DESC" if trash else "updated_at DESC, id DESC"), (kind,))
        entries = [entry_json(r, unpack(r["data_encrypted"]), kind) for r in rows]
        out = dict(ok=True, entries=entries, csrf=generate_csrf(), trashDays=TRASH_DAYS)
        if kind == "item":
            out["typesRev"], out["types"] = load_types()
        if not trash:
            out["trashCount"] = core.query_one(
                "SELECT COUNT(*) AS n FROM vault_entries WHERE kind=? AND deleted_at IS NOT NULL", (kind,))["n"]
        return jsonify(out)

    @app.route(API_PREFIX + "<kinds>", methods=["POST"])
    @api_limit
    @login_required
    def vault_create(kinds):
        kind = kind_of(kinds)
        if not kind:
            return jsonify(ok=False, error="没有这一类"), 404
        data = (clean_item if kind == "item" else clean_note)(body().get("data") or {})
        if data is None:
            return jsonify(ok=False, error="什么都没填"), 400
        now = core.utc_now_str()
        eid = core.execute("""INSERT INTO vault_entries(kind, data_encrypted, rev, created_at, updated_at)
                              VALUES (?,?,1,?,?)""", (kind, pack(data), now, now))
        return jsonify(ok=True, entry=entry_json(get_row(kind, eid), data, kind))

    @app.route(API_PREFIX + "<kinds>/<int:eid>", methods=["PUT"])
    @api_limit
    @login_required
    def vault_update(kinds, eid):
        kind = kind_of(kinds)
        row = get_row(kind, eid) if kind else None
        if not row or row["deleted_at"]:
            return jsonify(ok=False, error="这一条已经被删除了"), 404
        d = body()
        old = unpack(row["data_encrypted"])
        if d.get("rev") != row["rev"] and not d.get("force"):
            return jsonify(ok=False, conflict=True, error="这一条刚在别处被修改过",
                           entry=entry_json(row, old, kind)), 409
        incoming = d.get("data") or {}
        if d.get("patch") and isinstance(incoming, dict):
            # 表格里直接改某一格：只改带来的字段，其他（包括密码、附加信息）原样保留
            incoming = dict(old, **{k: v for k, v in incoming.items() if k != "extras"})
        if kind == "item" and isinstance(incoming, dict):
            # 页面没取过密码 / 保密信息时不会带回来：没带的就沿用原来的
            if "password" not in incoming:
                incoming["password"] = old.get("password", "")
            olds = [x for x in old.get("extras") or [] if x.get("secret")]
            for x in incoming.get("extras") or []:
                if isinstance(x, dict) and x.get("secret") and x.get("keep") and x.get("value") in (None, ""):
                    prev = next((o for o in olds if o.get("label") == x.get("label")), None)
                    x["value"] = prev["value"] if prev else ""
        data = (clean_item if kind == "item" else clean_note)(incoming if isinstance(incoming, dict) else {})
        if data is None:
            return jsonify(ok=False, error="什么都没填；不要这一条的话请删除"), 400
        now = core.utc_now_str()
        core.execute("UPDATE vault_entries SET data_encrypted=?, rev=rev+1, updated_at=? WHERE id=?",
                     (pack(data), now, eid))
        return jsonify(ok=True, entry=entry_json(get_row(kind, eid), data, kind))

    @app.route(API_PREFIX + "items/<int:eid>/reveal", methods=["POST"])
    @api_limit
    @login_required
    def vault_reveal(eid):
        row = get_row("item", eid)
        if not row:
            return jsonify(ok=False, error="这一条不存在了，请刷新页面"), 404
        return jsonify(ok=True, entry=entry_json(row, unpack(row["data_encrypted"]), "item", full=True))

    @app.route(API_PREFIX + "<kinds>/<int:eid>", methods=["DELETE"])
    @api_limit
    @login_required
    def vault_delete(kinds, eid):
        kind = kind_of(kinds)
        row = get_row(kind, eid) if kind else None
        if not row:
            return jsonify(ok=False, error="这一条不存在了"), 404
        if request.args.get("purge") == "1":
            if not row["deleted_at"]:
                return jsonify(ok=False, error="请先删除到「最近删除」"), 400
            core.execute("DELETE FROM vault_entries WHERE id=?", (eid,))
        else:
            core.execute("UPDATE vault_entries SET deleted_at=? WHERE id=?", (core.utc_now_str(), eid))
        return jsonify(ok=True)

    @app.route(API_PREFIX + "<kinds>/<int:eid>/restore", methods=["POST"])
    @api_limit
    @login_required
    def vault_restore(kinds, eid):
        kind = kind_of(kinds)
        row = get_row(kind, eid) if kind else None
        if not row:
            return jsonify(ok=False, error="这一条已经彻底删除了"), 404
        core.execute("UPDATE vault_entries SET deleted_at=NULL WHERE id=?", (eid,))
        row = get_row(kind, eid)
        return jsonify(ok=True, entry=entry_json(row, unpack(row["data_encrypted"]), kind))

    @app.route(API_PREFIX + "types", methods=["PUT"])
    @api_limit
    @login_required
    def vault_types():
        d = body()
        types = clean_types(d.get("types"))
        if not types:
            return jsonify(ok=False, error="至少要留一个类型"), 400
        db = core.get_db()
        db.execute("BEGIN IMMEDIATE")
        try:
            row = db.execute("SELECT rev FROM vault_meta WHERE key='types'").fetchone()
            current = row["rev"] if row else 0
            if d.get("rev") != current:
                db.rollback()
                rev, latest = load_types()
                return jsonify(ok=False, conflict=True, error="类型刚在别处改过", types=latest, typesRev=rev), 409
            db.execute("""INSERT INTO vault_meta(key, rev, data_encrypted, updated_at) VALUES ('types',?,?,?)
                          ON CONFLICT(key) DO UPDATE SET rev=excluded.rev, data_encrypted=excluded.data_encrypted,
                          updated_at=excluded.updated_at""", (current + 1, pack(types), core.utc_now_str()))
            db.commit()
        except Exception:
            db.rollback()
            raise
        return jsonify(ok=True, types=types, typesRev=current + 1)
