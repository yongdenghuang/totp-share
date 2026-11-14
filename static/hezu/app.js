'use strict';
(function () {
  const COUNTRIES = ['美国', '菲律宾', '尼日利亚', '中国', '香港', '新加坡', '英国', '欧洲'];
  const SEED_ISSUERS = [['Wise', ''], ['Maya Bank', '菲律宾'], ['PalawanPay', '菲律宾'], ['Revolut', ''], ['PayPal', ''], ['Krak', ''], ['Bybit EU', '欧洲'], ['Moniepoint', '尼日利亚']];
  const COUNTRY_GUESS = { mayabank: '菲律宾', maya: '菲律宾', palawanpay: '菲律宾', moniepoint: '尼日利亚', paga: '尼日利亚', bybiteu: '欧洲' };
  const ICONS = {
    grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
    users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
    play: '<rect x="2" y="4" width="20" height="14" rx="2"/><path d="M8 21h8"/><path d="m10 8 5 3-5 3z"/>',
    card: '<rect x="2" y="5" width="20" height="14" rx="2"/><path d="M2 10h20"/><path d="M6 15h4"/>',
    server: '<rect x="2" y="3" width="20" height="8" rx="2"/><rect x="2" y="13" width="20" height="8" rx="2"/><path d="M6 7h.01M6 17h.01"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    more: '<circle cx="5" cy="12" r="1.2"/><circle cx="12" cy="12" r="1.2"/><circle cx="19" cy="12" r="1.2"/>',
    chev: '<path d="m6 9 6 6 6-6"/>',
    left: '<path d="m15 18-6-6 6-6"/>',
    right: '<path d="m9 18 6-6-6-6"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/>',
    archive: '<rect x="2" y="3" width="20" height="5" rx="1"/><path d="M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8M10 12h4"/>',
    key: '<circle cx="8" cy="15" r="4"/><path d="m11 12 9-9M17 6l3 3M14 9l2 2"/>',
    list: '<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>',
    gear: '<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M2 12h3M19 12h3M4.9 19.1 7 17M17 7l2.1-2.1"/>',
  };

  let S = null;                       // 账本数据（加密存在服务器上）
  let G = [];                         // 分组：和验证码账号共用一套，以验证码后台为准
  let A = [];                         // 验证码账号名单（不含密钥和密码）
  let CSRF = document.getElementById('app').dataset.csrf || '';
  const API = '/admin/hezu/api';
  const codes = { map: {}, until: 0, timer: null, els: [] };   // 当前验证码，只显示不保存
  const view = { tab: 'home', month: null, unlocked: {}, q: '', country: '' };
  let updaters = [];                  // 改数字后需要刷新的合计
  let searchRows = [];                // 当前页面可被搜索过滤的行
  let dirty = false, saving = false, saveTimer = null, statusEl = null;
  let collapsed = {};
  try { collapsed = JSON.parse(localStorage.getItem('hezu-collapsed') || '{}') || {}; } catch (e) { collapsed = {}; }

  // ---------- 小工具 ----------
  function h(tag, attrs) {
    const el = document.createElement(tag);
    if (attrs) for (const k in attrs) {
      const v = attrs[k];
      if (v == null || v === false) continue;
      if (k === 'class') el.className = v;
      else if (k === 'text') el.textContent = v;
      else if (k.slice(0, 2) === 'on') el.addEventListener(k.slice(2), v);
      else if (k !== 'list' && k in el) el[k] = v;
      else el.setAttribute(k, v);
    }
    for (let i = 2; i < arguments.length; i++) add(el, arguments[i]);
    return el;
  }
  function add(el, c) {
    if (c == null || c === false) return;
    if (Array.isArray(c)) c.forEach(x => add(el, x)); else el.append(c);
  }
  function setKids(el) { el.replaceChildren(); for (let i = 1; i < arguments.length; i++) add(el, arguments[i]); }
  function icon(name, size) {
    const s = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    const a = { viewBox: '0 0 24 24', width: size || 17, height: size || 17, fill: 'none', stroke: 'currentColor', 'stroke-width': 1.9, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'aria-hidden': 'true' };
    for (const k in a) s.setAttribute(k, a[k]);
    s.innerHTML = ICONS[name];
    return s;
  }
  const p2 = n => String(n).padStart(2, '0');
  const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
  function num(v) {
    if (typeof v === 'number') return isFinite(v) ? v : 0;
    const n = parseFloat(String(v == null ? '' : v).replace(/[,，¥\s]/g, ''));
    return isFinite(n) ? n : 0;
  }
  const round2 = n => Math.round(n * 100) / 100;
  const plain = n => String(round2(num(n)));
  function money(n) {
    n = round2(num(n));
    const s = Math.abs(n).toLocaleString('zh-CN', { minimumFractionDigits: Number.isInteger(n) ? 0 : 2, maximumFractionDigits: 2 });
    return (n < 0 ? '-¥' : '¥') + s;
  }
  const isISO = s => /^\d{4}-\d{2}-\d{2}$/.test(s || '');
  function todayISO() { const d = new Date(); return d.getFullYear() + '-' + p2(d.getMonth() + 1) + '-' + p2(d.getDate()); }
  function shiftMonth(iso, n) {
    if (!isISO(iso)) return iso || '';
    let [y, m, d] = iso.split('-').map(Number);
    m += n; y += Math.floor((m - 1) / 12); m = ((m - 1) % 12 + 12) % 12 + 1;
    return y + '-' + p2(m) + '-' + p2(Math.min(d, new Date(y, m, 0).getDate()));
  }
  function nextYM(ym) { let [y, m] = ym.split('-').map(Number); if (++m > 12) { m = 1; y++; } return y + '-' + p2(m); }
  function ymLabel(ym) { const [y, m] = ym.split('-'); return y + ' 年 ' + Number(m) + ' 月'; }
  function daysUntil(iso) { return isISO(iso) ? Math.round((new Date(iso + 'T00:00:00') - new Date(todayISO() + 'T00:00:00')) / 864e5) : null; }
  function dateText(iso) {
    if (!isISO(iso)) return '';
    const [y, m, d] = iso.split('-').map(Number);
    return (y === new Date().getFullYear() ? '' : y + ' 年 ') + m + ' 月 ' + d + ' 日';
  }
  function relText(d) { return d < 0 ? '过期 ' + (-d) + ' 天' : d === 0 ? '今天' : d === 1 ? '明天' : d + ' 天后'; }
  const monthKeys = () => Object.keys(S.months).sort();
  const latestMonth = () => monthKeys().slice(-1)[0];
  const isEditable = () => !S.months[view.month].archived || !!view.unlocked[view.month];
  const LOOSE = { name: '未分组', color: '#8891a5', text: '#ffffff' };
  const totpById = id => A.find(a => a.id === id) || null;
  const normName = s => String(s || '').replace(/\s+/g, ' ').trim().toLowerCase();
  const sleep = ms => new Promise(r => setTimeout(r, ms));

  // ---------- 支付卡 ----------
  const digits = s => String(s || '').replace(/\D/g, '');
  const normKey = s => String(s || '').toLowerCase().replace(/[\s\-_.:：·,，]/g, '');
  const issuerById = id => S.issuers.find(i => i.id === id) || null;
  const cardById = id => S.cards.find(c => c.id === id) || null;
  const cardsOf = issuerId => S.cards.filter(c => c.issuerId === issuerId);
  const issuerLabel = i => i.name + (i.country ? ' · ' + i.country : '');
  function cardLabel(c, full) {
    if (!c) return '';
    const d = String(c.number || '').replace(/\s/g, '');
    const base = !full && /^\d{8,}$/.test(d) ? '•••• ' + d.slice(-4) : (c.number || '');
    return [base, c.note].filter(Boolean).join(' · ') || '未填卡号';
  }
  function ensureIssuer(name, country) {
    const key = normKey(name);
    let it = S.issuers.find(i => normKey(i.name) === key);
    if (!it) { it = { id: 'i_' + uid(), name: String(name).trim(), country: COUNTRY_GUESS[key] || '' }; S.issuers.push(it); }
    if (country && !it.country) it.country = country;
    return it;
  }
  // "dtcpay2号" -> { name: "dtcpay", tag: "2号" }
  function splitInfo(text) {
    let t = String(text || '').trim(), country = '';
    const c = t.match(new RegExp('^(' + COUNTRIES.join('|') + ')\\s+(.+)$'));
    if (c) { country = c[1]; t = c[2].trim(); }
    const m = t.match(/^(.+?)\s*(\d+\s*号)$/);
    return m ? { name: m[1].trim(), tag: m[2].replace(/\s/g, ''), country } : { name: t, tag: '', country };
  }
  // 把旧版本里手打的“卡信息 / 卡号”文字，转成卡种和卡号的引用
  function migrateCards(rows) {
    const best = {};   // 同一个卡号出现在多种写法下时，取最短的那个当卡种名
    for (const r of rows) {
      const n = digits(r.cardNo);
      if (n.length >= 12 && r.cardInfo) { const nm = splitInfo(r.cardInfo).name; if (nm && (!best[n] || nm.length < best[n].length)) best[n] = nm; }
    }
    for (const r of rows) {
      const n = digits(r.cardNo), isNum = n.length >= 12, info = splitInfo(r.cardInfo);
      let issuer = null, card = null;
      if (isNum) { card = S.cards.find(c => digits(c.number) === n) || null; if (card) issuer = issuerById(card.issuerId); }
      if (!issuer) {
        const name = (isNum && best[n]) || info.name;
        if (name) issuer = ensureIssuer(name, info.country); else if (r.cardNo) issuer = ensureIssuer('未分类');
      }
      if (issuer) {
        const sameName = normKey(info.name) === normKey(issuer.name);
        if (!card && r.cardNo) {
          const text = isNum ? n : String(r.cardNo).trim();
          card = cardsOf(issuer.id).find(c => isNum ? digits(c.number) === n : c.number === text) || null;
          if (!card) { card = { id: 'c_' + uid(), issuerId: issuer.id, number: text, note: sameName ? info.tag : '' }; S.cards.push(card); }
        } else if (!card && info.tag && sameName) {
          card = cardsOf(issuer.id).find(c => !c.number && c.note === info.tag) || null;
          if (!card) { card = { id: 'c_' + uid(), issuerId: issuer.id, number: '', note: info.tag }; S.cards.push(card); }
        }
        r.issuerId = issuer.id; r.cardId = card ? card.id : '';
        if (r.cardInfo && !sameName) r.note = [r.note, r.cardInfo].filter(Boolean).join(' · ');
      }
      delete r.cardInfo; delete r.cardNo;
    }
  }
  function cardStats(ym) {
    const byIssuer = {}, byCard = {}, none = { n: 0, cost: 0 };
    const M = S.months[ym];
    for (const sh of S.sheets) for (const r of (M.rows[sh.id] || [])) {
      const c = num(r.cost);
      if (!r.issuerId) { if (c) { none.n++; none.cost += c; } continue; }
      const a = byIssuer[r.issuerId] || (byIssuer[r.issuerId] = { n: 0, cost: 0 }); a.n++; a.cost += c;
      if (r.cardId) { const b = byCard[r.cardId] || (byCard[r.cardId] = { n: 0, cost: 0 }); b.n++; b.cost += c; }
    }
    return { byIssuer, byCard, none };
  }

  // ---------- 数据 ----------
  function fixRow(r) {
    r = r || {};
    const o = {
      id: r.id || uid(), group: r.group || '', account: r.account || '', renew: r.renew || '',
      issuerId: r.issuerId || '', cardId: r.cardId || '', totpId: Number(r.totpId) || 0,
      members: (r.members || []).map(m => ({ name: m.name || '', amount: num(m.amount), paid: !!m.paid })),
      unitPrice: num(r.unitPrice), count: num(r.count), cost: num(r.cost), note: r.note || '', stopped: !!r.stopped,
    };
    if (!o.issuerId && (r.cardInfo || r.cardNo)) { o.cardInfo = String(r.cardInfo || ''); o.cardNo = String(r.cardNo || ''); }
    return o;
  }
  function normalize() {
    delete S['groups']; S.sheets = S.sheets || []; S.months = S.months || {}; S.vps = S.vps || [];
    let changed = false;
    if (!Array.isArray(S.issuers)) {
      try { localStorage.setItem('hezu-before-cards', JSON.stringify(S)); } catch (e) { /* 存不下就算了 */ }
      S.issuers = SEED_ISSUERS.map(x => ({ id: 'i_' + uid(), name: x[0], country: x[1] })); changed = true;
    }
    S.cards = S.cards || [];
    if (!Object.keys(S.months).length) { S.months[todayISO().slice(0, 7)] = { archived: false, rows: {} }; changed = true; }
    const legacy = [];
    for (const ym of Object.keys(S.months).sort()) {
      const M = S.months[ym]; M.rows = M.rows || {};
      for (const sh of S.sheets) { M.rows[sh.id] = (M.rows[sh.id] || []).map(fixRow); M.rows[sh.id].forEach(r => { if ('cardInfo' in r) legacy.push(r); }); }
    }
    if (legacy.length) { migrateCards(legacy); changed = true; }
    const issuerIds = new Set(S.issuers.map(i => i.id));
    S.cards = S.cards.filter(c => issuerIds.has(c.issuerId));
    for (const ym in S.months) for (const sh of S.sheets) for (const r of S.months[ym].rows[sh.id]) {
      if (r.issuerId && !issuerIds.has(r.issuerId)) { r.issuerId = ''; r.cardId = ''; }
      if (r.cardId) { const c = cardById(r.cardId); if (!c || c.issuerId !== r.issuerId) r.cardId = ''; }
    }
    S.vps = S.vps.map(v => Object.assign({ id: uid(), host: '', ip: '', password: '', deploy: '', traffic: '', renew: '', price: '', email: '' }, v));
    if (!view.month || !S.months[view.month]) view.month = latestMonth();
    if (!['home', 'cards', 'vps'].includes(view.tab) && !S.sheets.some(s => s.id === view.tab)) view.tab = 'home';
    if (linkTotp()) changed = true;
    if (changed) touch();
  }
  // 账号和某个验证码账号同名（且只有一个）时自动关联。totpId: 0 = 没关联，-1 = 手动取消过，不再自动关联
  function linkTotp() {
    const byName = {}; let n = 0;
    A.forEach(a => { const k = normName(a.name); (byName[k] = byName[k] || []).push(a); });
    for (const ym in S.months) for (const sh of S.sheets) for (const r of S.months[ym].rows[sh.id]) {
      if (r.totpId > 0 && !totpById(r.totpId)) { r.totpId = 0; n++; }
      if (!r.totpId && r.account) { const m = byName[normName(r.account)]; if (m && m.length === 1) { r.totpId = m[0].id; n++; onLinked(r, sh, ym); } }
    }
    if (pullGroups()) n++;
    return n > 0;
  }
  // ---------- 分组两边保持一致 ----------
  // 关联了验证码账号的行，分组以验证码账号为准；只动进行中的月份，存档保持当时的样子。
  const groupIdByName = name => { const g = G.find(x => x.name === name); return g ? g.id : ''; };
  function pullGroups() {
    let n = 0;
    for (const ym in S.months) if (!S.months[ym].archived) for (const sh of S.sheets) if (sh.grouped) for (const r of S.months[ym].rows[sh.id] || []) {
      const a = r.totpId > 0 ? totpById(r.totpId) : null; if (!a) continue;
      const gid = groupIdByName(a.group);
      if (r.group !== gid) { r.group = gid; n++; }
    }
    return n > 0;
  }
  // 把验证码账号那边的分组改成 groupId 对应的分组（'' = 未分组）。先改本地再发请求，失败了下次打开会以服务器为准。
  function pushGroup(totpId, groupId) {
    const a = totpById(totpId), g = G.find(x => x.id === groupId); if (!a) return;
    a.group = g ? g.name : '';
    api('POST', '/admin/accounts/' + totpId + '/field', { field: 'group_name', value: a.group })
      .then(r => { if (!r.ok) setStatus('验证码账号的分组没改成，请刷新页面', true); }).catch(() => setStatus('验证码账号的分组没改成，请刷新页面', true));
  }
  // 刚关联上的那一刻：验证码账号有分组就跟它走；它没分组而这一行有，就把这一行的分组带过去
  function onLinked(row, sheet, ym) {
    const a = totpById(row.totpId);
    if (!a || !sheet.grouped || S.months[ym].archived) return;
    if (!a.group && row.group && G.some(g => g.id === row.group)) pushGroup(a.id, row.group);
  }
  function moveRow(row, groupId) {
    row.group = groupId;
    if (row.totpId > 0 && totpById(row.totpId) && !S.months[view.month].archived) { pushGroup(row.totpId, groupId); pullGroups(); }
    touch(); render();
  }
  function income(sheet, r) { return sheet.mode === 'members' ? r.members.reduce((a, m) => a + num(m.amount), 0) : num(r.unitPrice) * num(r.count); }
  function heads(sheet, r) { return sheet.mode === 'members' ? r.members.length : num(r.count); }
  const zero = () => ({ n: 0, heads: 0, income: 0, cost: 0, profit: 0 });
  function stats(sheet, rows) {
    const s = zero();
    for (const r of rows) { if (!r.stopped) s.n++; s.heads += heads(sheet, r); s.income += income(sheet, r); s.cost += num(r.cost); }
    s.profit = s.income - s.cost;
    return s;
  }
  function addStats(a, b) { for (const k in a) a[k] += b[k]; return a; }
  // 一个月按“分组 / 表”拆开的统计
  function breakdown(ym) {
    const M = S.months[ym], out = [];
    for (const sh of S.sheets) {
      const rows = (M.rows[sh.id] || []);
      if (sh.grouped) {
        const ids = new Set(G.map(g => g.id));
        for (const g of G) out.push({ key: 'g:' + g.id, label: g.name, color: g.color, text: g.text, sheet: sh.id, rows: rows.filter(r => r.group === g.id).length, st: stats(sh, rows.filter(r => r.group === g.id)) });
        const loose = rows.filter(r => !ids.has(r.group));
        if (loose.length) out.push({ key: 'loose:' + sh.id, label: '未分组', color: LOOSE.color, text: LOOSE.text, sheet: sh.id, rows: loose.length, st: stats(sh, loose) });
      } else out.push({ key: 's:' + sh.id, label: sh.name, color: null, sheet: sh.id, rows: rows.length, st: stats(sh, rows) });
    }
    return out;
  }
  function monthTotal(ym) { const t = zero(); breakdown(ym).forEach(p => addStats(t, p.st)); return t; }

  // ---------- 接口与保存 ----------
  async function api(method, path, body, raw) {
    const send = () => {
      const headers = {};
      if (method !== 'GET') headers['X-CSRFToken'] = CSRF;
      if (body != null && !raw) headers['Content-Type'] = 'application/json';
      return fetch(path.startsWith('/admin/') ? path : API + path, { method, headers, credentials: 'same-origin', body: body == null ? undefined : raw ? body : JSON.stringify(body) });
    };
    let r = await send();
    // 页面开久了防伪令牌会过期，重新登录后也会换：换一个新的再试一次。
    // 登录过期时服务器先报的是令牌无效（400），所以要靠这一步分辨出“其实是没登录”。
    if (method !== 'GET' && (r.status === 400 || r.status === 401)) {
      const ctx = await refreshContext();
      if (ctx === true) r = await send();
      else if (ctx === 'expired') r = new Response('{}', { status: 401 });
    }
    return r;
  }
  function useContext(d) { if (d.csrf) CSRF = d.csrf; if (d.groups) G = d.groups; if (d.accounts) A = d.accounts; }
  async function refreshContext() {
    try {
      const r = await fetch(API + '/context', { credentials: 'same-origin' });
      if (r.ok) { useContext(await r.json()); return true; }
      if (r.status === 401) return 'expired';
    } catch (e) { /* 断网，下次再试 */ }
    return false;
  }
  function setStatus(text, err) { if (statusEl) { statusEl.textContent = text; statusEl.className = 'status' + (err ? ' err' : ''); } }
  function touch() {
    dirty = true; setStatus('有改动…');
    clearTimeout(saveTimer); saveTimer = setTimeout(save, 900);
  }
  function saveNow() { dirty = true; clearTimeout(saveTimer); save(); }   // 归档、导入这类大改动立刻存，不等防抖
  // 登录过期时的提示条：改动留在页面里，重新登录后自动补存
  let reloginBar = null;
  function showRelogin(on) {
    if (on && !reloginBar) {
      reloginBar = h('div', { class: 'relogin', role: 'alert' }, h('span', { text: '登录已过期，刚才的改动还没保存。' }),
        h('a', { class: 'btn small primary', href: '/admin/login?next=/admin/hezu', target: '_blank', rel: 'noopener', text: '在新窗口重新登录' }),
        h('span', { class: 'muted', text: '登录后回到这里，会自动保存。' }));
      document.body.append(reloginBar);
    } else if (!on && reloginBar) { reloginBar.remove(); reloginBar = null; }
  }
  async function save() {
    if (saving || !dirty) return;
    saving = true; dirty = false; setStatus('保存中…');
    let again = 900;   // 保存期间又有改动时，多久后再存一次
    if (reloginBar && (await refreshContext()) !== true) {   // 还没重新登录：先别反复上传整份账本
      saving = false; dirty = true; setStatus('登录已过期', true);
      clearTimeout(saveTimer); saveTimer = setTimeout(save, 5000); return;
    }
    try {
      const r = await api('PUT', '/state', { rev: S.rev, state: S });
      if (r.status === 401) { dirty = true; again = 5000; setStatus('登录已过期', true); showRelogin(true); }
      else if (r.status === 409) {
        dirty = false;
        await alertBox('账本已经在别的窗口或设备上改过了。\n为了不互相覆盖，这里会重新加载最新数据，刚才这一下的改动需要重做。');
        saving = false; return load();
      }
      else if (!r.ok) throw new Error('HTTP ' + r.status);
      else {
        const d = await r.json(); S.rev = d.rev; if (d.csrf) CSRF = d.csrf;
        showRelogin(false);
        const t = new Date(); setStatus('已保存 ' + p2(t.getHours()) + ':' + p2(t.getMinutes()));
      }
    } catch (e) {
      dirty = true; again = 5000; setStatus('保存失败，稍后自动重试', true);
    } finally {
      saving = false;
    }
    if (dirty) { clearTimeout(saveTimer); saveTimer = setTimeout(save, again); }
  }
  // 离开本页（去验证码后台、退出登录）前，把没存完的先存掉
  async function settle() {
    clearTimeout(saveTimer);
    for (let i = 0; i < 60 && saving; i++) await sleep(100);
    if (dirty) await save();
  }
  async function leave(url) { await settle(); location.href = url; }
  window.addEventListener('beforeunload', e => { if (dirty || saving) { e.preventDefault(); e.returnValue = ''; } });

  // 从验证码各页的导航点过来时，地址里带着要看的分页（#ai、#cards……）
  function tabFromHash() {
    let t = ''; try { t = decodeURIComponent(location.hash.slice(1)); } catch (e) { t = ''; }
    if (t === 'new-sheet') { history.replaceState(null, '', location.pathname); return 'new-sheet'; }
    if (t) view.tab = t;
    return t;
  }
  function adopt(d) { useContext(d); S = d.state; S.rev = d.rev; dirty = false; const t = tabFromHash(); normalize(); render(); pollCodes(); if (t === 'new-sheet') sheetForm(null); }
  function openAddFromLink() {
    if (!new URLSearchParams(location.search).has('add')) return;
    history.replaceState(null, '', location.pathname);
    view.month = latestMonth();
    const sheet = S.sheets.find(s => s.grouped) || S.sheets[0];
    if (sheet) view.tab = sheet.id;
    render(); addAccountDialog({ sheet });
  }
  async function load() {
    const r = await fetch(API + '/state', { credentials: 'same-origin' });
    if (r.status === 401) { location.href = '/admin/login?next=/admin/hezu'; return; }
    if (!r.ok) throw new Error('HTTP ' + r.status);
    adopt(await r.json());
    openAddFromLink();
  }

  // ---------- 验证码（取自验证码后台，只在页面上显示，不写进账本） ----------
  async function pollCodes() {
    clearTimeout(codes.timer);
    if (!A.length) return;
    let wait = 30000;
    try {
      const r = await fetch('/admin/codes', { credentials: 'same-origin' });
      if (r.ok) { const d = await r.json(); codes.map = d.codes || {}; codes.until = Date.now() + d.remaining * 1000; wait = d.remaining * 1000 + 500; }
      else codes.map = {};
    } catch (e) { /* 断网时稍后再取 */ }
    paintCodes();
    codes.timer = setTimeout(pollCodes, wait);
  }
  function paintCodes() {
    const left = Math.max(0, Math.round((codes.until - Date.now()) / 1000));
    for (const x of codes.els) {
      if (x.el.dataset.busy) continue;
      const c = codes.map[String(x.id)];
      x.el.textContent = c ? c.slice(0, 3) + ' ' + c.slice(3) : '··· ···';
      x.el.classList.toggle('low', !!c && left <= 5);
      x.el.title = c ? '点一下复制验证码，' + left + ' 秒后更新' : '暂时取不到验证码';
    }
  }
  setInterval(paintCodes, 1000);
  async function copyText(text, el) {
    try { await navigator.clipboard.writeText(text); } catch (e) { await alertBox('浏览器不让自动复制，请手动复制：\n' + text); return; }
    if (!el) return;
    el.dataset.busy = '1'; el.textContent = '已复制';
    setTimeout(() => { delete el.dataset.busy; paintCodes(); }, 900);
  }
  function totpChip(row) {
    const a = row.totpId > 0 ? totpById(row.totpId) : null;
    if (!a) return null;
    const b = h('button', { class: 'code', type: 'button', 'aria-label': '复制验证码', onclick: () => { const c = codes.map[String(a.id)]; if (c) copyText(c, b); } });
    codes.els.push({ id: a.id, el: b });
    return b;
  }
  function linkTotpMenu(anchor, row) {
    const q = h('input', { type: 'text', placeholder: '搜索验证码账号', autocomplete: 'off' }), list = h('div', { class: 'picklist' });
    const draw = () => {
      const k = q.value.trim().toLowerCase();
      const items = A.filter(a => !k || (a.name + ' ' + a.group).toLowerCase().includes(k)).slice(0, 50);
      setKids(list, items.map(a => h('button', { class: 'item', type: 'button', onclick: () => { row.totpId = a.id; closePop(); const sh = S.sheets.find(x => x.id === view.tab); if (sh) onLinked(row, sh, view.month); pullGroups(); touch(); render(); } },
        a.name, a.group ? h('span', { class: 'faint', text: '  ' + a.group }) : null)), items.length ? null : h('div', { class: 'label', text: '没有匹配的验证码账号' }));
    };
    q.addEventListener('input', draw); draw();
    openPop(anchor, [h('div', { class: 'form' }, h('label', { class: 'field' }, '关联到哪个验证码账号', q)), list, h('div', { class: 'sep' }),
      h('button', { class: 'item', type: 'button', text: '＋ 新建验证码账号…', onclick: () => { closePop(); leave('/admin/accounts/new?name=' + encodeURIComponent(row.account || '')); } })]);
    q.focus();
  }
  async function copyShareInfo(row) {
    const r = await api('POST', '/admin/accounts/' + row.totpId + '/share-text', {});
    const d = await r.json().catch(() => ({}));
    if (!r.ok || !d.ok) return alertBox(d.error || '取不到分享信息，请刷新页面后再试。');
    await copyText(d.text);
    setStatus(d.has_password ? '已复制分享信息' : '已复制分享信息（这个账号没存密码）');
  }

  // ---------- 弹层 ----------
  let pop = null;
  function closePop() {
    if (!pop) return;
    const p = pop; pop = null;
    p.el.remove();
    document.removeEventListener('mousedown', p.down, true);
    document.removeEventListener('keydown', p.key, true);
    if (p.onClose) p.onClose();
  }
  function openPop(anchor, content, onClose) {
    closePop();
    const el = h('div', { class: 'pop' }, content);
    document.body.append(el);
    const r = anchor.getBoundingClientRect();
    const left = Math.max(8, Math.min(r.left, window.innerWidth - el.offsetWidth - 8));
    let top = r.bottom + 4;
    if (top + el.offsetHeight > window.innerHeight - 8 && r.top - el.offsetHeight - 4 > 8) top = r.top - el.offsetHeight - 4;
    el.style.left = (left + window.scrollX) + 'px'; el.style.top = (top + window.scrollY) + 'px';
    const p = { el, onClose };
    p.down = e => { if (!el.contains(e.target)) closePop(); };
    p.key = e => { if (e.key === 'Escape') closePop(); };
    document.addEventListener('mousedown', p.down, true);
    document.addEventListener('keydown', p.key, true);
    pop = p;
    return el;
  }
  function menu(anchor, items) {
    const els = items.filter(Boolean).map(it => {
      if (it === '-') return h('div', { class: 'sep' });
      if (it.label) return h('div', { class: 'label', text: it.label });
      return h('button', { class: 'item' + (it.danger ? ' danger' : ''), type: 'button', text: it.text, onclick: () => { closePop(); it.run(); } });
    });
    openPop(anchor, els);
  }
  function dialog(title, body, buttons) {
    const d = h('dialog', { class: 'dlg' });
    const close = v => { d.close(); d.remove(); if (d._done) d._done(v); };
    d.append(h('h3', { text: title }), h('div', { class: 'body' }, body),
      h('div', { class: 'foot' }, buttons.map(b => h('button', { class: 'btn ' + (b.cls || ''), type: 'button', text: b.text, onclick: async () => { if (b.run && await b.run() === false) return; close(b.value); } }))));
    d.addEventListener('cancel', e => { e.preventDefault(); close(undefined); });
    d.addEventListener('keydown', e => { if (e.key === 'Enter' && e.target.tagName === 'INPUT') { const ok = d.querySelector('.foot .primary'); if (ok) { e.preventDefault(); ok.click(); } } });
    document.body.append(d); d.showModal();
    return new Promise(res => { d._done = res; });
  }
  const confirmBox = (title, msg, okText, danger) => dialog(title, msg, [{ text: '取消' }, { text: okText || '确定', cls: danger ? 'danger' : 'primary', value: true }]);
  const alertBox = msg => dialog('提示', msg, [{ text: '知道了', cls: 'primary' }]);

  // ---------- 输入框 ----------
  function maskNumber(v) { v = String(v || ''); const d = v.replace(/\s/g, ''); return /^\d{8,}$/.test(d) ? '•••• •••• •••• ' + d.slice(-4) : v; }
  function maskAll(v) { return v ? '••••••••' : ''; }
  // opts: num, right, mask('card'|'all'), placeholder, cls, ro, after(), title
  function cell(obj, key, opts) {
    opts = opts || {};
    const masker = opts.mask === 'card' ? maskNumber : opts.mask === 'all' ? maskAll : null;
    const show = () => opts.num ? (num(obj[key]) ? plain(obj[key]) : '') : (obj[key] || '');
    const inp = h('input', {
      class: 'cell' + (opts.num || opts.right ? ' r' : '') + (opts.cls ? ' ' + opts.cls : ''), type: 'text',
      placeholder: opts.placeholder || (opts.num ? '0' : ''), readOnly: !!opts.ro, title: opts.title,
      autocomplete: 'off', spellcheck: false, inputMode: opts.num ? 'decimal' : undefined, list: opts.list,
      'aria-label': opts.label,
    });
    inp.value = masker ? masker(obj[key]) : show();
    if (masker) {
      inp.addEventListener('focus', () => { inp.value = obj[key] || ''; });
      inp.addEventListener('blur', () => { inp.value = masker(obj[key]); });
    } else if (opts.num) inp.addEventListener('blur', () => { inp.value = show(); });
    inp.addEventListener('input', () => {
      if (opts.ro) return;
      obj[key] = opts.num ? num(inp.value) : inp.value;
      touch(); if (opts.after) opts.after(); recalc();
    });
    inp.addEventListener('keydown', e => { if (e.key === 'Enter') inp.blur(); });
    return inp;
  }
  // 续费日期：平时显示“11 月 15 日 · 3 天后”，点一下弹出日历
  function dateCell(obj, key, ro, warnDays, live) {
    const main = h('span'), rel = h('span', { class: 'd-rel' });
    const wrap = h('label', { class: 'datecell' + (ro ? '' : ' edit') }, main, rel);
    const paint = () => {
      const v = obj[key];
      main.textContent = isISO(v) ? dateText(v) : (ro ? '—' : '设置日期');
      main.className = isISO(v) ? '' : 'faint';
      const d = live ? daysUntil(v) : null;
      const flag = d == null ? '' : d < 0 ? 'late' : d <= warnDays ? 'soon' : '';
      rel.className = 'd-rel ' + flag; rel.textContent = flag ? relText(d) : ''; rel.hidden = !flag;
      wrap.title = d == null ? '' : relText(d);
    };
    if (!ro) {
      const inp = h('input', { type: 'date', value: isISO(obj[key]) ? obj[key] : '', 'aria-label': '续费日期' });
      inp.addEventListener('change', () => { obj[key] = inp.value; touch(); paint(); });
      inp.addEventListener('click', () => { try { inp.showPicker(); } catch (e) { /* 老浏览器直接用原生输入 */ } });
      wrap.append(inp);
    }
    paint();
    return wrap;
  }
  function recalc() { updaters.forEach(f => f()); }
  function profitText(el, v) { el.textContent = money(v); el.classList.toggle('pos', v > 0); el.classList.toggle('neg', v < 0); }
  function profitPill(v) { const s = h('span', { class: 'profit' }); profitText(s, v); return s; }

  // ---------- 续费卡下拉 ----------
  function countryList() {
    let dl = document.getElementById('countries');
    if (!dl) { dl = h('datalist', { id: 'countries' }); document.body.append(dl); }
    const all = COUNTRIES.concat(S.issuers.map(i => i.country).filter(Boolean)).filter((v, i, a) => a.indexOf(v) === i);
    setKids(dl, all.map(c => h('option', { value: c })));
  }
  async function newIssuerDialog() {
    const name = h('input', { type: 'text', placeholder: '如 Wise、Maya Bank' });
    const country = h('input', { type: 'text', placeholder: '如 美国、菲律宾', list: 'countries' });
    const ok = await dialog('新增卡种', [h('label', { class: 'field' }, '卡信息（名称）', name), h('label', { class: 'field' }, '国家 / 地区', country)],
      [{ text: '取消' }, { text: '新增', cls: 'primary', value: true, run: () => { if (!name.value.trim()) { name.focus(); return false; } } }]);
    if (!ok) return null;
    const it = ensureIssuer(name.value.trim());
    if (country.value.trim()) it.country = country.value.trim();
    touch(); return it;
  }
  async function newCardDialog(issuer) {
    const number = h('input', { type: 'text', placeholder: '卡号', inputMode: 'numeric', autocomplete: 'off' });
    const note = h('input', { type: 'text', placeholder: '如 1 号卡、次卡，可不填' });
    const ok = await dialog('给 ' + issuer.name + ' 新增卡号', [h('label', { class: 'field' }, '卡号', number), h('label', { class: 'field' }, '备注', note)],
      [{ text: '取消' }, { text: '新增', cls: 'primary', value: true, run: () => { if (!number.value.trim() && !note.value.trim()) { number.focus(); return false; } } }]);
    if (!ok) return null;
    const c = { id: 'c_' + uid(), issuerId: issuer.id, number: number.value.trim(), note: note.value.trim() };
    S.cards.push(c); touch(); return c;
  }
  // 返回两个格子：卡种、卡号
  function cardCells(row, editable) {
    const tdI = h('td'), tdC = h('td');
    function draw() {
      const issuer = issuerById(row.issuerId);
      if (!editable) {
        setKids(tdI, h('span', { class: 'ro' + (issuer ? '' : ' faint'), text: issuer ? issuerLabel(issuer) : '—' }));
        const c = cardById(row.cardId);
        setKids(tdC, h('span', { class: 'ro num' + (c ? '' : ' faint'), text: c ? cardLabel(c) : '—' }));
        return;
      }
      const si = h('select', { class: 'cell' + (issuer ? '' : ' unset'), 'aria-label': '续费卡信息' },
        h('option', { value: '', text: '选择卡种' }),
        S.issuers.map(i => h('option', { value: i.id, text: issuerLabel(i) })),
        h('option', { value: '__new', text: '＋ 新增卡种…' }));
      si.value = row.issuerId || '';
      si.addEventListener('change', async () => {
        if (si.value === '__new') {
          si.value = row.issuerId || '';
          const it = await newIssuerDialog(); if (!it) return;
          row.issuerId = it.id; row.cardId = ''; touch(); return render();
        }
        row.issuerId = si.value;
        const own = cardsOf(row.issuerId);
        row.cardId = own.length === 1 ? own[0].id : '';
        touch(); draw();
      });
      setKids(tdI, si);
      if (!issuer) return setKids(tdC, h('span', { class: 'ro faint', text: '—' }));
      const sc = h('select', { class: 'cell num' + (row.cardId ? '' : ' unset'), 'aria-label': '卡号' },
        h('option', { value: '', text: '不指定卡号' }),
        cardsOf(issuer.id).map(c => h('option', { value: c.id, text: cardLabel(c) })),
        h('option', { value: '__new', text: '＋ 新增卡号…' }));
      sc.value = row.cardId || '';
      sc.addEventListener('change', async () => {
        if (sc.value === '__new') {
          sc.value = row.cardId || '';
          const c = await newCardDialog(issuer); if (!c) return;
          row.cardId = c.id; touch(); return render();
        }
        row.cardId = sc.value; touch(); draw();
      });
      setKids(tdC, sc);
    }
    draw();
    return [tdI, tdC];
  }

  // ---------- 收费情况：每人一个小标签 ----------
  // "300" "张三280" "张三 280" "35x4" "300 350 280"
  function parseMembers(text) {
    const out = []; let pending = '';
    for (const tok of String(text).trim().split(/[\s,，、+＋]+/)) {
      if (!tok) continue;
      let m = tok.match(/^(\d+(?:\.\d+)?)[xX×*](\d+)$/);
      if (m) { for (let i = 0; i < Math.min(+m[2], 50); i++) out.push({ name: '', amount: +m[1], paid: false }); pending = ''; continue; }
      m = tok.match(/^(.*?)[:：¥]?(\d+(?:\.\d+)?)$/);
      if (m) { out.push({ name: (pending + m[1]).trim(), amount: +m[2], paid: false }); pending = ''; }
      else pending += tok;
    }
    if (pending) out.push({ name: pending, amount: 0, paid: false });
    return out;
  }
  function membersCell(row, editable) {
    const td = h('td');
    function draw(focus) {
      const box = h('div', { class: 'chips' }); let addInp = null;
      row.members.forEach((m, i) => {
        const chip = h('span', { class: 'chip' + (m.paid ? ' paid' : '') });
        chip.append(
          h('button', { class: 'chip-dot', type: 'button', title: m.paid ? '已收。点一下改成未收' : '未收。点一下改成已收', 'aria-label': m.paid ? '已收' : '未收',
            onclick: () => { if (!editable) return; m.paid = !m.paid; touch(); draw(); recalc(); } }),
          h('button', { class: 'chip-body', type: 'button', title: editable ? '点开修改' : '', onclick: () => { if (editable) editMember(chip, row, i, () => { draw(); recalc(); }); } },
            m.name ? h('span', { class: 'chip-name', text: m.name }) : null, h('span', { text: plain(m.amount) })));
        box.append(chip);
      });
      if (editable) {
        const inp = h('input', { class: 'chip-add', type: 'text', autocomplete: 'off', 'aria-label': '添加收费', placeholder: row.members.length ? '+ 加人' : '填金额回车，如 300 或 张三280', title: '可一次填多个：300 350 张三280，或 35x4' });
        const commit = refocus => {
          const list = parseMembers(inp.value);
          inp.value = '';   // 重绘会让旧输入框失焦再触发一次，先清空避免重复添加
          if (!list.length) return;
          row.members.push.apply(row.members, list); touch(); draw(refocus); recalc();
        };
        inp.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); commit(true); } });
        inp.addEventListener('blur', () => commit(false));
        box.append(inp); addInp = inp;
      } else if (!row.members.length) box.append(h('span', { class: 'faint', text: '—' }));
      setKids(td, box);
      if (focus && addInp) addInp.focus();
    }
    draw();
    return td;
  }
  function editMember(anchor, row, i, done) {
    const m = row.members[i];
    const name = h('input', { type: 'text', value: m.name, placeholder: '可不填' });
    const amount = h('input', { type: 'text', value: plain(m.amount), inputMode: 'decimal' });
    const paid = h('input', { type: 'checkbox', checked: m.paid });
    let removed = false;
    const form = h('div', { class: 'form' },
      h('label', { class: 'field' }, '金额', amount),
      h('label', { class: 'field' }, '名字 / 备注', name),
      h('label', { class: 'check' }, paid, '本月已收'),
      h('div', { class: 'rowbtns' },
        h('button', { class: 'btn small danger', type: 'button', text: '删除', onclick: () => { removed = true; closePop(); } }),
        h('button', { class: 'btn small primary', type: 'button', text: '完成', onclick: closePop })));
    form.addEventListener('keydown', e => { if (e.key === 'Enter') closePop(); });
    openPop(anchor, form, () => {
      if (removed) row.members.splice(i, 1);
      else { m.name = name.value.trim(); m.amount = num(amount.value); m.paid = paid.checked; }
      touch(); done();
    });
    amount.focus(); amount.select();
  }
  function unitCell(row, editable) {
    return h('td', null, h('div', { class: 'unit' },
      cell(row, 'unitPrice', { num: true, ro: !editable, title: '单价', label: '单价' }), h('span', { class: 'x', text: '×' }),
      cell(row, 'count', { num: true, ro: !editable, title: '人数', label: '人数' })));
  }

  // ---------- 账号表 ----------
  function rowMenu(btn, sheet, rows, row) {
    const items = [];
    if (sheet.grouped) {
      items.push({ label: '移动到分组' });
      G.filter(g => g.id !== row.group).forEach(g => items.push({ text: g.name, run: () => moveRow(row, g.id) }));
      if (G.some(g => g.id === row.group)) items.push({ text: '未分组', run: () => moveRow(row, '') });
      items.push('-');
    }
    if (row.totpId > 0 && totpById(row.totpId)) {
      items.push({ text: '复制分享信息（账号、密码、验证码链接）', run: () => copyShareInfo(row) });
      items.push({ text: '编辑验证码账号（密钥、密码、分享链接）', run: () => leave('/admin/accounts/' + row.totpId + '/edit') });
      items.push({ text: '取消关联验证码', run: () => { row.totpId = -1; touch(); render(); } });
    } else items.push({ text: '关联验证码账号…', run: () => linkTotpMenu(btn, row) });
    items.push('-');
    items.push({ text: '续费日期顺延一个月', run: () => { if (!row.renew) return alertBox('这一行还没填续费日期。'); row.renew = shiftMonth(row.renew, 1); touch(); render(); } });
    if (sheet.mode === 'members' && row.members.some(m => !m.paid)) items.push({ text: '全部标记已收', run: () => { row.members.forEach(m => { m.paid = true; }); touch(); render(); } });
    items.push({ text: row.stopped ? '恢复使用' : '标记为停止（下月不再带入）', run: () => { row.stopped = !row.stopped; touch(); render(); } });
    items.push('-');
    items.push({ text: '删除这一行', danger: true, run: async () => {
      if (await confirmBox('删除账号', '删除 “' + (row.account || '未填账号') + '” 这一行？\n只影响 ' + ymLabel(view.month) + '，其他月份不变。', '删除', true)) { rows.splice(rows.indexOf(row), 1); touch(); render(); }
    } });
    menu(btn, items);
  }
  function rowEl(sheet, rows, row, editable, live) {
    const inc = h('td', { class: 'calc r' }), pill = h('span', { class: 'profit' }), prof = h('td', { class: 'calc r' }, pill);
    updaters.push(() => { const v = income(sheet, row); inc.textContent = money(v); profitText(pill, v - num(row.cost)); });
    const acct = cell(row, 'account', { ro: !editable, placeholder: '账号', cls: 'strong', label: '账号', title: row.stopped ? '已停止，下个月不会带过去' : '' });
    acct.addEventListener('change', () => { if (!row.totpId && linkTotp()) { touch(); render(); } });
    const tr = h('tr', { class: row.stopped ? 'stopped' : '' },
      h('td', null, h('div', { class: 'acct' }, acct, totpChip(row))),
      h('td', null, dateCell(row, 'renew', !editable, 3, live && !row.stopped)),
      cardCells(row, editable),
      sheet.mode === 'members' ? membersCell(row, editable) : unitCell(row, editable),
      inc,
      h('td', null, cell(row, 'cost', { num: true, ro: !editable, label: '续费成本' })),
      prof,
      h('td', null, cell(row, 'note', { ro: !editable, label: '备注' })),
      h('td', null, editable ? h('button', { class: 'btn ghost icon', type: 'button', 'aria-label': '更多操作', onclick: e => rowMenu(e.currentTarget, sheet, rows, row) }, icon('more')) : null));
    tr.dataset.row = row.id;
    searchRows.push({ tr, row });
    return tr;
  }
  function tableEl(sheet, rows, list, editable, live) {
    const cols = [['账号', 240], ['续费日期', 134], ['续费卡信息', 126], ['卡号', 118], [sheet.mode === 'members' ? '收费情况（每人）' : '单价 × 人数', 0], ['收费', 76, 1], ['续费成本', 78, 1], ['利润', 92, 1], ['备注', 88], ['', 42]];
    return h('div', { class: 'scroll' }, h('table', { class: 'grid', style: 'min-width:1170px;table-layout:fixed' },
      h('colgroup', null, cols.map(c => h('col', { style: c[1] ? 'width:' + c[1] + 'px' : '' }))),
      h('thead', null, h('tr', null, cols.map(c => h('th', { class: c[2] ? 'r' : '', text: c[0] })))),
      h('tbody', null, list.map(r => rowEl(sheet, rows, r, editable, live)))));
  }
  function section(sheet, rows, group, filter, editable, live) {
    const list = rows.filter(filter), key = sheet.id + ':' + (group ? group.id || 'loose' : 'all');
    const closed = !!collapsed[key];
    const sum = h('div', { class: 'group-sum' });
    updaters.push(() => {
      const s = stats(sheet, rows.filter(filter));
      setKids(sum, h('span', null, '收费 ', h('b', { text: money(s.income) })), h('span', null, '成本 ', h('b', { text: money(s.cost) })), profitPill(s.profit));
    });
    const count = h('span', { class: 'pill' });
    updaters.push(() => { const s = stats(sheet, rows.filter(filter)); count.textContent = list.length + ' 个账号 · ' + plain(s.heads) + ' 人'; });
    const toggle = () => { collapsed[key] = !closed; try { localStorage.setItem('hezu-collapsed', JSON.stringify(collapsed)); } catch (e) { /* 忽略 */ } render(); };
    const title = h('button', { class: 'group-title', type: 'button', 'aria-expanded': String(!closed), title: closed ? '展开' : '收起', onclick: toggle },
      h('span', { class: 'chev' }, icon('chev', 16)), group ? h('span', { class: 'dot', style: 'background:' + group.color }) : null, h('span', { text: group ? group.name : sheet.name }));
    const addBtn = editable && !closed ? h('button', { class: 'btn ghost small', type: 'button', onclick: () => addAccountDialog({ sheet, group }) }, icon('plus', 15), '添加账号') : null;
    return h('div', { class: 'group' + (closed ? ' closed' : '') },
      h('div', { class: 'group-head' }, title, count, sum),
      closed ? null : list.length ? tableEl(sheet, rows, list, editable, live) : h('div', { class: 'empty', text: editable ? '还没有账号，点下面的“添加账号”。' : '这个月没有账号。' }),
      addBtn ? h('div', { class: 'group-foot' }, addBtn) : null);
  }
  function tiles(getStats) {
    const v = [0, 1, 2, 3].map(() => h('div', { class: 'v' })), s3 = h('div', { class: 's' }), s2 = h('div', { class: 's' });
    const t = ['收费', '续费成本', '利润', '在用账号'].map((k, i) => h('div', { class: 'tile' }, h('div', { class: 'k', text: k }), v[i], i === 3 ? s3 : i === 2 ? s2 : null));
    updaters.push(() => {
      const s = getStats();
      v[0].textContent = money(s.income); v[1].textContent = money(s.cost); v[2].textContent = money(s.profit); v[3].textContent = String(s.n);
      t[2].className = 'tile' + (s.profit > 0 ? ' good' : s.profit < 0 ? ' bad' : '');
      s2.textContent = s.income ? '利润率 ' + Math.round(s.profit / s.income * 100) + '%' : ' ';
      s3.textContent = plain(s.heads) + ' 人付费';
    });
    return h('div', { class: 'tiles' }, t);
  }
  function applySearch() {
    const q = view.q.trim().toLowerCase();
    for (const { tr, row } of searchRows) {
      const it = issuerById(row.issuerId);
      const hay = [row.account, row.note, it ? it.name : '', row.members.map(m => m.name).join(' ')].join(' ').toLowerCase();
      tr.hidden = !!q && !hay.includes(q);
    }
  }
  function sheetView(sheet) {
    const M = S.months[view.month], rows = M.rows[sheet.id], editable = isEditable(), live = view.month === latestMonth() && !M.archived;
    const out = [tiles(() => stats(sheet, rows))];
    const q = h('input', { type: 'search', placeholder: '搜索账号、备注、卡种', value: view.q, 'aria-label': '搜索' });
    q.addEventListener('input', () => { view.q = q.value; applySearch(); });
    const bar = h('div', { class: 'toolbar' }, h('label', { class: 'search' }, icon('search', 15), q), h('span', { class: 'spacer' }));
    if (sheet.grouped) bar.append(h('button', { class: 'btn small', type: 'button', text: '分组', onclick: e => groupsMenu(e.currentTarget) }));
    bar.append(h('button', { class: 'btn ghost small', type: 'button', text: '表设置', onclick: e => sheetMenu(e.currentTarget, sheet) }));
    out.push(bar);
    if (sheet.grouped) {
      const ids = new Set(G.map(g => g.id));
      G.forEach(g => out.push(section(sheet, rows, g, r => r.group === g.id, editable, live)));
      if (rows.some(r => !ids.has(r.group))) out.push(section(sheet, rows, LOOSE, r => !ids.has(r.group), editable, live));
      if (!G.length) out.push(h('div', { class: 'empty', text: '还没有分组，点上面的“分组”新建。' }));
    } else out.push(section(sheet, rows, null, () => true, editable, live));
    return out;
  }

  // ---------- 添加账号：账本记录和验证码账号统一从这里加 ----------
  async function addAccountDialog(preset) {
    preset = preset || {};
    const name = h('input', { type: 'text', placeholder: '账号邮箱或名称', autocomplete: 'off', spellcheck: false });
    const groupSel = h('select', null, h('option', { value: '', text: '未分组' }), G.map(g => h('option', { value: g.id, text: g.name, selected: !!preset.group && g.id === preset.group.id })));
    const secret = h('input', { type: 'text', placeholder: '没开两步验证就留空', autocomplete: 'off', spellcheck: false });
    const password = h('input', { type: 'text', placeholder: '可不填；加密保存在验证码账号里', autocomplete: 'off', spellcheck: false });
    const toLedger = h('input', { type: 'checkbox', checked: true });
    const sheetSel = h('select', null, S.sheets.map(s => h('option', { value: s.id, text: s.name, selected: !!preset.sheet && s.id === preset.sheet.id })));
    const fSheet = h('label', { class: 'field' }, '记到哪张表', sheetSel);
    const err = h('div', { class: 'neg' });
    toLedger.addEventListener('change', () => { fSheet.hidden = !toLedger.checked; });
    let made = null;
    const submit = async () => {
      err.textContent = '';
      const n = name.value.trim(), sec = secret.value.trim(), pw = password.value.trim();
      const sheet = S.sheets.find(x => x.id === sheetSel.value), g = G.find(x => x.id === groupSel.value);
      if (!n) { name.focus(); return false; }
      if (!toLedger.checked && !sec) { err.textContent = '不记入账本的话，至少要填 TOTP 密钥（否则什么都没添加）。'; return false; }
      if (pw && !sec) { err.textContent = '登录密码是存在验证码账号里的，要存密码请同时填 TOTP 密钥。'; return false; }
      let totpId = 0;
      if (sec) {
        const body = { name: n, secret: sec, password: pw, group: g ? g.name : '' };
        let r = await api('POST', '/accounts', body), d = await r.json().catch(() => ({}));
        if (r.status === 409 && d.duplicate) {
          if (!await confirmBox('已有同名的验证码账号', d.error + '\n确认不是重复添加的话，可以继续。', '仍然添加')) return false;
          r = await api('POST', '/accounts', Object.assign({ confirmDuplicate: true }, body)); d = await r.json().catch(() => ({}));
        }
        if (!r.ok || !d.ok) { err.textContent = d.error || '添加失败，请重试。'; return false; }
        useContext(d); totpId = d.id;
      }
      if (toLedger.checked && sheet) {
        made = fixRow({ account: n, group: sheet.grouped && g ? g.id : '', totpId });
        S.months[view.month].rows[sheet.id].push(made);
        view.tab = sheet.id; view.q = '';
        if (!totpId) linkTotp();   // 没填密钥但验证码那边已有同名账号：直接关联上
        touch();
      }
    };
    const ok = await dialog('添加账号', [
      h('label', { class: 'field' }, '账号', name),
      h('label', { class: 'field' }, '分组', groupSel),
      h('label', { class: 'field' }, 'TOTP 密钥（两步验证）', secret),
      h('label', { class: 'field' }, '账号登录密码', password),
      h('label', { class: 'check' }, toLedger, '同时记入合租账本（' + ymLabel(view.month) + '）'), fSheet,
      h('div', { class: 'muted', text: '填了 TOTP 密钥会同时建好验证码账号和分享链接，两边自动关联、分组一致。续费日期、续费卡、收费等在表格里接着填。' }),
      err,
    ], [{ text: '取消' }, { text: '添加', cls: 'primary', value: true, run: submit }]);
    if (!ok) return;
    render(); pollCodes();
    if (made) { const inp = document.querySelectorAll('[data-row="' + made.id + '"] input')[0]; if (inp) { inp.scrollIntoView({ block: 'center' }); } }
    else setStatus('已添加验证码账号');
  }

  // ---------- 分组 / 表 管理 ----------
  // 分组和验证码账号共用一套：这里只能新建，改名、换颜色、删除去验证码后台的分组管理页
  async function createGroup(name) {
    const r = await api('POST', '/groups', { name }), d = await r.json().catch(() => ({}));
    if (!r.ok || !d.ok) { await alertBox(d.error || '新建分组失败'); return null; }
    useContext(d);
    return G.find(g => g.name === d.name) || null;
  }
  async function newGroupDialog() {
    const name = h('input', { type: 'text', placeholder: '如 GPT Plus' });
    const ok = await dialog('新建分组', [h('label', { class: 'field' }, '分组名称', name), h('div', { class: 'muted', text: '分组和验证码账号共用一套，新建后两边都能用。' })],
      [{ text: '取消' }, { text: '新建', cls: 'primary', value: true, run: () => { if (!name.value.trim()) { name.focus(); return false; } } }]);
    return ok ? createGroup(name.value.trim()) : null;
  }
  function groupsMenu(btn) {
    menu(btn, [
      { text: '新建分组…', run: async () => { if (await newGroupDialog()) render(); } },
      { text: '改名、换颜色、删除（去分组管理页）', run: () => leave('/admin/groups') },
    ]);
  }
  async function sheetForm(sheet) {
    const name = h('input', { type: 'text', value: sheet ? sheet.name : '', placeholder: '如 YouTube' });
    const mode = h('select', null,
      h('option', { value: 'unit', text: '单价 × 人数（每人价格一样）', selected: !sheet || sheet.mode === 'unit' }),
      h('option', { value: 'members', text: '每人单独填金额', selected: !!sheet && sheet.mode === 'members' }));
    const ok = await dialog(sheet ? '修改表' : '新建表', [h('label', { class: 'field' }, '名称', name), h('label', { class: 'field' }, '收费方式', mode)],
      [{ text: '取消' }, { text: sheet ? '保存' : '新建', cls: 'primary', value: true, run: () => { if (!name.value.trim()) { name.focus(); return false; } } }]);
    if (!ok) return;
    if (sheet) { sheet.name = name.value.trim(); sheet.mode = mode.value; }
    else { sheet = { id: 's_' + uid(), name: name.value.trim(), mode: mode.value }; S.sheets.push(sheet); view.tab = sheet.id; }
    normalize(); touch(); render();
  }
  function sheetMenu(btn, sheet) {
    menu(btn, [
      { text: '改名 / 改收费方式', run: () => sheetForm(sheet) },
      { text: '删除这张表', danger: true, run: async () => {
        if (await confirmBox('删除表', '删除 “' + sheet.name + '” 这张表？\n它在所有月份里的账号都会一起删除，不能恢复。', '删除', true)) {
          S.sheets.splice(S.sheets.indexOf(sheet), 1);
          for (const ym in S.months) delete S.months[ym].rows[sheet.id];
          normalize(); touch(); render();
        }
      } },
    ]);
  }

  // ---------- 支付卡后台 ----------
  function usageCount(test) {
    let n = 0;
    for (const ym in S.months) for (const sh of S.sheets) for (const r of S.months[ym].rows[sh.id]) if (test(r)) n++;
    return n;
  }
  function cardsView() {
    countryList();
    const cs = cardStats(view.month);
    const countries = S.issuers.map(i => i.country || '未填国家').filter((v, i, a) => a.indexOf(v) === i);
    if (view.country && !countries.includes(view.country)) view.country = '';
    const chip = (val, text) => h('button', { class: 'fchip' + (view.country === val ? ' on' : ''), type: 'button', text, onclick: () => { view.country = val; render(); } });
    const shown = S.issuers.filter(i => !view.country || (i.country || '未填国家') === view.country);
    const total = Object.keys(cs.byIssuer).reduce((a, k) => a + cs.byIssuer[k].cost, 0);
    const panels = shown.map(it => {
      const st = cs.byIssuer[it.id] || { n: 0, cost: 0 }, own = cardsOf(it.id);
      return h('div', { class: 'group' },
        h('div', { class: 'issuer-head' },
          cell(it, 'name', { cls: 'name', placeholder: '卡信息名称', label: '卡信息名称' }),
          cell(it, 'country', { placeholder: '国家 / 地区', list: 'countries', label: '国家或地区' }),
          h('button', { class: 'btn ghost icon', type: 'button', 'aria-label': '更多操作', onclick: e => menu(e.currentTarget, [{ text: '删除这个卡种', danger: true, run: async () => {
            const used = usageCount(r => r.issuerId === it.id);
            if (await confirmBox('删除卡种', '删除 “' + it.name + '” 和它下面的 ' + own.length + ' 个卡号？' + (used ? '\n有 ' + used + ' 个账号（含历史月份）选了它，删除后这些账号的续费卡会变成空。' : ''), '删除', true)) {
              S.issuers.splice(S.issuers.indexOf(it), 1); normalize(); touch(); render();
            }
          } }]) }, icon('more'))),
        h('div', { class: 'issuer-meta' }, h('span', null, ymLabel(view.month) + ' 续费 ', h('b', { text: money(st.cost) })), h('span', null, h('b', { text: String(st.n) }), ' 个账号在用'), h('span', null, h('b', { text: String(own.length) }), ' 个卡号')),
        own.map(c => {
          const s = cs.byCard[c.id] || { n: 0, cost: 0 };
          return h('div', { class: 'cardrow' },
            cell(c, 'number', { mask: 'card', cls: 'mono', placeholder: '卡号', title: '点一下显示完整卡号', label: '卡号' }),
            cell(c, 'note', { placeholder: '备注', label: '卡备注' }),
            h('div', { class: 'spend' }, money(s.cost), h('small', { text: s.n + ' 个账号' })),
            h('button', { class: 'btn ghost icon', type: 'button', 'aria-label': '删除卡号', title: '删除卡号', onclick: async () => {
              const used = usageCount(r => r.cardId === c.id);
              if (await confirmBox('删除卡号', '删除 ' + it.name + ' 的 ' + cardLabel(c) + '？' + (used ? '\n有 ' + used + ' 个账号（含历史月份）选了它，删除后会变成“不指定卡号”。' : ''), '删除', true)) {
                S.cards.splice(S.cards.indexOf(c), 1); normalize(); touch(); render();
              }
            } }, h('span', { text: '✕', 'aria-hidden': 'true' })));
        }),
        h('div', { class: 'group-foot' }, h('button', { class: 'btn ghost small', type: 'button', onclick: async () => { if (await newCardDialog(it)) render(); } }, icon('plus', 15), '添加卡号')));
    });
    return [
      h('div', { class: 'tiles' },
        h('div', { class: 'tile' }, h('div', { class: 'k', text: '卡种' }), h('div', { class: 'v', text: String(S.issuers.length) }), h('div', { class: 's', text: countries.filter(c => c !== '未填国家').length + ' 个国家 / 地区' })),
        h('div', { class: 'tile' }, h('div', { class: 'k', text: '卡号' }), h('div', { class: 'v', text: String(S.cards.length) }), h('div', { class: 's', text: ' ' })),
        h('div', { class: 'tile' }, h('div', { class: 'k', text: ymLabel(view.month) + ' 刷卡续费' }), h('div', { class: 'v', text: money(total) }), h('div', { class: 's', text: cs.none.cost ? '另有 ' + money(cs.none.cost) + ' 没选卡' : '全部已对应到卡' }))),
      h('div', { class: 'toolbar' }, h('div', { class: 'chipset' }, chip('', '全部'), countries.map(c => chip(c, c))), h('span', { class: 'spacer' }),
        h('button', { class: 'btn primary small', type: 'button', onclick: async () => { if (await newIssuerDialog()) render(); } }, icon('plus', 15), '新增卡种')),
      shown.length ? h('div', { class: 'issuers' }, panels) : h('div', { class: 'empty', text: '还没有卡种。' }),
    ];
  }

  // ---------- VPS ----------
  function vpsView() {
    const cols = [['主机', 190], ['IP', 130], ['密码', 120], ['部署', 0], ['流量及重置', 100], ['续费', 150], ['价格', 110], ['邮箱', 190], ['', 42]];
    const body = S.vps.map(v => h('tr', null,
      h('td', null, cell(v, 'host', { cls: 'strong', label: '主机' })), h('td', null, cell(v, 'ip', { cls: 'mono', label: 'IP' })),
      h('td', null, cell(v, 'password', { mask: 'all', title: '点一下显示', label: '密码' })),
      h('td', null, cell(v, 'deploy', { label: '部署' })), h('td', null, cell(v, 'traffic', { label: '流量及重置' })),
      h('td', null, dateCell(v, 'renew', false, 14, true)),
      h('td', null, cell(v, 'price', { label: '价格' })), h('td', null, cell(v, 'email', { label: '邮箱' })),
      h('td', null, h('button', { class: 'btn ghost icon', type: 'button', 'aria-label': '更多操作', onclick: e => menu(e.currentTarget, [{ text: '删除这一行', danger: true, run: async () => {
        if (await confirmBox('删除 VPS', '删除 “' + (v.host || '未命名') + '”？', '删除', true)) { S.vps.splice(S.vps.indexOf(v), 1); touch(); render(); }
      } }]) }, icon('more')))));
    return [
      h('div', { class: 'group' },
        h('div', { class: 'group-head' }, h('span', { class: 'group-title', text: '全部主机' }), h('span', { class: 'pill', text: S.vps.length + ' 台' }), h('span', { class: 'group-sum', text: '不分月份 · 14 天内到期会标出来' })),
        S.vps.length ? h('div', { class: 'scroll' }, h('table', { class: 'grid', style: 'min-width:1100px' },
          h('colgroup', null, cols.map(c => h('col', { style: c[1] ? 'width:' + c[1] + 'px' : '' }))),
          h('thead', null, h('tr', null, cols.map(c => h('th', { text: c[0] })))), h('tbody', null, body))) : h('div', { class: 'empty', text: '还没有 VPS。' }),
        h('div', { class: 'group-foot' }, h('button', { class: 'btn ghost small', type: 'button', onclick: () => { S.vps.push({ id: uid(), host: '', ip: '', password: '', deploy: '', traffic: '', renew: '', price: '', email: '' }); touch(); render(); const ins = document.querySelectorAll('tbody tr:last-child input'); if (ins[0]) ins[0].focus(); } }, icon('plus', 15), '添加 VPS'))),
    ];
  }

  // ---------- 总览 ----------
  function tagOrText(b) { return b.color ? h('span', { class: 'tag', style: 'background:' + b.color + ';color:' + (b.text || '#fff'), text: b.label }) : h('b', { text: b.label }); }
  function dueList() {
    const items = [];
    for (const sh of S.sheets) for (const r of S.months[view.month].rows[sh.id]) {
      const d = daysUntil(r.renew); if (r.stopped || d == null || d > 7) continue;
      const g = sh.grouped ? G.find(x => x.id === r.group) : null, it = issuerById(r.issuerId), c = cardById(r.cardId);
      items.push({ d, title: r.account || '未填账号', meta: [g ? g.name : sh.name, it ? it.name : '', c ? cardLabel(c) : ''].filter(Boolean).join(' · '), cost: money(r.cost),
        action: h('button', { class: 'btn small', type: 'button', text: '已续费', title: '续费日期顺延一个月', onclick: () => { r.renew = shiftMonth(r.renew, 1); touch(); render(); } }) });
    }
    for (const v of S.vps) {
      const d = daysUntil(v.renew); if (d == null || d > 14) continue;
      items.push({ d, title: v.host || '未命名 VPS', meta: ['VPS', v.deploy].filter(Boolean).join(' · '), cost: v.price || '', action: h('button', { class: 'btn ghost small', type: 'button', text: '去修改', onclick: () => { view.tab = 'vps'; render(); } }) });
    }
    items.sort((a, b) => a.d - b.d);
    return h('div', { class: 'group' },
      h('div', { class: 'group-head' }, h('span', { class: 'group-title', text: '待续费' }), h('span', { class: 'pill', text: items.length + ' 项' }), h('span', { class: 'group-sum', text: '账号 7 天内、VPS 14 天内到期' })),
      items.length ? items.map(x => h('div', { class: 'due' }, h('span', { class: 'd-rel ' + (x.d < 0 ? 'late' : 'soon'), text: relText(x.d) }),
        h('div', { style: 'min-width:0' }, h('div', { class: 't', text: x.title }), h('div', { class: 'm', text: x.meta })), h('span', { class: 'cost num muted', text: x.cost }), x.action))
        : h('div', { class: 'empty', text: '近期没有要续费的。' }));
  }
  function homeView() {
    const parts = breakdown(view.month), total = zero();
    const M = S.months[view.month], live = view.month === latestMonth() && !M.archived;
    const moneyTd = v => h('td', { class: 'calc r', text: money(v) });
    const line = (first, n, s, cls) => h('tr', { class: cls || '' }, h('td', { class: 'calc' }, first), h('td', { class: 'calc r', text: String(n) }), h('td', { class: 'calc r', text: plain(s.heads) }),
      moneyTd(s.income), moneyTd(s.cost), h('td', { class: 'calc r' }, profitPill(s.profit)));
    const rowsEl = []; let allRows = 0;
    for (const sh of S.sheets) {
      const mine = parts.filter(p => p.sheet === sh.id), sub = zero(); let n = 0;
      mine.forEach(p => { addStats(sub, p.st); n += p.rows; if (sh.grouped) rowsEl.push(line(tagOrText(p), p.rows, p.st)); });
      rowsEl.push(line(h('b', { text: sh.grouped ? sh.name + ' 小计' : sh.name }), n, sub, sh.grouped ? 'total' : ''));
      addStats(total, sub); allRows += n;
    }
    rowsEl.push(line(h('b', { text: '全部合计' }), allRows, total, 'total'));

    // 按卡统计
    const cs = cardStats(view.month);
    const iss = S.issuers.map(i => ({ i, st: cs.byIssuer[i.id] })).filter(x => x.st).sort((a, b) => b.st.cost - a.st.cost);
    const crd = S.cards.map(c => ({ c, st: cs.byCard[c.id] })).filter(x => x.st).sort((a, b) => b.st.cost - a.st.cost);
    const maxI = Math.max(1, ...iss.map(x => x.st.cost)), maxC = Math.max(1, ...crd.map(x => x.st.cost));
    const barTd = (v, max) => h('td', { class: 'calc r' }, h('div', { class: 'barcell' }, h('div', { class: 'bar' }, h('i', { style: 'width:' + Math.round(Math.max(0, v) / max * 100) + '%' })), h('span', { text: money(v) })));
    const cardTotal = iss.reduce((a, x) => a + x.st.cost, 0) + cs.none.cost;
    const issuerTable = h('div', { class: 'group' },
      h('div', { class: 'group-head' }, h('span', { class: 'group-title', text: '每种卡要花多少' }), h('span', { class: 'group-sum' }, '合计 ', h('b', { text: money(cardTotal) }))),
      iss.length || cs.none.cost ? h('div', { class: 'scroll' }, h('table', { class: 'grid' },
        h('thead', null, h('tr', null, ['卡信息', '国家 / 地区', '账号数', '续费成本'].map((t, i) => h('th', { class: i > 1 ? 'r' : '', text: t })))),
        h('tbody', null, iss.map(x => h('tr', null, h('td', { class: 'calc strong', text: x.i.name }), h('td', { class: 'calc muted', text: x.i.country || '—' }), h('td', { class: 'calc r', text: String(x.st.n) }), barTd(x.st.cost, maxI))),
          cs.none.cost ? h('tr', null, h('td', { class: 'calc faint', text: '没选卡的账号' }), h('td', { class: 'calc faint', text: '—' }), h('td', { class: 'calc r', text: String(cs.none.n) }), barTd(cs.none.cost, maxI)) : null)))
        : h('div', { class: 'empty', text: '这个月还没有账号选了续费卡。' }));
    const cardTable = h('div', { class: 'group' },
      h('div', { class: 'group-head' }, h('span', { class: 'group-title', text: '每个卡号要花多少' }), h('span', { class: 'group-sum', text: '余额不够时先看这里' })),
      crd.length ? h('div', { class: 'scroll' }, h('table', { class: 'grid' },
        h('thead', null, h('tr', null, ['卡号', '卡信息', '账号数', '续费成本'].map((t, i) => h('th', { class: i > 1 ? 'r' : '', text: t })))),
        h('tbody', null, crd.map(x => { const it = issuerById(x.c.issuerId); return h('tr', null, h('td', { class: 'calc strong num', text: cardLabel(x.c) }), h('td', { class: 'calc muted', text: it ? issuerLabel(it) : '—' }), h('td', { class: 'calc r', text: String(x.st.n) }), barTd(x.st.cost, maxC)); }))))
        : h('div', { class: 'empty', text: '这个月还没有账号选到具体卡号。' }));

    // 历月利润：列 = 现在的分组和表
    const colsDef = breakdown(latestMonth()).map(p => ({ key: p.key, label: p.label }));
    const keys = monthKeys().reverse();
    for (const ym of keys) for (const p of breakdown(ym)) if (!colsDef.some(c => c.key === p.key)) colsDef.push({ key: p.key, label: p.label });
    const hist = keys.map(ym => {
      const bd = breakdown(ym); let sum = 0;
      const tds = colsDef.map(c => { const p = bd.find(x => x.key === c.key); const v = p ? p.st.profit : 0; sum += v; const td = h('td', { class: 'calc r' }); if (p && p.rows) profitText(td, v); else { td.textContent = '—'; td.classList.add('faint'); } return td; });
      return h('tr', null, h('td', { class: 'calc' }, h('button', { class: 'btn ghost small', type: 'button', text: ymLabel(ym), title: '查看这个月', onclick: () => { view.month = ym; render(); } }), S.months[ym].archived ? null : h('span', { class: 'tag c-blue', text: '进行中' })), tds, h('td', { class: 'calc r' }, profitPill(sum)));
    });
    return [
      tiles(() => total),
      live ? dueList() : null,
      h('div', { class: 'group' },
        h('div', { class: 'group-head' }, h('span', { class: 'group-title', text: '各类利润' }), h('span', { class: 'pill', text: ymLabel(view.month) })),
        h('div', { class: 'scroll' }, h('table', { class: 'grid', style: 'min-width:640px' },
          h('thead', null, h('tr', null, ['类别', '账号数', '收费人数', '收费', '续费成本', '利润'].map((t, i) => h('th', { class: i ? 'r' : '', text: t })))), h('tbody', null, rowsEl)))),
      h('div', { class: 'cols' }, issuerTable, cardTable),
      h('div', { class: 'section-gap' }),
      h('div', { class: 'group' },
        h('div', { class: 'group-head' }, h('span', { class: 'group-title', text: '历月利润' }), h('span', { class: 'group-sum', text: '点月份可以打开那个月' })),
        h('div', { class: 'scroll' }, h('table', { class: 'grid', style: 'min-width:720px' },
          h('thead', null, h('tr', null, h('th', { text: '月份' }), colsDef.map(c => h('th', { class: 'r', text: c.label })), h('th', { class: 'r', text: '合计' }))), h('tbody', null, hist)))),
    ];
  }

  // ---------- 月份 ----------
  async function startNextMonth() {
    const last = latestMonth(), next = nextYM(last);
    if (!await confirmBox('归档并开始下个月', '把 ' + ymLabel(last) + ' 归档，并开始 ' + ymLabel(next) + '？\n\n· 账号、收费金额、成本和续费卡会复制到新月份，之后两个月各改各的\n· 续费日期早于新月份的会顺延到新月份\n· 收款状态全部重置为“未收”\n· 标记为停止的账号不会带过去\n· ' + ymLabel(last) + ' 变成只读存档，需要时可以解锁修改', '归档并开始')) return;
    const src = S.months[last], rows = {}, floor = next + '-01';
    for (const sh of S.sheets) rows[sh.id] = (src.rows[sh.id] || []).filter(r => !r.stopped).map(r => {
      const c = fixRow(JSON.parse(JSON.stringify(r))); c.id = uid();
      for (let i = 0; i < 36 && isISO(c.renew) && c.renew < floor; i++) c.renew = shiftMonth(c.renew, 1);
      c.members.forEach(m => { m.paid = false; });
      return c;
    });
    src.archived = true; S.months[next] = { archived: false, rows }; view.month = next; render(); saveNow();
  }
  async function deleteLatestMonth() {
    const keys = monthKeys(), last = keys[keys.length - 1], prev = keys[keys.length - 2];
    if (!await confirmBox('删除月份', '删除 ' + ymLabel(last) + ' 的全部数据？不能恢复。\n' + ymLabel(prev) + ' 会恢复成进行中的月份。', '删除', true)) return;
    delete S.months[last]; S.months[prev].archived = false; view.month = prev; render(); saveNow();
  }

  // ---------- 导入 ----------
  function pickImport() {
    const inp = h('input', { type: 'file', accept: '.xlsx' });
    inp.addEventListener('change', async () => {
      const f = inp.files[0]; if (!f) return;
      let data;
      try {
        const r = await api('POST', '/import', await f.arrayBuffer(), true);
        data = await r.json();
        if (!r.ok) return alertBox(data.error || '导入失败');
      } catch (e) { return alertBox('导入失败：' + e.message); }
      const byGroup = {};
      data.ai.forEach(r => { byGroup[r.groupName] = (byGroup[r.groupName] || 0) + 1; });
      const lines = Object.keys(byGroup).map(g => 'AI 合租 / ' + g + '：' + byGroup[g] + ' 个账号')
        .concat(Object.keys(data.sheets).map(n => n + '：' + data.sheets[n].length + ' 个账号'), data.vps.length ? ['VPS：' + data.vps.length + ' 台'] : []);
      if (!lines.length) return alertBox('这个文件里没找到能导入的内容。');
      const existing = S.sheets.reduce((a, sh) => a + S.months[view.month].rows[sh.id].length, 0) + (data.vps.length ? S.vps.length : 0);
      const ok = await dialog('导入到 ' + ymLabel(view.month), [
        h('ul', { class: 'plist' }, lines.map(t => h('li', { text: t }))),
        h('div', { class: 'muted', text: '表里的卡信息和卡号会自动整理到“支付卡”里，同一个卡号只建一次。' }),
        existing ? h('div', { class: 'neg', text: '注意：现在已经有 ' + existing + ' 行数据，导入的内容会追加在后面，不会去重。' }) : null,
        data.warnings.length ? h('ul', { class: 'warns' }, data.warnings.map(t => h('li', { text: t }))) : null,
      ], [{ text: '取消' }, { text: '导入', cls: 'primary', value: true }]);
      if (ok) await applyImport(data);
    });
    inp.click();
  }
  async function applyImport(data) {
    const M = S.months[view.month];
    const ai = S.sheets.find(s => s.grouped) || S.sheets.find(s => s.mode === 'members');
    const found = {};
    if (data.ai.length && ai) for (const r of data.ai) {
      const key = normName(r.groupName);
      if (!(key in found)) found[key] = G.find(x => normName(x.name) === key) || await createGroup(r.groupName);
      M.rows[ai.id].push(fixRow(Object.assign({}, r, { group: found[key] ? found[key].id : '', id: null })));
    }
    for (const name in data.sheets) {
      let sh = S.sheets.find(x => x.name.trim().toLowerCase() === name.toLowerCase());
      if (!sh) { sh = { id: 's_' + uid(), name, mode: 'unit' }; S.sheets.push(sh); M.rows[sh.id] = []; }
      data.sheets[name].forEach(r => M.rows[sh.id].push(fixRow(r)));
    }
    data.vps.forEach(v => S.vps.push(Object.assign({ id: uid() }, v)));
    normalize(); render(); saveNow();
  }
  function exportBackup() { download(new Blob([JSON.stringify(Object.assign({}, S, { groups: G.map(g => ({ id: g.id, name: g.name })) }), null, 1)], { type: 'application/json' }), 'hezu-backup-' + todayISO() + '.json'); }
  function restoreBackup() {
    const inp = h('input', { type: 'file', accept: '.json,application/json' });
    inp.addEventListener('change', async () => {
      const f = inp.files[0]; if (!f) return;
      let state;
      try { state = JSON.parse(await f.text()); } catch (e) { return alertBox('这个文件不是 JSON 备份。'); }
      if (!state || typeof state.months !== 'object' || !Array.isArray(state.sheets)) return alertBox('这不是合租账本的备份文件。');
      const n = Object.keys(state.months).length;
      if (!await confirmBox('从备份恢复', '用这份备份（' + n + ' 个月的数据）整体替换现在的账本？\n\n现在的内容不会丢：它会留在“恢复到某天的版本”里，保留 60 天。\n备份里的分组会按名称对应到现有分组，没有的会新建。', '替换', true)) return;
      await settle();
      const r = await api('POST', '/restore', { state }), d = await r.json().catch(() => ({}));
      if (!r.ok || !d.ok) return alertBox(d.error || '恢复失败');
      adopt(d);
    });
    inp.click();
  }
  async function historyDialog() {
    const r = await fetch(API + '/history', { credentials: 'same-origin' }), d = await r.json().catch(() => ({}));
    if (!r.ok) return alertBox('取不到历史版本。');
    if (!d.days.length) return alertBox('还没有历史版本。\n每天第一次保存前，系统会自动把上一版留一份，保留 60 天。');
    const sel = h('select', null, d.days.map(x => h('option', { value: x.day, text: x.day + ' 开始前的版本' })));
    const ok = await dialog('恢复到某天的版本', [h('label', { class: 'field' }, '选一个版本', sel),
      h('div', { class: 'muted', text: '会用选中的版本整体替换现在的账本（所有月份、支付卡、VPS）。\n现在的内容同样会留一份，今天第一次恢复或保存前的状态可以再恢复回来。' })],
      [{ text: '取消' }, { text: '恢复', cls: 'danger', value: true }]);
    if (!ok) return;
    await settle();
    const r2 = await api('POST', '/history/' + sel.value + '/restore', {}), d2 = await r2.json().catch(() => ({}));
    if (!r2.ok || !d2.ok) return alertBox(d2.error || '恢复失败');
    adopt(d2);
  }
  async function logout() {
    await settle(); await refreshContext();
    const f = h('form', { method: 'post', action: '/admin/logout' }, h('input', { type: 'hidden', name: 'csrf_token', value: CSRF }));
    document.body.append(f); f.submit();
  }

  // ---------- 导出 Excel ----------
  const XML_HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
  const CRC_TABLE = (() => { const t = new Uint32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return t; })();
  function crc32(u8) { let c = 0xFFFFFFFF; for (let i = 0; i < u8.length; i++) c = CRC_TABLE[(c ^ u8[i]) & 0xFF] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; }
  // 不压缩的 zip（xlsx 文件本质上就是一个 zip）
  function zipStore(files) {
    const enc = new TextEncoder(), now = new Date();
    const time = (now.getHours() << 11) | (now.getMinutes() << 5) | (now.getSeconds() >> 1);
    const date = ((now.getFullYear() - 1980) << 9) | ((now.getMonth() + 1) << 5) | now.getDate();
    const chunks = [], central = []; let offset = 0;
    for (const f of files) {
      const name = enc.encode(f.name), data = enc.encode(f.text), crc = crc32(data);
      const head = new DataView(new ArrayBuffer(30));
      head.setUint32(0, 0x04034b50, true); head.setUint16(4, 20, true); head.setUint16(6, 0x0800, true);
      head.setUint16(10, time, true); head.setUint16(12, date, true); head.setUint32(14, crc, true);
      head.setUint32(18, data.length, true); head.setUint32(22, data.length, true); head.setUint16(26, name.length, true);
      const cd = new DataView(new ArrayBuffer(46));
      cd.setUint32(0, 0x02014b50, true); cd.setUint16(4, 20, true); cd.setUint16(6, 20, true); cd.setUint16(8, 0x0800, true);
      cd.setUint16(12, time, true); cd.setUint16(14, date, true); cd.setUint32(16, crc, true);
      cd.setUint32(20, data.length, true); cd.setUint32(24, data.length, true); cd.setUint16(28, name.length, true); cd.setUint32(42, offset, true);
      chunks.push(new Uint8Array(head.buffer), name, data); central.push(new Uint8Array(cd.buffer), name);
      offset += 30 + name.length + data.length;
    }
    const end = new DataView(new ArrayBuffer(22));
    end.setUint32(0, 0x06054b50, true); end.setUint16(8, files.length, true); end.setUint16(10, files.length, true);
    end.setUint32(12, central.reduce((a, c) => a + c.length, 0), true); end.setUint32(16, offset, true);
    return new Blob(chunks.concat(central, [new Uint8Array(end.buffer)]), { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
  }
  const xmlEsc = s => String(s).replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F￾￿]/g, '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  function colName(i) { let s = ''; for (i++; i > 0; i = Math.floor((i - 1) / 26)) s = String.fromCharCode(65 + (i - 1) % 26) + s; return s; }
  function dateSerial(iso) { const [y, m, d] = iso.split('-').map(Number); return Math.round((Date.UTC(y, m - 1, d) - Date.UTC(1899, 11, 30)) / 864e5); }
  const D = iso => isISO(iso) ? { date: iso } : (iso || '');   // 日期格子
  const B = v => ({ v, bold: true });                           // 加粗格子
  // sheet: { name, head: [...], rows: [[格子...]] }，格子可以是文字、数字、D()、B()
  function sheetXml(sh) {
    const all = [sh.head.map(t => ({ v: t, head: true }))].concat(sh.rows), widths = [];
    const body = all.map((row, r) => '<row r="' + (r + 1) + '">' + row.map((c, i) => {
      let style = 0, v = c;
      if (c && typeof c === 'object') { if (c.date) { v = dateSerial(c.date); style = 3; } else { v = c.v; style = c.head ? 1 : 2; } }
      if (v == null || v === '') return '';
      if (typeof v === 'number') v = round2(v);
      const ref = colName(i) + (r + 1), shown = style === 3 ? '2026/12/31' : String(v);
      let w = 0; for (const ch of shown) w += ch.charCodeAt(0) > 255 ? 2 : 1;
      widths[i] = Math.max(widths[i] || 0, w);
      return typeof v === 'number' ? '<c r="' + ref + '" s="' + style + '"><v>' + v + '</v></c>'
        : '<c r="' + ref + '" s="' + style + '" t="inlineStr"><is><t xml:space="preserve">' + xmlEsc(v) + '</t></is></c>';
    }).join('') + '</row>').join('');
    const cols = sh.head.map((_, i) => '<col min="' + (i + 1) + '" max="' + (i + 1) + '" width="' + Math.min(60, Math.max(8, (widths[i] || 0) + 3)) + '" customWidth="1"/>').join('');
    return XML_HEAD + '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>' + cols + '</cols><sheetData>' + body + '</sheetData></worksheet>';
  }
  function makeXlsx(sheets) {
    const NSM = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main', NSR = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships', NSP = 'http://schemas.openxmlformats.org/package/2006/relationships';
    const CT = 'application/vnd.openxmlformats-officedocument.spreadsheetml.', used = new Set();
    sheets.forEach(sh => {   // 工作表名：最长 31 个字，不能有 []:*?/\，不能重名
      const base = String(sh.name).replace(/[\[\]:*?\/\\]/g, ' ').trim().slice(0, 31) || 'Sheet'; let n = base, k = 2;
      while (used.has(n.toLowerCase())) n = base.slice(0, 28) + ' ' + k++;
      used.add(n.toLowerCase()); sh.safe = n;
    });
    const files = [
      { name: '[Content_Types].xml', text: XML_HEAD + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="' + CT + 'sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="' + CT + 'styles+xml"/>' + sheets.map((_, i) => '<Override PartName="/xl/worksheets/sheet' + (i + 1) + '.xml" ContentType="' + CT + 'worksheet+xml"/>').join('') + '</Types>' },
      { name: '_rels/.rels', text: XML_HEAD + '<Relationships xmlns="' + NSP + '"><Relationship Id="rId1" Type="' + NSR + '/officeDocument" Target="xl/workbook.xml"/></Relationships>' },
      { name: 'xl/workbook.xml', text: XML_HEAD + '<workbook xmlns="' + NSM + '" xmlns:r="' + NSR + '"><sheets>' + sheets.map((sh, i) => '<sheet name="' + xmlEsc(sh.safe) + '" sheetId="' + (i + 1) + '" r:id="rId' + (i + 1) + '"/>').join('') + '</sheets></workbook>' },
      { name: 'xl/_rels/workbook.xml.rels', text: XML_HEAD + '<Relationships xmlns="' + NSP + '">' + sheets.map((_, i) => '<Relationship Id="rId' + (i + 1) + '" Type="' + NSR + '/worksheet" Target="worksheets/sheet' + (i + 1) + '.xml"/>').join('') + '<Relationship Id="rId' + (sheets.length + 1) + '" Type="' + NSR + '/styles" Target="styles.xml"/></Relationships>' },
      { name: 'xl/styles.xml', text: XML_HEAD + '<styleSheet xmlns="' + NSM + '"><fonts count="2"><font><sz val="11"/><name val="Arial"/></font><font><b/><sz val="11"/><name val="Arial"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFE4E7F5"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>' },
    ].concat(sheets.map((sh, i) => ({ name: 'xl/worksheets/sheet' + (i + 1) + '.xml', text: sheetXml(sh) })));
    return zipStore(files);
  }
  // months: 升序的月份；yearly 为真时每张表多一列“月份”，并多一张年度汇总
  function exportSheets(months, yearly) {
    const out = [], MH = yearly ? ['月份'] : [];
    const M = ym => yearly ? [Number(ym.split('-')[1]) + ' 月'] : [];
    if (yearly) {
      const colsDef = [];
      months.forEach(ym => breakdown(ym).forEach(p => { if (!colsDef.some(c => c.key === p.key)) colsDef.push({ key: p.key, label: p.label }); }));
      const sums = colsDef.map(() => 0), tot = zero();
      const rows = months.map(ym => {
        const bd = breakdown(ym), t = monthTotal(ym); addStats(tot, t);
        return [ymLabel(ym)].concat(colsDef.map((c, i) => { const p = bd.find(x => x.key === c.key), v = p ? p.st.profit : 0; sums[i] += v; return v; }), [t.income, t.cost, t.profit]);
      });
      rows.push([B('全年合计')].concat(sums.map(B), [B(tot.income), B(tot.cost), B(tot.profit)]));
      out.push({ name: '年度汇总', head: ['月份'].concat(colsDef.map(c => c.label + ' 利润'), ['收费合计', '续费成本合计', '利润合计']), rows });
    }
    const prof = [];
    for (const ym of months) {
      const bd = breakdown(ym), total = zero(); let all = 0;
      for (const sh of S.sheets) {
        const sub = zero(); let n = 0;
        bd.filter(p => p.sheet === sh.id).forEach(p => { addStats(sub, p.st); n += p.rows; if (sh.grouped) prof.push(M(ym).concat([p.label, p.rows, p.st.heads, p.st.income, p.st.cost, p.st.profit])); });
        const line = [sh.grouped ? sh.name + ' 小计' : sh.name, n, sub.heads, sub.income, sub.cost, sub.profit];
        prof.push(M(ym).concat(sh.grouped ? line.map(B) : line));
        addStats(total, sub); all += n;
      }
      prof.push(M(ym).concat(['全部合计', all, total.heads, total.income, total.cost, total.profit].map(B)));
    }
    out.push({ name: yearly ? '各类利润' : '利润汇总', head: MH.concat(['类别', '账号数', '收费人数', '收费', '续费成本', '利润']), rows: prof });
    const gOrder = id => { const i = G.findIndex(g => g.id === id); return i < 0 ? 9999 : i; };
    for (const sh of S.sheets) {
      const members = sh.mode === 'members', rows = [];
      for (const ym of months) {
        let list = (S.months[ym].rows[sh.id] || []).slice();
        if (sh.grouped) list = list.map((r, i) => [r, i]).sort((a, b) => gOrder(a[0].group) - gOrder(b[0].group) || a[1] - b[1]).map(x => x[0]);
        for (const r of list) {
          const g = G.find(x => x.id === r.group), it = issuerById(r.issuerId), c = cardById(r.cardId), inc = income(sh, r);
          rows.push(M(ym).concat(sh.grouped ? [g ? g.name : '未分组'] : [], [r.account, D(r.renew), it ? it.name : '', it ? it.country || '' : '', c ? cardLabel(c, true) : ''],
            members ? [r.members.map(m => (m.name || '') + plain(m.amount)).join(' + '), r.members.length] : [num(r.unitPrice), num(r.count)],
            [inc, num(r.cost), inc - num(r.cost), r.note, r.stopped ? '已停止' : '']));
        }
      }
      out.push({ name: sh.name, head: MH.concat(sh.grouped ? ['分组'] : [], ['账号', '续费日期', '续费卡信息', '国家 / 地区', '卡号'], members ? ['收费情况（每人）', '收费人数'] : ['单价', '人数'], ['收费', '续费成本', '利润', '备注', '状态']), rows });
    }
    const spend = [];
    for (const ym of months) {
      const cs = cardStats(ym);
      for (const it of S.issuers) {
        const st = cs.byIssuer[it.id]; if (!st) continue;
        spend.push(M(ym).concat([B(it.name), it.country || '', B('合计'), B(st.n), B(st.cost)]));
        let n = st.n, cost = st.cost;
        for (const c of cardsOf(it.id)) { const s = cs.byCard[c.id]; if (!s) continue; n -= s.n; cost -= s.cost; spend.push(M(ym).concat([it.name, it.country || '', cardLabel(c, true), s.n, s.cost])); }
        if (n > 0) spend.push(M(ym).concat([it.name, it.country || '', '未指定卡号', n, cost]));
      }
      if (cs.none.cost) spend.push(M(ym).concat(['没选卡的账号', '', '', cs.none.n, cs.none.cost]));
    }
    out.push({ name: '按卡统计', head: MH.concat(['卡信息', '国家 / 地区', '卡号', '账号数', '续费成本']), rows: spend });
    const cardRows = [];
    for (const it of S.issuers) { const own = cardsOf(it.id); if (!own.length) cardRows.push([it.name, it.country || '', '', '']); own.forEach(c => cardRows.push([it.name, it.country || '', c.number || '', c.note || ''])); }
    out.push({ name: '支付卡', head: ['卡信息', '国家 / 地区', '卡号', '备注'], rows: cardRows });
    out.push({ name: 'VPS', head: ['主机', 'IP', '密码', '部署', '流量及重置', '续费', '价格', '邮箱'], rows: S.vps.map(v => [v.host, v.ip, v.password, v.deploy, v.traffic, D(v.renew), v.price, v.email]) });
    return out;
  }
  function download(blob, name) {
    const a = h('a', { href: URL.createObjectURL(blob), download: name });
    document.body.append(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }
  async function exportDialog() {
    const keys = monthKeys(), years = keys.map(k => k.slice(0, 4)).filter((v, i, a) => a.indexOf(v) === i);
    const mode = h('select', null, h('option', { value: 'month', text: '按月导出' }), h('option', { value: 'year', text: '按年导出' }));
    const month = h('select', null, keys.slice().reverse().map(k => h('option', { value: k, text: ymLabel(k), selected: k === view.month })));
    const year = h('select', null, years.slice().reverse().map(y => h('option', { value: y, text: y + ' 年（共 ' + keys.filter(k => k.slice(0, 4) === y).length + ' 个月有数据）', selected: y === view.month.slice(0, 4) })));
    const fm = h('label', { class: 'field' }, '月份', month), fy = h('label', { class: 'field', hidden: true }, '年份', year);
    mode.addEventListener('change', () => { fm.hidden = mode.value !== 'month'; fy.hidden = mode.value !== 'year'; });
    const ok = await dialog('导出 Excel', [h('label', { class: 'field' }, '范围', mode), fm, fy,
      h('div', { class: 'muted', text: '按年导出会多一张“年度汇总”，其余各表把全年每个月的数据排在一起。\n文件里的卡号和 VPS 密码是完整的，注意保管。' })],
      [{ text: '取消' }, { text: '导出', cls: 'primary', value: true }]);
    if (!ok) return;
    const yearly = mode.value === 'year', months = yearly ? keys.filter(k => k.slice(0, 4) === year.value) : [month.value];
    download(makeXlsx(exportSheets(months, yearly)), '合租管理-' + (yearly ? year.value + '年' : ymLabel(month.value).replace(/\s/g, '')) + '.xlsx');
  }


  // ---------- 页面 ----------
  function render() {
    closePop(); updaters = []; searchRows = []; codes.els = [];
    if (location.hash.slice(1) !== view.tab && !location.search) history.replaceState(null, '', '#' + view.tab);
    const M = S.months[view.month], keys = monthKeys(), isLatest = view.month === keys[keys.length - 1], i = keys.indexOf(view.month);
    const go = ym => { view.month = ym; render(); };
    const sheet = S.sheets.find(s => s.id === view.tab);
    const monthBound = view.tab !== 'vps';
    statusEl = h('div', { class: 'status', text: statusEl ? statusEl.textContent : '' });
    const nav = (id, text, ic, count) => h('button', { class: 'nav' + (view.tab === id ? ' on' : ''), type: 'button', 'aria-current': view.tab === id ? 'page' : undefined, onclick: () => { view.tab = id; view.q = ''; render(); } },
      icon(ic), h('span', { text }), count != null ? h('span', { class: 'count', text: String(count) }) : null);
    const link = (href, text, ic, count) => h('a', { class: 'nav', href, onclick: e => { e.preventDefault(); leave(href); } },
      icon(ic), h('span', { text }), count != null ? h('span', { class: 'count', text: String(count) }) : null);
    const side = h('nav', { class: 'side', 'aria-label': '主导航' },
      h('div', { class: 'brand' }, h('div', { class: 'logo', text: '租' }), h('span', { text: '合租管理' })),
      nav('home', '总览', 'grid'),
      h('div', { class: 'nav-label', text: '账号' }),
      S.sheets.map(s => nav(s.id, s.name, s.grouped ? 'users' : 'play', M.rows[s.id].length)),
      h('button', { class: 'nav', type: 'button', title: '新建一张表', onclick: () => sheetForm(null) }, icon('plus'), h('span', { text: '新建表' })),
      h('div', { class: 'nav-label', text: '后台' }),
      nav('cards', '支付卡', 'card', S.cards.length), nav('vps', 'VPS', 'server', S.vps.length),
      h('div', { class: 'nav-label', text: '验证码' }),
      link('/admin/dashboard', '验证码账号', 'key', A.length), link('/admin/logs', '访问记录', 'list'), link('/admin/settings', '设置', 'gear'),
      h('div', { class: 'side-foot' }, statusEl,
        h('button', { class: 'nav', type: 'button', onclick: e => menu(e.currentTarget, [
          { text: '导入 Excel…', run: () => isEditable() ? pickImport() : alertBox('当前月份已归档。请先切到进行中的月份，或解锁后再导入。') },
          { text: '导出 Excel…', run: exportDialog },
          { text: '导出数据备份（JSON）', run: exportBackup },
          { text: '从 JSON 备份恢复…', run: restoreBackup },
          { text: '恢复到某天的版本…', run: historyDialog },
          isLatest && keys.length > 1 ? { text: '删除 ' + ymLabel(view.month), danger: true, run: deleteLatestMonth } : null,
          '-',
          { text: '退出登录', run: logout },
        ]) }, icon('more'), h('span', { text: '更多' }))));
    const title = view.tab === 'home' ? '总览' : view.tab === 'cards' ? '支付卡' : view.tab === 'vps' ? 'VPS' : sheet.name;
    const top = h('div', { class: 'top' }, h('h1', { text: title }), h('span', { class: 'spacer' }));
    if (monthBound) {
      add(top, [
        isLatest ? null : h('span', { class: 'badge', text: '已归档' }),
        h('div', { class: 'month' },
          h('button', { class: 'btn ghost icon', type: 'button', 'aria-label': '上个月', disabled: i === 0, onclick: () => go(keys[i - 1]) }, icon('left', 16)),
          h('select', { 'aria-label': '月份', onchange: e => go(e.target.value) }, keys.slice().reverse().map(k => h('option', { value: k, text: ymLabel(k) + (S.months[k].archived ? '（已归档）' : ''), selected: k === view.month }))),
          h('button', { class: 'btn ghost icon', type: 'button', 'aria-label': '下个月', disabled: i === keys.length - 1, onclick: () => go(keys[i + 1]) }, icon('right', 16))),
        isLatest && view.tab !== 'cards' ? h('button', { class: 'btn', type: 'button', onclick: startNextMonth }, icon('archive', 15), '归档并开始 ' + Number(nextYM(view.month).split('-')[1]) + ' 月') : null]);
    }
    const body = h('div', { class: 'view' });
    if (monthBound && view.tab !== 'cards' && M.archived) {
      body.append(h('div', { class: 'banner' }, h('span', { text: view.unlocked[view.month] ? ymLabel(view.month) + ' 是存档，已临时解锁，可以修改。' : ymLabel(view.month) + ' 是存档，只能看不能改。' }),
        view.unlocked[view.month] ? h('button', { class: 'btn small', type: 'button', text: '重新锁定', onclick: () => { delete view.unlocked[view.month]; render(); } })
          : h('button', { class: 'btn small', type: 'button', text: '解锁修改', onclick: () => { view.unlocked[view.month] = true; render(); } })));
    }
    add(body, view.tab === 'home' ? homeView() : view.tab === 'cards' ? cardsView() : view.tab === 'vps' ? vpsView() : sheetView(sheet));
    countryList();
    setKids(document.getElementById('app'), h('div', { class: 'shell' }, side, h('main', { class: 'main' }, top, body)));
    recalc(); applySearch(); paintCodes();
  }
  load().catch(e => {
    console.error(e);
    setKids(document.getElementById('app'), h('div', { class: 'login' }, h('form', null, h('h1', { text: '合租账本' }),
      h('div', { class: 'err', text: '加载失败：' + e.message }), h('a', { class: 'btn primary', href: '/admin/hezu', text: '重试' }))));
  });
})();
