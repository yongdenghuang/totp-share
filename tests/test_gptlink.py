"""GPT 账号（接 sub2api）：用假的 sub2api 测转发、汇总、授权回调解析。全部是假数据。"""
from datetime import datetime, timedelta, timezone

import gptlink
from conftest import BASE_URL

API = "/api/app/gpt"


def call(c, method, path, **kw):
    return getattr(c, method)(path, base_url=BASE_URL, **kw)


class FakeSub2api:
    def __init__(self):
        self.calls = []
        self.plans = []

    def __call__(self, method, path, body=None, query=None, url=None, key=None, timeout=None):
        self.calls.append((method, path, body, query))
        future = (datetime.now(timezone.utc) + timedelta(hours=2)).isoformat()
        past = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()
        if path == "/api/v1/admin/accounts":
            return {"items": [
                {"id": 7, "name": "plus-01", "status": "active", "schedulable": True,
                 "credentials": {"email": "a@example.com", "plan_type": "plus"},
                 "extra": {"codex_5h_used_percent": 42.5, "codex_5h_reset_at": future,
                           "codex_7d_used_percent": 80, "codex_7d_reset_at": past}},
                {"id": 8, "name": "pro-01", "status": "error", "error_message": "401", "credentials": {}, "extra": {}}],
                "total": 2}
        if path.endswith("/states/by-accounts"):
            return [{"account_id": 7, "kind": "candy", "last_outcome": "quality_fail", "consecutive_fails": 3, "state": "flagged", "recent": [True, False, False, False]},
                    {"account_id": 8, "kind": "candy", "last_outcome": "infra_error"}]
        if path == "/api/v1/admin/iqtest/plans" and method == "GET":
            return self.plans
        if path == "/api/v1/admin/iqtest/plans" and method == "POST":
            self.plans.append(dict(body, id=1)); return self.plans[-1]
        if path.startswith("/api/v1/admin/iqtest/plans/") and method == "PUT":
            self.plans[0] = dict(body, id=1); return self.plans[0]
        if path.endswith("/runs/adhoc"):
            return {"run_id": 99}
        if path.endswith("/generate-auth-url"):
            return {"auth_url": "https://auth.openai.com/oauth/authorize?state=abc", "session_id": "s1"}
        if path.endswith("/create-from-oauth"):
            return {"id": 9, "name": "new", "credentials": {"email": "n@example.com"}}
        return {}


def setup(ctx, monkeypatch):
    fake = FakeSub2api()
    monkeypatch.setattr(gptlink, "call", fake)
    return fake


def test_requires_login_and_config(ctx, monkeypatch):
    c = ctx.client()
    assert call(c, "get", f"{API}/accounts").status_code == 401
    a = ctx.admin()
    assert call(a, "get", f"{API}/config").get_json() == {"ok": True, "url": "", "hasKey": False}
    assert call(a, "post", f"{API}/config", json={"url": "ftp://x"}).status_code == 400


def test_config_saves_key_encrypted(ctx, monkeypatch):
    fake = setup(ctx, monkeypatch)
    a = ctx.admin()
    r = call(a, "post", f"{API}/config", json={"url": "sub.example.com/", "key": "adm_sc_1_secretvalue"})
    assert r.get_json() == {"ok": True, "url": "https://sub.example.com", "hasKey": True}
    assert fake.calls[0][1] == "/api/v1/admin/accounts"          # 保存前先试连一次
    rows = ctx.sql("SELECT value FROM settings WHERE key='sub2api_key_enc'")
    assert rows and "secretvalue" not in rows[0]["value"]
    assert "secretvalue" not in call(a, "get", f"{API}/config").get_data(as_text=True)


def test_accounts_summary(ctx, monkeypatch):
    setup(ctx, monkeypatch)
    d = call(ctx.admin(), "get", f"{API}/accounts").get_json()
    a, b = d["accounts"]
    assert a["email"] == "a@example.com" and a["plan"] == "plus"
    assert a["fiveHour"]["used"] == 42.5 and a["sevenDay"]["used"] == 0          # 已经重置过的窗口当 0
    assert a["iq"]["label"] == "降智" and a["iq"]["consecutiveFails"] == 3
    assert b["iq"]["label"] == "待确认" and b["status"] == "error" and b["fiveHour"]["used"] is None


def test_plan_test_and_oauth(ctx, monkeypatch):
    fake = setup(ctx, monkeypatch)
    a = ctx.admin()
    assert call(a, "post", f"{API}/plan", json={"enabled": True, "intervalMinutes": 5}).get_json()["plan"]["intervalMinutes"] == 10
    call(a, "post", f"{API}/plan", json={"enabled": True, "intervalMinutes": 120})
    assert len(fake.plans) == 1 and fake.plans[0]["platforms"] == ["openai"] and fake.plans[0]["checks"] == [{"kind": "candy", "model": "auto"}]
    assert call(a, "post", f"{API}/test", json={}).get_json()["runId"] == 99
    adhoc = next(x for x in fake.calls if x[1].endswith("/runs/adhoc"))
    assert adhoc[2]["account_ids"] == [7, 8]
    s = call(a, "post", f"{API}/oauth/start", json={}).get_json()
    assert s["sessionId"] == "s1"
    bad = call(a, "post", f"{API}/oauth/finish", json={"sessionId": "s1", "callback": "随便写的"})
    assert bad.status_code == 400
    ok = call(a, "post", f"{API}/oauth/finish", json={"sessionId": "s1", "callback": "http://localhost:1455/auth/callback?code=c123&scope=x&state=abc"}).get_json()
    assert ok["account"]["email"] == "n@example.com"
    create = next(x for x in fake.calls if x[1].endswith("/create-from-oauth"))
    assert create[2] == {"session_id": "s1", "code": "c123", "state": "abc", "concurrency": 10, "priority": 1}
