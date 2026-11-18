"""VPS 监控：接入用户自己的 Komari 探针（只读）。

用的是 Komari 的公开接口（首页展示用的那几个），不需要账号密码，所以这里只保存 Komari 的网址：
  GET  /api/nodes                         各节点的基本信息（名字、地区、配置、价格、到期、流量上限）
  POST /api/rpc2 common:getNodesLatestStatus  各节点此刻的状态（在线、CPU、内存、硬盘、网速、流量、延迟丢包）
服务器把两份合在一起、缓存几秒再给网页和 App，浏览器和手机不直接连 Komari。

双向同步（设了 Komari 的 API Key 才开）：后台线程每 2 分钟、账本保存后各跑一次 sync_once()：
  Komari 新加的节点 → 账本里新建一台 VPS；账本新加的 VPS → 先按 IP / 名字找现成的节点，找不到就在 Komari 新建；
  改名哪边改了跟哪边（两边都改了以账本为准）；一边删了另一边也删（一次删太多会停下来不删，记在同步日志里）。
API Key 用 Fernet 加密存在 settings 表，不下发到浏览器或手机。

由 app.py 末尾调用 install() 接入。
"""
import json
import os
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


def get_key():
    enc = _core.get_setting("komari_key_enc")
    if not enc:
        return ""
    try:
        return _core.FERNET.decrypt(enc.encode()).decode()
    except Exception:
        return ""


def save_key(key):
    _core.set_setting("komari_key_enc", _core.FERNET.encrypt(key.encode()).decode() if key else "")


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


def admin(method, path, body=None, url=None, key=None):
    """调 Komari 管理接口（Authorization: Bearer <API Key>）。出错信息里不带 Key。"""
    url = url or get_url(); key = key or get_key()
    if not url or not key:
        raise KomariError("还没设置 Komari 的 API Key")
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url + path, data=data, method=method, headers={
        "Authorization": "Bearer " + key, "Accept": "application/json", "User-Agent": "totp-share/komari",
        **({"Content-Type": "application/json"} if data is not None else {}),
    })
    try:
        with _opener.open(req, timeout=TIMEOUT) as r:
            raw = r.read(8 * 1024 * 1024)
    except urllib.error.HTTPError as e:
        raise KomariError("Komari 拒绝了 API Key（是不是在 Komari 设置里改掉了？）" if e.code in (401, 403) else f"Komari 管理接口返回 {e.code}")
    except Exception as e:
        raise KomariError(f"连不上 Komari：{e}")
    try:
        d = json.loads(raw.decode("utf-8") or "{}")
    except ValueError:
        raise KomariError("Komari 管理接口返回的不是 JSON")
    if isinstance(d, dict) and d.get("status") not in (None, "success"):
        raise KomariError("Komari：" + str(d.get("message") or d.get("status")))
    return d


def admin_nodes():
    d = admin("GET", "/api/admin/client/list")
    d = d.get("data") if isinstance(d, dict) else d
    if not isinstance(d, list):
        raise KomariError("Komari 返回的节点列表格式不对")
    return [n for n in d if isinstance(n, dict) and n.get("uuid")]


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


# ---------- 双向同步 ----------
SYNC_EVERY = 120          # 后台每隔多少秒同步一次
MAX_DELETES = 2           # 一次最多跟着删几台；超过就停下来不删（防止 Komari 出问题时把账本清空）
_sync_lock = threading.Lock()
_kick = threading.Event()
_thread = None


def _meta():
    try:
        m = json.loads(_core.get_setting("komari_sync") or "{}")
    except ValueError:
        m = {}
    return m if isinstance(m, dict) else {}


def _save_meta(m):
    _core.set_setting("komari_sync", json.dumps(m, ensure_ascii=False, separators=(",", ":")))


def _price_of(v):
    """账本价格是自由文字（如 "$28.18  40cad"），取第一个数字；带 ¥ / 元 / cny 的当人民币"""
    import re
    t = str(v.get("price") or "")
    m = re.search(r"\d+(?:\.\d+)?", t.replace(",", ""))
    cur = "¥" if re.search(r"[¥￥元]|cny|rmb", t, re.I) else "$"
    return (float(m.group(0)) if m else 0.0), cur


def _vps_from_node(n, new_id):
    exp = str(n.get("expired_at") or "")
    price = _num(n.get("price"))
    return {"id": new_id, "host": n.get("name") or "", "site": "", "ip": n.get("ipv4") or n.get("ipv6") or "", "port": "",
            "password": "", "tags": [], "traffic": "", "renew": exp[:10] if exp and not exp.startswith("0001") else "",
            "price": (str(n.get("currency") or "$") + ("%g" % price)) if price > 0 else "", "email": "", "loginPassword": "",
            "komari": n["uuid"], "komariName": n.get("name") or ""}


def _norm(t):
    return "".join(ch for ch in str(t or "").lower() if ch.isalnum())


def sync_once():
    """跑一轮双向同步，返回这一轮做了什么（列表，给日志用）。没设 Key 时什么也不做。"""
    import hezu
    url, key = get_url(), get_key()
    if not url or not key:
        return []
    with _sync_lock:
        meta = _meta()
        try:
            nodes = admin_nodes()
        except KomariError as e:
            meta.update(error=str(e), last=int(time.time())); _save_meta(meta)
            return []
        actions, warn = [], ""
        for attempt in range(2):          # 保存时版本冲突（别处刚改过）就重新读一次再做
            rev, st = hezu.load_state()
            vps = st.setdefault("vps", [])
            by_uuid = {n["uuid"]: n for n in nodes}
            links = meta.get("links") if isinstance(meta.get("links"), dict) else {}   # 上一轮的 {VPS id: 节点 uuid}
            ids = {v.get("id") for v in vps}
            changed = False

            # 1. 删除：上一轮还关联着，这一轮一边没了
            del_nodes = [u for vid, u in links.items() if vid not in ids and u in by_uuid]        # 账本里删了 → 删节点
            del_vps = [v for v in vps if v.get("komari") and v["komari"] not in by_uuid and links.get(v.get("id")) == v["komari"]]  # Komari 删了 → 删 VPS
            if len(del_nodes) + len(del_vps) > MAX_DELETES:
                warn = f"这一轮有 {len(del_nodes)} 台要删 Komari 节点、{len(del_vps)} 台要删账本 VPS，超过 {MAX_DELETES} 台，为安全没有删，请检查后在一边手动删掉"
                del_nodes, del_vps = [], []
            for u in del_nodes:
                if attempt == 0:
                    admin("POST", f"/api/admin/client/{u}/remove")
                    actions.append("账本删了，Komari 也删除：" + (by_uuid[u].get("name") or u))
                by_uuid.pop(u, None)
                nodes[:] = [n for n in nodes if n["uuid"] != u]   # 重试时别再当成新节点
            for v in del_vps:
                vps.remove(v); changed = True
                actions.append("Komari 删了，账本也删除：" + (v.get("host") or "未命名"))
            # 关联的节点已经不在了（又不是上一轮关联的，比如手动改过）：解除关联，下面会重新匹配
            for v in vps:
                if v.get("komari") and v["komari"] not in by_uuid:
                    v.pop("komari", None); v.pop("komariName", None); changed = True

            # 2. 账本里没关联的 VPS：按 IP、再按名字找没关联的节点；找不到就在 Komari 新建
            linked = {v["komari"] for v in vps if v.get("komari")}
            for v in vps:
                if v.get("komari") or not str(v.get("host") or "").strip():
                    continue
                free = [n for n in by_uuid.values() if n["uuid"] not in linked]
                ip = str(v.get("ip") or "").strip().lower()
                hit = next((n for n in free if ip and ip in (str(n.get("ipv4") or "").lower(), str(n.get("ipv6") or "").lower())), None)
                if not hit:
                    same = [n for n in free if _norm(n.get("name")) == _norm(v["host"])]
                    hit = same[0] if len(same) == 1 else None
                if not hit:
                    price, cur = _price_of(v)
                    d = admin("POST", "/api/admin/client/add", {"name": v["host"].strip()})
                    u = d.get("uuid") or (d.get("data") or {}).get("uuid")
                    if not u:
                        raise KomariError("Komari 新建节点没返回 uuid")
                    edit = {"price": price, "currency": cur}
                    if v.get("renew"):
                        edit["expired_at"] = str(v["renew"])[:10] + "T00:00:00Z"
                    try:
                        admin("POST", f"/api/admin/client/{u}/edit", edit)
                    except KomariError:
                        pass
                    hit = {"uuid": u, "name": v["host"].strip()}
                    by_uuid[u] = hit; nodes.append(hit)
                    actions.append("账本新加的，在 Komari 新建节点：" + v["host"].strip() + "（要在机器上装探针才有数据）")
                else:
                    actions.append("关联上：" + v["host"] + " ↔ " + (hit.get("name") or ""))
                v["komari"] = hit["uuid"]; v["komariName"] = hit.get("name") or ""
                linked.add(hit["uuid"]); changed = True

            # 3. Komari 里没关联的节点：账本里新建一台 VPS
            for n in by_uuid.values():
                if n["uuid"] not in linked:
                    vps.append(_vps_from_node(n, "k" + n["uuid"].replace("-", "")[:10]))
                    linked.add(n["uuid"]); changed = True
                    actions.append("Komari 新加的，账本也新建：" + (n.get("name") or ""))

            # 4. 改名、补 IP：哪边改了跟哪边，两边都改了以账本为准
            for v in vps:
                n = by_uuid.get(v.get("komari"))
                if not n:
                    continue
                host, name, last = str(v.get("host") or "").strip(), str(n.get("name") or ""), v.get("komariName")
                if last is None:
                    last = name
                if host and host != name:
                    if name != last and host == last:        # 只有 Komari 改了
                        v["host"] = name; changed = True
                        actions.append("Komari 改了名字，账本跟着改：" + name)
                    else:                                    # 账本改了（或两边都改了）
                        admin("POST", f"/api/admin/client/{n['uuid']}/edit", {"name": host})
                        n["name"] = host
                        actions.append("账本改了名字，Komari 跟着改：" + host)
                if v.get("komariName") != n["name"]:
                    v["komariName"] = n["name"]; changed = True
                if not str(v.get("ip") or "").strip() and (n.get("ipv4") or n.get("ipv6")):
                    v["ip"] = n.get("ipv4") or n.get("ipv6"); changed = True

            if not changed or hezu.save_state(st, rev) is not None:
                break
            actions = [a for a in actions if "Komari 也删除" in a or "新建节点" in a or "Komari 跟着改" in a]   # 已经做了的留着
        meta["links"] = {v["id"]: v["komari"] for v in vps if v.get("komari") and v.get("id")}
        log = [{"t": int(time.time()), "a": a} for a in actions] + (meta.get("log") or [])
        meta.update(error=warn, last=int(time.time()), log=log[:30])
        _save_meta(meta)
        with _lock:
            _cache["at"] = 0          # 节点有变化，下次读监控数据时重新取
        return actions


def sync_status():
    m = _meta()
    return {"enabled": bool(get_key()), "last": m.get("last") or 0, "error": m.get("error") or "", "log": (m.get("log") or [])[:10]}


def kick():
    _kick.set()


def _loop():
    time.sleep(5)
    while True:
        try:
            with _core.app.app_context():
                sync_once()
        except Exception as e:      # 不能让后台线程死掉
            try:
                with _core.app.app_context():
                    m = _meta(); m.update(error=f"同步出错：{e}", last=int(time.time())); _save_meta(m)
            except Exception:
                pass
        _kick.wait(SYNC_EVERY)
        time.sleep(3)               # 连续保存时攒一下再同步
        _kick.clear()


def start_thread():
    global _thread
    if _thread is None and not _core.app.config.get("TESTING") and os.environ.get("KOMARI_SYNC", "1") != "0":
        _thread = threading.Thread(target=_loop, name="komari-sync", daemon=True)
        _thread.start()


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
            return jsonify(ok=True, configured=False, url="", nodes=[], sync=None)
        return jsonify(ok=True, configured=True, url=url, nodes=nodes_cached(url), sync=sync_status())

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
        key = d.get("apiKey") if isinstance(d, dict) else None
        if key:
            admin_nodes_check = admin("GET", "/api/admin/client/list", url=url, key=str(key).strip())   # Key 不对就报错，不保存
            del admin_nodes_check
        _core.set_setting("komari_url", url)
        if key is not None:
            save_key(str(key).strip())
            kick()
        return jsonify(ok=True, configured=bool(url), url=url, nodes=nodes, sync=sync_status())

    @app.route(PREFIX + "/install/<uuid>")
    @limiter.limit("30 per minute")
    @login_required
    def komari_install(uuid):
        """这台节点的探针一键安装命令（在 VPS 上用 root 跑）"""
        if not all(c.isalnum() or c == "-" for c in uuid):
            return jsonify(ok=False, error="参数错误"), 400
        d = admin("GET", f"/api/admin/client/{uuid}")
        d = d.get("data") if isinstance(d.get("data"), dict) else d
        token = d.get("token") or ""
        if not token:
            return jsonify(ok=False, error="Komari 没给这台节点的令牌"), 502
        cmd = ("bash <(curl -sL https://raw.githubusercontent.com/komari-monitor/komari-agent/refs/heads/main/install.sh)"
               f" -e {get_url()} -t {token}")
        return jsonify(ok=True, command=cmd)

    @app.route(PREFIX + "/sync", methods=["POST"])
    @limiter.limit("10 per minute")
    @login_required
    def komari_sync_now():
        actions = sync_once()
        return jsonify(ok=True, actions=actions, sync=sync_status())

    @app.after_request
    def komari_after_save(resp):
        # 账本存好了就提醒后台同步一次（新加 / 删掉 / 改名的 VPS 很快同步到 Komari）
        if request.endpoint == "hezu_state_put" and resp.status_code == 200:
            kick()
        return resp

    @app.before_request
    def komari_start():
        start_thread()
