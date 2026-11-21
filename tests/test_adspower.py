"""AdsPower 登录设备数量：只存数量，按邮箱（小写）对上。全部是假数据。"""
from conftest import BASE_URL

API = "/api/app/adspower/devices"


def test_devices_roundtrip(ctx):
    assert ctx.client().get(API, base_url=BASE_URL).status_code == 401
    a = ctx.admin()
    assert a.get(API, base_url=BASE_URL).get_json() == {"ok": True, "updated": 0, "counts": {}, "devices": {}}
    assert a.post(API, base_url=BASE_URL, json={"counts": [1]}).status_code == 400
    d = a.post(API, base_url=BASE_URL, json={"counts": {" A@x.com ": 3, "b@x.com": "2", "bad": "x", "neg": -1}}).get_json()
    assert d["counts"] == {"a@x.com": 3, "b@x.com": 2} and d["updated"] > 0
    assert a.get(API, base_url=BASE_URL).get_json()["counts"] == {"a@x.com": 3, "b@x.com": 2}


def test_devices_details(ctx):
    a = ctx.admin()
    d = a.post(API, base_url=BASE_URL, json={"devices": {"M@x.com": [{"name": "Mac", "ip": "1.2.3.4", "region": "CN", "time": "2026-11-21 12:33", "x": 1}, "bad"]}}).get_json()
    assert d["counts"] == {"m@x.com": 1}
    assert d["devices"] == {"m@x.com": [{"name": "Mac", "ip": "1.2.3.4", "region": "CN", "time": "2026-11-21 12:33"}]}
