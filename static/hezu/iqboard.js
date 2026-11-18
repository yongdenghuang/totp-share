'use strict';
// GPT 账号（网页版）：数据来自用户自己的 sub2api，由本站服务器转发（Key 不会到浏览器）。和 App 里的同一套功能。
(function () {
  // 浅色打底（和手机 App 同一套颜色）：按智商状态上色
  function tinted(el, color) { if (el && color) { el.classList.add('tinted'); el.style.setProperty('--tint', color); } return el; }
  const root = document.getElementById('gpt');
  if (!root) return;
  const showErr = m => { const b = document.createElement('div'); b.className = 'banner bad'; b.textContent = '页面出错：' + m + '（请截图发给我）'; root.prepend(b); };
  window.addEventListener('error', e => showErr((e.message || e) + (e.filename ? ' @' + e.filename.split('/').pop() + ':' + e.lineno : '')));
  window.addEventListener('unhandledrejection', e => showErr(e.reason && e.reason.message || String(e.reason)));
  root.innerHTML = '<div class="top"><h1>GPT 账号</h1></div><div class="view"><div class="group"><div class="empty">加载中…</div></div></div>';
  let CSRF = root.dataset.csrf;
  const API = '/api/app/gpt/';

  // ---------- 小工具 ----------
  function h(tag, attrs) {
    const el = document.createElement(tag);
    if (attrs) for (const k in attrs) {
      const v = attrs[k];
      if (v == null || v === false) continue;
      if (k === 'class') el.className = v;
      else if (k === 'text') el.textContent = v;
      else if (k.slice(0, 2) === 'on') el.addEventListener(k.slice(2), v);
      else if (k in el && k !== 'list') el[k] = v;
      else el.setAttribute(k, v);
    }
    for (let i = 2; i < arguments.length; i++) add(el, arguments[i]);
    return el;
  }
  function add(el, c) { if (c == null || c === false) return; if (Array.isArray(c)) c.forEach(x => add(el, x)); else el.append(c); }
  function setKids(el) { el.replaceChildren(); for (let i = 1; i < arguments.length; i++) add(el, arguments[i]); }

  async function api(method, path, body) {
    const send = () => fetch(API + path, {
      method, credentials: 'same-origin',
      headers: Object.assign(method !== 'GET' ? { 'X-CSRFToken': CSRF } : {}, body != null ? { 'Content-Type': 'application/json' } : {}),
      body: body == null ? undefined : JSON.stringify(body),
    });
    let r = await send();
    if (method !== 'GET' && r.status === 400) {
      const c = await fetch('/api/app/session', { credentials: 'same-origin' }).then(x => x.json()).catch(() => null);
      if (c && c.csrf) { CSRF = c.csrf; r = await send(); }
    }
    if (r.status === 401) { location.href = '/admin/login?next=/admin/gpt'; throw new Error('登录已过期'); }
    const d = await r.json().catch(() => ({}));
    if (!r.ok || d.ok === false) throw new Error(d.error || '出错了（' + r.status + '）');
    return d;
  }

  function dialog(title, body, buttons, cls) {
    const d = h('dialog', { class: 'dlg' + (cls ? ' ' + cls : '') });
    const close = v => { d.close(); d.remove(); if (d._done) d._done(v); };
    d.append(h('h3', { text: title }), h('div', { class: 'body' }, body),
      h('div', { class: 'foot' }, buttons.map(b => h('button', { class: 'btn ' + (b.cls || ''), type: 'button', text: b.text, onclick: async () => { if (b.run && await b.run() === false) return; close(b.value); } }))));
    d.addEventListener('cancel', e => { e.preventDefault(); close(undefined); });
    document.body.append(d); d.showModal();
    return new Promise(res => { d._done = res; });
  }
  const confirmBox = (t, m, ok, danger) => dialog(t, m, [{ text: '取消' }, { text: ok, cls: danger ? 'danger' : 'primary', value: true }]);
  let toastEl, toastTimer;
  function toast(t) {
    if (!toastEl) { toastEl = h('div', { class: 'vtoast', role: 'status' }); document.body.append(toastEl); }
    toastEl.textContent = t; toastEl.classList.add('show');
    clearTimeout(toastTimer); toastTimer = setTimeout(() => toastEl.classList.remove('show'), 1800);
  }
  async function copy(t, label) { try { await navigator.clipboard.writeText(t); toast('已复制' + (label || '')); } catch (e) { toast('浏览器不让复制'); } }

  const fmt = new Intl.DateTimeFormat('zh-CN', { timeZone: 'Asia/Shanghai', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false });
  const time = iso => { const d = new Date(iso); return isNaN(d) ? (iso || '') : fmt.format(d).replace(/\//g, '-'); };
  function until(iso) {
    const s = Math.round((new Date(iso) - Date.now()) / 1000);
    if (!iso || isNaN(s)) return '';
    if (s <= 0) return '已重置';
    const hh = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60);
    return hh >= 24 ? Math.floor(hh / 24) + ' 天 ' + hh % 24 + ' 小时后重置' : hh ? hh + ' 小时 ' + m + ' 分后重置' : Math.max(1, m) + ' 分钟后重置';
  }
  const iqCls = l => l === '正常' ? 'good' : l === '降智' ? 'bad' : 'muted';

  // ---------- 状态 ----------
  let S = { configured: null, url: '', accounts: [], plan: {}, filter: '', runId: null, run: {}, error: '' };

  async function load() {
    try {
      const c = await api('GET', 'config');
      S.url = c.url; S.configured = !!(c.url && c.hasKey);
      if (S.configured) {
        const [a, p] = await Promise.all([api('GET', 'accounts'), api('GET', 'plan').catch(() => ({ plan: {} }))]);
        S.accounts = a.accounts; S.plan = p.plan || {};
      }
      S.error = '';
    } catch (e) { S.error = e.message; }
    try { render(); } catch (e) { showErr(e.message + ' ' + ((e.stack || '').split('\n')[1] || '').trim()); }
  }

  // ---------- 页面 ----------
  function render() {
    const top = h('div', { class: 'top' }, h('h1', { text: 'GPT 账号' }),
      S.configured ? h('span', { class: 'sub', text: '来自 ' + S.url.replace(/^https?:\/\//, '') }) : null, h('span', { class: 'spacer' }),
      S.configured ? [h('button', { class: 'btn', type: 'button', text: '连接设置', onclick: setupDialog }),
        h('button', { class: 'btn primary', type: 'button', text: '＋ 授权登录', onclick: authDialog })] : null);
    const view = h('div', { class: 'view' });
    setKids(root, top, view);
    if (S.configured === false) return setKids(view, setupCard());
    if (S.configured === null) return setKids(view, h('div', { class: 'group' }, h('div', { class: 'empty', text: S.error || '加载中…' })));
    const list = sorted().filter(a => !S.filter || a.iq.label === S.filter);
    setKids(view,
      counts(),
      planCard(),
      S.error ? h('div', { class: 'banner bad' }, S.error) : null,
      h('div', { class: 'group' },
        h('div', { class: 'group-head' }, h('span', { class: 'group-title', text: '账号' }), h('span', { class: 'pill', text: list.length + ' 个' }),
          h('span', { class: 'group-sum', text: '智商状态看最近一次糖果题（正确答案 21）；连续答错 3 次标记降智' })),
        list.length ? h('div', { class: 'gpt-list' }, list.map(accountRow))
          : h('div', { class: 'empty', text: S.accounts.length ? '没有这一类的账号。' : 'sub2api 里还没有 GPT 账号，点右上角「授权登录」添加。' })));
  }

  function sorted() {
    const order = { '降智': 0, '待确认': 1, '正常': 2 };
    return S.accounts.slice().sort((a, b) => (order[a.iq.label] ?? 3) - (order[b.iq.label] ?? 3) || a.name.localeCompare(b.name));
  }

  function counts() {
    const n = l => S.accounts.filter(a => a.iq.label === l).length;
    const tile = (l, cls) => h('button', { class: 'tile gpt-count ' + cls + (S.filter === l ? ' on' : ''), type: 'button', onclick: () => { S.filter = S.filter === l ? '' : l; render(); } },
      h('div', { class: 'k', text: l }), h('div', { class: 'v', text: String(n(l)) }), h('div', { class: 's', text: S.filter === l ? '再点一下显示全部' : '点一下只看这一类' }));
    return h('div', { class: 'tiles gpt-tiles' }, tile('正常', 'good'), tile('降智', 'bad'), tile('待确认', 'muted'));
  }

  function planCard() {
    const on = !!S.plan.enabled, minutes = S.plan.intervalMinutes || 360;
    const toggle = h('input', { type: 'checkbox', checked: on, onchange: () => savePlan(toggle.checked, minutes) });
    const sel = h('select', { disabled: !on, onchange: () => savePlan(true, +sel.value) },
      [60, 180, 360, 720, 1440].map(m => h('option', { value: m, text: m < 1440 ? '每 ' + m / 60 + ' 小时' : '每天', selected: m === minutes })));
    const running = S.runId != null;
    const done = (S.run.pass || 0) + (S.run.quality_fail || 0) + (S.run.infra_error || 0) + (S.run.skipped || 0);
    return h('div', { class: 'group gpt-plan' },
      h('label', { class: 'gpt-switch' }, toggle, h('span', { class: 'track' }), h('span', null, h('b', { text: '定期智商测试' }),
        h('small', { text: on && S.plan.nextRunAt ? '下次 ' + time(S.plan.nextRunAt) : '在 sub2api 里定时测糖果题，只测 GPT 账号' }))),
      sel,
      h('span', { class: 'spacer' }),
      h('button', { class: 'btn', type: 'button', disabled: running, onclick: () => testRun([]) },
        running ? '测试中 ' + done + '/' + (S.run.accounts || '…') : '▶ 立即测试全部账号'));
  }

  async function savePlan(enabled, minutes) {
    try { S.plan = (await api('POST', 'plan', { enabled, intervalMinutes: minutes })).plan; toast(enabled ? '已开启定期测试' : '已关闭定期测试'); }
    catch (e) { toast(e.message); }
    render();
  }

  async function testRun(ids) {
    try {
      const d = await api('POST', 'test', { account_ids: ids });
      S.runId = d.runId; S.run = { status: 'running' }; render(); toast(ids.length ? '已开始测试' : '已开始测试全部账号');
      while (S.runId != null) {
        await new Promise(r => setTimeout(r, 4000));
        try { S.run = (await api('GET', 'runs/' + S.runId)).run; } catch (e) { continue; }
        if (S.run.status !== 'running') { S.runId = null; await load(); toast('测试完成：答对 ' + (S.run.pass || 0) + '，答错 ' + (S.run.quality_fail || 0)); }
        else render();
      }
    } catch (e) { toast(e.message); }
  }

  function bar(label, w, cls) {
    const used = w && w.used != null ? w.used : null;
    return h('div', { class: 'gpt-bar' },
      h('div', { class: 'gpt-bar-head' }, h('span', { text: label }), h('b', { class: used >= 90 ? 'neg' : '', text: used == null ? '—' : Math.round(used) + '%' })),
      h('div', { class: 'gpt-track' }, h('i', { class: (used >= 90 ? 'hi ' : '') + cls, style: 'width:' + Math.min(100, Math.max(0, used || 0)) + '%' })),
      h('small', { text: w && w.resetAt ? until(w.resetAt) : ' ' }));
  }

  function dots(recent) {
    return h('span', { class: 'gpt-dots' }, (recent || []).slice(-8).map(ok => h('i', { class: ok ? 'ok' : 'no' })), (recent || []).length ? null : h('small', { class: 'faint', text: '还没测过' }));
  }

  const day = iso => { const d = new Date(iso); return isNaN(d) ? '' : (d.getMonth() + 1) + '-' + d.getDate(); };
  // 重置次数（sub2api 每次刷新额度时记下来的）
  function resetBadge(r) {
    if (!r) return null;
    if (!r.known) return h('span', { class: 'gpt-reset unknown', title: '在详情里点「刷新额度」后显示', text: '重置 ?' });
    const t = r.available ? '重置 ' + r.available + ' 次' : '没有重置次数';
    const tip = (r.expiresAt || []).map(e => day(e) + ' 到期').join('、') + (r.auto ? (r.expiresAt.length ? '；' : '') + '已开启自动重置' : '');
    return h('span', { class: 'gpt-reset' + (r.available ? '' : ' none'), title: tip || null, text: t + (r.available && r.expiresAt[0] ? ' · ' + day(r.expiresAt[0]) + ' 到期' : '') + (r.auto ? ' · 自动' : '') });
  }
  function resetText(r) {
    if (!r || !r.known) return '还没刷新过，点上面的「刷新额度」';
    return (r.available ? r.available + ' 次' : '0 次') + (r.expiresAt.length ? '（' + r.expiresAt.map(e => day(e) + ' 到期').join('、') + '）' : '') + (r.auto ? ' · 已开启自动重置' : '');
  }

  function accountRow(a) {
    const iq = a.iq;
    const status = a.status === 'error' ? h('span', { class: 'neg', text: '出错' }) : !a.schedulable ? h('span', { class: 'warn', text: '已暂停调度' })
      : a.rateLimitResetAt && until(a.rateLimitResetAt) !== '已重置' ? h('span', { class: 'warn', text: '限流中' }) : h('span', { class: 'faint', text: '正常调度' });
    return tinted(h('div', { class: 'gpt-row' },
      h('div', { class: 'gpt-who' },
        h('div', null, h('b', { text: a.name || a.email }), a.plan ? h('span', { class: 'gpt-plan-tag', text: a.plan }) : null),
        a.email && a.email !== a.name ? h('button', { class: 'gpt-email', type: 'button', title: '点一下复制', text: a.email, onclick: () => copy(a.email, '邮箱') }) : null,
        h('div', { class: 'gpt-meta' }, status, resetBadge(a.resets), a.lastUsedAt ? h('span', { class: 'faint', text: '最近使用 ' + time(a.lastUsedAt) }) : null)),
      h('div', { class: 'gpt-iq' },
        h('span', { class: 'gpt-badge ' + iqCls(iq.label), text: iq.label + (iq.label === '降智' && iq.consecutiveFails > 1 ? ' ×' + iq.consecutiveFails : '') }),
        dots(iq.recent)),
      bar('5 小时', a.fiveHour, 'c5'),
      bar('7 天', a.sevenDay, 'c7'),
      h('div', { class: 'gpt-actions' },
        h('button', { class: 'btn small', type: 'button', text: '测一次', onclick: () => testRun([a.id]) }),
        h('button', { class: 'btn small', type: 'button', text: '详情', onclick: () => detail(a) }))),
      iq.label === '正常' ? '#0a8558' : iq.label === '降智' ? '#d32f4c' : '#8891a5');
  }

  // ---------- 详情 ----------
  async function detail(a) {
    const info = h('div', { class: 'gpt-kv' });
    const kv = (k, v) => v ? [h('span', { class: 'muted', text: k }), h('span', { text: v })] : null;
    setKids(info, kv('账号', a.email), kv('名称', a.name), kv('套餐', a.plan), kv('订阅到期', a.subscriptionExpiresAt && time(a.subscriptionExpiresAt)),
      kv('状态', a.status === 'error' ? '出错：' + a.error : a.schedulable ? '正常调度' : '已暂停调度'),
      kv('训练数据', a.privacy === 'training_off' ? '已关闭' : a.privacy), kv('额度观测于', a.usageUpdatedAt && time(a.usageUpdatedAt)), kv('重置次数', resetText(a.resets)));
    const quotaBox = h('div', { class: 'gpt-quota' }, bar('5 小时', a.fiveHour, 'c5'), bar('7 天', a.sevenDay, 'c7'));
    const quotaInfo = h('div', { class: 'muted small' });
    const hist = h('div', { class: 'gpt-hist' }, h('div', { class: 'faint', text: '加载中…' }));
    const sched = h('input', { type: 'checkbox', checked: a.schedulable, onchange: async () => {
      try { await api('POST', 'accounts/' + a.id + '/schedulable', { schedulable: sched.checked }); toast(sched.checked ? '已恢复调度' : '已暂停调度'); load(); }
      catch (e) { toast(e.message); sched.checked = !sched.checked; }
    } });
    const refresh = h('button', { class: 'btn small', type: 'button', text: '刷新额度', onclick: async () => {
      refresh.disabled = true; refresh.textContent = '刷新中…';
      try {
        const q = (await api('GET', 'accounts/' + a.id + '/quota')).quota || {};
        const rc = q.rate_limit_reset_credits || {}, cr = q.credits || {};
        quotaInfo.textContent = '可用重置次数 ' + (rc.available_count || 0) + ' · 点数 ' + (cr.unlimited ? '无限' : (cr.balance || '—')) + ' · ' + ((q.rate_limit || {}).limit_reached ? '已到上限' : '当前可用');
        await load(); const fresh = S.accounts.find(x => x.id === a.id); if (fresh) setKids(quotaBox, bar('5 小时', fresh.fiveHour, 'c5'), bar('7 天', fresh.sevenDay, 'c7'));
      } catch (e) { quotaInfo.textContent = e.message; }
      refresh.disabled = false; refresh.textContent = '刷新额度';
    } });
    api('GET', 'accounts/' + a.id + '/results').then(d => {
      setKids(hist, d.results.length ? d.results.map(r => {
        const o = r.outcome, label = o === 'pass' ? '答对' : o === 'quality_fail' ? '答错' : o === 'skipped' ? '跳过' : '请求失败';
        return h('div', { class: 'gpt-hrow' },
          h('span', { class: 'gpt-badge ' + (o === 'pass' ? 'good' : o === 'quality_fail' ? 'bad' : 'muted'), text: label }),
          h('span', { class: 'mono small', text: r.model || '' }),
          h('span', { class: 'small faint', text: (r.reason || '') + (r.detail ? ' · ' + r.detail : '') }),
          h('span', { class: 'spacer' }),
          h('span', { class: 'small faint', text: (r.duration_ms ? (r.duration_ms / 1000).toFixed(1) + ' 秒 · ' : '') + time(r.created_at) }));
      }) : h('div', { class: 'faint', text: '还没有测试记录' }));
    }).catch(e => setKids(hist, h('div', { class: 'neg', text: e.message })));
    await dialog(a.name || a.email, [
      info,
      h('div', { class: 'gpt-sec' }, h('b', { text: '额度' }), refresh), quotaBox, quotaInfo,
      h('div', { class: 'gpt-sec' }, h('b', { text: '操作' })),
      h('div', { class: 'gpt-ops' },
        h('button', { class: 'btn small', type: 'button', text: '测一次智商', onclick: () => testRun([a.id]) }),
        h('label', { class: 'check' }, sched, '参与调度'),
        h('button', { class: 'btn small danger', type: 'button', text: '删除这个账号', onclick: async () => {
          if (!await confirmBox('删除这个 GPT 账号？', '会从 sub2api 里删除「' + (a.name || a.email) + '」，不能恢复。', '删除', true)) return;
          try { await api('DELETE', 'accounts/' + a.id); toast('已删除'); document.querySelector('dialog.gpt-detail')?.close(); load(); } catch (e) { toast(e.message); }
        } })),
      h('div', { class: 'gpt-sec' }, h('b', { text: '智商测试记录（糖果题，正确答案 21）' })), hist,
    ], [{ text: '关闭', cls: 'primary' }], 'gpt-detail');
  }

  // ---------- 授权登录 ----------
  async function authDialog() {
    let session = '';
    const err = h('div', { class: 'neg' });
    const link = h('div', { class: 'small muted' });
    const cb = h('textarea', { rows: 3, placeholder: 'http://localhost:1455/auth/callback?code=…&state=…', spellcheck: false });
    const name = h('input', { type: 'text', placeholder: '名称（可不填，默认用邮箱）' });
    const open = h('button', { class: 'btn primary', type: 'button', text: '1. 打开授权页面', onclick: async () => {
      try {
        const d = await api('POST', 'oauth/start', {});
        session = d.sessionId; window.open(d.authUrl, '_blank', 'noopener');
        setKids(link, '已在新标签页打开（30 分钟内有效）。没弹出来的话：', h('a', { href: d.authUrl, target: '_blank', rel: 'noopener', text: '点这里打开' }));
        open.textContent = '重新打开授权页面';
      } catch (e) { err.textContent = e.message; }
    } });
    await dialog('授权登录 GPT', [
      h('div', { class: 'muted', text: '在打开的 OpenAI 页面里，用要添加的 GPT 账号登录并同意授权。' }), open, link,
      h('label', { class: 'field' }, '2. 登录完浏览器会跳到一个 http://localhost 开头、打不开的页面（这是正常的），把地址栏的完整地址粘贴到这里', cb),
      h('label', { class: 'field' }, '名称', name), err,
    ], [{ text: '取消' }, { text: '添加', cls: 'primary', run: async () => {
      if (!session) { err.textContent = '请先打开授权页面并登录'; return false; }
      try { const d = await api('POST', 'oauth/finish', { sessionId: session, callback: cb.value.trim(), name: name.value.trim() }); toast('已添加 ' + (d.account.email || '')); load(); }
      catch (e) { err.textContent = e.message; return false; }
    } }], 'gpt-auth');
  }

  // ---------- 连接设置 ----------
  function setupForm(done) {
    const url = h('input', { type: 'text', value: S.url, placeholder: 'https://api.example.com', spellcheck: false, autocomplete: 'off' });
    const key = h('input', { type: 'password', placeholder: S.configured ? '管理员 API Key（不改就留空）' : '管理员 API Key', autocomplete: 'off' });
    const err = h('div', { class: 'neg' });
    const save = async () => {
      err.textContent = '';
      try { const b = { url: url.value.trim() }; if (key.value.trim()) b.key = key.value.trim(); await api('POST', 'config', b); toast('已连接 sub2api'); done && done(); await load(); return true; }
      catch (e) { err.textContent = e.message; return false; }
    };
    return { save, el: [
      h('label', { class: 'field' }, 'sub2api 地址', url),
      h('label', { class: 'field' }, '管理员 API Key', key),
      h('div', { class: 'muted small gpt-help' },
        'GPT 账号、额度和智商测试都在你自己的 sub2api 里，这里只是读取和操作。\nKey 在 sub2api 后台创建：系统设置 → 安全与认证 → 管理员访问密钥 → 创建管理密钥，并勾选「全权访问」（不勾选的话读不到智商测试，也不能授权登录）。Key 只显示一次。\nKey 加密保存在本站服务器上，不会发到浏览器或手机。'),
      err] };
  }
  function setupCard() {
    const f = setupForm();
    return h('div', { class: 'group gpt-setup' }, h('div', { class: 'group-head' }, h('span', { class: 'group-title', text: '连接 sub2api' })),
      h('div', { class: 'gpt-setup-body' }, f.el, h('button', { class: 'btn primary', type: 'button', text: '保存并连接', onclick: f.save })));
  }
  async function setupDialog() {
    const f = setupForm();
    await dialog('连接设置', f.el, [{ text: '取消' }, { text: '保存', cls: 'primary', run: f.save }]);
  }

  load();
})();
