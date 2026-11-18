"""GPT 账号：接入用户自己的 sub2api（读账号、额度、智商测试结果，并在 sub2api 里发起授权、测试）。

合租管理不保存任何 GPT 的令牌，只保存 sub2api 的地址和管理员 API Key（Fernet 加密存在 settings 表）。
所有请求由服务器转发到 sub2api（带 x-api-key），页面和 App 只跟本站说话，Key 不会下发到浏览器或手机。

由 app.py 末尾调用 install() 接入。
"""
import json
import urllib.error
import urllib.parse
import urllib.request

from flask import jsonify, render_template, request

PREFIX = "/api/app/gpt/"
TIMEOUT = 25
# 直接连 sub2api，不走系统 / 环境变量里的代理（Key 不能经过第三方代理）
_opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
_core = None


class Sub2apiError(Exception):
    def __init__(self, message, status=502):
        super().__init__(message)
        self.status = status


# ---------- 配置 ----------
def get_config():
    url = (_core.get_setting("sub2api_url") or "").rstrip("/")
    enc = _core.get_setting("sub2api_key_enc")
    key = ""
    if enc:
        try:
            key = _core.FERNET.decrypt(enc.encode()).decode()
        except Exception:
            key = ""
    return url, key


def save_config(url, key):
    _core.set_setting("sub2api_url", url.rstrip("/"))
    if key is not None:
        _core.set_setting("sub2api_key_enc", _core.FERNET.encrypt(key.encode()).decode() if key else "")


def normalize_url(raw):
    u = (raw or "").strip().rstrip("/")
    if "://" in u and not u.lower().startswith(("http://", "https://")):
        raise ValueError("sub2api 地址不对，例如 https://api.example.com")
    if u and not u.lower().startswith(("http://", "https://")):
        u = "https://" + u
    p = urllib.parse.urlparse(u)
    if not u:
        return ""
    if p.scheme not in ("http", "https") or not p.netloc:
        raise ValueError("sub2api 地址不对，例如 https://api.example.com")
    return f"{p.scheme}://{p.netloc}{p.path.rstrip('/')}"


# ---------- 调用 sub2api ----------
def call(method, path, body=None, query=None, url=None, key=None, timeout=TIMEOUT):
    """调用 sub2api 管理接口，返回 data 部分。sub2api 的返回外层是 {code, message, data}。"""
    if url is None or key is None:
        url, key = get_config()
    if not url or not key:
        raise Sub2apiError("还没设置 sub2api 的地址和管理员 API Key", 409)
    full = url + path + ("?" + urllib.parse.urlencode(query, doseq=True) if query else "")
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(full, data=data, method=method, headers={
        "x-api-key": key, "Accept": "application/json", "User-Agent": "totp-share/gptlink",
        **({"Content-Type": "application/json"} if data is not None else {}),
    })
    try:
        with _opener.open(req, timeout=timeout) as r:
            raw = r.read(8 * 1024 * 1024)
    except urllib.error.HTTPError as e:
        msg = ""
        try:
            msg = json.loads(e.read(65536).decode("utf-8", "replace")).get("message") or ""
        except Exception:
            pass
        if e.code == 401:
            raise Sub2apiError("sub2api 拒绝了请求：管理员 API Key 不对或已失效", 502)
        if e.code == 403:
            raise Sub2apiError("sub2api 说这个 Key 没有权限：请用勾选了「全权访问」的管理密钥", 502)
        if e.code == 423:
            raise Sub2apiError("sub2api 要求管理员先在网页后台登录一次并确认合规提示", 502)
        raise Sub2apiError(f"sub2api 返回 {e.code}" + (f"：{msg}" if msg else ""), 502)
    except Exception as e:   # 连不上、超时、证书……
        raise Sub2apiError(f"连不上 sub2api：{e}", 502)
    try:
        d = json.loads(raw.decode("utf-8"))
    except ValueError:
        raise Sub2apiError("sub2api 返回的不是 JSON（地址是不是填成了别的网站？）", 502)
    if isinstance(d, dict) and "code" in d and d.get("code") not in (0, 200, 201, 202):
        raise Sub2apiError(d.get("message") or f"sub2api 出错（{d.get('code')}）", 502)
    return d.get("data") if isinstance(d, dict) and "data" in d else d


def install(core):
    global _core
    _core = core
    app, limiter, login_required = core.app, core.limiter, core.login_required
    gpt_limit = limiter.limit("120 per minute")

    def body():
        d = request.get_json(silent=True)
        return d if isinstance(d, dict) else {}

    @app.errorhandler(Sub2apiError)
    def sub2api_error(e):
        return jsonify(ok=False, error=str(e)), e.status

    @app.route("/admin/gpt")
    @login_required
    def gpt_page():
        return render_template("gpt.html")

    @app.route(PREFIX + "config")
    @gpt_limit
    @login_required
    def gpt_config():
        url, key = get_config()
        return jsonify(ok=True, url=url, hasKey=bool(key))

    @app.route(PREFIX + "config", methods=["POST"])
    @limiter.limit("10 per minute")
    @login_required
    def gpt_config_save():
        d = body()
        try:
            url = normalize_url(d.get("url"))
        except ValueError as e:
            return jsonify(ok=False, error=str(e)), 400
        key = d.get("key")
        key = str(key).strip() if key is not None else None
        old_url, old_key = get_config()
        test_key = key if key else old_key
        if url and test_key:
            call("GET", "/api/v1/admin/accounts", query={"page": 1, "page_size": 1, "platform": "openai"}, url=url, key=test_key)
        save_config(url, key if key else None)
        return jsonify(ok=True, url=url, hasKey=bool(test_key))

    # ---------- 账号列表（额度、智商状态一起） ----------
    PLAN_NAME = "合租管理-糖果测试"

    def pct(extra, win):
        """5h / 7d 用量：重置时间已经过了就当 0（和 sub2api 页面一样）"""
        used = extra.get(f"codex_{win}_used_percent")
        reset = extra.get(f"codex_{win}_reset_at") or ""
        if used is None:
            return {"used": None, "resetAt": reset}
        try:
            from datetime import datetime, timezone
            if reset and datetime.fromisoformat(reset.replace("Z", "+00:00")) <= datetime.now(timezone.utc):
                used = 0
        except ValueError:
            pass
        return {"used": round(float(used), 1), "resetAt": reset}

    def summarize(a, states):
        cred, extra = a.get("credentials") or {}, a.get("extra") or {}
        candy = next((s for s in states if s.get("account_id") == a.get("id") and s.get("kind") == "candy"), None)
        last = (candy or {}).get("last_outcome") or ""
        return {
            "id": a.get("id"), "name": a.get("name") or "", "email": cred.get("email") or "",
            "plan": cred.get("plan_type") or a.get("parent_plan_type") or "",
            "subscriptionExpiresAt": cred.get("subscription_expires_at") or "",
            "status": a.get("status") or "", "error": a.get("error_message") or "",
            "schedulable": bool(a.get("schedulable")), "privacy": extra.get("privacy_mode") or "",
            "rateLimitResetAt": a.get("rate_limit_reset_at") or "", "overloadUntil": a.get("overload_until") or "",
            "tempUnschedulableUntil": a.get("temp_unschedulable_until") or "",
            "lastUsedAt": a.get("last_used_at") or "", "createdAt": a.get("created_at") or "", "notes": a.get("notes") or "",
            "groups": [g.get("name") for g in a.get("groups") or [] if isinstance(g, dict)],
            "fiveHour": pct(extra, "5h"), "sevenDay": pct(extra, "7d"),
            "usageUpdatedAt": extra.get("codex_usage_updated_at") or "",
            "iq": {
                # 和 sub2api 列表的「智商状态」一样：只看最近一次糖果题
                "label": "正常" if last == "pass" else "降智" if last == "quality_fail" else "待确认",
                "state": (candy or {}).get("state") or "", "lastOutcome": last, "lastReason": (candy or {}).get("last_reason") or "",
                "consecutiveFails": (candy or {}).get("consecutive_fails") or 0, "recent": ((candy or {}).get("recent") or [])[-10:],
                "updatedAt": (candy or {}).get("updated_at") or "",
            },
        }

    @app.route(PREFIX + "accounts")
    @gpt_limit
    @login_required
    def gpt_accounts():
        data = call("GET", "/api/v1/admin/accounts", query={"platform": "openai", "page": 1, "page_size": 1000})
        items = (data or {}).get("items") or []
        ids = [a.get("id") for a in items if a.get("id") is not None]
        states = []
        for i in range(0, len(ids), 500):
            states += call("GET", "/api/v1/admin/iqtest/states/by-accounts", query={"ids": ",".join(map(str, ids[i:i + 500]))}) or []
        return jsonify(ok=True, accounts=[summarize(a, states) for a in items])

    @app.route(PREFIX + "accounts/<int:aid>/usage", methods=["POST"])
    @gpt_limit
    @login_required
    def gpt_usage(aid):
        """主动查询额度（会发一个很小的请求给 OpenAI，每个账号 10 分钟最多一次，force 时不限）"""
        return jsonify(ok=True, usage=call("GET", f"/api/v1/admin/accounts/{aid}/usage", query={"source": "active", "force": "true"}, timeout=60))

    @app.route(PREFIX + "accounts/<int:aid>/quota")
    @gpt_limit
    @login_required
    def gpt_quota(aid):
        """额度详情（官方用量接口）：5h / 7d 窗口、重置次数、点数余额"""
        return jsonify(ok=True, quota=call("POST", f"/api/v1/admin/openai/accounts/{aid}/quota/refresh", body={}, timeout=60))

    @app.route(PREFIX + "accounts/<int:aid>/results")
    @gpt_limit
    @login_required
    def gpt_results(aid):
        return jsonify(ok=True, results=call("GET", f"/api/v1/admin/iqtest/accounts/{aid}/results", query={"kind": "candy", "limit": 30}) or [])

    @app.route(PREFIX + "accounts/<int:aid>/schedulable", methods=["POST"])
    @gpt_limit
    @login_required
    def gpt_schedulable(aid):
        call("POST", f"/api/v1/admin/accounts/{aid}/schedulable", body={"schedulable": bool(body().get("schedulable"))})
        return jsonify(ok=True)

    @app.route(PREFIX + "accounts/<int:aid>", methods=["DELETE"])
    @gpt_limit
    @login_required
    def gpt_delete(aid):
        call("DELETE", f"/api/v1/admin/accounts/{aid}")
        return jsonify(ok=True)

    # ---------- 智商测试 ----------
    @app.route(PREFIX + "test", methods=["POST"])
    @limiter.limit("10 per minute")
    @login_required
    def gpt_test():
        """马上测一次糖果题（不传 account_ids = 全部 GPT 账号）"""
        ids = body().get("account_ids")
        if not ids:
            data = call("GET", "/api/v1/admin/accounts", query={"platform": "openai", "page": 1, "page_size": 1000, "status": "active"})
            ids = [a.get("id") for a in (data or {}).get("items") or []]
        if not ids:
            return jsonify(ok=False, error="没有可以测试的 GPT 账号"), 400
        run = call("POST", "/api/v1/admin/iqtest/runs/adhoc", body={"account_ids": [int(i) for i in ids][:500], "checks": [{"kind": "candy", "model": "auto"}], "policy": {}})
        return jsonify(ok=True, runId=(run or {}).get("run_id"))

    @app.route(PREFIX + "runs/<int:rid>")
    @gpt_limit
    @login_required
    def gpt_run(rid):
        return jsonify(ok=True, run=call("GET", f"/api/v1/admin/iqtest/runs/{rid}"))

    def find_plan():
        plans = call("GET", "/api/v1/admin/iqtest/plans") or []
        return next((p for p in plans if p.get("name") == PLAN_NAME), None)

    @app.route(PREFIX + "plan")
    @gpt_limit
    @login_required
    def gpt_plan():
        p = find_plan()
        return jsonify(ok=True, plan={"enabled": bool(p and p.get("enabled")), "intervalMinutes": (p or {}).get("interval_minutes") or 360,
                                      "nextRunAt": (p or {}).get("next_run_at") or "", "lastRunAt": (p or {}).get("last_run_at") or "",
                                      "exists": bool(p)})

    @app.route(PREFIX + "plan", methods=["POST"])
    @limiter.limit("10 per minute")
    @login_required
    def gpt_plan_save():
        """定期测试：在 sub2api 里建 / 改一个只测糖果题、只测 GPT 账号的计划"""
        d = body()
        minutes = max(10, min(43200, int(d.get("intervalMinutes") or 360)))
        plan = {"name": PLAN_NAME, "enabled": bool(d.get("enabled")), "checks": [{"kind": "candy", "model": "auto"}],
                "schedule_type": "interval", "interval_minutes": minutes, "scope_type": "all", "platforms": ["openai"],
                "policy": {"mode": "consecutive", "consecutive_fails": 3, "recover_passes": 2},
                "max_concurrency": 3, "jitter_seconds": 5, "keep_results": 50, "max_requests_per_run": 0}
        p = find_plan()
        saved = call("PUT", f"/api/v1/admin/iqtest/plans/{p['id']}", body=plan) if p else call("POST", "/api/v1/admin/iqtest/plans", body=plan)
        return jsonify(ok=True, plan={"enabled": bool(saved.get("enabled")), "intervalMinutes": saved.get("interval_minutes"),
                                      "nextRunAt": saved.get("next_run_at") or "", "lastRunAt": saved.get("last_run_at") or "", "exists": True})

    # ---------- 授权登录（OAuth） ----------
    @app.route(PREFIX + "oauth/start", methods=["POST"])
    @limiter.limit("10 per minute")
    @login_required
    def gpt_oauth_start():
        d = call("POST", "/api/v1/admin/openai/generate-auth-url", body={})
        return jsonify(ok=True, authUrl=d.get("auth_url"), sessionId=d.get("session_id"))

    @app.route(PREFIX + "oauth/finish", methods=["POST"])
    @limiter.limit("10 per minute")
    @login_required
    def gpt_oauth_finish():
        """登录完浏览器会跳到 http://localhost:1455/auth/callback?code=…&state=…（打不开是正常的），把这个地址贴回来"""
        d = body()
        raw = str(d.get("callback") or "").strip()
        q = urllib.parse.parse_qs(urllib.parse.urlparse(raw).query) if "code=" in raw else {}
        code = (q.get("code") or [""])[0] or (raw if "=" not in raw else "")
        state = (q.get("state") or [""])[0]
        if not code or not state or not d.get("sessionId"):
            return jsonify(ok=False, error="没认出授权结果：请把浏览器跳转到的 localhost 开头的完整地址贴进来"), 400
        payload = {"session_id": d["sessionId"], "code": code, "state": state, "concurrency": 10, "priority": 1}
        if d.get("name"):
            payload["name"] = str(d["name"])[:100]
        acc = call("POST", "/api/v1/admin/openai/create-from-oauth", body=payload, timeout=150)
        return jsonify(ok=True, account={"id": acc.get("id"), "name": acc.get("name"), "email": (acc.get("credentials") or {}).get("email")})

    return call
