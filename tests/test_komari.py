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
    assert call(a, "get", API).get_json() == {"ok": True, "configured": False, "url": "", "nodes": []}
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
