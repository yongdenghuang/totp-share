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

from migrate import ensure_schema, next_group_color

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

# ---------- 账号密码与分享信息 ----------
MAX_ACCOUNT_PASSWORD = 200
MAX_TEMPLATE_LENGTH = 1000
# 「复制信息」生成的文字。占位符：{分组} {账号} {密码} {链接}
DEFAULT_SHARE_TEMPLATE = (
    "{分组}账号密码\n"
    "帐户：{账号}\n"
    "密码：{密码}\n"
    "验证码获取链接：{链接}"
)

def parse_account_password(raw):
    """账号本身的登录密码。留空 = 不保存（返回 None）；否则返回加密后的密文。"""
    s = (raw or "").strip()
    if not s:
        return None
    if len(s) > MAX_ACCOUNT_PASSWORD:
        raise ValueError(f"账号密码最长 {MAX_ACCOUNT_PASSWORD} 个字符")
    return encrypt_secret(s)

def password_change_sql(row, new_plain):
    """把账号密码改成 new_plain 需要的 SET 片段和参数；没变化时返回空。
    原来有密码的话顺手存成「上一个密码」：经常改密码时，万一官网那边没改成功，
    或者新密码没来得及记下，还能从这里把旧的找回来。
    """
    new_plain = (new_plain or "").strip()
    old_plain = decrypt_account_password(row["password_encrypted"])
    if new_plain == old_plain:
        return [], []
    parts, args = ["password_encrypted=?"], [parse_account_password(new_plain)]
    if old_plain:
        parts.append("password_prev_encrypted=?")
        args.append(row["password_encrypted"])
    return parts, args

def decrypt_account_password(enc):
    if not enc:
        return ""
    try:
        return decrypt_secret(enc)
    except InvalidToken:
        return ""

def render_share_text(template, group, name, password, url):
    """把模板里的占位符换成账号信息。
    账号没存密码时，整行去掉带 {密码} 的那一行，免得发出去一行空的"密码："。
    """
    values = {"分组": group or "", "账号": name, "密码": password or "", "链接": url}
    lines = []
    for line in template.replace("\r\n", "\n").split("\n"):
        if "{密码}" in line and not password:
            continue
        # 一次扫描完成全部替换：密码或账号名里碰巧有 {链接} 这样的字样时不会被二次替换
        lines.append(re.sub(r"\{(分组|账号|密码|链接)\}", lambda m: values[m.group(1)], line))
    return "\n".join(lines).strip()

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
    if request.path.startswith("/t/") or request.path.startswith("/admin"):
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
            if (request.is_json or request.endpoint == "admin_codes"
                    or request.path.startswith("/admin/hezu/api/")):
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
                               password_encrypted IS NOT NULL AS has_password,
                               share_password_hash IS NOT NULL AS has_own_password
                        FROM accounts ORDER BY COALESCE(sort_order, 999999), created_at DESC""")
    last_seen = {r["account_id"]: r["seen"] for r in query_all(
        """SELECT account_id, MAX(last_seen_at) AS seen FROM access_logs
           WHERE event='view' GROUP BY account_id""")}
    name_counts = Counter(norm_name(r["name"]) for r in rows)
    groups = group_rows()
    accounts = [{
        "id": r["id"], "name": r["name"], "url_token": r["url_token"],
        "created_at": r["created_at"],
        "group_name": r["group_name"] or "",
        "has_own_password": bool(r["has_own_password"]),
        "has_password": bool(r["has_password"]),
        "is_duplicate": name_counts[norm_name(r["name"])] > 1,
        "last_seen": last_seen.get(r["id"]),
    } for r in rows]
    styles = {g["name"]: g for g in groups}
    for a in accounts:
        a["group_style"] = styles.get(a["group_name"])
    return render_template("dashboard.html", accounts=accounts, groups=groups,
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

# ---------- 分组 ----------
NEW_GROUP_OPTION = "__new__"   # 账号表单下拉里「＋ 新建分组…」这一项的取值

def parse_group_name(raw):
    s = re.sub(r"\s+", " ", raw or "").strip()[:30]
    return s or None

def parse_color(raw):
    """分组颜色只接受 #rrggbb；颜色会写进页面的 style 属性，必须严格校验。"""
    s = (raw or "").strip().lower()
    if not re.fullmatch(r"#[0-9a-f]{6}", s):
        raise ValueError("颜色格式不正确")
    return s

def text_color_on(bg):
    """在这个底色上用白字还是深色字更清楚（按感知亮度判断）。"""
    r, g, b = (int(bg[i:i + 2], 16) for i in (1, 3, 5))
    return "#1f2937" if (0.299 * r + 0.587 * g + 0.114 * b) > 160 else "#ffffff"

def group_rows():
    """全部分组及其标签配色：[{"name", "color", "text"}]，按创建顺序。"""
    out = []
    for r in query_all("SELECT name, color FROM account_groups ORDER BY COALESCE(sort_order, id), id"):
        color = r["color"] or "#6c757d"
        out.append({"name": r["name"], "color": color, "text": text_color_on(color)})
    return out

def list_groups():
    return [r["name"] for r in query_all("SELECT name FROM account_groups ORDER BY COALESCE(sort_order, id), id")]

def find_group(name):
    """按名称找已有分组（忽略大小写和多余空白），返回库里的规范写法或 None。"""
    key = norm_name(name)
    return next((g for g in list_groups() if norm_name(g) == key), None)

def create_group(raw):
    """新建分组并返回名称；同名分组已存在时直接返回已有的那个。"""
    name = parse_group_name(raw)
    if not name:
        raise ValueError("请填写分组名称")
    if name == NEW_GROUP_OPTION:
        raise ValueError("这个名称不能用作分组名")
    existing = find_group(name)
    if existing:
        return existing
    used = [r["color"] for r in query_all("SELECT color FROM account_groups")]
    execute("INSERT INTO account_groups(name, color, sort_order) "
            "VALUES (?, ?, (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM account_groups))",
            (name, next_group_color(used)))
    return name

def save_group_order(names):
    """按 names 的先后保存分组顺序；没列到的分组排在后面，保持原来的相对顺序。"""
    known = list_groups()
    picked = []
    for n in names:
        g = find_group(n)
        if g and g not in picked:
            picked.append(g)
    db = get_db()
    for idx, name in enumerate(picked + [g for g in known if g not in picked]):
        db.execute("UPDATE account_groups SET sort_order=? WHERE name=?", (idx + 1, name))
    db.commit()

def resolve_group(raw):
    """把提交上来的分组名对应到已有分组。留空 = 未分组（返回 None）。"""
    name = parse_group_name(raw)
    if not name:
        return None
    existing = find_group(name)
    if not existing:
        raise ValueError(f"分组「{name}」不存在，请先新建")
    return existing

def group_from_form(form):
    """账号表单：下拉选了已有分组，或选「新建分组」并填了新名字。"""
    choice = form.get("group_name", "")
    if choice == NEW_GROUP_OPTION:
        return create_group(form.get("new_group", ""))
    return resolve_group(choice)

# ---------- 账号表单 ----------

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
    rows = query_all("SELECT id, name FROM accounts ORDER BY id")
    return {
        "group_options": list_groups(),
        "new_group_option": NEW_GROUP_OPTION,
        "existing_names": [r["name"] for r in rows if r["id"] != exclude_id],
        "share_pw_enabled": get_setting("share_password_enabled") == "1",
    }

@app.route("/admin/accounts/new", methods=["GET", "POST"])
@login_required
def account_new():
    error = None
    dup_warning = None
    # 从合租账本点「新建验证码账号」过来时，名称已经带在地址里
    form_data = {"name": request.args.get("name", "").strip()[:100],
                 "secret": "", "group_name": "", "new_group": "",
                 "link_password": "", "account_password": ""}
    if request.method == "POST":
        form_data["name"] = request.form.get("name", "").strip()[:100]
        form_data["secret"] = request.form.get("secret", "").strip()
        form_data["group_name"] = request.form.get("group_name", "").strip()
        form_data["new_group"] = request.form.get("new_group", "").strip()
        form_data["link_password"] = request.form.get("link_password", "")
        form_data["account_password"] = request.form.get("account_password", "").strip()
        if not form_data["name"]:
            error = "请填写账号名称"
        else:
            try:
                secret_norm = validate_base32(form_data["secret"])
                pyotp.TOTP(secret_norm).now()
                link_pw_hash = parse_link_password(form_data["link_password"])
                account_pw = parse_account_password(form_data["account_password"])
                if form_data["group_name"] != NEW_GROUP_OPTION:
                    resolve_group(form_data["group_name"])   # 先校验，别等到确认重名之后才报错
                dups = find_same_name(form_data["name"])
                if dups and request.form.get("confirm_duplicate") != "1":
                    dup_warning = duplicate_warning(dups)
                else:
                    group = group_from_form(request.form)
                    token = new_token()
                    execute("""INSERT INTO accounts(
                                 name, secret_encrypted, url_token, url_token_hash,
                                 group_name, share_password_hash, password_encrypted)
                               VALUES (?,?,?,?, ?,?,?)""",
                            (form_data["name"], encrypt_secret(secret_norm),
                             token, hash_token(token), group, link_pw_hash, account_pw))
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
               "new_group": "",
               # 编辑页直接带出已保存的账号密码：清空再保存 = 删除
               "account_password": decrypt_account_password(row["password_encrypted"]),
               "link_password": "", "has_own_password": bool(row["share_password_hash"])}
    if request.method == "POST":
        account["name"] = request.form.get("name", "").strip()[:100]
        account["secret"] = request.form.get("secret", "").strip()
        account["group_name"] = request.form.get("group_name", "").strip()
        account["new_group"] = request.form.get("new_group", "").strip()
        account["link_password"] = request.form.get("link_password", "")
        account["account_password"] = request.form.get("account_password", "").strip()
        regen = request.form.get("regen_url") == "1"
        clear_pw = request.form.get("clear_link_password") == "1"
        account["regen_url"] = regen
        account["clear_link_password"] = clear_pw
        if not account["name"]:
            error = "请填写账号名称"
        else:
            try:
                link_pw_hash = parse_link_password(account["link_password"])
                if account["group_name"] != NEW_GROUP_OPTION:
                    resolve_group(account["group_name"])
                sql_parts = ["name=?"]
                args = [account["name"]]
                pw_sql, pw_args = password_change_sql(row, account["account_password"])
                sql_parts += pw_sql
                args += pw_args
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
                    sql_parts.append("group_name=?")
                    args.append(group_from_form(request.form))
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

@app.route("/admin/accounts/<int:aid>/share-text", methods=["POST"])
@login_required
def account_share_text(aid):
    """「复制信息」：按模板拼出可以直接发给合租人的文字（分组、账号、密码、验证码链接）。
    用 POST + CSRF，密码明文只在管理员点按钮时才下发，不放进列表页的 HTML。
    """
    row = query_one("SELECT name, group_name, url_token, password_encrypted "
                    "FROM accounts WHERE id=?", (aid,))
    if not row:
        return jsonify(ok=False, error="账号不存在"), 404
    password = decrypt_account_password(row["password_encrypted"])
    text = render_share_text(
        get_setting("share_template") or DEFAULT_SHARE_TEMPLATE,
        row["group_name"], row["name"], password,
        request.host_url.rstrip("/") + "/t/" + row["url_token"])
    return jsonify(ok=True, text=text, has_password=bool(password))

@app.route("/admin/accounts/<int:aid>/password/reveal", methods=["POST"])
@login_required
def account_password_reveal(aid):
    """「改密码」弹窗用：取当前密码和上一个密码（去官网改密码时通常要先填当前密码）。"""
    row = query_one("SELECT password_encrypted, password_prev_encrypted FROM accounts WHERE id=?", (aid,))
    if not row:
        return jsonify(ok=False, error="账号不存在"), 404
    return jsonify(ok=True,
                   password=decrypt_account_password(row["password_encrypted"]),
                   previous=decrypt_account_password(row["password_prev_encrypted"]))

@app.route("/admin/accounts/<int:aid>/password", methods=["POST"])
@login_required
def account_password_save(aid):
    """「改密码」弹窗用：把新密码存下来，原密码转存为「上一个密码」。"""
    row = query_one("SELECT password_encrypted FROM accounts WHERE id=?", (aid,))
    if not row:
        return jsonify(ok=False, error="账号不存在"), 404
    data = request.get_json(silent=True) or {}
    new_plain = str(data.get("password") or "").strip()
    if not new_plain:
        return jsonify(ok=False, error="新密码不能为空（要删除密码请到「编辑」里清空）"), 400
    try:
        parts, args = password_change_sql(row, new_plain)
    except ValueError as e:
        return jsonify(ok=False, error=str(e)), 400
    if parts:
        execute(f"UPDATE accounts SET {', '.join(parts)} WHERE id=?", args + [aid])
    return jsonify(ok=True, changed=bool(parts))

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
    """列表页内联编辑。接收 JSON: {"field": "group_name" | "name", "value": "..."}
    开放分组和账号名（合租账本里改账号名时同步过来）；返回 {"ok": True, "display": "...", "raw_value": "..."}
    """
    data = request.get_json(silent=True) or {}
    if data.get("field") not in ("group_name", "name"):
        return jsonify(ok=False, error="不允许的字段"), 400
    if not query_one("SELECT 1 FROM accounts WHERE id=?", (aid,)):
        return jsonify(ok=False, error="账号不存在"), 404
    raw = data.get("value")
    if data["field"] == "name":
        name = str(raw or "").strip()[:100]
        if not name:
            return jsonify(ok=False, error="账号名称不能为空"), 400
        execute("UPDATE accounts SET name=? WHERE id=?", (name, aid))
        return jsonify(ok=True, display=name, raw_value=name)
    try:
        group = resolve_group(str(raw) if raw is not None else "")
    except ValueError as e:
        return jsonify(ok=False, error=str(e)), 400
    execute("UPDATE accounts SET group_name=? WHERE id=?", (group, aid))
    return jsonify(ok=True, display=group or "-", raw_value=group or "")

# ---------- 分组管理 ----------
@app.route("/admin/groups", methods=["GET", "POST"])
@login_required
def groups_page():
    error = None; msg = None
    if request.method == "POST":
        action = request.form.get("action")
        try:
            if action == "add":
                raw = request.form.get("name", "")
                if parse_group_name(raw) and find_group(raw):
                    raise ValueError(f"分组「{find_group(raw)}」已存在")
                msg = f"已新建分组「{create_group(raw)}」"
            elif action == "rename":
                old = find_group(request.form.get("old_name", ""))
                new = parse_group_name(request.form.get("name", ""))
                if not old:
                    raise ValueError("分组不存在")
                if not new or new == NEW_GROUP_OPTION:
                    raise ValueError("请填写新的分组名称")
                clash = find_group(new)
                if clash and clash != old:
                    raise ValueError(f"分组「{clash}」已存在")
                color = request.form.get("color")
                color = parse_color(color) if color else None   # 没带颜色 = 不改颜色
                db = get_db()   # 分组表和账号上的分组名一起改，要么都成要么都不成
                if color:
                    db.execute("UPDATE account_groups SET color=? WHERE name=?", (color, old))
                db.execute("UPDATE account_groups SET name=? WHERE name=?", (new, old))
                db.execute("UPDATE accounts SET group_name=? WHERE group_name=?", (new, old))
                db.commit()
                msg = f"已把「{old}」改名为「{new}」" if new != old else f"已保存「{new}」"
            elif action == "move":
                old = find_group(request.form.get("old_name", ""))
                if not old:
                    raise ValueError("分组不存在")
                names = list_groups()
                i = names.index(old)
                j = i - 1 if request.form.get("direction") == "up" else i + 1
                if 0 <= j < len(names):
                    names[i], names[j] = names[j], names[i]
                    save_group_order(names)
            elif action == "delete":
                old = find_group(request.form.get("old_name", ""))
                if not old:
                    raise ValueError("分组不存在")
                db = get_db()
                db.execute("UPDATE accounts SET group_name=NULL WHERE group_name=?", (old,))
                db.execute("DELETE FROM account_groups WHERE name=?", (old,))
                db.commit()
                msg = f"已删除分组「{old}」，组内账号变为未分组"
        except ValueError as e:
            error = str(e)
    counts = {r["group_name"]: r["n"] for r in query_all(
        "SELECT group_name, COUNT(*) AS n FROM accounts "
        "WHERE group_name IS NOT NULL GROUP BY group_name")}
    return render_template("groups.html", error=error, msg=msg,
                           groups=[dict(g, count=counts.get(g["name"], 0)) for g in group_rows()])

@app.route("/admin/groups/reorder", methods=["POST"])
@login_required
def groups_reorder():
    """拖动分组标签调整顺序。请求体: {"order": ["分组名", ...]}，验证码列表和合租账本共用这个顺序。"""
    data = request.get_json(silent=True) or {}
    order = data.get("order")
    if not isinstance(order, list) or len(order) > 500 or not all(isinstance(x, str) for x in order):
        return jsonify(ok=False, error="参数错误"), 400
    save_group_order(order)
    return jsonify(ok=True, groups=list_groups())

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
        elif action == "share_template":
            tpl = request.form.get("share_template", "").replace("\r\n", "\n").strip()
            if len(tpl) > MAX_TEMPLATE_LENGTH:
                error = f"模板最长 {MAX_TEMPLATE_LENGTH} 个字符"
            elif not tpl or tpl == DEFAULT_SHARE_TEMPLATE:
                execute("DELETE FROM settings WHERE key='share_template'")
                msg = "已恢复默认的分享信息模板"
            else:
                set_setting("share_template", tpl)
                msg = "分享信息模板已保存"
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
                           share_template=get_setting("share_template") or DEFAULT_SHARE_TEMPLATE,
                           share_template_is_default=not get_setting("share_template"),
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

# ---------- 合租账本 ----------
import sys      # noqa: E402
import hezu     # noqa: E402
hezu.install(sys.modules[__name__])

if __name__ == "__main__":
    app.run(host=os.environ.get("BIND_ADDR", "127.0.0.1"),
            port=int(os.environ.get("PORT", "5000")), debug=False)
