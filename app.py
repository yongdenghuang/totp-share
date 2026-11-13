"""TOTP-Share: 共享 TOTP 验证码 Web 应用（v2）"""
import os
import sqlite3
import secrets
import hashlib
import re
import time
from datetime import date, timedelta
from decimal import Decimal, ROUND_HALF_UP, InvalidOperation
from functools import wraps

import pyotp
from dateutil.relativedelta import relativedelta
from flask import (Flask, g, request, session, redirect, url_for,
                   render_template, flash, abort, jsonify)
from flask_wtf.csrf import CSRFProtect
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError, VerificationError, InvalidHashError
from cryptography.fernet import Fernet, InvalidToken

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

csrf = CSRFProtect(app)
limiter = Limiter(get_remote_address, app=app,
                  default_limits=["300 per hour"],
                  storage_uri="memory://",
                  strategy="fixed-window")

# ---------- 常量 ----------
CURRENCIES = [
    ("CNY", "人民币 CNY"),
    ("USD", "美元 USD"),
    ("HKD", "港币 HKD"),
    ("EUR", "欧元 EUR"),
    ("PHP", "菲律宾比索 PHP"),
    ("TRY", "土耳其里拉 TRY"),
]
VALID_CURRENCIES = {c for c, _ in CURRENCIES}
RENEWAL_PERIODS = [
    (1,  "1 个月"),
    (3,  "3 个月"),
    (6,  "半年（6 个月）"),
    (12, "1 年（12 个月）"),
]
VALID_PERIODS = {1, 3, 6, 12}
# 仅用于排序时跨币种近似比较
FX_TO_CNY = {"CNY": 1.0, "USD": 7.2, "EUR": 7.8, "HKD": 0.92, "PHP": 0.13, "TRY": 0.21}

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
    import re, base64
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

# ---------- 剩余价值计算 ----------
def calc_remaining(renewal_date, period_months, amount, currency, today=None):
    """返回 (display, is_expired, sort_key_cny, has_value)。
    has_value=False 表示字段不全，显示为 '-'。
    """
    if not (renewal_date and period_months and amount and currency):
        return "-", False, "", False
    try:
        r = date.fromisoformat(renewal_date)
        m = int(period_months)
        a = Decimal(str(amount))
    except (ValueError, InvalidOperation, TypeError):
        return "-", False, "", False
    if m not in VALID_PERIODS or a < 0 or currency not in VALID_CURRENCIES:
        return "-", False, "", False
    if today is None:
        today = date.today()
    end = r + relativedelta(months=m)
    total = (end - r).days
    if total <= 0:
        return "-", False, "", False
    if today >= end:
        return "已过期", True, "0.00", True
    if today < r:
        v = a.quantize(Decimal("0.01"), ROUND_HALF_UP)
        rate = FX_TO_CNY.get(currency, 1.0)
        return f"{currency} {v}", False, f"{float(v) * rate:.2f}", True
    remaining_days = total - (today - r).days
    v = (a / Decimal(total)) * Decimal(remaining_days)
    v = v.quantize(Decimal("0.01"), ROUND_HALF_UP)
    rate = FX_TO_CNY.get(currency, 1.0)
    return f"{currency} {v}", False, f"{float(v) * rate:.2f}", True

def amount_cny_str(amount, currency):
    if not amount or not currency:
        return ""
    try:
        return f"{float(amount) * FX_TO_CNY.get(currency, 1.0):.2f}"
    except (ValueError, TypeError):
        return ""

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
    if request.path.startswith("/t/"):
        resp.headers["Cache-Control"] = "no-store, private, max-age=0"
    return resp

# ---------- 登录装饰器 ----------
def login_required(f):
    @wraps(f)
    def wrapper(*a, **kw):
        if not session.get("admin_id"):
            return redirect(url_for("login", next=request.path))
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
    rows = query_all("""SELECT id, name, url_token, created_at,
                               share_count, renewal_period, renewal_date,
                               renewal_amount, currency, recharge_channel,
                               sort_order
                        FROM accounts ORDER BY COALESCE(sort_order, 999999), created_at DESC""")
    accounts = []
    for r in rows:
        disp, is_exp, sort_cny, has_val = calc_remaining(
            r["renewal_date"], r["renewal_period"],
            r["renewal_amount"], r["currency"])
        accounts.append({
            "id": r["id"], "name": r["name"], "url_token": r["url_token"],
            "created_at": r["created_at"],
            "share_count": r["share_count"],
            "renewal_period": r["renewal_period"],
            "renewal_date": r["renewal_date"],
            "renewal_amount": r["renewal_amount"],
            "currency": r["currency"],
            "recharge_channel": r["recharge_channel"],
            "remaining_display": disp,
            "remaining_is_expired": is_exp,
            "remaining_has_value": has_val,
            "remaining_sort_cny": sort_cny,
            "renewal_amount_cny": amount_cny_str(r["renewal_amount"], r["currency"]),
        })
    share_pw_enabled = get_setting("share_password_enabled") == "1"

    # === v2.5 统计与提醒 ===
    PRICE_PER_PERSON = 300  # 每人每月收 300 元
    today = date.today()
    total_share = 0
    total_amount = Decimal("0")
    due_soon = []      # 7 天内到期
    expired = []       # 已过期
    for a in accounts:
        if a.get("share_count"):
            try:
                total_share += int(a["share_count"])
            except (ValueError, TypeError):
                pass
        if a.get("renewal_amount"):
            try:
                total_amount += Decimal(str(a["renewal_amount"]))
            except (InvalidOperation, ValueError):
                pass
        # 到期检查：renewal_date 就是到期日本身
        if a.get("renewal_date"):
            try:
                end = date.fromisoformat(a["renewal_date"])
                days_left = (end - today).days
                a["_days_left"] = days_left
                a["_end_date"] = end.isoformat()
                if days_left < 0:
                    expired.append(a)
                elif days_left <= 7:
                    due_soon.append(a)
            except (ValueError, TypeError):
                pass

    # 合计租金 = 总人数 * 每人价格
    total_rent = total_share * PRICE_PER_PERSON
    total_cost_int = int(total_amount)
    profit = total_rent - total_cost_int

    stats = {
        "account_count": len(accounts),
        "total_share": total_share,
        "total_rent": total_rent,
        "total_cost": total_cost_int,
        "profit": profit,
        "price_per_person": PRICE_PER_PERSON,
    }
    # 按剩余天数排序
    expired.sort(key=lambda x: x.get("_days_left", 0))
    due_soon.sort(key=lambda x: x.get("_days_left", 99))

    return render_template("dashboard.html", accounts=accounts,
                           base_url=request.host_url.rstrip("/"),
                           share_pw_enabled=share_pw_enabled,
                           stats=stats,
                           expired=expired, due_soon=due_soon)

# ---------- 账号表单字段解析 ----------
def _parse_account_fields(form):
    """从 form 中解析新字段，返回 dict 或抛出 ValueError。"""
    out = {}
    sc = form.get("share_count", "").strip()
    if sc:
        try:
            n = int(sc)
            if not (1 <= n <= 99):
                raise ValueError("合租人数需在 1-99 之间")
            out["share_count"] = n
        except ValueError:
            raise ValueError("合租人数必须是 1-99 的整数")
    else:
        out["share_count"] = None

    rp = form.get("renewal_period", "").strip()
    if rp:
        try:
            n = int(rp)
            if n not in VALID_PERIODS:
                raise ValueError("无效的续费周期")
            out["renewal_period"] = n
        except ValueError:
            raise ValueError("无效的续费周期")
    else:
        out["renewal_period"] = None

    rd = form.get("renewal_date", "").strip()
    if rd:
        try:
            date.fromisoformat(rd)
            out["renewal_date"] = rd
        except ValueError:
            raise ValueError("续费日期格式不正确")
    else:
        out["renewal_date"] = None

    ra = form.get("renewal_amount", "").strip()
    if ra:
        try:
            a = Decimal(ra)
            if a < 0:
                raise ValueError("续费金额不能为负数")
            out["renewal_amount"] = str(a)
        except (InvalidOperation, ValueError) as e:
            raise ValueError("续费金额格式不正确" if "decimal" in str(e).lower() else str(e))
    else:
        out["renewal_amount"] = None

    cur = form.get("currency", "").strip()
    if cur:
        if cur not in VALID_CURRENCIES:
            raise ValueError("无效的币种")
        out["currency"] = cur
    else:
        out["currency"] = None

    rc = form.get("recharge_channel", "").strip()[:50]
    out["recharge_channel"] = rc or None

    # v2.3: 填了金额但未指定币种/周期，自动补默认（让剩余价值计算仍可工作）
    if out["renewal_amount"]:
        if not out["currency"]:
            out["currency"] = "CNY"
        if not out["renewal_period"]:
            out["renewal_period"] = 1

    return out

# ---------- 添加账号 ----------
@app.route("/admin/accounts/new", methods=["GET", "POST"])
@login_required
def account_new():
    error = None
    form_data = {"name": "", "secret": ""}
    if request.method == "POST":
        form_data["name"] = request.form.get("name", "").strip()[:100]
        form_data["secret"] = request.form.get("secret", "").strip()
        if not form_data["name"]:
            error = "请填写账号名称"
        else:
            try:
                secret_norm = validate_base32(form_data["secret"])
                pyotp.TOTP(secret_norm).now()
                extra = _parse_account_fields(request.form)
                token = new_token()
                execute("""INSERT INTO accounts(
                             name, secret_encrypted, url_token, url_token_hash,
                             share_count, renewal_period, renewal_date,
                             renewal_amount, currency, recharge_channel)
                           VALUES (?,?,?,?, ?,?,?, ?,?,?)""",
                        (form_data["name"], encrypt_secret(secret_norm),
                         token, hash_token(token),
                         extra["share_count"], extra["renewal_period"],
                         extra["renewal_date"], extra["renewal_amount"],
                         extra["currency"], extra["recharge_channel"]))
                flash("账号已添加。分享链接：" + request.host_url + "t/" + token, "success")
                return redirect(url_for("dashboard"))
            except ValueError as e:
                error = str(e)
    return render_template("account_form.html", mode="new", error=error,
                           account=form_data, currencies=CURRENCIES,
                           periods=RENEWAL_PERIODS)

# ---------- 编辑账号 ----------
@app.route("/admin/accounts/<int:aid>/edit", methods=["GET", "POST"])
@login_required
def account_edit(aid):
    row = query_one("SELECT * FROM accounts WHERE id=?", (aid,))
    if not row: abort(404)
    error = None
    account = dict(row)
    account["secret"] = ""
    if request.method == "POST":
        account["name"] = request.form.get("name", "").strip()[:100]
        account["secret"] = request.form.get("secret", "").strip()
        regen = request.form.get("regen_url") == "1"
        if not account["name"]:
            error = "请填写账号名称"
        else:
            try:
                extra = _parse_account_fields(request.form)
                # 回填到 account 以便重新渲染时保留
                for k, v in extra.items():
                    account[k] = v
                sql_parts, args = ["name=?"], [account["name"]]
                if account["secret"]:
                    s = validate_base32(account["secret"])
                    pyotp.TOTP(s).now()
                    sql_parts.append("secret_encrypted=?")
                    args.append(encrypt_secret(s))
                if regen:
                    t = new_token()
                    sql_parts.append("url_token=?"); args.append(t)
                    sql_parts.append("url_token_hash=?"); args.append(hash_token(t))
                for field in ("share_count", "renewal_period", "renewal_date",
                              "renewal_amount", "currency", "recharge_channel"):
                    sql_parts.append(f"{field}=?")
                    args.append(extra[field])
                args.append(aid)
                execute(f"UPDATE accounts SET {', '.join(sql_parts)} WHERE id=?", args)
                flash("账号已更新", "success")
                return redirect(url_for("dashboard"))
            except ValueError as e:
                error = str(e)
    return render_template("account_form.html", mode="edit", error=error,
                           account=account, account_id=aid,
                           currencies=CURRENCIES, periods=RENEWAL_PERIODS)

@app.route("/admin/accounts/<int:aid>/delete", methods=["POST"])
@login_required
def account_delete(aid):
    execute("DELETE FROM accounts WHERE id=?", (aid,))
    flash("账号已删除", "success")
    return redirect(url_for("dashboard"))

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
    """内联编辑单个字段。接收 JSON: {"field": "share_count", "value": "3"}
    允许字段: share_count, renewal_period, renewal_date,
              renewal_amount, currency, recharge_channel
    返回 JSON: {"ok": True, "display": "...", "sort_value": "..."}
    """
    ALLOWED = {"share_count", "renewal_period", "renewal_date",
               "renewal_amount", "currency", "recharge_channel"}
    data = request.get_json(silent=True) or {}
    field = data.get("field")
    raw = data.get("value")
    if field not in ALLOWED:
        return jsonify(ok=False, error="不允许的字段"), 400
    if raw is not None:
        raw = str(raw).strip()

    # 用现有解析函数的子集来校验
    try:
        parsed = None
        if not raw:
            parsed = None
        elif field == "share_count":
            n = int(raw)
            if not (1 <= n <= 99):
                raise ValueError("合租人数需在 1-99 之间")
            parsed = n
        elif field == "renewal_period":
            n = int(raw)
            if n not in VALID_PERIODS:
                raise ValueError("无效的续费周期（只能是 1/3/6/12）")
            parsed = n
        elif field == "renewal_date":
            # 支持两种输入：完整 YYYY-MM-DD 或只填 MM-DD
            s = raw.strip()
            if re.fullmatch(r"\d{4}-\d{2}-\d{2}", s):
                date.fromisoformat(s)
                parsed = s
            elif re.fullmatch(r"\d{1,2}[-/.]\d{1,2}", s):
                # 解析月日，自动补年份
                sep = "-" if "-" in s else ("/" if "/" in s else ".")
                m_str, d_str = s.split(sep)
                m, d = int(m_str), int(d_str)
                today = date.today()
                try:
                    candidate = date(today.year, m, d)
                except ValueError:
                    raise ValueError("无效的月日")
                # 在今天之后 → 今年；否则 → 明年
                if candidate < today:
                    try:
                        candidate = date(today.year + 1, m, d)
                    except ValueError:
                        raise ValueError("无效的月日")
                parsed = candidate.isoformat()
            else:
                raise ValueError("请输入月-日（如 05-20）")
        elif field == "renewal_amount":
            a = Decimal(raw)
            if a < 0:
                raise ValueError("续费金额不能为负数")
            parsed = str(a)
        elif field == "currency":
            if raw not in VALID_CURRENCIES:
                raise ValueError("无效的币种")
            parsed = raw
        elif field == "recharge_channel":
            parsed = raw[:50]
    except (ValueError, InvalidOperation) as e:
        msg = str(e) if str(e) else "格式不正确"
        return jsonify(ok=False, error=msg), 400

    # 检查 account 存在
    row = query_one("SELECT id FROM accounts WHERE id=?", (aid,))
    if not row:
        return jsonify(ok=False, error="账号不存在"), 404

    execute(f"UPDATE accounts SET {field}=? WHERE id=?", (parsed, aid))

    # v2.3: 编辑 renewal_amount 时自动补币种和周期（如果为空）
    if field == "renewal_amount" and parsed is not None:
        cur_row = query_one("SELECT currency, renewal_period FROM accounts WHERE id=?", (aid,))
        if cur_row:
            if not cur_row["currency"]:
                execute("UPDATE accounts SET currency='CNY' WHERE id=?", (aid,))
            if not cur_row["renewal_period"]:
                execute("UPDATE accounts SET renewal_period=1 WHERE id=?", (aid,))

    # 返回更新后的显示值（给前端渲染）
    row = query_one("""SELECT share_count, renewal_period, renewal_date,
                              renewal_amount, currency, recharge_channel
                       FROM accounts WHERE id=?""", (aid,))
    display = ""
    sort_value = ""
    if field == "share_count":
        display = f"{row['share_count']} 人" if row["share_count"] else "-"
        sort_value = str(row["share_count"]) if row["share_count"] else ""
    elif field == "renewal_date":
        display = row["renewal_date"] or "-"
        sort_value = row["renewal_date"] or ""
    elif field == "renewal_amount" or field == "currency":
        if row["renewal_amount"] and row["currency"]:
            try:
                display = f"{row['currency']} {float(row['renewal_amount']):.2f}"
            except (ValueError, TypeError):
                display = "-"
        else:
            display = "-"
        sort_value = amount_cny_str(row["renewal_amount"], row["currency"])
    elif field == "renewal_period":
        period_map = dict(RENEWAL_PERIODS)
        display = period_map.get(row["renewal_period"], "-") if row["renewal_period"] else "-"
        sort_value = str(row["renewal_period"]) if row["renewal_period"] else ""
    elif field == "recharge_channel":
        display = row["recharge_channel"] or "-"
        sort_value = row["recharge_channel"] or ""

    return jsonify(ok=True, display=display, sort_value=sort_value,
                   raw_value=parsed if parsed is not None else "")



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
def share_view(token):
    if not token or len(token) > 128:
        abort(404)
    row = query_one(
        "SELECT id, name, secret_encrypted, url_token FROM accounts WHERE url_token_hash=?",
        (hash_token(token),))
    if not row or not secrets.compare_digest(row["url_token"], token):
        abort(404)

    pw_enabled = get_setting("share_password_enabled") == "1"
    pw_session_key = "share_ok_" + str(row["id"])
    if pw_enabled and not session.get(pw_session_key):
        if request.method == "POST":
            submitted = request.form.get("password", "")
            stored = get_setting("share_password_hash")
            try:
                PH.verify(stored, submitted)
                session[pw_session_key] = True
                return redirect(request.path)
            except (VerifyMismatchError, VerificationError, InvalidHashError):
                return render_template("share_password.html",
                                       name=row["name"], error="密码错误")
        return render_template("share_password.html", name=row["name"])

    try:
        decrypt_secret(row["secret_encrypted"])
    except InvalidToken:
        abort(500)
    return render_template("share.html", name=row["name"], token=token)

@app.route("/t/<token>/code")
@limiter.limit("120 per minute")
def share_code_api(token):
    row = query_one(
        "SELECT id, secret_encrypted, url_token FROM accounts WHERE url_token_hash=?",
        (hash_token(token),))
    if not row or not secrets.compare_digest(row["url_token"], token):
        abort(404)
    if (get_setting("share_password_enabled") == "1"
            and not session.get("share_ok_" + str(row["id"]))):
        abort(403)
    try:
        totp = pyotp.TOTP(decrypt_secret(row["secret_encrypted"]))
    except InvalidToken:
        abort(500)
    now = int(time.time()); step = 30
    remaining = step - (now % step)
    return jsonify(code=totp.now(), remaining=remaining, period=step)

@app.errorhandler(404)
def not_found(e):
    return render_template("404.html"), 404

@app.errorhandler(429)
def rate_limited(e):
    return render_template("404.html", rate=True), 429

if __name__ == "__main__":
    app.run(host=os.environ.get("BIND_ADDR", "127.0.0.1"),
            port=int(os.environ.get("PORT", "5000")), debug=False)
