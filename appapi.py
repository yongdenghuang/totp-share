"""给 iOS App 用的 JSON 接口。

App 和网页共用同一套登录会话（cookie）和防伪令牌：先 GET session 拿到令牌，之后的 POST/DELETE 都在
X-CSRFToken 头里带上。网页已有的 JSON 接口（验证码、改密码、换链接、密码本、备忘录、合租账本……）App 直接复用，
这里只补网页上原本是 HTML 页面或表单的那几样：登录、退出、验证码账号列表、删除账号。

由 app.py 末尾调用 install() 接入；这里不直接 import app，避免循环引用。
"""
from collections import Counter

from flask import jsonify, request, session
from flask_wtf.csrf import generate_csrf

PREFIX = "/api/app/"


def install(core):
    app, limiter, login_required = core.app, core.limiter, core.login_required

    def body():
        d = request.get_json(silent=True)
        return d if isinstance(d, dict) else {}

    def base_url():
        return request.host_url.rstrip("/")

    @app.route(PREFIX + "session")
    @limiter.limit("60 per minute")
    def app_session():
        """打开 App 时先问一下：登录着没有，顺便拿防伪令牌（登录表单也要用）。"""
        ok = core.admin_session_valid()
        if ok:
            session["last_active"] = int(core.time.time())
        return jsonify(ok=True, loggedIn=bool(ok), user=session.get("admin_user") if ok else None,
                       remember=bool(session.get("remember")) if ok else False, csrf=generate_csrf())

    @app.route(PREFIX + "login", methods=["POST"])
    @limiter.limit("5 per minute; 20 per hour")
    def app_login():
        d = body()
        if not core.admin_sign_in(str(d.get("username") or ""), str(d.get("password") or ""),
                                  bool(d.get("remember", True))):
            return jsonify(ok=False, error="用户名或密码错误"), 401
        return jsonify(ok=True, user=session.get("admin_user"), csrf=generate_csrf())

    @app.route(PREFIX + "logout", methods=["POST"])
    def app_logout():
        session.clear()
        return jsonify(ok=True, csrf=generate_csrf())

    @app.route(PREFIX + "accounts")
    @limiter.limit("120 per minute")
    @login_required
    def app_accounts():
        """验证码账号列表（不含密钥和密码）+ 分组（顺序、颜色）。验证码本身用 /admin/codes 取。"""
        rows = core.query_all(
            """SELECT id, name, url_token, created_at, group_name,
                      password_encrypted IS NOT NULL AS has_password
               FROM accounts ORDER BY COALESCE(sort_order, 999999), created_at DESC""")
        last_seen = {r["account_id"]: r["seen"] for r in core.query_all(
            """SELECT account_id, MAX(last_seen_at) AS seen FROM access_logs
               WHERE event='view' GROUP BY account_id""")}
        dup = Counter(core.norm_name(r["name"]) for r in rows)
        accounts = [{
            "id": r["id"], "name": r["name"], "group": r["group_name"] or "",
            "hasPassword": bool(r["has_password"]),
            "shareUrl": base_url() + "/t/" + r["url_token"],
            "lastSeen": core.cn_time(last_seen[r["id"]], "%m-%d %H:%M") if last_seen.get(r["id"]) else "",
            "duplicate": dup[core.norm_name(r["name"])] > 1,
        } for r in rows]
        groups = [{"name": g["name"], "color": g["color"], "text": core.text_color_on(g["color"])}
                  for g in core.group_rows()]
        return jsonify(ok=True, accounts=accounts, groups=groups, csrf=generate_csrf())

    @app.route(PREFIX + "accounts/<int:aid>", methods=["DELETE"])
    @login_required
    def app_account_delete(aid):
        if not core.query_one("SELECT 1 FROM accounts WHERE id=?", (aid,)):
            return jsonify(ok=False, error="账号不存在"), 404
        core.execute("DELETE FROM accounts WHERE id=?", (aid,))
        return jsonify(ok=True)
