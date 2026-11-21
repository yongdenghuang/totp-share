"""AdsPower 成员的登录设备（数量 + 每台的名字、IP、地区、最近登录时间）。

AdsPower 没有公开接口给这个数，网页里的接口是加密的，所以不去破解：
数量由人（或 Claude 在用户自己登录的浏览器里）从「团队管理 → 成员 → 登录活动」读出来，再 POST 进来。
存在 settings 表 adspower_devices：{"updated": 时间戳, "counts": {"邮箱小写": 数量},
  "devices": {"邮箱小写": [{"name", "ip", "region", "time"}]}}。
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
    devices = d.get("devices") if isinstance(d.get("devices"), dict) else {}
    return {"updated": d.get("updated") or 0, "counts": counts, "devices": devices}


def _clean_devices(devices):
    out = {}
    for k, lst in (devices or {}).items():
        k = str(k).strip().lower()
        if not k or len(k) > 200 or not isinstance(lst, list):
            continue
        out[k] = [{f: str(x.get(f) or "")[:120] for f in ("name", "ip", "region", "time")}
                  for x in lst[:100] if isinstance(x, dict)]
    return out


def save(counts=None, devices=None):
    devices = _clean_devices(devices)
    counts = dict(counts or {})
    for k, lst in devices.items():
        counts.setdefault(k, len(lst))
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
    d = {"updated": int(time.time()), "counts": clean, "devices": devices}
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
        devices = d.get("devices") if isinstance(d, dict) else None
        if not isinstance(counts, (dict, type(None))) or not isinstance(devices, (dict, type(None))) or (counts is None and devices is None):
            return jsonify(ok=False, error="要传 counts {邮箱: 数量} 或 devices {邮箱: [设备]}"), 400
        return jsonify(ok=True, **save(counts, devices))
