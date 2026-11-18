"""VPS 监控（接 Komari）：用假的 Komari 接口测合并、流量计算、配置。全部是假数据。"""
import komari
from conftest import BASE_URL

API = "/api/app/komari"


def call(c, method, path, **kw):
    return getattr(c, method)(path, base_url=BASE_URL, **kw)


def fake_get(calls):
    def _get(url, path, body=None):
        calls.append((url, path))
        if path == "/api/nodes":
            return {"data": [
                {"uuid": "u1", "name": "box-b", "region": "🇯🇵", "weight": 1, "price": 10, "currency": "$", "billing_cycle": 365,
                 "traffic_limit": 1000, "traffic_limit_type": "max", "mem_total": 2048, "disk_total": 4096},
                {"uuid": "u2", "name": "box-a", "weight": 0, "traffic_limit_type": "sum"},
                {"uuid": "u3", "name": "secret", "hidden": True}]}
        return {"result": {
            "u1": {"online": True, "cpu": 3.5, "ram": 512, "ram_total": 2048, "net_total_up": 300, "net_total_down": 200,
                   "ping": {"1": {"name": "成都移动", "latest": 67, "loss": 1.5}}},
            "u3": {"online": True}}}
    return _get


def test_requires_login_and_not_configured(ctx):
    assert call(ctx.client(), "get", API).status_code == 401
    a = ctx.admin()
    assert call(a, "get", API).get_json() == {"ok": True, "configured": False, "url": "", "nodes": [], "sync": None}
    assert call(a, "post", API + "/config", json={"url": "ftp://x"}).status_code == 400


def test_config_and_merge(ctx, monkeypatch):
    calls = []
    monkeypatch.setattr(komari, "_get", fake_get(calls))
    komari._cache.update(url=None, at=0, data=None)
    a = ctx.admin()
    d = call(a, "post", API + "/config", json={"url": "k.example.com/"}).get_json()
    assert d["url"] == "https://k.example.com" and d["configured"]
    assert calls[0] == ("https://k.example.com", "/api/nodes")
    d = call(a, "get", API).get_json()
    names = [n["name"] for n in d["nodes"]]
    assert names == ["box-a", "box-b"]                  # 按权重排，隐藏的不出现
    b = d["nodes"][1]
    assert b["online"] and b["cpu"] == 3.5 and b["trafficUsed"] == 300   # max(上传, 下载)
    assert b["ping"] == {"name": "成都移动", "latest": 67, "loss": 1.5}
    assert d["nodes"][0]["online"] is False and d["nodes"][0]["ping"] is None


def test_unreachable(ctx, monkeypatch):
    def boom(url, path, body=None):
        raise komari.KomariError("连不上 Komari：timeout")
    monkeypatch.setattr(komari, "_get", boom)
    r = call(ctx.admin(), "post", API + "/config", json={"url": "https://k.example.com"})
    assert r.status_code == 502 and "连不上" in r.get_json()["error"]
    assert not ctx.sql("SELECT value FROM settings WHERE key='komari_url' AND value != ''")


# ---------- 双向同步 ----------
class FakeAdmin:
    """假的 Komari 管理接口：nodes 是 {uuid: 节点}"""
    def __init__(self, nodes):
        self.nodes = {n["uuid"]: dict(n) for n in nodes}
        self.calls = []
        self.n = 0

    def __call__(self, method, path, body=None, url=None, key=None):
        self.calls.append((method, path, body))
        if path == "/api/admin/client/list":
            return list(self.nodes.values())
        if path == "/api/admin/client/add":
            self.n += 1
            u = f"new-{self.n}"
            self.nodes[u] = {"uuid": u, "name": body["name"]}
            return {"status": "success", "uuid": u, "token": "tok"}
        u = path.split("/")[4]
        if path.endswith("/edit"):
            self.nodes[u].update(body); return {"status": "success"}
        if path.endswith("/remove"):
            self.nodes.pop(u); return {"status": "success"}
        return dict(self.nodes[u], token="tok-" + u)


def ledger(ctx):
    import hezu
    with ctx.app.app_context():
        return hezu.load_state()


def put_vps(ctx, vps):
    import hezu
    with ctx.app.app_context():
        rev, st = hezu.load_state()
        st["vps"] = vps
        assert hezu.save_state(st, rev) is not None


def run_sync(ctx):
    with ctx.app.app_context():
        return komari.sync_once()


def enable(ctx, monkeypatch, fake):
    monkeypatch.setattr(komari, "admin", fake)
    with ctx.app.app_context():
        ctx.app_module.set_setting("komari_url", "https://k.example.com")
        komari.save_key("hz_test")


def test_sync_both_ways(ctx, monkeypatch):
    fake = FakeAdmin([{"uuid": "n1", "name": "Megabox pro", "ipv4": "1.1.1.1"},
                      {"uuid": "n2", "name": "only-in-komari", "ipv4": "2.2.2.2", "price": 10, "currency": "$", "expired_at": "2027-01-02T00:00:00Z"}])
    enable(ctx, monkeypatch, fake)
    put_vps(ctx, [{"id": "a", "host": "bwg-1", "ip": "1.1.1.1", "price": "$45"},
                  {"id": "b", "host": "only-in-ledger", "ip": "", "price": "¥30", "renew": "2026-12-20"}])
    acts = run_sync(ctx)
    assert any("新建节点" in a for a in acts) and any("账本也新建" in a for a in acts)
    rev, st = ledger(ctx)
    v = {x["host"]: x for x in st["vps"]}
    assert v["bwg-1"]["komari"] == "n1"                         # 按 IP 对上
    assert fake.nodes["n1"]["name"] == "bwg-1"                 # 名字以账本为准
    assert v["only-in-ledger"]["komari"] == "new-1"            # Komari 里新建了
    assert fake.nodes["new-1"]["price"] == 30 and fake.nodes["new-1"]["currency"] == "¥"
    assert fake.nodes["new-1"]["expired_at"] == "2026-12-20T00:00:00Z"
    c = v["only-in-komari"]                                     # 账本里新建了
    assert c["komari"] == "n2" and c["ip"] == "2.2.2.2" and c["price"] == "$10" and c["renew"] == "2027-01-02"

    # 再跑一次不会重复建
    assert run_sync(ctx) == [] and len(fake.nodes) == 3 and len(ledger(ctx)[1]["vps"]) == 3

    # Komari 改名 → 账本跟着改；账本改名 → Komari 跟着改
    fake.nodes["n2"]["name"] = "renamed-in-komari"
    rev, st = ledger(ctx)
    for x in st["vps"]:
        if x["id"] == "a":
            x["host"] = "renamed-in-ledger"
    put_vps(ctx, st["vps"])
    run_sync(ctx)
    hosts = {x["id"]: x["host"] for x in ledger(ctx)[1]["vps"]}
    assert "renamed-in-komari" in hosts.values() and fake.nodes["n1"]["name"] == "renamed-in-ledger"

    # 账本删一台 → Komari 也删；Komari 删一台 → 账本也删
    put_vps(ctx, [x for x in ledger(ctx)[1]["vps"] if x["id"] != "b"])
    fake.nodes.pop("n2")
    acts = run_sync(ctx)
    assert "new-1" not in fake.nodes
    assert [x["id"] for x in ledger(ctx)[1]["vps"]] == ["a"]
    assert any("Komari 也删除" in a for a in acts) and any("账本也删除" in a for a in acts)


def test_sync_refuses_mass_delete(ctx, monkeypatch):
    fake = FakeAdmin([{"uuid": f"n{i}", "name": f"box{i}"} for i in range(4)])
    enable(ctx, monkeypatch, fake)
    put_vps(ctx, [])
    run_sync(ctx)
    assert len(ledger(ctx)[1]["vps"]) == 4
    fake.nodes.clear()                     # Komari 那边突然全没了
    run_sync(ctx)
    assert len(ledger(ctx)[1]["vps"]) == 4  # 没跟着删
    with ctx.app.app_context():
        assert "为安全没有删" in komari.sync_status()["error"]


def test_sync_off_without_key_and_install_command(ctx, monkeypatch):
    assert run_sync(ctx) == []
    fake = FakeAdmin([{"uuid": "n1", "name": "x"}])
    enable(ctx, monkeypatch, fake)
    d = call(ctx.admin(), "get", API + "/install/n1").get_json()
    assert d["ok"] and "-e https://k.example.com -t tok-n1" in d["command"]
    assert call(ctx.admin(), "get", API + "/install/../x").status_code in (400, 404)
    with ctx.app.app_context():
        assert "hz_test" not in (ctx.app_module.get_setting("komari_key_enc") or "")
