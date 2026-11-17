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

    # ---------- 访问记录 ----------
    @app.route(PREFIX + "logs")
    @limiter.limit("60 per minute")
    @login_required
    def app_logs():
        core.execute("DELETE FROM access_logs WHERE last_seen_at<?", (core.utc_now_str(-core.LOG_RETENTION_DAYS * 86400),))
        aid = request.args.get("account", type=int)
        page = max(request.args.get("page", 1, type=int), 1)
        where, args = ("WHERE account_id=?", [aid]) if aid else ("", [])
        size = core.LOG_PAGE_SIZE
        rows = core.query_all(f"SELECT * FROM access_logs {where} ORDER BY last_seen_at DESC, id DESC LIMIT ? OFFSET ?",
                              args + [size + 1, (page - 1) * size])
        logs = [{"id": r["id"], "accountId": r["account_id"], "account": r["account_name"], "event": r["event"],
                 "ip": r["ip"] or "", "country": r["country"] or "", "userAgent": r["user_agent"] or "",
                 "first": core.cn_time(r["created_at"], "%m-%d %H:%M"), "last": core.cn_time(r["last_seen_at"], "%m-%d %H:%M"),
                 "hits": r["hits"]} for r in rows[:size]]
        accounts = [{"id": r["id"], "name": r["name"]} for r in core.query_all(
            "SELECT id, name FROM accounts ORDER BY COALESCE(sort_order, 999999), created_at DESC")]
        return jsonify(ok=True, logs=logs, hasNext=len(rows) > size, page=page, accounts=accounts,
                       retentionDays=core.LOG_RETENTION_DAYS, mergeMinutes=core.LOG_MERGE_SECONDS // 60)

    # ---------- 设置 ----------
    @app.route(PREFIX + "settings")
    @login_required
    def app_settings():
        tpl = core.get_setting("share_template")
        return jsonify(ok=True, username=session.get("admin_user", ""),
                       sharePasswordEnabled=core.get_setting("share_password_enabled") == "1",
                       sharePasswordSet=bool(core.get_setting("share_password_hash")),
                       shareTemplate=tpl or core.DEFAULT_SHARE_TEMPLATE, shareTemplateDefault=not tpl,
                       defaultShareTemplate=core.DEFAULT_SHARE_TEMPLATE, maxTemplate=core.MAX_TEMPLATE_LENGTH)

    @app.route(PREFIX + "settings/share-password", methods=["POST"])
    @login_required
    def app_share_password():
        d = body()
        if not d.get("enabled"):
            core.set_setting("share_password_enabled", "0")
            return jsonify(ok=True, message="已关闭密码保护")
        pw = str(d.get("password") or "")
        if pw:
            if len(pw) < 4:
                return jsonify(ok=False, error="分享密码至少 4 位"), 400
            core.set_setting("share_password_hash", core.PH.hash(pw))
        elif not core.get_setting("share_password_hash"):
            return jsonify(ok=False, error="首次开启请设置密码"), 400
        core.set_setting("share_password_enabled", "1")
        return jsonify(ok=True, message="已开启密码保护" + ("并更新密码" if pw else ""))

    @app.route(PREFIX + "settings/share-template", methods=["POST"])
    @login_required
    def app_share_template():
        tpl = str(body().get("template") or "").replace("\r\n", "\n").strip()
        if len(tpl) > core.MAX_TEMPLATE_LENGTH:
            return jsonify(ok=False, error=f"模板最长 {core.MAX_TEMPLATE_LENGTH} 个字符"), 400
        if not tpl or tpl == core.DEFAULT_SHARE_TEMPLATE:
            core.execute("DELETE FROM settings WHERE key='share_template'")
            return jsonify(ok=True, message="已恢复默认的分享信息模板")
        core.set_setting("share_template", tpl)
        return jsonify(ok=True, message="分享信息模板已保存")

    def check_admin_password(pw):
        row = core.query_one("SELECT password_hash FROM admin WHERE id=?", (session["admin_id"],))
        try:
            core.PH.verify(row["password_hash"], pw or "")
            return True
        except Exception:
            return False

    @app.route(PREFIX + "settings/admin-password", methods=["POST"])
    @limiter.limit("5 per minute")
    @login_required
    def app_admin_password():
        d = body()
        new = str(d.get("new") or "")
        if len(new) < 12:
            return jsonify(ok=False, error="新密码至少 12 位"), 400
        if not check_admin_password(str(d.get("old") or "")):
            return jsonify(ok=False, error="原密码错误"), 400
        new_hash = core.PH.hash(new)
        core.execute("UPDATE admin SET password_hash=? WHERE id=?", (new_hash, session["admin_id"]))
        session["pwfp"] = core._session_fingerprint(new_hash)    # 本机保持登录，其他设备全部退出
        return jsonify(ok=True, message="管理员密码已修改，其他设备上的登录已全部退出")

    @app.route(PREFIX + "settings/username", methods=["POST"])
    @limiter.limit("5 per minute")
    @login_required
    def app_username():
        d = body()
        new_u = str(d.get("username") or "").strip()
        if not (2 <= len(new_u) <= 64):
            return jsonify(ok=False, error="新用户名需在 2-64 个字符之间"), 400
        if not check_admin_password(str(d.get("password") or "")):
            return jsonify(ok=False, error="密码错误"), 400
        if core.query_one("SELECT 1 FROM admin WHERE username=? AND id<>?", (new_u, session["admin_id"])):
            return jsonify(ok=False, error="该用户名已被占用"), 400
        core.execute("UPDATE admin SET username=? WHERE id=?", (new_u, session["admin_id"]))
        session["admin_user"] = new_u
        return jsonify(ok=True, message=f"用户名已修改为「{new_u}」", username=new_u)

    # ---------- 分组（和验证码账号、合租账本共用） ----------
    def groups_payload():
        counts = {r["group_name"]: r["n"] for r in core.query_all(
            "SELECT group_name, COUNT(*) AS n FROM accounts WHERE group_name IS NOT NULL GROUP BY group_name")}
        return [dict(g, count=counts.get(g["name"], 0)) for g in core.group_rows()]

    @app.route(PREFIX + "groups")
    @login_required
    def app_groups():
        return jsonify(ok=True, groups=groups_payload())

    @app.route(PREFIX + "groups", methods=["POST"])
    @login_required
    def app_group_add():
        raw = str(body().get("name") or "")
        try:
            if core.parse_group_name(raw) and core.find_group(raw):
                raise ValueError(f"分组「{core.find_group(raw)}」已存在")
            name = core.create_group(raw)
        except ValueError as e:
            return jsonify(ok=False, error=str(e)), 400
        return jsonify(ok=True, name=name, groups=groups_payload())

    @app.route(PREFIX + "groups/update", methods=["POST"])
    @login_required
    def app_group_update():
        """改名 / 换颜色。账号上的分组名一起改，要么都成要么都不成。"""
        d = body()
        old = core.find_group(str(d.get("old") or ""))
        new = core.parse_group_name(str(d.get("name") or ""))
        try:
            if not old:
                raise ValueError("分组不存在")
            if not new or new == core.NEW_GROUP_OPTION:
                raise ValueError("请填写分组名称")
            clash = core.find_group(new)
            if clash and clash != old:
                raise ValueError(f"分组「{clash}」已存在")
            color = core.parse_color(d["color"]) if d.get("color") else None
        except ValueError as e:
            return jsonify(ok=False, error=str(e)), 400
        db = core.get_db()
        if color:
            db.execute("UPDATE account_groups SET color=? WHERE name=?", (color, old))
        db.execute("UPDATE account_groups SET name=? WHERE name=?", (new, old))
        db.execute("UPDATE accounts SET group_name=? WHERE group_name=?", (new, old))
        db.commit()
        return jsonify(ok=True, groups=groups_payload())

    @app.route(PREFIX + "groups/delete", methods=["POST"])
    @login_required
    def app_group_delete():
        old = core.find_group(str(body().get("name") or ""))
        if not old:
            return jsonify(ok=False, error="分组不存在"), 404
        db = core.get_db()
        db.execute("UPDATE accounts SET group_name=NULL WHERE group_name=?", (old,))
        db.execute("DELETE FROM account_groups WHERE name=?", (old,))
        db.commit()
        return jsonify(ok=True, groups=groups_payload())
