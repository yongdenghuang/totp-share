"""TOTP-Share: TOTP 账号管理与验证码分享（v3）"""
import os
import sqlite3
import secrets
import hashlib
import re
import time
from collections import Counter
from datetime import datetime, timedelta, timezone
from functools import wraps

import pyotp
from flask import (Flask, g, request, session, redirect, url_for,
                   render_template, flash, abort, jsonify)
from flask_wtf.csrf import CSRFProtect
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError, VerificationError, InvalidHashError
from cryptography.fernet import Fernet, InvalidToken

from migrate import ensure_schema

app = Flask(__name__)
app.config.update(
    SECRET_KEY=os.environ["SECRET_KEY"],
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
    SESSION_COOKIE_SECURE=True,
    PERMANENT_SESSION_LIFETIME=timedelta(minutes=30),
    WTF_CSRF_TIME_LIMIT=3600,
    MAX_CONTENT_LENGTH=64 * 1024,
)
app.json.ensure_ascii = False
DATABASE = os.environ["DATABASE_PATH"]
FERNET = Fernet(os.environ["FERNET_KEY"].encode())
PH = PasswordHasher()

# 启动时把数据库补齐到当前结构（幂等，只加表加列）
_conn = sqlite3.connect(DATABASE)
try:
    ensure_schema(_conn)
finally:
    _conn.close()


def client_ip():
    """访客真实 IP。
    经 Cloudflare 隧道进来的请求，连接来源是本机回环地址，此时才信任
    CF-Connecting-IP；直连端口的请求一律用连接地址，避免伪造请求头。
    """
    addr = get_remote_address() or ""
    if addr in ("127.0.0.1", "::1"):
        fwd = request.headers.get("CF-Connecting-IP", "").strip()
        if fwd:
            return fwd[:64]
    return addr


csrf = CSRFProtect(app)
limiter = Limiter(client_ip, app=app,
                  default_limits=["300 per hour"],
                  storage_uri="memory://",
                  strategy="fixed-window")

# ---------- 常量 ----------
TOTP_STEP = 30
# 管理员无操作多久后需要重新登录。列表页自动刷新验证码的请求不算"操作"，
# 否则开着页面就永远不会过期。
ADMIN_IDLE_SECONDS = 30 * 60
# 访问记录：同一访客在这段时间内的连续访问合并成一条
LOG_MERGE_SECONDS = 300
LOG_RETENTION_DAYS = 180
LOG_PAGE_SIZE = 100
TS_FORMAT = "%Y-%m-%d %H:%M:%S"            # 数据库里一律存 UTC
TZ_DISPLAY = timezone(timedelta(hours=8))  # 页面按北京时间显示

# ---------- 数据库 ----------
def get_db():
    if "db" not in g:
        db = sqlite3.connect(DATABASE, detect_types=sqlite3.PARSE_DECLTYPES)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA journal_mode=WAL")
        db.execute("PRAGMA synchronous=NORMAL")
        db.execute("PRAGMA busy_timeout=5000")
        db.execute("PRAGMA foreign_keys=ON")
        g.db = db
    return g.db

@app.teardown_appcontext
def close_db(exc):
    db = g.pop("db", None)
    if db is not None:
        db.close()

def query_one(sql, args=()):
    cur = get_db().execute(sql, args)
    row = cur.fetchone(); cur.close(); return row

def query_all(sql, args=()):
    cur = get_db().execute(sql, args)
    rows = cur.fetchall(); cur.close(); return rows

def execute(sql, args=()):
    db = get_db(); cur = db.execute(sql, args); db.commit()
    last = cur.lastrowid; cur.close(); return last

# ---------- 工具函数 ----------
def hash_token(token):
    return hashlib.sha256(token.encode()).hexdigest()

def new_token():
    return secrets.token_urlsafe(9)

def encrypt_secret(raw):
    return FERNET.encrypt(raw.encode())

def decrypt_secret(enc):
    return FERNET.decrypt(enc).decode()

def validate_base32(s):
    import base64
    s = re.sub(r"[\s-]", "", s).upper()
    if not re.fullmatch(r"[A-Z2-7]+=*", s):
        raise ValueError("TOTP 密钥必须为 Base32 格式（A-Z, 2-7）")
    if len(s.rstrip("=")) < 16:
        raise ValueError("TOTP 密钥过短（至少 16 个 Base32 字符）")
    try:
        base64.b32decode(s, casefold=False)
    except Exception:
        raise ValueError("TOTP 密钥 Base32 解码失败")
    return s

def get_setting(key, default=""):
    row = query_one("SELECT value FROM settings WHERE key=?", (key,))
    return row["value"] if row else default

def set_setting(key, value):
    execute("INSERT INTO settings(key,value) VALUES(?,?) "
            "ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, value))

# ---------- 重名检查 ----------
def norm_name(s):
    """比较名称时忽略大小写和多余空白。"""
    return re.sub(r"\s+", " ", s or "").strip().casefold()

def find_same_name(name, exclude_id=None):
    key = norm_name(name)
    return [r for r in query_all("SELECT id, name, created_at FROM accounts ORDER BY id")
            if norm_name(r["name"]) == key and r["id"] != exclude_id]

def duplicate_warning(dups):
    names = "、".join(f"「{d['name']}」（{str(d['created_at'])[:10]} 创建）" for d in dups[:3])
    return f"已存在同名账号 {names}。确认不是重复添加的话，请再点一次保存。"

# ---------- 分享密码 ----------
def required_share_hash(row):
    """此链接需要校验的密码哈希；None 表示不需要密码。
    账号的单独密码优先；没有单独密码时跟随「设置」里的统一密码。
    """
    if row["share_password_hash"]:
        return row["share_password_hash"]
    if get_setting("share_password_enabled") == "1":
        return get_setting("share_password_hash")
    return None

def _share_session_key(account_id):
    return "share_ok_" + str(account_id)

def _hash_fingerprint(pw_hash):
    return hashlib.sha256(pw_hash.encode()).hexdigest()[:16]

def share_unlocked(account_id, pw_hash):
    """会话里记的是通过校验时的密码指纹，密码一改，旧会话自动失效。"""
    return session.get(_share_session_key(account_id)) == _hash_fingerprint(pw_hash)

# ---------- 访问记录 ----------
def utc_now_str(delta_seconds=0):
    return (datetime.now(timezone.utc) + timedelta(seconds=delta_seconds)).strftime(TS_FORMAT)

@app.template_filter("cn_time")
def cn_time(ts, fmt="%m-%d %H:%M"):
    """UTC 时间字符串 → 北京时间。"""
    if not ts:
        return ""
    try:
        dt = datetime.strptime(str(ts)[:19], TS_FORMAT).replace(tzinfo=timezone.utc)
    except ValueError:
        return str(ts)
    return dt.astimezone(TZ_DISPLAY).strftime(fmt)

@app.template_filter("ua_brief")
def ua_brief(ua):
    """把 User-Agent 压缩成「系统 · 浏览器」。"""
    if not ua:
        return "未知设备"
    systems = [("iPhone", "iPhone"), ("iPad", "iPad"), ("Android", "Android"),
               ("Windows", "Windows"), ("Mac OS X", "Mac"), ("Macintosh", "Mac"),
               ("Linux", "Linux")]
    # 顺序有讲究：微信、Edge 的 UA 里也带 Chrome/Safari 字样
    browsers = [("MicroMessenger", "微信"), ("QQ/", "QQ"), ("Edg", "Edge"),
                ("Firefox", "Firefox"), ("CriOS", "Chrome"), ("Chrome", "Chrome"),
                ("Safari", "Safari")]
    os_name = next((label for key, label in systems if key in ua), "")
    browser = next((label for key, label in browsers if key in ua), "")
    return " · ".join(p for p in (os_name, browser) if p) or ua[:30]

def log_access(account_id, account_name, event):
    """记一次分享页访问。event: 'view'（看到验证码）/ 'pw_fail'（密码输错）。
    同一访客（IP + 设备）短时间内的连续访问只更新同一条记录的结束时间和次数；
    分享页每 30 秒自动取一次码，不合并的话一个人挂着页面就会刷出上百条。
    管理员自己点「预览」不记录。写入失败只记日志，不能影响取码。
    """
    if session.get("admin_id"):
        return
    ip = client_ip() or None
    ua = (request.headers.get("User-Agent") or "")[:300] or None
    country = (request.headers.get("CF-IPCountry") or "")[:8] or None
    now = utc_now_str()
    try:
        db = get_db()
        recent = db.execute(
            """SELECT id FROM access_logs
               WHERE account_id=? AND event=? AND ip IS ? AND user_agent IS ?
                 AND last_seen_at>=?
               ORDER BY id DESC LIMIT 1""",
            (account_id, event, ip, ua, utc_now_str(-LOG_MERGE_SECONDS))).fetchone()
        if recent:
            db.execute("UPDATE access_logs SET last_seen_at=?, hits=hits+1 WHERE id=?",
                       (now, recent["id"]))
        else:
            db.execute(
                """INSERT INTO access_logs(account_id, account_name, event, ip, country,
                                           user_agent, created_at, last_seen_at)
                   VALUES (?,?,?,?,?,?,?,?)""",
                (account_id, account_name, event, ip, country, ua, now, now))
        db.commit()
    except sqlite3.Error:
        app.logger.exception("写入访问记录失败")

# ---------- 响应头 ----------
@app.after_request
def set_security_headers(resp):
    resp.headers["X-Frame-Options"] = "DENY"
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["Referrer-Policy"] = "same-origin"
    resp.headers["Content-Security-Policy"] = (
        "default-src 'self'; "
        "script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; "
        "style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; "
        "img-src 'self' data:; "
        "frame-ancestors 'none'; "
        "base-uri 'self'"
    )
    if request.path.startswith("/t/") or request.path == "/admin/codes":
        resp.headers["Cache-Control"] = "no-store, private, max-age=0"
    return resp

# ---------- 登录装饰器 ----------
def login_required(f):
    @wraps(f)
    def wrapper(*a, **kw):
        now = int(time.time())
        logged_in = bool(session.get("admin_id"))
        if logged_in and now - session.get("last_active", now) > ADMIN_IDLE_SECONDS:
            session.clear()
            logged_in = False
        if not logged_in:
            if request.is_json or request.endpoint == "admin_codes":
                return jsonify(ok=False, error="登录已过期，请刷新页面重新登录"), 401
            return redirect(url_for("login", next=request.path))
        if request.endpoint != "admin_codes":
            session["last_active"] = now
        return f(*a, **kw)
    return wrapper

@app.route("/")
def index():
    return redirect(url_for("admin_root"))

@app.route("/admin", methods=["GET"])
def admin_root():
    return redirect(url_for("dashboard") if session.get("admin_id") else url_for("login"))

# ---------- 登录 / 登出 ----------
@app.route("/admin/login", methods=["GET", "POST"])
@limiter.limit("5 per minute; 20 per hour", methods=["POST"])
def login():
    error = None
    if request.method == "POST":
        u = request.form.get("username", "").strip()
        p = request.form.get("password", "")
        row = query_one("SELECT id, username, password_hash FROM admin WHERE username=?", (u,))
        dummy = "$argon2id$v=19$m=65536,t=3,p=4$aaaaaaaaaaaaaaaa$" + "a"*43
        try:
            PH.verify(row["password_hash"] if row else dummy, p)
            if row:
                if PH.check_needs_rehash(row["password_hash"]):
                    execute("UPDATE admin SET password_hash=? WHERE id=?",
                            (PH.hash(p), row["id"]))
                session.clear()
                session.permanent = True
                session["admin_id"] = row["id"]
                session["admin_user"] = row["username"]
                session["last_active"] = int(time.time())
                return redirect(request.args.get("next") or url_for("dashboard"))
        except (VerifyMismatchError, VerificationError, InvalidHashError):
            pass
        error = "用户名或密码错误"
    return render_template("login.html", error=error)

@app.route("/admin/logout", methods=["POST"])
@login_required
def logout():
    session.clear()
    return redirect(url_for("login"))

# ---------- 后台首页 ----------
@app.route("/admin/dashboard")
@login_required
def dashboard():
    rows = query_all("""SELECT id, name, url_token, created_at, group_name,
                               share_password_hash IS NOT NULL AS has_own_password
                        FROM accounts ORDER BY COALESCE(sort_order, 999999), created_at DESC""")
    last_seen = {r["account_id"]: r["seen"] for r in query_all(
        """SELECT account_id, MAX(last_seen_at) AS seen FROM access_logs
           WHERE event='view' GROUP BY account_id""")}
    name_counts = Counter(norm_name(r["name"]) for r in rows)
    accounts = [{
        "id": r["id"], "name": r["name"], "url_token": r["url_token"],
        "created_at": r["created_at"],
        "group_name": r["group_name"] or "",
        "has_own_password": bool(r["has_own_password"]),
        "is_duplicate": name_counts[norm_name(r["name"])] > 1,
        "last_seen": last_seen.get(r["id"]),
    } for r in rows]
    return render_template("dashboard.html", accounts=accounts,
                           base_url=request.host_url.rstrip("/"),
                           share_pw_enabled=get_setting("share_password_enabled") == "1")

@app.route("/admin/codes")
@limiter.limit("120 per minute")
@login_required
def admin_codes():
    """列表页用：一次返回所有账号当前的验证码。"""
    now = int(time.time())
    codes = {}
    for r in query_all("SELECT id, secret_encrypted FROM accounts"):
        try:
            codes[str(r["id"])] = pyotp.TOTP(decrypt_secret(r["secret_encrypted"])).at(now)
        except (InvalidToken, ValueError, TypeError):
            codes[str(r["id"])] = None
    return jsonify(codes=codes, remaining=TOTP_STEP - (now % TOTP_STEP), period=TOTP_STEP)

# ---------- 账号表单 ----------
def parse_group_name(raw):
    s = re.sub(r"\s+", " ", raw or "").strip()[:30]
    return s or None

def parse_link_password(raw):
    """分享链接的单独密码。留空返回 None（表示不修改）。"""
    if not raw:
        return None
    if len(raw) < 4:
        raise ValueError("分享密码至少 4 位")
    if len(raw) > 128:
        raise ValueError("分享密码最长 128 位")
    return PH.hash(raw)

def _form_context(exclude_id=None):
    """账号表单需要的辅助数据：已有分组（下拉提示）、已有名称（输入时即时提示重名）。"""
    rows = query_all("SELECT id, name, group_name FROM accounts ORDER BY id")
    return {
        "group_options": sorted({r["group_name"] for r in rows if r["group_name"]}),
        "existing_names": [r["name"] for r in rows if r["id"] != exclude_id],
        "share_pw_enabled": get_setting("share_password_enabled") == "1",
    }

@app.route("/admin/accounts/new", methods=["GET", "POST"])
@login_required
def account_new():
    error = None
    dup_warning = None
    form_data = {"name": "", "secret": "", "group_name": "", "link_password": ""}
    if request.method == "POST":
        form_data["name"] = request.form.get("name", "").strip()[:100]
        form_data["secret"] = request.form.get("secret", "").strip()
        form_data["group_name"] = request.form.get("group_name", "").strip()
        form_data["link_password"] = request.form.get("link_password", "")
        if not form_data["name"]:
            error = "请填写账号名称"
        else:
            try:
                secret_norm = validate_base32(form_data["secret"])
                pyotp.TOTP(secret_norm).now()
                link_pw_hash = parse_link_password(form_data["link_password"])
                dups = find_same_name(form_data["name"])
                if dups and request.form.get("confirm_duplicate") != "1":
                    dup_warning = duplicate_warning(dups)
                else:
                    token = new_token()
                    execute("""INSERT INTO accounts(
                                 name, secret_encrypted, url_token, url_token_hash,
                                 group_name, share_password_hash)
                               VALUES (?,?,?,?, ?,?)""",
                            (form_data["name"], encrypt_secret(secret_norm),
                             token, hash_token(token),
                             parse_group_name(form_data["group_name"]), link_pw_hash))
                    flash("账号已添加。分享链接：" + request.host_url + "t/" + token, "success")
                    return redirect(url_for("dashboard"))
            except ValueError as e:
                error = str(e)
    return render_template("account_form.html", mode="new", error=error,
                           dup_warning=dup_warning, account=form_data,
                           **_form_context())

@app.route("/admin/accounts/<int:aid>/edit", methods=["GET", "POST"])
@login_required
def account_edit(aid):
    row = query_one("SELECT * FROM accounts WHERE id=?", (aid,))
    if not row: abort(404)
    error = None
    dup_warning = None
    account = {"name": row["name"], "secret": "", "group_name": row["group_name"] or "",
               "link_password": "", "has_own_password": bool(row["share_password_hash"])}
    if request.method == "POST":
        account["name"] = request.form.get("name", "").strip()[:100]
        account["secret"] = request.form.get("secret", "").strip()
        account["group_name"] = request.form.get("group_name", "").strip()
        account["link_password"] = request.form.get("link_password", "")
        regen = request.form.get("regen_url") == "1"
        clear_pw = request.form.get("clear_link_password") == "1"
        account["regen_url"] = regen
        account["clear_link_password"] = clear_pw
        if not account["name"]:
            error = "请填写账号名称"
        else:
            try:
                link_pw_hash = parse_link_password(account["link_password"])
                sql_parts = ["name=?", "group_name=?"]
                args = [account["name"], parse_group_name(account["group_name"])]
                if account["secret"]:
                    s = validate_base32(account["secret"])
                    pyotp.TOTP(s).now()
                    sql_parts.append("secret_encrypted=?")
                    args.append(encrypt_secret(s))
                # 只在改了名字时才查重，免得每次编辑已有的重名账号都被拦一下
                dups = (find_same_name(account["name"], exclude_id=aid)
                        if norm_name(account["name"]) != norm_name(row["name"]) else [])
                if dups and request.form.get("confirm_duplicate") != "1":
                    dup_warning = duplicate_warning(dups)
                else:
                    if regen:
                        t = new_token()
                        sql_parts.append("url_token=?"); args.append(t)
                        sql_parts.append("url_token_hash=?"); args.append(hash_token(t))
                    if link_pw_hash:
                        sql_parts.append("share_password_hash=?"); args.append(link_pw_hash)
                    elif clear_pw:
                        sql_parts.append("share_password_hash=NULL")
                    args.append(aid)
                    execute(f"UPDATE accounts SET {', '.join(sql_parts)} WHERE id=?", args)
                    flash("账号已更新", "success")
                    return redirect(url_for("dashboard"))
            except ValueError as e:
                error = str(e)
    return render_template("account_form.html", mode="edit", error=error,
                           dup_warning=dup_warning, account=account, account_id=aid,
                           **_form_context(exclude_id=aid))

@app.route("/admin/accounts/<int:aid>/delete", methods=["POST"])
@login_required
def account_delete(aid):
    execute("DELETE FROM accounts WHERE id=?", (aid,))
    flash("账号已删除", "success")
    return redirect(url_for("dashboard"))

@app.route("/admin/accounts/<int:aid>/regen", methods=["POST"])
@login_required
def account_regen(aid):
    """一键更换分享链接：生成新链接，旧链接立即失效。"""
    if not query_one("SELECT 1 FROM accounts WHERE id=?", (aid,)):
        return jsonify(ok=False, error="账号不存在"), 404
    token = new_token()
    execute("UPDATE accounts SET url_token=?, url_token_hash=? WHERE id=?",
            (token, hash_token(token), aid))
    return jsonify(ok=True, url_token=token,
                   url=request.host_url.rstrip("/") + "/t/" + token)

@app.route("/admin/accounts/reorder", methods=["POST"])
@login_required
def accounts_reorder():
    """接收拖拽后的新顺序，保存到 sort_order 列。
    请求体: {"order": [id1, id2, id3, ...]}
    """
    data = request.get_json(silent=True) or {}
    order = data.get("order", [])
    if not isinstance(order, list) or not all(isinstance(x, int) for x in order):
        return jsonify(ok=False, error="参数错误"), 400
    if len(order) > 1000:
        return jsonify(ok=False, error="数量过多"), 400
    db = get_db()
    try:
        for idx, aid in enumerate(order):
            db.execute("UPDATE accounts SET sort_order=? WHERE id=?", (idx, aid))
        db.commit()
    except Exception as e:
        return jsonify(ok=False, error=str(e)), 500
    return jsonify(ok=True, count=len(order))

@app.route("/admin/accounts/<int:aid>/field", methods=["POST"])
@login_required
def account_field_update(aid):
    """列表页内联编辑。接收 JSON: {"field": "group_name", "value": "plus"}
    目前只开放分组；返回 {"ok": True, "display": "...", "raw_value": "..."}
    """
    data = request.get_json(silent=True) or {}
    if data.get("field") != "group_name":
        return jsonify(ok=False, error="不允许的字段"), 400
    if not query_one("SELECT 1 FROM accounts WHERE id=?", (aid,)):
        return jsonify(ok=False, error="账号不存在"), 404
    raw = data.get("value")
    group = parse_group_name(str(raw) if raw is not None else "")
    execute("UPDATE accounts SET group_name=? WHERE id=?", (group, aid))
    return jsonify(ok=True, display=group or "-", raw_value=group or "")

# ---------- 设置 ----------
@app.route("/admin/settings", methods=["GET", "POST"])
@login_required
def settings():
    error = None; msg = None
    if request.method == "POST":
        action = request.form.get("action")
        if action == "toggle":
            enabled = request.form.get("share_password_enabled") == "on"
            new_pw = request.form.get("share_password", "")
            if enabled:
                if new_pw:
                    if len(new_pw) < 4:
                        error = "分享密码至少 4 位"
                    else:
                        set_setting("share_password_enabled", "1")
                        set_setting("share_password_hash", PH.hash(new_pw))
                        msg = "已开启密码保护并更新密码"
                else:
                    if not get_setting("share_password_hash"):
                        error = "首次开启请设置密码"
                    else:
                        set_setting("share_password_enabled", "1")
                        msg = "已开启密码保护"
            else:
                set_setting("share_password_enabled", "0")
                msg = "已关闭密码保护"
        elif action == "change_admin_password":
            old = request.form.get("old_password", "")
            new = request.form.get("new_password", "")
            if len(new) < 12:
                error = "新密码至少 12 位"
            else:
                row = query_one("SELECT password_hash FROM admin WHERE id=?", (session["admin_id"],))
                try:
                    PH.verify(row["password_hash"], old)
                    execute("UPDATE admin SET password_hash=? WHERE id=?",
                            (PH.hash(new), session["admin_id"]))
                    msg = "管理员密码已修改"
                except (VerifyMismatchError, VerificationError):
                    error = "原密码错误"
        elif action == "change_admin_username":
            pw = request.form.get("username_password", "")
            new_u = request.form.get("new_username", "").strip()
            if not (2 <= len(new_u) <= 64):
                error = "新用户名需在 2-64 个字符之间"
            else:
                row = query_one("SELECT password_hash FROM admin WHERE id=?", (session["admin_id"],))
                try:
                    PH.verify(row["password_hash"], pw)
                    exists = query_one("SELECT 1 FROM admin WHERE username=? AND id<>?",
                                       (new_u, session["admin_id"]))
                    if exists:
                        error = "该用户名已被占用"
                    else:
                        execute("UPDATE admin SET username=? WHERE id=?",
                                (new_u, session["admin_id"]))
                        session["admin_user"] = new_u
                        msg = f"用户名已修改为「{new_u}」"
                except (VerifyMismatchError, VerificationError):
                    error = "密码错误"
    return render_template("settings.html",
                           share_pw_enabled=get_setting("share_password_enabled") == "1",
                           current_username=session.get("admin_user", ""),
                           error=error, msg=msg)

# ---------- 分享页面 ----------
@app.route("/t/<token>", methods=["GET", "POST"])
@limiter.limit("60 per minute")
@limiter.limit("10 per minute", methods=["POST"])  # 限制猜分享密码的速度
def share_view(token):
    if not token or len(token) > 128:
        abort(404)
    row = query_one(
        """SELECT id, name, secret_encrypted, url_token, share_password_hash
           FROM accounts WHERE url_token_hash=?""",
        (hash_token(token),))
    if not row or not secrets.compare_digest(row["url_token"], token):
        abort(404)

    pw_hash = required_share_hash(row)
    if pw_hash is not None and not share_unlocked(row["id"], pw_hash):
        if request.method == "POST":
            submitted = request.form.get("password", "")
            try:
                PH.verify(pw_hash, submitted)
                session[_share_session_key(row["id"])] = _hash_fingerprint(pw_hash)
                return redirect(request.path)
            except (VerifyMismatchError, VerificationError, InvalidHashError):
                log_access(row["id"], row["name"], "pw_fail")
                return render_template("share_password.html",
                                       name=row["name"], error="密码错误")
        return render_template("share_password.html", name=row["name"])

    try:
        decrypt_secret(row["secret_encrypted"])
    except InvalidToken:
        abort(500)
    log_access(row["id"], row["name"], "view")
    return render_template("share.html", name=row["name"], token=token)

@app.route("/t/<token>/code")
@limiter.limit("120 per minute")
def share_code_api(token):
    row = query_one(
        """SELECT id, name, secret_encrypted, url_token, share_password_hash
           FROM accounts WHERE url_token_hash=?""",
        (hash_token(token),))
    if not row or not secrets.compare_digest(row["url_token"], token):
        abort(404)
    pw_hash = required_share_hash(row)
    if pw_hash is not None and not share_unlocked(row["id"], pw_hash):
        abort(403)
    try:
        totp = pyotp.TOTP(decrypt_secret(row["secret_encrypted"]))
    except InvalidToken:
        abort(500)
    log_access(row["id"], row["name"], "view")
    now = int(time.time())
    return jsonify(code=totp.now(), remaining=TOTP_STEP - (now % TOTP_STEP), period=TOTP_STEP)

# ---------- 访问记录 ----------
@app.route("/admin/logs")
@login_required
def access_logs():
    # 顺手清掉过期记录，省得单独配定时任务
    execute("DELETE FROM access_logs WHERE last_seen_at<?",
            (utc_now_str(-LOG_RETENTION_DAYS * 86400),))
    account_id = request.args.get("account", type=int)
    page = max(request.args.get("page", 1, type=int), 1)
    where, args = "", []
    if account_id:
        where, args = "WHERE account_id=?", [account_id]
    rows = query_all(
        f"""SELECT * FROM access_logs {where}
            ORDER BY last_seen_at DESC, id DESC LIMIT ? OFFSET ?""",
        args + [LOG_PAGE_SIZE + 1, (page - 1) * LOG_PAGE_SIZE])
    return render_template(
        "logs.html", logs=rows[:LOG_PAGE_SIZE], page=page,
        has_next=len(rows) > LOG_PAGE_SIZE, account_id=account_id,
        accounts=query_all("SELECT id, name FROM accounts "
                           "ORDER BY COALESCE(sort_order, 999999), created_at DESC"),
        retention_days=LOG_RETENTION_DAYS, merge_minutes=LOG_MERGE_SECONDS // 60)

@app.errorhandler(404)
def not_found(e):
    return render_template("404.html"), 404

@app.errorhandler(429)
def rate_limited(e):
    return render_template("404.html", rate=True), 429

if __name__ == "__main__":
    app.run(host=os.environ.get("BIND_ADDR", "127.0.0.1"),
            port=int(os.environ.get("PORT", "5000")), debug=False)
