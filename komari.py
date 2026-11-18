"""VPS 监控：接入用户自己的 Komari 探针（只读）。

用的是 Komari 的公开接口（首页展示用的那几个），不需要账号密码，所以这里只保存 Komari 的网址：
  GET  /api/nodes                         各节点的基本信息（名字、地区、配置、价格、到期、流量上限）
  POST /api/rpc2 common:getNodesLatestStatus  各节点此刻的状态（在线、CPU、内存、硬盘、网速、流量、延迟丢包）
服务器把两份合在一起、缓存几秒再给网页和 App，浏览器和手机不直接连 Komari。

由 app.py 末尾调用 install() 接入。
"""
import json
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

from flask import jsonify, request

PREFIX = "/api/app/komari"
TIMEOUT = 12
CACHE_SECONDS = 8
_opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
_core = None
_cache = {"url": None, "at": 0.0, "data": None}
_lock = threading.Lock()


class KomariError(Exception):
    pass


def get_url():
    return (_core.get_setting("komari_url") or "").rstrip("/")


def normalize_url(raw):
    u = (raw or "").strip().rstrip("/")
    if not u:
        return ""
    if "://" not in u:
        u = "https://" + u
    p = urllib.parse.urlparse(u)
    if p.scheme not in ("http", "https") or not p.netloc:
        raise ValueError("Komari 地址不对，例如 https://k.example.com")
    return f"{p.scheme}://{p.netloc}{p.path.rstrip('/')}"


def _get(url, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url + path, data=data, method="POST" if data else "GET", headers={
        "Accept": "application/json", "User-Agent": "totp-share/komari",
        **({"Content-Type": "application/json"} if data else {}),
    })
    try:
        with _opener.open(req, timeout=TIMEOUT) as r:
            raw = r.read(8 * 1024 * 1024)
    except urllib.error.HTTPError as e:
        raise KomariError(f"Komari 返回 {e.code}" + ("（是不是开了「私有站点」？）" if e.code in (401, 403) else ""))
    except Exception as e:
        raise KomariError(f"连不上 Komari：{e}")
    try:
        return json.loads(raw.decode("utf-8"))
    except ValueError:
        raise KomariError("Komari 返回的不是 JSON（地址是不是填成了别的网站？）")


def _num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


def traffic_used(node, st):
    """按 Komari 的流量计算方式（上传、下载、取大、取小、合计）算这个月用了多少"""
    up, down = _num(st.get("net_total_up")), _num(st.get("net_total_down"))
    t = node.get("traffic_limit_type") or "sum"
    return {"up": up, "down": down, "max": max(up, down), "min": min(up, down)}.get(t, up + down)


def fetch(url):
    nodes = _get(url, "/api/nodes")
    nodes = nodes.get("data") if isinstance(nodes, dict) else nodes
    if not isinstance(nodes, list):
        raise KomariError("Komari 返回的节点列表格式不对")
    rpc = _get(url, "/api/rpc2", {"jsonrpc": "2.0", "method": "common:getNodesLatestStatus", "id": 1})
    status = rpc.get("result") if isinstance(rpc, dict) else None
    status = status if isinstance(status, dict) else {}
    out = []
    for n in nodes:
        if not isinstance(n, dict) or n.get("hidden"):
            continue
        st = status.get(n.get("uuid")) or {}
        pings = [p for p in (st.get("ping") or {}).values() if isinstance(p, dict)]
        ping = pings[0] if pings else {}
        out.append({
            "uuid": n.get("uuid"), "name": n.get("name") or "", "region": n.get("region") or "", "group": n.get("group") or "",
            "os": n.get("os") or "", "cpuName": n.get("cpu_name") or "", "cores": n.get("cpu_cores") or 0, "weight": n.get("weight") or 0,
            "price": _num(n.get("price")), "currency": n.get("currency") or "", "billingCycle": n.get("billing_cycle") or 0,
            "expiredAt": n.get("expired_at") or "", "autoRenewal": bool(n.get("auto_renewal")),
            "trafficLimit": _num(n.get("traffic_limit")), "trafficType": n.get("traffic_limit_type") or "sum",
            "online": bool(st.get("online")), "time": st.get("time") or "", "uptime": _num(st.get("uptime")),
            "cpu": _num(st.get("cpu")), "load": [_num(st.get("load")), _num(st.get("load5")), _num(st.get("load15"))],
            "ram": _num(st.get("ram")), "ramTotal": _num(st.get("ram_total") or n.get("mem_total")),
            "disk": _num(st.get("disk")), "diskTotal": _num(st.get("disk_total") or n.get("disk_total")),
            "netIn": _num(st.get("net_in")), "netOut": _num(st.get("net_out")),
            "totalUp": _num(st.get("net_total_up")), "totalDown": _num(st.get("net_total_down")),
            "trafficUsed": traffic_used(n, st),
            "ping": {"name": ping.get("name") or "", "latest": _num(ping.get("latest")), "loss": _num(ping.get("loss"))} if ping else None,
        })
    out.sort(key=lambda x: (x["weight"], x["name"]))
    return out


def nodes_cached(url, force=False):
    with _lock:
        if not force and _cache["url"] == url and time.time() - _cache["at"] < CACHE_SECONDS:
            return _cache["data"]
    data = fetch(url)
    with _lock:
        _cache.update(url=url, at=time.time(), data=data)
    return data


def install(core):
    global _core
    _core = core
    app, limiter, login_required = core.app, core.limiter, core.login_required

    @app.errorhandler(KomariError)
    def komari_error(e):
        return jsonify(ok=False, error=str(e)), 502

    @app.route(PREFIX)
    @limiter.limit("240 per minute")
    @login_required
    def komari_nodes():
        url = get_url()
        if not url:
            return jsonify(ok=True, configured=False, url="", nodes=[])
        return jsonify(ok=True, configured=True, url=url, nodes=nodes_cached(url))

    @app.route(PREFIX + "/config", methods=["POST"])
    @limiter.limit("20 per minute")
    @login_required
    def komari_config():
        d = request.get_json(silent=True) or {}
        try:
            url = normalize_url(d.get("url") if isinstance(d, dict) else "")
        except ValueError as e:
            return jsonify(ok=False, error=str(e)), 400
        nodes = nodes_cached(url, force=True) if url else []   # 先试一下能不能连上，连不上就不保存
        _core.set_setting("komari_url", url)
        return jsonify(ok=True, configured=bool(url), url=url, nodes=nodes)
