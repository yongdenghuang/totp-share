"""AdsPower 成员的登录设备数量（只存数量）。

AdsPower 没有公开接口给这个数，网页里的接口是加密的，所以不去破解：
数量由人（或 Claude 在用户自己登录的浏览器里）从「团队管理 → 成员 → 登录活动」读出来，再 POST 进来。
存在 settings 表 adspower_devices：{"updated": 时间戳, "counts": {"邮箱小写": 数量}}。
账本里「只存账号」表的每一行按账号邮箱对上，显示「N 台设备」。

由 app.py 末尾调用 install() 接入。
"""
import json
import time

from flask import jsonify, request

PREFIX = "/api/app/adspower"
KEY = "adspower_devices"
_core = None


def load():
    try:
        d = json.loads(_core.get_setting(KEY) or "{}")
    except ValueError:
        d = {}
    counts = d.get("counts") if isinstance(d.get("counts"), dict) else {}
    return {"updated": d.get("updated") or 0, "counts": counts}


def save(counts):
    clean = {}
    for k, v in (counts or {}).items():
        k = str(k).strip().lower()
        if not k or len(k) > 200:
            continue
        try:
            n = int(v)
        except (TypeError, ValueError):
            continue
        if 0 <= n <= 1000:
            clean[k] = n
    d = {"updated": int(time.time()), "counts": clean}
    _core.set_setting(KEY, json.dumps(d, ensure_ascii=False, separators=(",", ":")))
    return d


def install(core):
    global _core
    _core = core
    app, limiter, login_required = core.app, core.limiter, core.login_required

    @app.route(PREFIX + "/devices")
    @limiter.limit("240 per minute")
    @login_required
    def adspower_devices():
        return jsonify(ok=True, **load())

    @app.route(PREFIX + "/devices", methods=["POST"])
    @limiter.limit("20 per minute")
    @login_required
    def adspower_devices_set():
        d = request.get_json(silent=True) or {}
        counts = d.get("counts") if isinstance(d, dict) else None
        if not isinstance(counts, dict):
            return jsonify(ok=False, error="counts 必须是 {邮箱: 数量}"), 400
        return jsonify(ok=True, **save(counts))
