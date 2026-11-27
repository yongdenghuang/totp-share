'use strict';
(function () {
  const COUNTRIES = ['美国', '菲律宾', '尼日利亚', '中国', '香港', '新加坡', '英国', '欧洲'];
  const SEED_ISSUERS = [['Wise', ''], ['Maya Bank', '菲律宾'], ['PalawanPay', '菲律宾'], ['Revolut', ''], ['PayPal', ''], ['Krak', ''], ['Bybit EU', '欧洲'], ['Moniepoint', '尼日利亚']];
  const COUNTRY_GUESS = { mayabank: '菲律宾', maya: '菲律宾', palawanpay: '菲律宾', moniepoint: '尼日利亚', paga: '尼日利亚', bybiteu: '欧洲' };
  const ICONS = {
    chev: '<path d="m6 9 6 6 6-6"/>',
    edit: '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>',
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
    bolt: '<path d="M13 2 3 14h9l-1 8 10-12h-9l1-8z"/>',
    pen: '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/>',
    link: '<path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>',
    fx: '<path d="M7 4 3 8l4 4"/><path d="M3 8h13a4 4 0 0 1 4 4"/><path d="m17 20 4-4-4-4"/><path d="M21 16H8a4 4 0 0 1-4-4"/>',
    brain: '<path d="M9 3a3 3 0 0 0-3 3v.2A3 3 0 0 0 4 9a3 3 0 0 0 1 2.2A3 3 0 0 0 5 15a3 3 0 0 0 3 3v.5A2.5 2.5 0 0 0 12 20V5a2 2 0 0 0-3-2z"/><path d="M15 3a3 3 0 0 1 3 3v.2A3 3 0 0 1 20 9a3 3 0 0 1-1 2.2A3 3 0 0 1 19 15a3 3 0 0 1-3 3v.5A2.5 2.5 0 0 1 12 20"/>',
    lock: '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/><path d="M12 15v2"/>',
    note: '<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><path d="M14 3v6h6"/><path d="M8 13h8M8 17h5"/>',
    gear: '<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M2 12h3M19 12h3M4.9 19.1 7 17M17 7l2.1-2.1"/>',
  };

  let S = null;                       // 账本数据（加密存在服务器上）
  let G = [];                         // 账号验证码的分组（新建验证码账号、「只存账号」表认领时用）；AI 合租的分组在 sheet.groups 里
  let A = [];                         // 验证码账号名单（不含密钥和密码）
  let VC = { items: 0, notes: 0 };    // 密码本、备忘录的条数（导航上显示）
  let NAV = { sections: ['accounts', 'backend', 'backup', 'totp'], items: {} };   // 左侧导航的顺序（服务器上存着）
  let CSRF = document.getElementById('app').dataset.csrf || '';
  const API = '/admin/hezu/api';
  const codes = { map: {}, until: 0, period: 30, timer: null, els: [], timers: [] };   // 当前验证码，只显示不保存
  const view = { tab: 'home', month: null, unlocked: {}, q: '', country: '', gfilter: null };   // gfilter: null = 全部，'__loose' = 未分组，否则分组 id
  // 上次的分组筛选、国家筛选记在浏览器里，刷新后还是那样
  try { const v = JSON.parse(localStorage.getItem('hezu-view') || '{}') || {}; if ('gfilter' in v) view.gfilter = v.gfilter; if (typeof v.country === 'string') view.country = v.country; } catch (e) { /* 忽略 */ }
  function saveView() { try { localStorage.setItem('hezu-view', JSON.stringify({ gfilter: view.gfilter, country: view.country })); } catch (e) { /* 忽略 */ } }
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
      const c = rowCost(sh, r);
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
      unitPrice: num(r.unitPrice), unitCost: num(r.unitCost), count: num(r.count), cost: num(r.cost), note: r.note || '', stopped: !!r.stopped,
      password: String(r.password || ''),
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
    S.vps = S.vps.map(v => {
      const o = Object.assign(newVps(), v);
      if (!Array.isArray(o.tags)) o.tags = [];
      if ('deploy' in o) { if (o.deploy && !o.tags.length) o.tags = splitTags(o.deploy); delete o.deploy; changed = true; }
      if (o.tags.some(t => typeof t !== 'object' || !t)) changed = true;
      o.tags = o.tags.map(tagObj).filter(t => t.name);
      return o;
    });
    if (!view.month || !S.months[view.month]) view.month = latestMonth();
    if (!['home', 'cards', 'vps'].includes(view.tab) && !S.sheets.some(s => s.id === view.tab)) view.tab = 'home';
    if (linkTotp()) changed = true;
    if (syncFromTotp()) changed = true;
    if (changed) touch();
  }
  // 「只存账号」表认领了某个验证码分组时：这个分组里、这个月还没记上的验证码账号，自动在那张表补一行。
  // AI 合租这类分组表有自己的一套分组，验证码里新加的账号不会自动加进去（要用就点「添加账号」从验证码里选）。
  // 手动删掉或取消关联过的记在 totpSkip 里，不会被自动补回来。
  function syncFromTotp() {
    const ids = new Set(A.map(a => a.id));
    const before = (S.totpSkip || []).length;
    S.totpSkip = (S.totpSkip || []).filter((id, i, arr) => ids.has(id) && arr.indexOf(id) === i);
    let n = S.totpSkip.length !== before ? 1 : 0;
    const ym = latestMonth(), M = S.months[ym];
    if (!M || M.archived) return n > 0;
    const skip = new Set(S.totpSkip), have = new Set();
    for (const sh of S.sheets) for (const r of M.rows[sh.id]) if (r.totpId > 0) have.add(r.totpId);
    for (const a of A) if (!have.has(a.id) && !skip.has(a.id)) {
      const own = sheetForGroup(a.group);
      if (!own) continue;
      M.rows[own.id].push(fixRow({ account: a.name, totpId: a.id }));
      n++;
    }
    return n > 0;
  }
  function skipTotp(id, on) {
    const list = (S.totpSkip || []).filter(x => x !== id);
    if (on) list.push(id);
    S.totpSkip = list;
  }
  // 关联的验证码账号被删了：解除关联。按名字自动关联只在「只存账号」表做（那里的账号就是那个验证码分组的）；
  // 其他表要关联请手动选。totpId: 0 = 没关联，-1 = 手动的 / 取消过，不再自动关联
  function linkTotp() {
    const byName = {}; let n = 0;
    A.forEach(a => { const k = normName(a.name); (byName[k] = byName[k] || []).push(a); });
    for (const ym in S.months) for (const sh of S.sheets) for (const r of S.months[ym].rows[sh.id]) {
      if (r.totpId > 0 && !totpById(r.totpId)) { r.totpId = 0; n++; }
      if (!r.totpId && r.account && sh.mode === 'accounts' && sh.totpGroup) {
        const m = (byName[normName(r.account)] || []).filter(a => a.group === sh.totpGroup);
        if (m.length === 1) { r.totpId = m[0].id; n++; onLinked(r, sh, ym); }
      }
    }
    if (pullNames()) n++;
    return n > 0;
  }
  // 关联了验证码账号的行：账号名以验证码账号为准（存档月份保持当时的样子）。分组两边各管各的，不同步。
  function pullNames() {
    let n = 0;
    for (const ym in S.months) if (!S.months[ym].archived) for (const sh of S.sheets) for (const r of S.months[ym].rows[sh.id] || []) {
      const a = r.totpId > 0 ? totpById(r.totpId) : null;
      if (a && a.name && r.account !== a.name) { r.account = a.name; n++; }
    }
    return n > 0;
  }
  // 在账本里改了关联行的账号名：同步改验证码账号，其他月份里同一个账号也跟着改
  function pushName(row) {
    const a = row.totpId > 0 ? totpById(row.totpId) : null;
    const name = String(row.account || '').trim();
    if (!a || !name || name === a.name) return;
    a.name = name; pullNames(); touch(); render();
    api('POST', '/admin/accounts/' + a.id + '/field', { field: 'name', value: name })
      .then(r => { if (!r.ok) setStatus('验证码账号的名称没改成，请刷新页面', true); }).catch(() => setStatus('验证码账号的名称没改成，请刷新页面', true));
  }
  // 刚关联上的那一刻：这一行填过密码而验证码账号还没有，就把密码存过去
  function onLinked(row, sheet, ym) {
    const a = totpById(row.totpId);
    if (!a || S.months[ym].archived) return;
    if (row.password && !a.hasPassword) {
      const pw = row.password;
      api('POST', '/admin/accounts/' + a.id + '/password', { password: pw }).then(r => { if (r.ok) { a.hasPassword = true; if (row.password === pw) { row.password = ''; touch(); } } });
    }
  }
  function moveRow(row, groupId) { row.group = groupId; touch(); render(); }
  function newVps() { return { id: uid(), host: '', site: '', ip: '', port: '', password: '', tags: [], traffic: '', renew: '', price: '', email: '', loginPassword: '' }; }
  const VPS_DUE_DAYS = 30;   // 一个月内要续费的 VPS 整行标黄
  function splitTags(t) { return String(t || '').split(/[，,、/;；|\n]+/).map(x => x.trim()).filter((x, i, a) => x && a.indexOf(x) === i); }
  // 部署标签：{ name: 项目名, url: 这个项目的网址（可空） }；老数据里是纯文字
  function tagObj(t) { return typeof t === 'object' && t ? { name: String(t.name || '').trim(), url: String(t.url || '').trim() } : { name: String(t || '').trim(), url: '' }; }
  const tagNames = v => (v.tags || []).map(t => tagObj(t).name);
  // 表的收费方式：members = 每人单独填金额；unit = 单价 × 人数；resale = 代充（售价、成本/份固定，按数量算）
  // accounts = 只存账号（账号、密码、验证码、备注），不算钱，也不进总览的收费 / 利润
  function rowCost(sheet, r) { return sheet.mode === 'accounts' ? 0 : sheet.mode === 'resale' ? num(r.unitCost) * num(r.count) : num(r.cost); }
  function income(sheet, r) { return sheet.mode === 'accounts' ? 0 : sheet.mode === 'members' ? r.members.reduce((a, m) => a + num(m.amount), 0) : num(r.unitPrice) * num(r.count); }
  function heads(sheet, r) { return sheet.mode === 'accounts' ? 0 : sheet.mode === 'members' ? r.members.length : num(r.count); }
  // 「只存账号」表可以认领一个验证码分组（totpGroup）：这个分组的验证码账号自动记到这张表
  const sheetForGroup = name => S.sheets.find(x => x.mode === 'accounts' && x.totpGroup && x.totpGroup === name) || null;
  // 分组表（AI 合租）自己的分组：sheet.groups = [{ id, name, color, text }]，和账号验证码的分组互不影响
  const sheetGroups = sh => (sh && Array.isArray(sh.groups)) ? sh.groups : [];
  const visibleGroups = sh => sheetGroups(sh);
  const shownIds = sh => new Set(sheetGroups(sh).map(g => g.id));
  const groupOf = (sh, id) => sheetGroups(sh).find(g => g.id === id) || null;
  // 底色上用白字还是深色字（和服务器 text_color_on 一样）
  function textOn(bg) {
    const m = /^#([0-9a-f]{6})$/i.exec(bg || ''); if (!m) return '#ffffff';
    const v = parseInt(m[1], 16), r = v >> 16, g = (v >> 8) & 255, b = v & 255;
    return 0.299 * r + 0.587 * g + 0.114 * b > 160 ? '#1f2937' : '#ffffff';
  }
  const GROUP_COLORS = ['#3b82f6', '#22c55e', '#f97316', '#8b5cf6', '#ec4899', '#14b8a6', '#eab308', '#ef4444', '#64748b', '#0ea5e9'];
  const zero = () => ({ n: 0, heads: 0, income: 0, cost: 0, profit: 0 });
  function stats(sheet, rows) {
    const s = zero();
    for (const r of rows) { if (!r.stopped) s.n++; s.heads += heads(sheet, r); s.income += income(sheet, r); s.cost += rowCost(sheet, r); }
    s.profit = s.income - s.cost;
    return s;
  }
  function addStats(a, b) { for (const k in a) a[k] += b[k]; return a; }
  // 一个月按“分组 / 表”拆开的统计
  function breakdown(ym) {
    const M = S.months[ym], out = [];
    for (const sh of S.sheets) {
      if (sh.mode === 'accounts') continue;
      const rows = (M.rows[sh.id] || []);
      if (sh.grouped) {
        const ids = shownIds(sh);
        for (const g of visibleGroups(sh)) out.push({ key: 'g:' + g.id, label: g.name, color: g.color, text: g.text, sheet: sh.id, rows: rows.filter(r => r.group === g.id).length, st: stats(sh, rows.filter(r => r.group === g.id)) });
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
  function useContext(d) { if (d.csrf) CSRF = d.csrf; if (d.groups) G = d.groups; if (d.accounts) A = d.accounts; if (d.vault) VC = d.vault; if (d.navOrder) NAV = d.navOrder; }
  async function refreshContext() {
    try {
      const r = await fetch(API + '/context', { credentials: 'same-origin' });
      if (r.ok) { useContext(await r.json()); return true; }
      if (r.status === 401) return 'expired';
    } catch (e) { /* 断网，下次再试 */ }
    return false;
  }
  let lastStatus = { text: '', err: false };
  function setStatus(text, err) {
    lastStatus = { text, err: !!err };
    document.querySelectorAll('.save-status').forEach(el => { el.textContent = text; el.classList.toggle('err', !!err); el.classList.toggle('ok', !err && /^已保存/.test(text)); });
  }
  function touch() {
    dirty = true; setStatus('有改动…');
    clearTimeout(saveTimer); saveTimer = setTimeout(save, 900);
  }
  function saveNow() { dirty = true; clearTimeout(saveTimer); save(); }   // 归档、导入这类大改动立刻存，不等防抖
  // 登录过期时的提示条：改动留在页面里，重新登录后自动补存
  let reloginBar = null;
  function showRelogin(on) {
    if (on && !reloginBar) {
      const pending = dirty || saving;
      reloginBar = h('div', { class: 'relogin', role: 'alert' }, h('span', { text: pending ? '登录已过期，刚才的改动还没保存。' : '登录已过期（30 分钟没有操作会自动退出）。' }),
        h('a', { class: 'btn small primary', href: '/admin/login?next=/admin/hezu', target: '_blank', rel: 'noopener', text: '在新窗口重新登录' }),
        h('span', { class: 'muted', text: pending ? '登录后回到这里，会自动保存，不要刷新本页。' : '登录后回到这里再修改。' }));
      document.body.append(reloginBar);
    } else if (!on && reloginBar) { reloginBar.remove(); reloginBar = null; }
  }
  // ---------- 冲突合并 ----------
  // base = 本页最后一次和服务器一致时的账本。别的窗口（或服务器上的脚本）先存了一版时，
  // 用 base 找出“本页改了什么、对方改了什么”，两边的改动都留下；同一个格子两边都改了，以本页为准。
  let base = null;
  const clone = x => JSON.parse(JSON.stringify(x));
  function stable(x) {
    if (Array.isArray(x)) return '[' + x.map(stable).join(',') + ']';
    if (x && typeof x === 'object') return '{' + Object.keys(x).sort().map(k => JSON.stringify(k) + ':' + stable(x[k])).join(',') + '}';
    return JSON.stringify(x === undefined ? null : x);
  }
  const same = (a, b) => stable(a) === stable(b);
  const isObj = x => x && typeof x === 'object' && !Array.isArray(x);
  const keyed = a => Array.isArray(a) && a.every(x => isObj(x) && x.id != null);
  function merge3(b, l, r) {
    if (same(l, b)) return r;
    if (same(r, b) || same(l, r)) return l;
    if (keyed(l) && keyed(r)) {
      const bl = keyed(b) ? b : [], bm = new Map(bl.map(x => [x.id, x])), lm = new Map(l.map(x => [x.id, x])), rm = new Map(r.map(x => [x.id, x]));
      const localReordered = !same(l.map(x => x.id).filter(id => bm.has(id) && rm.has(id)), bl.map(x => x.id).filter(id => lm.has(id) && rm.has(id)));
      const first = localReordered ? l : r, second = localReordered ? r : l, ids = first.map(x => x.id);
      // 另一边新加的：放在它后一个邻居前面；后面没有邻居（多半是加在末尾）就放最后
      second.forEach((x, k) => { if (!ids.includes(x.id)) { const next = second.slice(k + 1).find(y => ids.includes(y.id)); ids.splice(next ? ids.indexOf(next.id) : ids.length, 0, x.id); } });
      const out = [];
      for (const id of ids) {
        const bx = bm.get(id), lx = lm.get(id), rx = rm.get(id);
        if (lx && rx) out.push(merge3(bx, lx, rx));
        else if (lx) { if (!bx || !same(lx, bx)) out.push(lx); }       // 对方删了、本页没动 → 删
        else if (rx) { if (!bx || !same(rx, bx)) out.push(rx); }       // 本页删了、对方没动 → 删
      }
      return out;
    }
    if (isObj(l) && isObj(r)) {
      const bb = isObj(b) ? b : {}, out = {};
      for (const k of new Set([...Object.keys(r), ...Object.keys(l)])) {
        if (k in l && k in r) out[k] = merge3(bb[k], l[k], r[k]);
        else if (k in l) { if (!(k in bb) || !same(l[k], bb[k])) out[k] = l[k]; }
        else if (!(k in bb) || !same(r[k], bb[k])) out[k] = r[k];
      }
      return out;
    }
    return l;
  }
  const bare = st => { const c = clone(st); delete c.rev; return c; };
  // 服务器上有新版本：本页没有未保存的改动就直接换成新版本；有的话合并进去再存
  async function pullLatest(reason) {
    const r = await fetch(API + '/state', { credentials: 'same-origin' });
    if (r.status === 401) { showRelogin(true); return false; }
    if (!r.ok) return false;
    const d = await r.json();
    useContext(d); if (d.csrf) CSRF = d.csrf;
    if (d.rev === S.rev) {   // 账本没变，但验证码账号可能改了名字或分组
      if (linkTotp()) { touch(); render(); }
      return true;
    }
    const remote = d.state;
    const local = bare(S), changed = base && !same(local, base);
    const next = changed ? merge3(base, local, bare(remote)) : bare(remote);
    base = bare(remote);
    S = next; S.rev = d.rev;
    normalize(); render(); pollCodes();
    if (changed) { dirty = true; setStatus(reason === 'conflict' ? '已合并别处的修改，正在保存…' : '已同步别处的修改'); }
    else setStatus('已同步别处的修改');
    return true;
  }
  const channel = 'BroadcastChannel' in window ? new BroadcastChannel('hezu-ledger') : null;
  if (channel) channel.onmessage = e => { if (e.data && e.data.rev !== (S && S.rev) && !saving) pullLatest('peer').then(() => { if (dirty) { clearTimeout(saveTimer); saveTimer = setTimeout(save, 300); } }); };
  // 切回这个窗口时看看服务器上有没有新版本，顺便确认登录还在
  let lastCheck = 0;
  async function checkFresh() {
    if (!S || saving || Date.now() - lastCheck < 5000) return;
    lastCheck = Date.now();
    await pullLatest('focus');
    if (dirty) { clearTimeout(saveTimer); saveTimer = setTimeout(save, 300); }
  }
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') checkFresh(); });
  window.addEventListener('focus', checkFresh);

  // 网页版本号：服务器拒收旧页面的保存，免得开着没刷新的旧页面按旧规则把账本改回去
  const CLIENT_VERSION = 4;
  let conflicts = 0;
  async function save() {
    if (saving || !dirty) return;
    saving = true; dirty = false; setStatus('保存中…');
    let again = 900;   // 保存期间又有改动时，多久后再存一次
    if (reloginBar && (await refreshContext()) !== true) {   // 还没重新登录：先别反复上传整份账本
      saving = false; dirty = true; setStatus('登录已过期，改动还没保存', true);
      clearTimeout(saveTimer); saveTimer = setTimeout(save, 5000); return;
    }
    const sent = bare(S);
    try {
      const r = await api('PUT', '/state', { rev: S.rev, state: S, client: CLIENT_VERSION });
      if (r.status === 401) { dirty = true; again = 5000; setStatus('登录已过期，改动还没保存', true); showRelogin(true); }
      else if (r.status === 409) {
        // 别的窗口先存了：把两边的改动合并后再存，不丢本页的改动
        dirty = true; saving = false;
        if (++conflicts > 5) { conflicts = 0; setStatus('保存冲突，请刷新页面', true); return; }
        await pullLatest('conflict');
        clearTimeout(saveTimer); saveTimer = setTimeout(save, 200); return;
      }
      else if (!r.ok) throw new Error('HTTP ' + r.status);
      else {
        const d = await r.json(); S.rev = d.rev; if (d.csrf) CSRF = d.csrf;
        base = sent; conflicts = 0;
        showRelogin(false);
        if (channel) channel.postMessage({ rev: d.rev });
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
  function adopt(d) { useContext(d); S = d.state; S.rev = d.rev; base = bare(d.state); dirty = false; const t = tabFromHash(); normalize(); render(); pollCodes(); if (t === 'new-sheet') sheetForm(null); }
  function openAddFromLink() {
    if (!new URLSearchParams(location.search).has('add')) return;
    history.replaceState(null, '', location.pathname);
    view.month = latestMonth();
    const sheet = S.sheets.find(s => s.grouped) || S.sheets[0];
    if (sheet) view.tab = sheet.id;
    render(); if (sheet) addAccountDialog({ sheet, group: null });
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
      if (r.ok) { const d = await r.json(); codes.map = d.codes || {}; codes.until = Date.now() + d.remaining * 1000; codes.period = d.period || 30; wait = d.remaining * 1000 + 500; }
      else { codes.map = {}; if (r.status === 401) showRelogin(true); }
    } catch (e) { /* 断网时稍后再取 */ }
    paintCodes();
    codes.timer = setTimeout(pollCodes, wait);
  }
  function paintCodes() {
    const left = Math.max(0, Math.round((codes.until - Date.now()) / 1000));
    for (const t of codes.timers) {
      const on = codes.until > 0;
      t.el.hidden = !on; if (!on) continue;
      t.el.classList.toggle('low', left <= 5);
      t.bar.style.transition = left > t.prev ? 'none' : '';   // 换码那一下直接回满，不倒着动画
      t.bar.style.width = Math.round(left / codes.period * 100) + '%';
      t.sec.textContent = left + 's';
      t.el.title = '验证码 ' + left + ' 秒后更新';
      t.prev = left;
    }
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
      setKids(list, items.map(a => h('button', { class: 'item', type: 'button', onclick: () => { row.totpId = a.id; skipTotp(a.id, false); closePop(); const sh = S.sheets.find(x => x.id === view.tab); if (sh) onLinked(row, sh, view.month); pullNames(); touch(); render(); } },
        a.name, a.group ? h('span', { class: 'faint', text: '  ' + a.group }) : null)), items.length ? null : h('div', { class: 'label', text: '没有匹配的验证码账号' }));
    };
    q.addEventListener('input', draw); draw();
    openPop(anchor, [h('div', { class: 'form' }, h('label', { class: 'field' }, '关联到哪个验证码账号', q)), list, h('div', { class: 'sep' }),
      h('button', { class: 'item', type: 'button', text: '＋ 新建验证码账号…', onclick: () => { closePop(); leave('/admin/accounts/new?name=' + encodeURIComponent(row.account || '')); } })]);
    q.focus();
  }
  async function copyShareInfo(row, el) {
    let has = true;
    const text = api('POST', '/admin/accounts/' + row.totpId + '/share-text', {}).then(r => r.json().catch(() => ({}))).then(d => {
      if (!d.ok) throw new Error(d.error || '取不到分享信息，请刷新页面后再试。');
      has = d.has_password; return d.text;
    });
    try { await copyLater(text, el); } catch (e) { return alertBox(e.message || '复制失败'); }
    setStatus(has ? '已复制分享信息' : '已复制分享信息（这个账号还没存密码，点「改密码」设置）', !has);
  }
  const shareUrl = a => location.origin + '/t/' + a.token;
  // 分享链接不在账本数据里：打开「只存账号」表时按需取一次
  const shareTok = {}, sharePending = new Set(); let shareTimer = null;
  function loadShareLinks(ids) {
    ids.forEach(id => { if (!(id in shareTok)) sharePending.add(id); });
    if (!sharePending.size || shareTimer) return;
    shareTimer = setTimeout(() => {        // 同一次画表里的所有行，一起取
      const need = Array.from(sharePending); sharePending.clear();
      api('POST', '/share-links', { ids: need }).then(r => r.json()).then(d => {
        need.forEach(id => { shareTok[id] = d.ok ? (d.links || {})[id] || '' : ''; });
        render();
      }).catch(() => { need.forEach(id => { shareTok[id] = ''; }); render(); }).finally(() => { shareTimer = null; });
    }, 0);
  }

  // 「只存账号」表：和验证码账号页一样的分享链接（复制 / 换链接）和操作按钮（复制信息、改密码、预览、记录、编辑）
  function shareCell(row) {
    const a0 = row.totpId > 0 ? totpById(row.totpId) : null;
    if (!a0) return h('span', { class: 'faint small', text: '—' });
    const a = Object.assign({}, a0, { token: shareTok[a0.id] });
    if (!a.token) { loadShareLinks([a0.id]); return h('span', { class: 'faint small', text: a.id in shareTok ? '取不到链接' : '…' }); }
    const link = h('span', { class: 'share-link mono', title: shareUrl(a), text: '/t/' + a.token });
    const copy = h('button', { class: 'btn xs', type: 'button', text: '复制', title: '复制验证码分享链接', onclick: () => copyLater(Promise.resolve(shareUrl(a)), copy) });
    const regen = h('button', { class: 'btn xs warn', type: 'button', text: '换链接', title: '生成新链接，旧链接立即失效', onclick: async () => {
      if (!await confirmBox('换链接', '给「' + a.name + '」换一条新的分享链接？\n\n旧链接会立即失效，正在使用的人需要拿到新链接才能继续看验证码。', '换链接', true)) return;
      const r = await api('POST', '/admin/accounts/' + a.id + '/regen', {}), d = await r.json().catch(() => ({}));
      if (!r.ok || !d.ok) return alertBox(d.error || '换链接失败');
      shareTok[a.id] = d.url_token; render();
      try { await navigator.clipboard.writeText(d.url); setStatus('已换新链接并复制到剪贴板'); } catch (e) { setStatus('已换新链接（自动复制失败，请点「复制」）'); }
    } });
    return h('div', { class: 'share-cell' }, link, copy, regen);
  }
  function acctActions(row) {
    const a = row.totpId > 0 ? totpById(row.totpId) : null;
    if (!a) return h('button', { class: 'btn xs', type: 'button', text: '关联验证码账号…', onclick: e => linkTotpMenu(e.currentTarget, row) });
    const tok = shareTok[a.id];
    const info = h('button', { class: 'btn xs primary', type: 'button', text: '复制信息', title: '复制分组、账号、密码和验证码链接' + (a.hasPassword ? '' : '（这个账号还没保存密码）'), onclick: () => copyShareInfo(row, info) });
    return h('div', { class: 'acct-actions' }, info,
      h('button', { class: 'btn xs ok', type: 'button', text: '改密码', title: '生成新密码、查看当前密码', onclick: () => pwDialog(row, a) }),
      h('a', { class: 'btn xs', href: tok ? '/t/' + tok : '#', target: '_blank', rel: 'noopener', text: '预览', onclick: e => { if (!tok) e.preventDefault(); } }),
      h('a', { class: 'btn xs', href: '/admin/logs?account=' + a.id, text: '记录', onclick: e => { e.preventDefault(); leave('/admin/logs?account=' + a.id); } }),
      h('a', { class: 'btn xs', href: '/admin/accounts/' + a.id + '/edit', text: '编辑', onclick: e => { e.preventDefault(); leave('/admin/accounts/' + a.id + '/edit'); } }));
  }
  // 改密码：和验证码账号页的弹窗一样——看当前 / 上一个密码，生成新密码，保存并复制，再复制信息发给对方
  function pwDialog(row, a) {
    const G2 = window.PwGen;
    const field = (label, inp, ...btns) => h('label', { class: 'field' }, label, h('div', { class: 'pw-line' }, inp, btns));
    const ro = () => h('input', { type: 'text', readOnly: true, class: 'mono', spellcheck: false });
    const cur = ro(), prev = ro(), neu = h('input', { type: 'text', class: 'mono', spellcheck: false, autocomplete: 'off' });
    const copyBtn = inp => { const b = h('button', { class: 'btn small', type: 'button', text: '复制', onclick: () => { if (inp.value) copyLater(Promise.resolve(inp.value), b); } }); return b; };
    const p = G2 ? G2.loadPrefs() : { length: 20, digits: true, symbols: true };
    const len = h('input', { type: 'range', min: G2 ? G2.MIN_LENGTH : 8, max: 40, value: Math.min(p.length, 40) }), lenV = h('b', { text: String(len.value) });
    const dg = h('input', { type: 'checkbox', checked: p.digits }), sy = h('input', { type: 'checkbox', checked: p.symbols });
    const opts = () => ({ length: len.value, digits: dg.checked, symbols: sy.checked });
    let saved = '';
    const note = h('div', { class: 'muted small' }), prevWrap = field('上一个密码', prev, copyBtn(prev)); prevWrap.hidden = true;
    const saveBtn = h('button', { class: 'btn small primary', type: 'button', text: '保存并复制新密码' });
    const infoBtn = h('button', { class: 'btn small', type: 'button', text: '复制信息', hidden: true, onclick: () => copyShareInfo(row, infoBtn) });
    const refresh = () => { const dirtyPw = neu.value.trim() && neu.value.trim() !== saved; saveBtn.disabled = !dirtyPw; saveBtn.textContent = dirtyPw || !saved ? '保存并复制新密码' : '已保存 ✓'; };
    const gen = () => { lenV.textContent = len.value; if (G2) { neu.value = G2.generate(opts()); G2.savePrefs(opts()); } refresh(); };
    len.addEventListener('input', gen); dg.addEventListener('change', gen); sy.addEventListener('change', gen); neu.addEventListener('input', refresh);
    saveBtn.addEventListener('click', () => {
      const v = neu.value.trim(); if (!v) return;
      saveBtn.disabled = true;
      const done = api('POST', '/admin/accounts/' + a.id + '/password', { password: v }).then(r => r.json().catch(() => ({}))).then(d => {
        if (!d.ok) throw new Error(d.error || '保存失败');
        if (saved) { prev.value = saved; prevWrap.hidden = false; }
        saved = v; cur.value = v; a.hasPassword = true; infoBtn.hidden = false; refresh();
        return v;
      });
      copyLater(done, null);   // 存好的同时放进剪贴板（复制不了会弹提示）
      done.then(() => { note.textContent = '✓ 已保存，新密码已复制。去官网改好后，回来点「复制信息」发给对方'; },
        e => { note.textContent = '✗ ' + (e.message || '保存失败'); refresh(); });
    });
    gen();
    note.textContent = '正在读取当前密码…';
    api('POST', '/admin/accounts/' + a.id + '/password/reveal', {}).then(r => r.json().catch(() => ({}))).then(d => {
      if (!d.ok) throw new Error(d.error || '读取失败');
      cur.value = saved = d.password || ''; prev.value = d.previous || ''; prevWrap.hidden = !d.previous;
      note.textContent = ''; refresh();
    }).catch(e => { note.textContent = '读取当前密码失败：' + e.message; });
    dialog('改密码 · ' + a.name, [
      field('当前保存的密码', cur, copyBtn(cur)), prevWrap,
      field('新密码', neu, h('button', { class: 'btn small', type: 'button', text: '重新生成', onclick: gen }), copyBtn(neu)),
      h('div', { class: 'pw-opts' }, h('label', null, '长度 ', len, ' ', lenV), h('label', null, dg, ' 数字'), h('label', null, sy, ' 符号')),
      h('div', { class: 'rowbtns' }, saveBtn, infoBtn), note,
      h('div', { class: 'muted small', text: '① 点「保存并复制新密码」→ ② 去官网把密码改成它（已在剪贴板里）→ ③ 回来点「复制信息」发给对方。' })],
      [{ text: '关闭', cls: 'primary', run: () => {
        if (neu.value.trim() && neu.value.trim() !== saved && cur.value !== neu.value.trim()) return confirm('新密码还没有保存，确定关闭？') ? undefined : false;
      } }]).then(() => render());
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
  // 有效期：「1228」→「12/28」
  function fmtExpiry(v) { v = String(v || '').trim(); const d = v.replace(/\D/g, ''); return v.includes('/') || d.length < 3 ? v : d.slice(0, 2) + '/' + d.slice(2, 6); }
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
    const expiry = h('input', { type: 'text', placeholder: 'MM/YY', inputMode: 'numeric', autocomplete: 'off' });
    const cvc = h('input', { type: 'text', placeholder: 'CVC', inputMode: 'numeric', autocomplete: 'off' });
    const ok = await dialog('给 ' + issuer.name + ' 新增卡号', [h('label', { class: 'field' }, '卡号', number),
      h('div', { class: 'field-row' }, h('label', { class: 'field' }, '有效期', expiry), h('label', { class: 'field' }, 'CVC', cvc)),
      h('label', { class: 'field' }, '备注', note), h('div', { class: 'muted', text: '卡号、有效期和 CVC 都加密保存在服务器上。' })],
      [{ text: '取消' }, { text: '新增', cls: 'primary', value: true, run: () => { if (!number.value.trim() && !note.value.trim()) { number.focus(); return false; } } }]);
    if (!ok) return null;
    const c = { id: 'c_' + uid(), issuerId: issuer.id, number: number.value.trim(), note: note.value.trim(), expiry: fmtExpiry(expiry.value), cvc: cvc.value.trim() };
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


  // ---------- 账号密码 ----------
  // 密码不放在页面里，点的时候才向服务器取。Safari 只允许在点击的那一刻发起复制，所以把“还没取回来的密码”直接交给剪贴板
  async function copyLater(textPromise, el) {
    try {
      if (window.ClipboardItem && navigator.clipboard && navigator.clipboard.write) {
        try { await navigator.clipboard.write([new ClipboardItem({ 'text/plain': textPromise.then(t => new Blob([t], { type: 'text/plain' })) })]); }
        catch (e) { if (e && e.name === 'NotAllowedError') throw e; await navigator.clipboard.writeText(await textPromise); }
      } else await navigator.clipboard.writeText(await textPromise);
      if (el) flash(el, '已复制');
    } catch (e) {
      try { await textPromise; } catch (e2) { return alertBox(e2.message); }
      alertBox('浏览器不让自动复制，请在“改密码”里查看。');
    }
  }
  function revealPw(a) {
    return api('POST', '/admin/accounts/' + a.id + '/password/reveal', {}).then(r => r.json().catch(() => ({}))).then(d => {
      if (!d.ok) throw new Error(d.error || '取不到密码，请刷新页面');
      return d.password || '';
    });
  }
  function editPw(anchor, a) {
    const inp = h('input', { type: 'text', placeholder: '账号密码', autocomplete: 'off', spellcheck: false });
    const err = h('div', { class: 'neg' });
    const save = async () => {
      const v = inp.value.trim();
      if (!v) { err.textContent = '密码不能为空（要删掉密码请到验证码账号的“编辑”里清空）'; return; }
      const r = await api('POST', '/admin/accounts/' + a.id + '/password', { password: v }), d = await r.json().catch(() => ({}));
      if (!r.ok || !d.ok) { err.textContent = d.error || '保存失败'; return; }
      a.hasPassword = true; closePop(); render(); setStatus('账号密码已保存');
    };
    const form = h('div', { class: 'form pwform' },
      h('label', { class: 'field' }, a.name + ' 的账号密码', inp),
      h('div', { class: 'muted small', text: '和验证码账号里的是同一个密码，改了两边一起变；原来的密码会留作“上一个密码”。' }),
      err,
      h('div', { class: 'rowbtns' }, h('button', { class: 'btn small', type: 'button', text: '取消', onclick: closePop }), h('button', { class: 'btn small primary', type: 'button', text: '保存', onclick: save })));
    inp.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); save(); } });
    openPop(anchor, form);
    inp.focus();
    if (a.hasPassword) revealPw(a).then(p => { if (!inp.value) { inp.value = p; inp.select(); } }).catch(e => { err.textContent = e.message; });
  }
  function pwField(row, editable) {
    const a = row.totpId > 0 ? totpById(row.totpId) : null;
    // 没关联验证码账号：密码记在账本这一行里（加密保存）；以后关联上了会交给验证码账号
    if (!a) return copyField(row, 'password', { mask: true, ro: !editable, label: '账号密码', placeholder: '账号密码' });
    const wrap = h('div', { class: 'cf' });
    if (!a.hasPassword) {
      setKids(wrap, editable ? h('button', { class: 'cf-val empty', type: 'button', title: '还没保存密码，点一下设置', onclick: () => editPw(wrap, a) }, '设置密码') : h('span', { class: 'ro faint', text: '—' }));
      return wrap;
    }
    const val = h('button', { class: 'cf-val mono', type: 'button', title: '点一下复制账号密码（和验证码账号里的是同一个）',
      onclick: () => copyLater(revealPw(a).then(p => { if (!p) throw new Error('这个账号还没保存密码'); return p; }), val) }, '••••••••');
    setKids(wrap, val, editable ? h('button', { class: 'cf-edit', type: 'button', title: '修改账号密码', 'aria-label': '修改账号密码', onclick: () => editPw(wrap, a) }, icon('pen', 13)) : null);
    return wrap;
  }

  // ---------- 账号表 ----------
  function rowMenu(btn, sheet, rows, row) {
    const items = [];
    if (sheet.grouped) {
      items.push({ label: '移动到分组' });
      sheetGroups(sheet).filter(g => g.id !== row.group).forEach(g => items.push({ text: g.name, run: () => moveRow(row, g.id) }));
      if (groupOf(sheet, row.group)) items.push({ text: '未分组', run: () => moveRow(row, '') });
      items.push('-');
    }
    if (row.totpId > 0 && totpById(row.totpId)) {
      items.push({ text: '复制分享信息（账号、密码、验证码链接）', run: () => copyShareInfo(row) });
      items.push({ text: '编辑验证码账号（密钥、密码、分享链接）', run: () => leave('/admin/accounts/' + row.totpId + '/edit') });
      items.push({ text: '取消关联验证码', run: () => { skipTotp(row.totpId, true); row.totpId = -1; touch(); render(); } });
    } else items.push({ text: '关联验证码账号…', run: () => linkTotpMenu(btn, row) });
    items.push('-');
    items.push({ text: '续费日期顺延一个月', run: () => { if (!row.renew) return alertBox('这一行还没填续费日期。'); row.renew = shiftMonth(row.renew, 1); touch(); render(); } });
    if (sheet.mode === 'members' && row.members.some(m => !m.paid)) items.push({ text: '全部标记已收', run: () => { row.members.forEach(m => { m.paid = true; }); touch(); render(); } });
    items.push({ text: row.stopped ? '恢复使用' : '标记为停止（下月不再带入）', run: () => { row.stopped = !row.stopped; touch(); render(); } });
    items.push('-');
    items.push({ text: '删除这一行', danger: true, run: async () => {
      if (await confirmBox('删除账号', '删除 “' + (row.account || '未填账号') + '” 这一行？\n只影响 ' + ymLabel(view.month) + '，其他月份不变。', '删除', true)) {
        rows.splice(rows.indexOf(row), 1);
        if (row.totpId > 0 && view.month === latestMonth()) skipTotp(row.totpId, true);
        touch(); render();
      }
    } });
    menu(btn, items);
  }
  function resaleRowEl(sheet, rows, row, editable) {
    const per = h('td', { class: 'calc r muted' }), inc = h('td', { class: 'calc r' }), cost = h('td', { class: 'calc r' }), pill = h('span', { class: 'profit' });
    updaters.push(() => {
      const i = income(sheet, row), c = rowCost(sheet, row);
      per.textContent = money(num(row.unitPrice) - num(row.unitCost)); inc.textContent = money(i); cost.textContent = money(c); profitText(pill, i - c);
    });
    const countInp = cell(row, 'count', { num: true, ro: !editable, label: '本月数量', cls: 'stepnum' });
    const step = d => { row.count = Math.max(0, num(row.count) + d); countInp.value = row.count ? plain(row.count) : ''; touch(); recalc(); };
    const tr = h('tr', { class: row.stopped ? 'stopped' : '' },
      h('td', null, cell(row, 'account', { ro: !editable, placeholder: '项目名，如 Plus代充', cls: 'strong', label: '项目' })),
      cardCells(row, editable),
      h('td', null, cell(row, 'unitPrice', { num: true, ro: !editable, label: '售价' })),
      h('td', null, cell(row, 'unitCost', { num: true, ro: !editable, label: '成本/份' })),
      per,
      h('td', null, h('div', { class: 'stepper' },
        editable ? h('button', { class: 'step', type: 'button', 'aria-label': '减一单', title: '减一单', onclick: () => step(-1) }, '−') : null,
        countInp,
        editable ? h('button', { class: 'step plus', type: 'button', 'aria-label': '加一单', title: '加一单', onclick: () => step(1) }, '+') : null)),
      inc, cost, h('td', { class: 'calc r' }, pill),
      h('td', null, cell(row, 'note', { ro: !editable, label: '备注' })),
      h('td', null, editable ? h('button', { class: 'btn ghost icon', type: 'button', 'aria-label': '更多操作', onclick: e => rowMenu(e.currentTarget, sheet, rows, row) }, icon('more')) : null));
    tr.dataset.row = row.id;
    searchRows.push({ tr, row });
    return tr;
  }
  // AdsPower 成员的登录设备数量（只读；数据由 /api/app/adspower/devices 提供，按账号邮箱对上）
  let ADS = null, adsLoading = null;
  const adsUpdatedText = () => ADS && ADS.updated ? '更新于 ' + new Date(ADS.updated * 1000).toLocaleString('zh-CN', { hour12: false }) : '';
  function showDevices(row) {
    const key = String(row.account || '').trim().toLowerCase(), list = (ADS && ADS.devices && ADS.devices[key]) || [];
    const body = list.length ? h('ul', { class: 'dev-list' }, list.map(d => h('li', null,
      h('div', { class: 'dev-top' }, h('b', { text: d.name || '未知设备' }), h('span', { class: 'dev-time', text: d.time || '' })),
      h('div', { class: 'dev-sub', text: [d.ip, d.region].filter(Boolean).join(' · ') }))))
      : h('p', { class: 'muted', text: ADS && ADS.counts && ADS.counts[key] === 0 ? '没有登录中的设备。' : '这次只记了数量，没有设备明细。' });
    dialog('登录设备 · ' + (row.account || ''), [body, h('p', { class: 'dev-note', text: adsUpdatedText() + (adsUpdatedText() ? ' · ' : '') + '数据来自 AdsPower「团队管理 → 登录活动」' })], [{ text: '关闭', cls: 'primary' }]);
  }
  function devChip(row) {
    const el = h('button', { class: 'dev-chip', type: 'button', hidden: true, onclick: () => showDevices(row) });
    const paint = () => {
      const n = ADS && ADS.counts ? ADS.counts[String(row.account || '').trim().toLowerCase()] : undefined;
      el.hidden = n === undefined;
      if (n === undefined) return;
      el.textContent = n + ' 台';
      el.className = 'dev-chip' + (n === 0 ? ' zero' : '');
      el.title = 'AdsPower 登录设备 ' + n + ' 台，点一下看明细' + (ADS.updated ? ' · ' + adsUpdatedText() : '');
    };
    if (ADS) paint();
    else {
      if (!adsLoading) adsLoading = fetch('/api/app/adspower/devices', { credentials: 'same-origin' }).then(r => r.ok ? r.json() : null).catch(() => null).then(d => { ADS = d || { counts: {} }; });
      adsLoading.then(paint);
    }
    return el;
  }
  function accountsRowEl(sheet, rows, row, editable) {
    const acct = copyField(row, 'account', { plain: true, ro: !editable, placeholder: '账号', label: '账号', title: '点一下复制账号',
      onChange: () => { if (row.totpId > 0 && totpById(row.totpId)) pushName(row); else if (linkTotp()) { touch(); render(); } } });
    const tr = h('tr', { class: row.stopped ? 'stopped' : '' },
      h('td', null, h('div', { class: 'acct' }, acct, devChip(row), totpChip(row))),
      h('td', null, pwField(row, editable)),
      h('td', null, shareCell(row)),
      h('td', null, cell(row, 'note', { ro: !editable, label: '备注', placeholder: '备注' })),
      h('td', null, acctActions(row)),
      h('td', null, editable ? h('button', { class: 'btn ghost icon', type: 'button', 'aria-label': '更多操作', onclick: e => rowMenu(e.currentTarget, sheet, rows, row) }, icon('more')) : null));
    tr.dataset.row = row.id;
    searchRows.push({ tr, row });
    return tr;
  }
  function rowEl(sheet, rows, row, editable, live) {
    if (sheet.mode === 'resale') return resaleRowEl(sheet, rows, row, editable);
    if (sheet.mode === 'accounts') return accountsRowEl(sheet, rows, row, editable);
    const inc = h('td', { class: 'calc r' }), pill = h('span', { class: 'profit' }), prof = h('td', { class: 'calc r' }, pill);
    updaters.push(() => { const v = income(sheet, row); inc.textContent = money(v); profitText(pill, v - rowCost(sheet, row)); });
    const acct = copyField(row, 'account', { plain: true, ro: !editable, placeholder: '账号', label: '账号',
      title: row.stopped ? '已停止，下个月不会带过去 · 点一下复制账号' : '点一下复制账号',
      onChange: () => { if (row.totpId > 0 && totpById(row.totpId)) pushName(row); else if (linkTotp()) { touch(); render(); } } });
    const tr = h('tr', { class: row.stopped ? 'stopped' : '' },
      h('td', null, h('div', { class: 'acct' }, acct, totpChip(row))),
      h('td', null, pwField(row, editable)),
      h('td', null, dateCell(row, 'renew', !editable, 3, live && !row.stopped)),
      cardCells(row, editable),
      sheet.mode === 'members' ? membersCell(row, editable) : [
        h('td', null, cell(row, 'unitPrice', { num: true, ro: !editable, label: '单价', placeholder: '0' })),
        h('td', null, cell(row, 'count', { num: true, ro: !editable, label: '人数', placeholder: '0', cls: 'center' }))],
      inc,
      h('td', null, cell(row, 'cost', { num: true, ro: !editable, label: '续费成本' })),
      prof,
      h('td', null, cell(row, 'note', { ro: !editable, label: '备注' })),
      h('td', null, editable ? h('button', { class: 'btn ghost icon', type: 'button', 'aria-label': '更多操作', onclick: e => rowMenu(e.currentTarget, sheet, rows, row) }, icon('more')) : null));
    tr.dataset.row = row.id;
    searchRows.push({ tr, row });
    return tr;
  }
  // 表头「账号」一栏右边的验证码倒计时，正好在验证码那一列上方
  function codeTimerHead(label) {
    const bar = h('i'), sec = h('span', { class: 'sec' });
    const el = h('span', { class: 'code-timer', hidden: true, 'aria-label': '验证码刷新倒计时' }, h('span', { class: 'track' }, bar), sec);
    codes.timers.push({ el, bar, sec, prev: 0 });
    return h('div', { class: 'acct-head' }, h('span', { text: label }), el);
  }
  function tableEl(sheet, rows, list, editable, live) {
    if (sheet.mode === 'resale') {
      const rc = [['项目', 170], ['付款渠道', 132], ['卡号', 112], ['售价', 86, 1], ['成本/份', 86, 1], ['每单利润', 88, 1], ['本月数量', 130], ['收费', 88, 1], ['成本', 88, 1], ['利润', 98, 1], ['备注', 0], ['', 40]];
      return h('div', { class: 'scroll' }, h('table', { class: 'grid resale', style: 'min-width:1150px;table-layout:fixed' },
        h('colgroup', null, rc.map(c => h('col', { style: c[1] ? 'width:' + c[1] + 'px' : '' }))),
        h('thead', null, h('tr', null, rc.map(c => h('th', { class: c[2] ? 'r' : '', text: c[0] })))),
        h('tbody', null, list.map(r => tinted(rowEl(sheet, rows, r, editable, live), rowTint(sheet, r))))));
    }
    if (sheet.mode === 'accounts') {
      // 和验证码账号页一样：账号、密码、分享链接、操作按钮；宽屏时多出来的空间给备注
      const ac = [['账号', 390], ['账号密码', 140], ['分享链接', 230], ['备注', 0], ['操作', 330], ['', 42]];
      return h('div', { class: 'scroll' }, h('table', { class: 'grid accounts', style: 'min-width:1280px;table-layout:fixed' },
        h('colgroup', null, ac.map(c => h('col', { style: c[1] ? 'width:' + c[1] + 'px' : '' }))),
        h('thead', null, h('tr', null, ac.map((c, i) => h('th', null, i === 0 && list.some(r => r.totpId > 0 && totpById(r.totpId)) ? codeTimerHead(c[0]) : c[0])))),
        h('tbody', null, list.map(r => tinted(rowEl(sheet, rows, r, editable, live), rowTint(sheet, r))))));
    }
    const cols = sheet.mode === 'members'
      ? [['账号', 240], ['账号密码', 112]].concat([['续费日期', 134], ['续费卡信息', 126], ['卡号', 118], ['收费情况（每人）', 0], ['收费', 76, 1], ['续费成本', 78, 1], ['利润', 92, 1], ['备注', 88], ['', 42]])
      : [['账号', 220], ['账号密码', 112], ['续费日期', 136], ['续费卡信息', 136], ['卡号', 116], ['单价', 84, 1], ['人数', 70, 2], ['收费', 92, 1], ['续费成本', 92, 1], ['利润', 100, 1], ['备注', 0], ['', 42]];
    return h('div', { class: 'scroll' }, h('table', { class: 'grid' + (sheet.mode === 'members' ? '' : ' unitsheet'), style: (sheet.mode === 'members' ? 'min-width:1290px' : 'min-width:1290px') + ';table-layout:fixed' },
      h('colgroup', null, cols.map(c => h('col', { style: c[1] ? 'width:' + c[1] + 'px' : '' }))),
      h('thead', null, h('tr', null, cols.map((c, i) => h('th', { class: c[2] === 1 ? 'r' : c[2] === 2 ? 'c' : '' }, i === 0 && list.some(r => r.totpId > 0 && totpById(r.totpId)) ? codeTimerHead(c[0]) : c[0])))),
      h('tbody', null, list.map(r => tinted(rowEl(sheet, rows, r, editable, live), rowTint(sheet, r))))));
  }
  function section(sheet, rows, group, filter, editable, live) {
    const list = rows.filter(filter), key = sheet.id + ':' + (group ? group.id || 'loose' : 'all');
    const closed = !!collapsed[key];
    const sum = h('div', { class: 'group-sum' });
    if (sheet.mode !== 'accounts') updaters.push(() => {
      const s = stats(sheet, rows.filter(filter));
      setKids(sum, h('span', null, '收费 ', h('b', { text: money(s.income) })), h('span', null, '成本 ', h('b', { text: money(s.cost) })), profitPill(s.profit));
    });
    else sum.textContent = '点账号复制账号，点验证码复制验证码';
    const count = h('span', { class: 'pill' });
    updaters.push(() => { const s = stats(sheet, rows.filter(filter)); count.textContent = sheet.mode === 'accounts' ? list.length + ' 个账号' : sheet.mode === 'resale' ? list.length + ' 个项目 · ' + plain(s.heads) + ' 单' : list.length + ' 个账号 · ' + plain(s.heads) + ' 人'; });
    const toggle = () => { collapsed[key] = !closed; try { localStorage.setItem('hezu-collapsed', JSON.stringify(collapsed)); } catch (e) { /* 忽略 */ } render(); };
    const title = h('button', { class: 'group-title', type: 'button', 'aria-expanded': String(!closed), title: closed ? '展开' : '收起', onclick: toggle },
      h('span', { class: 'chev' }, icon('chev', 16)), group ? h('span', { class: 'dot', style: 'background:' + group.color }) : null, h('span', { text: group ? group.name : sheet.name }));
    const addBtn = editable && !closed ? h('button', { class: 'btn ghost small', type: 'button', onclick: () => addAccountDialog({ sheet, group }) }, icon('plus', 15), sheet.mode === 'resale' ? '添加项目' : '添加账号') : null;
    return h('div', { class: 'group' + (closed ? ' closed' : '') },
      h('div', { class: 'group-head' }, title, count, sum),
      closed ? null : list.length ? tableEl(sheet, rows, list, editable, live) : h('div', { class: 'empty', text: sheet.mode === 'resale' ? (editable ? '还没有代充项目，点下面的“添加项目”。' : '这个月没有代充项目。') : editable ? '还没有账号，点下面的“添加账号”。' : '这个月没有账号。' }),
      addBtn ? h('div', { class: 'group-foot' }, addBtn) : null);
  }
  function tiles(getStats, resale) {
    const v = [0, 1, 2, 3].map(() => h('div', { class: 'v' })), s3 = h('div', { class: 's' }), s2 = h('div', { class: 's' });
    const t = (resale ? ['收费', '成本', '利润', '本月单数'] : ['收费', '续费成本', '利润', '在用账号']).map((k, i) => h('div', { class: 'tile' }, h('div', { class: 'k', text: k }), v[i], i === 3 ? s3 : i === 2 ? s2 : null));
    updaters.push(() => {
      const s = getStats();
      v[0].textContent = money(s.income); v[1].textContent = money(s.cost); v[2].textContent = money(s.profit); v[3].textContent = resale ? plain(s.heads) : String(s.n);
      t[2].className = 'tile' + (s.profit > 0 ? ' good' : s.profit < 0 ? ' bad' : '');
      s2.textContent = s.income ? '利润率 ' + Math.round(s.profit / s.income * 100) + '%' : ' ';
      s3.textContent = resale ? s.n + ' 个项目' : plain(s.heads) + ' 人付费';
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
    const out = sheet.mode === 'accounts' ? [] : [tiles(() => stats(sheet, rows), sheet.mode === 'resale')];
    const q = h('input', { type: 'search', placeholder: '搜索账号、备注、卡种', value: view.q, 'aria-label': '搜索' });
    q.addEventListener('input', () => { view.q = q.value; applySearch(); });
    const bar = h('div', { class: 'toolbar' }, h('label', { class: 'search' }, icon('search', 15), q));
    if (sheet.grouped) bar.append(groupChips(rows, sheet));
    bar.append(h('span', { class: 'spacer' }), h('button', { class: 'btn ghost small', type: 'button', text: '表设置', onclick: e => sheetMenu(e.currentTarget, sheet) }));
    out.push(bar);
    if (sheet.grouped) {
      const ids = shownIds(sheet), f = view.gfilter;
      visibleGroups(sheet).forEach(g => { if (f === null || f === g.id) out.push(section(sheet, rows, g, r => r.group === g.id, editable, live)); });
      if ((f === null || f === '__loose') && rows.some(r => !ids.has(r.group))) out.push(section(sheet, rows, LOOSE, r => !ids.has(r.group), editable, live));
      if (!sheetGroups(sheet).length) out.push(h('div', { class: 'empty', text: '还没有分组，点上面的“管理分组”新建。' }));
    } else out.push(section(sheet, rows, null, () => true, editable, live));
    return out;
  }

  // ---------- 添加账号 ----------
  // 账号可以从验证码账号里直接选（关联上），也可以手动填；手动填的可以勾选「同时添加到账号验证码」。
  // 手动填、不同步的就是这张表自己的账号：记成 totpId = -1，以后也不会按名字自动关联到别处。
  function acctPicker(sheet) {
    const name = h('input', { type: 'text', placeholder: '输入账号，或在下面的验证码账号里点一个', autocomplete: 'off', spellcheck: false });
    const list = h('div', { class: 'picklist acct-pick' });
    const chosen = h('div', { class: 'acct-chosen', hidden: true });
    const here = new Set(((S.months[view.month] || { rows: {} }).rows[sheet.id] || []).map(r => r.totpId).filter(x => x > 0));
    let picked = null, changed = () => {};
    const draw = () => {
      const k = normName(name.value);
      const items = picked ? [] : A.filter(a => !k || normName(a.name + ' ' + (a.group || '')).includes(k)).slice(0, 40);
      setKids(list, h('div', { class: 'label', text: items.length ? '从账号验证码里选（' + items.length + (items.length === 40 ? '+' : '') + '）' : (k ? '验证码账号里没有，按手动添加' : '') }),
        items.map(a => h('button', { class: 'item', type: 'button', onclick: () => pick(a) }, a.name,
          h('span', { class: 'faint', text: '  ' + (a.group || '未分组') + (here.has(a.id) ? ' · 已在这张表' : '') }))));
      list.hidden = !!picked || (!items.length && !k);
    };
    const unpick = () => { picked = null; name.readOnly = false; chosen.hidden = true; draw(); changed(); name.focus(); };
    const pick = a => {
      picked = a; name.value = a.name; name.readOnly = true;
      setKids(chosen, icon('link', 14), h('span', { text: '关联验证码账号（' + (a.group || '未分组') + '）' }),
        h('button', { class: 'btn ghost xs', type: 'button', text: '改成手动填', onclick: unpick }));
      chosen.hidden = false; draw(); changed();
    };
    name.addEventListener('input', draw); draw();
    return { name, list, chosen, picked: () => picked, onChange: f => { changed = f; } };
  }
  // 「同时添加到账号验证码」：要填 TOTP 密钥（验证码账号就是存两步验证的）
  function syncPart(groupChoice, defName) {
    const box = h('input', { type: 'checkbox' });
    const secret = h('input', { type: 'text', placeholder: '网站「两步验证」给的密钥（Base32）', autocomplete: 'off', spellcheck: false });
    const grp = groupChoice ? h('select', null, h('option', { value: '', text: '未分组' }), G.map(g => h('option', { value: g.name, text: g.name, selected: g.name === defName }))) : null;
    const fields = h('div', { class: 'form sync-fields', hidden: true },
      h('label', { class: 'field' }, 'TOTP 密钥', secret), grp ? h('label', { class: 'field' }, '验证码分组', grp) : null);
    const row = h('label', { class: 'check' }, box, '同时添加到账号验证码');
    box.addEventListener('change', () => { fields.hidden = !box.checked; if (box.checked) secret.focus(); });
    return { row, fields, on: () => box.checked, secret, grp, show: v => { row.hidden = !v; fields.hidden = !v || !box.checked; } };
  }
  // 建验证码账号（重名先确认）。返回新账号 id；失败返回 0 并把原因写进 err
  async function createTotp(body, err) {
    let r = await api('POST', '/accounts', body), d = await r.json().catch(() => ({}));
    if (r.status === 409 && d.duplicate) {
      if (!await confirmBox('已有同名的验证码账号', d.error + '\n确认不是重复添加的话，可以继续。', '仍然添加')) return 0;
      r = await api('POST', '/accounts', Object.assign({ confirmDuplicate: true }, body)); d = await r.json().catch(() => ({}));
    }
    if (!r.ok || !d.ok) { err.textContent = d.error || '添加失败，请重试。'; return 0; }
    useContext(d); skipTotp(d.id, false);
    return d.id;
  }

  // AI 合租（分组表）和「只存账号」表的添加账号
  async function addAccountDialog(preset) {
    preset = preset || {};
    const sheet = preset.sheet;
    if (!sheet) return;
    if (!sheet.grouped && sheet.mode !== 'accounts') return addRowDialog(sheet);
    const owned = sheet.mode === 'accounts' && sheet.totpGroup ? sheet.totpGroup : '';
    const ac = acctPicker(sheet);
    const groupSel = h('select', null, h('option', { value: '', text: '未分组' }), visibleGroups(sheet).map(g => h('option', { value: g.id, text: g.name, selected: !!preset.group && g.id === preset.group.id })));
    const password = h('input', { type: 'text', placeholder: '可不填；加密保存', autocomplete: 'off', spellcheck: false });
    const fPw = h('label', { class: 'field' }, '账号登录密码', password);
    // 新建验证码账号时放进哪个验证码分组（和这张表的分组无关）；默认挑同名的
    const sp = syncPart(!owned, preset.group ? preset.group.name : '');
    const hint = h('div', { class: 'muted small' });
    const err = h('div', { class: 'neg' });
    const refresh = () => { const a = ac.picked(); sp.show(!a); fPw.hidden = !!a; };
    ac.onChange(refresh); groupSel.addEventListener('change', refresh); refresh();
    let made = null;
    const submit = async () => {
      err.textContent = '';
      const n = ac.name.value.trim(), a = ac.picked(), g = groupOf(sheet, groupSel.value), pw = password.value.trim();
      if (!n) { ac.name.focus(); return false; }
      let totpId = -1;
      if (a) {
        totpId = a.id; skipTotp(a.id, false);
      } else if (sp.on()) {
        const sec = sp.secret.value.trim();
        if (!sec) { err.textContent = '同时添加到账号验证码需要填 TOTP 密钥；没有两步验证的账号就别勾这个。'; sp.secret.focus(); return false; }
        totpId = await createTotp({ name: n, secret: sec, password: pw, group: owned || (sp.grp ? sp.grp.value : '') }, err);
        if (!totpId) return false;
      }
      made = fixRow({ account: n, group: sheet.grouped && g ? g.id : '', totpId, password: totpId > 0 ? '' : pw });
      S.months[view.month].rows[sheet.id].push(made);
      view.tab = sheet.id; view.q = '';
      pullNames(); touch();
    };
    const ok = await dialog('添加账号到 ' + sheet.name, [
      h('label', { class: 'field' }, '账号', ac.name), ac.chosen, ac.list,
      sheet.grouped ? h('label', { class: 'field' }, '分组', groupSel) : (owned ? h('div', { class: 'muted small', text: '验证码分组：' + owned }) : null),
      hint, fPw, sp.row, sp.fields,
      h('div', { class: 'muted', text: sheet.mode === 'accounts' ? '选了验证码账号的，分享链接、改密码等都用它的。' : '续费日期、续费卡、收费等在表格里接着填。' }),
      err,
    ], [{ text: '取消' }, { text: '添加', cls: 'primary', value: true, run: submit }]);
    if (!ok) return;
    render(); pollCodes();
    if (made) { const inp = document.querySelectorAll('[data-row="' + made.id + '"] input')[0]; if (inp) inp.scrollIntoView({ block: 'center' }); }
  }

  // ---------- 分组筛选条（和验证码列表一样：点一下筛选，拖动调整顺序） ----------
  let dragGroup = null;
  function groupChips(rows, sheet) {
    const ids = shownIds(sheet), counts = {}; let loose = 0;
    rows.forEach(r => { if (ids.has(r.group)) counts[r.group] = (counts[r.group] || 0) + 1; else loose++; });
    if (view.gfilter === '__loose' ? !loose : view.gfilter !== null && !ids.has(view.gfilter)) view.gfilter = null;
    const box = h('div', { class: 'chipset gchips' });
    const chip = (label, val, n, g) => {
      const b = h('button', { class: 'fchip' + (view.gfilter === val ? ' on' : ''), type: 'button', onclick: () => { view.gfilter = val; render(); } },
        g ? h('span', { class: 'gdot', style: 'background:' + g.color }) : null, label + ' ' + n);
      if (g) dragChip(b, g, sheet);
      return b;
    };
    box.append(chip('全部', null, rows.length));
    visibleGroups(sheet).forEach(g => box.append(chip(g.name, g.id, counts[g.id] || 0, g)));
    if (loose) box.append(chip('未分组', '__loose', loose));
    box.append(h('button', { class: 'btn ghost small', type: 'button', text: sheetGroups(sheet).length ? '管理分组' : '＋ 新建分组', onclick: e => groupsMenu(e.currentTarget, sheet) }));
    return box;
  }
  function dragChip(b, g, sheet) {
    b.draggable = true;
    b.title = '点一下筛选，拖动可以调整分组顺序';
    const clear = () => document.querySelectorAll('.gchips .drop-before, .gchips .drop-after').forEach(x => x.classList.remove('drop-before', 'drop-after'));
    b.addEventListener('dragstart', e => { dragGroup = g.id; b.classList.add('dragging'); e.dataTransfer.effectAllowed = 'move'; e.dataTransfer.setData('text/plain', g.id); });
    b.addEventListener('dragend', () => { dragGroup = null; b.classList.remove('dragging'); clear(); });
    b.addEventListener('dragover', e => {
      if (!dragGroup || dragGroup === g.id) return;
      e.preventDefault();
      const r = b.getBoundingClientRect(), after = e.clientX > r.left + r.width / 2;
      b.classList.toggle('drop-after', after); b.classList.toggle('drop-before', !after);
    });
    b.addEventListener('dragleave', () => b.classList.remove('drop-before', 'drop-after'));
    b.addEventListener('drop', e => {
      e.preventDefault();
      const after = b.classList.contains('drop-after'), from = dragGroup;
      clear();
      if (from && from !== g.id) moveGroup(sheet, from, g.id, after);
    });
  }
  function moveGroup(sheet, fromId, toId, after) {
    const all = sheetGroups(sheet), list = all.filter(x => x.id !== fromId), moved = all.find(x => x.id === fromId);
    if (!moved) return;
    list.splice(list.findIndex(x => x.id === toId) + (after ? 1 : 0), 0, moved);
    sheet.groups = list; touch(); render(); setStatus('分组顺序已保存');
  }

  // Netflix / Spotify / iCloud 这类普通表：只填这张表自己的列，续费卡和收费在表格里接着填
  async function addRowDialog(sheet) {
    if (sheet.mode === 'resale') return addResaleDialog(sheet);
    const unit = sheet.mode === 'unit';
    const ac = acctPicker(sheet), name = ac.name;
    const sp = syncPart(true), err = h('div', { class: 'neg' });
    ac.onChange(() => sp.show(!ac.picked()));
    const renew = h('input', { type: 'date' });
    const price = h('input', { type: 'text', inputMode: 'decimal', placeholder: '每人每月', autocomplete: 'off' });
    const count = h('input', { type: 'text', inputMode: 'numeric', placeholder: '几个人', autocomplete: 'off' });
    const cost = h('input', { type: 'text', inputMode: 'decimal', placeholder: '0', autocomplete: 'off' });
    const note = h('input', { type: 'text', placeholder: '可不填', autocomplete: 'off' });
    let made = null;
    const ok = await dialog('添加账号到 ' + sheet.name, [
      h('label', { class: 'field' }, '账号', name), ac.chosen, ac.list,
      h('label', { class: 'field' }, '续费日期', renew),
      unit ? h('div', { class: 'field-row' }, h('label', { class: 'field' }, '单价', price), h('label', { class: 'field' }, '人数', count)) : null,
      h('label', { class: 'field' }, '续费成本', cost),
      h('label', { class: 'field' }, '备注', note),
      sp.row, sp.fields,
      h('div', { class: 'muted', text: unit ? '续费卡在表格里选；收费 = 单价 × 人数，自动算。' : '续费卡和每人收费在表格里接着填。' }),
      err,
    ], [{ text: '取消' }, { text: '添加', cls: 'primary', value: true, run: async () => {
      err.textContent = '';
      const n = name.value.trim(), a = ac.picked();
      if (!n) { name.focus(); return false; }
      let totpId = -1;
      if (a) { totpId = a.id; skipTotp(a.id, false); }
      else if (sp.on()) {
        const sec = sp.secret.value.trim();
        if (!sec) { err.textContent = '同时添加到账号验证码需要填 TOTP 密钥；没有两步验证的账号就别勾这个。'; sp.secret.focus(); return false; }
        totpId = await createTotp({ name: n, secret: sec, password: '', group: sp.grp.value }, err);
        if (!totpId) return false;
      }
      made = fixRow({ account: n, renew: renew.value, unitPrice: num(price.value), count: num(count.value), cost: num(cost.value), note: note.value.trim(), totpId });
    } }]);
    if (!ok || !made) return;
    S.months[view.month].rows[sheet.id].push(made);
    pullNames(); touch(); render(); pollCodes();
    const inp = document.querySelector('[data-row="' + made.id + '"] input'); if (inp) inp.scrollIntoView({ block: 'center' });
  }

  async function addResaleDialog(sheet) {
    const name = h('input', { type: 'text', placeholder: '如 Plus代充、Pro20x', autocomplete: 'off' });
    const price = h('input', { type: 'text', inputMode: 'decimal', placeholder: '卖给客户的价格', autocomplete: 'off' });
    const cost = h('input', { type: 'text', inputMode: 'decimal', placeholder: '每单的进货成本', autocomplete: 'off' });
    const count = h('input', { type: 'text', inputMode: 'numeric', placeholder: '0', autocomplete: 'off' });
    const note = h('input', { type: 'text', placeholder: '可不填', autocomplete: 'off' });
    let made = null;
    const ok = await dialog('添加代充项目到 ' + sheet.name, [
      h('label', { class: 'field' }, '项目名', name),
      h('div', { class: 'field-row' }, h('label', { class: 'field' }, '售价', price), h('label', { class: 'field' }, '成本/份', cost)),
      h('label', { class: 'field' }, '本月已经代充几单', count),
      h('label', { class: 'field' }, '备注', note),
      h('div', { class: 'muted', text: '售价和成本以后每个月自动带过去，只需要在表格里点 + 记单数。付款渠道在表格里选。' }),
    ], [{ text: '取消' }, { text: '添加', cls: 'primary', value: true, run: () => {
      if (!name.value.trim()) { name.focus(); return false; }
      made = fixRow({ account: name.value.trim(), unitPrice: num(price.value), unitCost: num(cost.value), count: num(count.value), note: note.value.trim() });
    } }]);
    if (!ok || !made) return;
    S.months[view.month].rows[sheet.id].push(made);
    touch(); render();
  }

  // ---------- 分组 / 表 管理 ----------
  // 分组表（AI 合租）的分组是它自己的：新建、改名、换颜色、排序、删除都只影响这张表，不动账号验证码的分组
  function createGroup(sheet, name, color) {
    name = String(name || '').trim().slice(0, 40);
    if (!name) return null;
    const list = sheetGroups(sheet), same = list.find(g => normName(g.name) === normName(name));
    if (same) return same;
    color = color || GROUP_COLORS[list.length % GROUP_COLORS.length];
    const g = { id: 'g_' + uid(), name, color, text: textOn(color) };
    sheet.groups = list.concat([g]);
    touch();
    return g;
  }
  async function newGroupDialog(sheet) {
    const name = h('input', { type: 'text', placeholder: '如 GPT Plus' });
    const ok = await dialog('新建分组', [h('label', { class: 'field' }, '分组名称', name), h('div', { class: 'muted', text: '只是「' + sheet.name + '」里的分组，账号验证码的分组不受影响。' })],
      [{ text: '取消' }, { text: '新建', cls: 'primary', value: true, run: () => { if (!name.value.trim()) { name.focus(); return false; } } }]);
    return ok ? createGroup(sheet, name.value) : null;
  }
  function groupsMenu(btn, sheet) {
    menu(btn, [
      { text: '新建分组…', run: () => newGroupDialog(sheet).then(g => { if (g) render(); }) },
      { text: '改名、换颜色、删除分组…', run: () => manageGroupsDialog(sheet) },
    ]);
  }
  // 一次改好这张表的全部分组：名字、颜色、删除（顺序在分组条上拖）
  async function manageGroupsDialog(sheet) {
    const M = S.months[view.month], rows = M ? (M.rows[sheet.id] || []) : [];
    const items = sheetGroups(sheet).map(g => ({ g, name: h('input', { type: 'text', value: g.name, maxLength: 40 }), color: h('input', { type: 'color', value: /^#[0-9a-f]{6}$/i.test(g.color) ? g.color : '#64748b' }), del: false }));
    const list = h('div', { class: 'grp-edit' });
    const draw = () => setKids(list, items.length ? items.map(it => {
      const n = rows.filter(r => r.group === it.g.id).length;
      return h('div', { class: 'grp-row' + (it.del ? ' del' : '') }, it.color, it.name,
        h('span', { class: 'faint small', text: n ? n + ' 个账号' : '' }),
        h('button', { class: 'btn ghost xs', type: 'button', text: it.del ? '撤销' : '删除', onclick: () => { it.del = !it.del; draw(); } }));
    }) : h('div', { class: 'muted', text: '还没有分组。' }));
    draw();
    const err = h('div', { class: 'neg' });
    const ok = await dialog(sheet.name + ' 的分组', [list,
      h('div', { class: 'muted small', text: '只改「' + sheet.name + '」自己的分组，账号验证码的分组和账号都不动。删掉的分组里的账号会放到「未分组」，账号不会删。顺序在分组条上直接拖。' }), err],
      [{ text: '取消' }, { text: '保存', cls: 'primary', value: true, run: () => {
        const keep = items.filter(it => !it.del), names = keep.map(it => normName(it.name.value));
        if (names.some(n => !n)) { err.textContent = '分组名称不能是空的。'; return false; }
        if (new Set(names).size !== names.length) { err.textContent = '有两个分组同名了。'; return false; }
      } }]);
    if (!ok) return;
    const gone = new Set(items.filter(it => it.del).map(it => it.g.id));
    sheet.groups = items.filter(it => !it.del).map(it => ({ id: it.g.id, name: it.name.value.trim(), color: it.color.value, text: textOn(it.color.value) }));
    // 进行中的月份：删掉的分组里的账号放到未分组（存档月份保持原样，显示时自然算未分组）
    for (const ym in S.months) if (!S.months[ym].archived) for (const r of S.months[ym].rows[sheet.id] || []) if (gone.has(r.group)) r.group = '';
    if (gone.has(view.gfilter)) view.gfilter = null;
    touch(); render(); setStatus('分组已保存');
  }
  async function sheetForm(sheet) {
    const name = h('input', { type: 'text', value: sheet ? sheet.name : '', placeholder: '如 YouTube' });
    const mode = h('select', null,
      h('option', { value: 'unit', text: '单价 × 人数（每人价格一样）', selected: !sheet || sheet.mode === 'unit' }),
      h('option', { value: 'members', text: '每人单独填金额', selected: !!sheet && sheet.mode === 'members' }),
      h('option', { value: 'resale', text: '代充（售价、成本固定，只填每月数量）', selected: !!sheet && sheet.mode === 'resale' }),
      h('option', { value: 'accounts', text: '只存账号（账号、密码、验证码，不算钱）', selected: !!sheet && sheet.mode === 'accounts' }));
    const grp = h('select', null, h('option', { value: '', text: '不认领' }), G.map(g => h('option', { value: g.name, text: g.name, selected: !!sheet && sheet.totpGroup === g.name })));
    const fGrp = h('label', { class: 'field', hidden: mode.value !== 'accounts' }, '这个验证码分组的账号放到这张表', grp);
    mode.addEventListener('change', () => { fGrp.hidden = mode.value !== 'accounts'; });
    const ok = await dialog(sheet ? '修改表' : '新建表', [h('label', { class: 'field' }, '名称', name), h('label', { class: 'field' }, '收费方式', mode), fGrp],
      [{ text: '取消' }, { text: sheet ? '保存' : '新建', cls: 'primary', value: true, run: () => { if (!name.value.trim()) { name.focus(); return false; } } }]);
    if (!ok) return;
    if (sheet) { convertSheetMode(sheet, mode.value); sheet.name = name.value.trim(); sheet.mode = mode.value; }
    else { sheet = { id: 's_' + uid(), name: name.value.trim(), mode: mode.value }; S.sheets.push(sheet); view.tab = sheet.id; }
    if (mode.value === 'accounts' && grp.value) sheet.totpGroup = grp.value; else delete sheet.totpGroup;
    normalize(); touch(); render();
  }
  // 换收费方式时把还在进行的月份的数据换算过去（存档月份保持原样）
  function convertSheetMode(sheet, to) {
    const from = sheet.mode;
    if (from === to) return;
    for (const ym in S.months) {
      if (S.months[ym].archived) continue;
      for (const r of S.months[ym].rows[sheet.id] || []) {
        if (to === 'resale') {
          if (from === 'members') { r.unitPrice = r.members.length ? r.members.reduce((a, m) => a + num(m.amount), 0) / r.members.length : 0; r.count = r.members.length; }
          r.unitCost = num(r.count) ? round2(num(r.cost) / num(r.count)) : num(r.cost);
        } else if (from === 'resale') {
          r.cost = round2(num(r.unitCost) * num(r.count));
        }
      }
    }
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
  // 这张卡（或这一类卡）这个月被哪些账号用着：鼠标停上去显示，也可以点一下（手机上用）
  function accountsUsing(filter) {
    const out = [];
    for (const sh of S.sheets) for (const r of S.months[view.month].rows[sh.id] || []) {
      if (filter.cardId ? r.cardId !== filter.cardId : r.issuerId !== filter.issuerId) continue;
      const g = sh.grouped ? groupOf(sh, r.group) : null;
      out.push({ sheet: sh, row: r, where: sh.grouped ? sh.name + ' · ' + (g ? g.name : '未分组') : sh.name, color: g ? g.color : null, cost: rowCost(sh, r) });
    }
    return out;
  }
  let usageTimer = null;
  function usageLink(el, filter, title) {
    const list = accountsUsing(filter);
    if (!list.length) return el;
    el.classList.add('has-usage');
    el.tabIndex = 0;
    el.setAttribute('role', 'button');
    const show = () => {
      clearTimeout(usageTimer);
      if (pop && pop.anchor === el) return;
      const box = openPop(el, [
        h('div', { class: 'label', text: title + ' · ' + ymLabel(view.month) + ' · ' + list.length + ' 个账号' }),
        h('div', { class: 'usage-head' }, h('span', { text: '种类' }), h('span', { text: '账号' }), h('span', { text: '价格' })),
        list.map(x => h('button', { class: 'item usage-item', type: 'button', title: '去这个账号', onclick: () => {
          closePop(); view.tab = x.sheet.id; view.q = x.row.account; view.gfilter = null; render();
          const tr = document.querySelector('[data-row="' + x.row.id + '"]'); if (tr) tr.scrollIntoView({ block: 'center' });
        } },
          h('span', { class: 'usage-where' }, x.color ? h('span', { class: 'gdot', style: 'background:' + x.color }) : null, x.where),
          h('span', { class: 'usage-acct', text: x.row.account || '未填账号' }),
          h('span', { class: 'usage-cost', text: money(x.cost) }))),
      ]);
      box.classList.add('usage-pop');
      pop.anchor = el;
      box.addEventListener('mouseenter', () => clearTimeout(usageTimer));
      box.addEventListener('mouseleave', hide);
    };
    const hide = () => { clearTimeout(usageTimer); usageTimer = setTimeout(() => { if (pop && pop.anchor === el) closePop(); }, 250); };
    el.addEventListener('mouseenter', () => { clearTimeout(usageTimer); usageTimer = setTimeout(show, 150); });
    el.addEventListener('mouseleave', hide);
    el.addEventListener('click', e => { e.stopPropagation(); if (pop && pop.anchor === el) closePop(); else show(); });
    el.addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); show(); } });
    return el;
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
      return tinted(h('div', { class: 'group' },
        h('div', { class: 'issuer-head' },
          cell(it, 'name', { cls: 'name', placeholder: '卡信息名称', label: '卡信息名称' }),
          cell(it, 'country', { cls: 'country', placeholder: '国家 / 地区', list: 'countries', label: '国家或地区' }),
          h('button', { class: 'btn ghost icon', type: 'button', 'aria-label': '更多操作', onclick: e => menu(e.currentTarget, [{ text: '删除这个卡种', danger: true, run: async () => {
            const used = usageCount(r => r.issuerId === it.id);
            if (await confirmBox('删除卡种', '删除 “' + it.name + '” 和它下面的 ' + own.length + ' 个卡号？' + (used ? '\n有 ' + used + ' 个账号（含历史月份）选了它，删除后这些账号的续费卡会变成空。' : ''), '删除', true)) {
              S.issuers.splice(S.issuers.indexOf(it), 1); normalize(); touch(); render();
            }
          } }]) }, icon('more'))),
        h('div', { class: 'issuer-meta' }, h('span', null, ymLabel(view.month) + ' 续费 ', h('b', { text: money(st.cost) })), usageLink(h('span', { class: 'usage' }, h('b', { text: String(st.n) }), ' 个账号在用'), { issuerId: it.id }, it.name), h('span', null, h('b', { text: String(own.length) }), ' 个卡号')),
        own.length ? h('div', { class: 'cardhead', 'aria-hidden': 'true' }, h('span', { text: '卡号' }), h('span', { text: '有效期' }), h('span', { text: 'CVC' }), h('span', { text: '备注' }), h('span', { class: 'r', text: '本月' }), h('span')) : null,
        own.map(c => {
          const s = cs.byCard[c.id] || { n: 0, cost: 0 };
          return h('div', { class: 'cardrow' },
            copyField(c, 'number', { mono: true, label: '卡号', placeholder: '卡号', title: '点一下复制完整卡号', display: maskNumber }),
            copyField(c, 'expiry', { mono: true, label: '有效期', placeholder: 'MM/YY', onChange: () => { c.expiry = fmtExpiry(c.expiry); touch(); } }),
            copyField(c, 'cvc', { mono: true, label: ' CVC', placeholder: 'CVC', title: '点一下复制 CVC', display: () => '•••' }),
            cell(c, 'note', { placeholder: '备注', label: '卡备注' }),
            h('div', { class: 'spend' + (s.cost || s.n ? '' : ' zero') }, money(s.cost), usageLink(h('small', { class: 'usage', text: s.n + ' 个账号' }), { cardId: c.id }, it.name + ' ' + cardLabel(c))),
            h('button', { class: 'btn ghost icon', type: 'button', 'aria-label': '删除卡号', title: '删除卡号', onclick: async () => {
              const used = usageCount(r => r.cardId === c.id);
              if (await confirmBox('删除卡号', '删除 ' + it.name + ' 的 ' + cardLabel(c) + '？' + (used ? '\n有 ' + used + ' 个账号（含历史月份）选了它，删除后会变成“不指定卡号”。' : ''), '删除', true)) {
                S.cards.splice(S.cards.indexOf(c), 1); normalize(); touch(); render();
              }
            } }, h('span', { text: '✕', 'aria-hidden': 'true' })));
        }),
        h('div', { class: 'group-foot' }, h('button', { class: 'btn ghost small', type: 'button', onclick: async () => { if (await newCardDialog(it)) render(); } }, icon('plus', 15), '添加卡号'))), tintKey(it.id));
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
  const TAG_COLORS = ['teal', 'blue', 'amber', 'purple', 'green', 'pink', 'red', 'gray'];
  // 浅色打底（和手机 App 同一套颜色）：本身没颜色的东西按名字固定取一个
  const TINTS = ['#0d9488', '#ea580c', '#2563eb', '#db2777', '#7c3aed', '#16a34a', '#d97706', '#0891b2', '#dc2626', '#4f46e5', '#c026d3', '#65a30d'];
  function tintKey(s) { let n = 5381; for (const ch of String(s)) n = (n * 33 + ch.codePointAt(0)) >>> 0; return TINTS[n % TINTS.length]; }
  function tinted(el, color) { if (el && color) { el.classList.add('tinted'); el.style.setProperty('--tint', color); } return el; }
  const SHEET_TINTS = ['#7c3aed', '#dc2626', '#4f46e5', '#c026d3', '#0891b2', '#65a30d', '#d97706', '#e11d48', '#0f766e', '#475569'];
  function rowTint(sheet, r) {
    if (r.stopped) return '#8891a5';
    const g = sheet.grouped ? groupOf(sheet, r.group) : null;
    if (g) return g.color;
    if (sheet.grouped) return LOOSE.color;
    return SHEET_TINTS[Math.max(0, S.sheets.indexOf(sheet)) % SHEET_TINTS.length];
  }
  function vpsTint(v, d) { return d != null && d < 0 ? '#d32f4c' : d != null && d <= VPS_DUE_DAYS ? '#ad5f03' : tintKey(v.provider || v.host || ''); }
  function hashColor(text) { let n = 0; for (const ch of String(text)) n = (n * 31 + ch.codePointAt(0)) >>> 0; return 'c-' + TAG_COLORS[n % TAG_COLORS.length]; }
  // 价格列是自由文字（如 "$28.18  40cad"），汇总时取第一个数字，按美元算
  function priceUsd(t) { const m = String(t || '').replace(/,/g, '').match(/\d+(?:\.\d+)?/); return m ? +m[0] : null; }
  let RATES = null, ratesAt = 0;
  async function ensureRates() {
    if (RATES || Date.now() - ratesAt < 60000) return;
    ratesAt = Date.now();
    try { const r = await fetch(API + '/rates', { credentials: 'same-origin' }), d = await r.json(); if (r.ok && d.ok) RATES = d; } catch (e) { /* 取不到就只显示美元 */ }
    if (RATES) recalc();
  }
  const usdToCny = usd => RATES && RATES.rates.CNY ? usd * RATES.rates.CNY : null;
  function flash(el, text) {
    if (el.dataset.flash) return;
    el.dataset.flash = el.textContent; el.textContent = text; el.classList.add('ok');
    setTimeout(() => { el.textContent = el.dataset.flash; delete el.dataset.flash; el.classList.remove('ok'); }, 900);
  }
  async function copyQuiet(text, el) {
    try { await navigator.clipboard.writeText(text); if (el) flash(el, '已复制'); else setStatus('已复制'); }
    catch (e) { alertBox('浏览器不让自动复制，请手动复制：\n' + text); }
  }
  // 点一下复制的格子：IP、密码。旁边的小笔用来修改；空着的时候直接是输入框
  function copyField(v, key, opts) {
    const wrap = h('div', { class: 'cf' });
    const editor = () => {
      const inp = cell(v, key, { cls: (opts.mono ? 'mono ' : '') + (opts.plain ? 'strong' : ''), placeholder: opts.placeholder, label: opts.label });
      inp.addEventListener('blur', () => { if (v[key]) setTimeout(draw, 0); });
      if (opts.onChange) inp.addEventListener('change', opts.onChange);
      return inp;
    };
    function draw(edit) {
      if (!opts.ro && (edit || !v[key])) {
        const inp = editor(); setKids(wrap, inp);
        if (edit) { inp.focus(); inp.select(); }
        return;
      }
      if (!v[key]) return setKids(wrap, h('span', { class: 'ro faint', text: '—' }));
      const val = h('button', { class: 'cf-val' + (opts.mono ? ' mono' : '') + (opts.plain ? ' plain' : ''), type: 'button', title: opts.title || '点一下复制' + opts.label, onclick: () => copyQuiet(v[key], val) },
        opts.display ? opts.display(v[key]) : opts.mask ? '••••••••' : v[key]);
      setKids(wrap, val, opts.ro ? null : h('button', { class: 'cf-edit', type: 'button', title: '修改' + opts.label, 'aria-label': '修改' + opts.label, onclick: () => draw(true) }, icon('pen', 13)));
    }
    draw(false);
    return wrap;
  }
  const fixUrl = u => { u = String(u || '').trim(); return !u || /^https?:\/\//i.test(u) ? u : 'https://' + u; };
  function siteField(v) {
    const wrap = h('div', { class: 'cf' }), fix = fixUrl;
    function draw(edit) {
      if (edit || !v.site) {
        const inp = cell(v, 'site', { placeholder: '官网网址', label: '官网网址' });
        const done = () => { const f = fix(v.site); if (f !== v.site) { v.site = f; touch(); } if (v.site) setTimeout(() => draw(false), 0); };
        inp.addEventListener('change', done); inp.addEventListener('blur', done);
        setKids(wrap, inp);
        if (edit) { inp.focus(); inp.select(); }
        return;
      }
      setKids(wrap, h('a', { class: 'site-link', href: fix(v.site), target: '_blank', rel: 'noopener noreferrer', title: '打开 ' + fix(v.site) }, h('span', { text: '官网' }), icon('link', 13)),
        h('button', { class: 'cf-edit', type: 'button', title: '修改官网网址', 'aria-label': '修改官网网址', onclick: () => draw(true) }, icon('pen', 13)));
    }
    draw(false);
    return wrap;
  }
  function editTag(anchor, v, i, done) {
    const t = v.tags[i];
    const name = h('input', { type: 'text', value: t.name, placeholder: '项目名' });
    const url = h('input', { type: 'text', value: t.url, placeholder: 'https://… 可不填', spellcheck: false, autocomplete: 'off' });
    let removed = false;
    const form = h('div', { class: 'form tagform' },
      h('label', { class: 'field' }, '项目名', name),
      h('label', { class: 'field' }, '网址（点标签时打开）', url),
      h('div', { class: 'rowbtns' },
        h('button', { class: 'btn small danger', type: 'button', text: '删除', onclick: () => { removed = true; closePop(); } }),
        h('button', { class: 'btn small primary', type: 'button', text: '完成', onclick: closePop })));
    form.addEventListener('keydown', e => { if (e.key === 'Enter') closePop(); });
    openPop(anchor, form, () => {
      if (removed || !name.value.trim()) v.tags.splice(i, 1);
      else { t.name = name.value.trim(); t.url = fixUrl(url.value); }
      touch(); done();
    });
    (t.url ? name : url).focus();
  }
  function tagsField(v) {
    const box = h('div', { class: 'vtags' });
    function draw(focus) {
      const add = h('input', { class: 'vtag-add', type: 'text', placeholder: v.tags.length ? '+' : '+ 项目', 'aria-label': '添加部署项目', autocomplete: 'off', title: '输入项目名回车；可以一次填多个，用逗号隔开' });
      const commit = refocus => {
        const fresh = splitTags(add.value).filter(n => !v.tags.some(t => t.name === n)); add.value = '';
        if (!fresh.length) return;
        v.tags.push(...fresh.map(n => ({ name: n, url: '' }))); touch(); draw(refocus);
      };
      add.addEventListener('keydown', e => {
        if (e.key === 'Enter') { e.preventDefault(); commit(true); }
        else if (e.key === 'Backspace' && !add.value && v.tags.length) { v.tags.pop(); touch(); draw(true); }
      });
      add.addEventListener('blur', () => commit(false));
      setKids(box, v.tags.map((t, i) => {
        const chip = h('span', { class: 'vtag ' + hashColor(t.name) + (t.url ? ' linked' : '') });
        const edit = h('button', { class: 'vtag-edit', type: 'button', title: '改名字或网址', 'aria-label': '修改 ' + t.name, onclick: () => editTag(chip, v, i, () => draw()) }, icon('pen', 11));
        chip.append(t.url
          ? h('a', { class: 'vtag-name', href: fixUrl(t.url), target: '_blank', rel: 'noopener noreferrer', title: '打开 ' + fixUrl(t.url) }, h('span', { text: t.name }), icon('link', 11))
          : h('button', { class: 'vtag-name', type: 'button', title: '还没有网址，点一下填', onclick: () => editTag(chip, v, i, () => draw()) }, h('span', { text: t.name })),
          edit);
        return chip;
      }), add);
      if (focus) add.focus();
    }
    draw(false);
    return box;
  }
  // ---------- Komari 实时监控（服务器转发 Komari 的公开接口，这里每 10 秒刷一次，只更新这一块）----------
  let KOM = null, komTimer = 0, komBadges = [], komSeen = 0;
  const komEl = h('div', { class: 'group kom' });
  const fmtBytes = b => { b = +b || 0; const u = ['B', 'KB', 'MB', 'GB', 'TB']; let i = 0; while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; } return (b >= 100 || i === 0 ? b.toFixed(0) : b.toFixed(b >= 10 ? 1 : 2)) + ' ' + u[i]; };
  const fmtSpeed = b => fmtBytes(b) + '/s';
  const pct = (a, b) => b > 0 ? Math.min(100, a / b * 100) : 0;
  const cycleText = c => ({ 30: '月', 31: '月', 90: '季', 92: '季', 180: '半年', 183: '半年', 365: '年', 730: '两年', 1095: '三年' })[c] || (c > 0 ? c + ' 天' : '');
  const komNorm = t => String(t || '').toLowerCase().replace(/[^a-z0-9一-鿿]/g, '');
  function komNodeOf(v) {
    if (!KOM || !KOM.nodes) return null;
    if (v.komari) return KOM.nodes.find(n => n.uuid === v.komari) || null;
    const a = komNorm(v.host); if (a.length < 3) return null;
    const hits = KOM.nodes.filter(n => { const b = komNorm(n.name); return b.length >= 3 && (a === b || a.includes(b) || b.includes(a)); });
    return hits.length === 1 ? hits[0] : null;   // 名字对不上或者对上好几台，就等手动关联
  }
  async function komLoad() {
    clearTimeout(komTimer);
    if (view.tab !== 'vps' || document.hidden) { komTimer = setTimeout(komLoad, 10000); return; }
    try { const r = await fetch('/api/app/komari', { credentials: 'same-origin' }), d = await r.json(); KOM = r.ok ? d : { error: d.error || ('HTTP ' + r.status), nodes: KOM && KOM.nodes }; }
    catch (e) { KOM = { error: '连不上服务器', nodes: KOM && KOM.nodes }; }
    if (!komEl.contains(document.activeElement)) komPaint();   // 正在填地址时不重画，免得把输入清掉
    // 后台同步改了账本（Komari 那边加 / 删 / 改名了机器）：没有正在编辑的改动就拉一下新版本
    if (KOM.sync && KOM.sync.last && KOM.sync.last !== komSeen) { if (komSeen && !dirty && !saving) pullLatest('komari'); komSeen = KOM.sync.last; }
    if (KOM.configured !== false) komTimer = setTimeout(komLoad, 10000);
  }
  function meter(label, p, main, sub, warnAt) {
    return h('div', { class: 'km' }, h('div', { class: 'km-top' }, h('span', { text: label }), h('b', { text: main })),
      h('div', { class: 'km-bar' }, h('i', { class: p >= (warnAt || 90) ? 'bad' : p >= (warnAt || 90) - 20 ? 'warn' : '', style: 'width:' + p.toFixed(1) + '%' })),
      h('div', { class: 'km-sub', text: sub }));
  }
  function komCard(n) {
    const up = n.online ? Math.floor(n.uptime / 86400) : null, exp = n.expiredAt && !n.expiredAt.startsWith('0001') ? daysUntil(n.expiredAt.slice(0, 10)) : null;
    const linked = S.vps.find(v => komNodeOf(v) === n);
    const ping = n.ping;
    return tinted(h('div', { class: 'kcard' + (n.online ? '' : ' off') },
      h('div', { class: 'kc-head' }, h('span', { class: 'kdot' + (n.online ? ' on' : '') }), h('b', { class: 'kc-name', text: n.name, title: n.os + (n.cpuName ? '\n' + n.cpuName + ' · ' + n.cores + ' 核' : '') }), h('span', { text: n.region })),
      h('div', { class: 'kc-meta' }, h('span', { text: n.online ? '在线 ' + up + ' 天' : '离线' }),
        exp != null ? h('span', { class: exp < 0 ? 'neg' : exp <= VPS_DUE_DAYS ? 'warn' : '', text: relText(exp) + '到期' }) : null,
        n.price ? h('span', { class: 'kc-price', text: n.currency + n.price + (cycleText(n.billingCycle) ? ' / ' + cycleText(n.billingCycle) : '') }) : null),
      h('div', { class: 'kc-grid' },
        meter('CPU', n.cpu, n.cpu.toFixed(1) + '%', n.load.map(x => x.toFixed(2)).join(', ')),
        meter('内存', pct(n.ram, n.ramTotal), pct(n.ram, n.ramTotal).toFixed(1) + '%', fmtBytes(n.ram) + ' / ' + fmtBytes(n.ramTotal)),
        meter('硬盘', pct(n.disk, n.diskTotal), pct(n.disk, n.diskTotal).toFixed(1) + '%', fmtBytes(n.disk) + ' / ' + fmtBytes(n.diskTotal)),
        n.trafficLimit ? meter('流量', pct(n.trafficUsed, n.trafficLimit), pct(n.trafficUsed, n.trafficLimit).toFixed(1) + '%', fmtBytes(n.trafficUsed) + ' / ' + fmtBytes(n.trafficLimit), 80)
          : meter('流量', 0, fmtBytes(n.totalUp + n.totalDown), '没设上限')),
      h('div', { class: 'kc-foot' },
        h('span', { class: 'kup', text: '↑ ' + fmtSpeed(n.netOut) }), h('span', { class: 'kdown', text: '↓ ' + fmtSpeed(n.netIn) }),
        h('span', { class: 'faint', text: '共 ↑' + fmtBytes(n.totalUp) + ' ↓' + fmtBytes(n.totalDown) })),
      ping ? h('div', { class: 'kc-foot' }, h('span', { text: (ping.name || '延迟') + ' ' + Math.round(ping.latest) + ' ms' }),
        h('span', { class: ping.loss >= 10 ? 'neg' : ping.loss >= 3 ? 'warn' : 'pos', text: '丢包 ' + ping.loss.toFixed(1) + '%' })) : null,
      linked ? h('div', { class: 'kc-link', text: '对应表格里的 ' + (linked.host || '未命名') }) : null),
      !n.online ? '#8891a5' : n.cpu >= 90 || (ping && ping.loss >= 10) ? '#d32f4c' : '#0d9488');
  }
  function komSetup() {
    const inp = h('input', { class: 'inp', type: 'url', placeholder: 'https://k.example.com', value: (KOM && KOM.url) || '' });
    const msg = h('span', { class: 'faint' });
    const save = async () => {
      msg.textContent = '正在连接…';
      const r = await fetch('/api/app/komari/config', { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json', 'X-CSRFToken': CSRF }, body: JSON.stringify({ url: inp.value }) }), d = await r.json().catch(() => ({}));
      if (r.ok && d.ok) { KOM = d; komPaint(); render(); } else msg.textContent = d.error || ('保存失败（HTTP ' + r.status + '）');
    };
    return h('div', { class: 'kom-setup' }, h('span', { text: 'Komari 网址' }), inp, h('button', { class: 'btn small primary', type: 'button', text: '连接', onclick: save }), msg,
      h('div', { class: 'faint', text: '只用 Komari 首页公开的数据，不需要账号密码。' }));
  }
  function komSyncEl() {
    const y = KOM && KOM.sync;
    if (!y || !y.enabled) return h('span', { class: 'faint', text: '双向同步未开启' });
    const ago = y.last ? Math.max(0, Math.round((Date.now() / 1000 - y.last) / 60)) : null;
    const tip = (y.log || []).map(x => new Date(x.t * 1000).toLocaleString('zh-CN', { hour12: false }) + '  ' + x.a).join('\n') || '还没有同步过任何变化';
    const btn = h('button', { class: 'btn ghost small', type: 'button', text: '立即同步', title: tip, onclick: async () => {
      btn.disabled = true; btn.textContent = '同步中…';
      try {
        const r = await fetch('/api/app/komari/sync', { method: 'POST', credentials: 'same-origin', headers: { 'X-CSRFToken': CSRF } }), d = await r.json().catch(() => ({}));
        if (!r.ok || !d.ok) await alertBox(d.error || ('同步失败（HTTP ' + r.status + '）'));
        else { if (d.actions.length) await alertBox('同步完成：\n' + d.actions.join('\n')); await pullLatest('komari'); }
      } finally { komLoad(); }
    } });
    return h('span', { class: 'ksync', title: tip }, h('span', { class: y.error ? 'neg' : 'pos', text: y.error ? '⚠ ' + y.error : '⇄ 双向同步' + (ago == null ? '' : ' · ' + (ago < 1 ? '刚刚' : ago + ' 分钟前')) }), btn);
  }
  async function copyInstall(v) {
    const n = komNodeOf(v);
    if (!n) return alertBox('这台还没关联 Komari 节点。');
    const r = await fetch('/api/app/komari/install/' + encodeURIComponent(n.uuid), { credentials: 'same-origin' }), d = await r.json().catch(() => ({}));
    if (!r.ok || !d.ok) return alertBox(d.error || ('取不到安装命令（HTTP ' + r.status + '）'));
    await copyQuiet(d.command);
    alertBox('已复制 ' + (v.host || '这台') + ' 的探针安装命令。\n用 root 登录这台 VPS，粘贴运行，装好后几秒内就有监控数据。');
  }
  function komPaint() {
    for (const b of komBadges) {
      const n = komNodeOf(b.v);
      setKids(b.el, n ? [h('span', { class: 'kdot' + (n.online ? ' on' : '') }), n.online ? 'CPU ' + n.cpu.toFixed(0) + '% · 内存 ' + pct(n.ram, n.ramTotal).toFixed(0) + '%' : '离线'] : []);
      b.el.title = n ? 'Komari：' + n.name + (n.ping ? ' · 延迟 ' + Math.round(n.ping.latest) + ' ms' : '') : '';
    }
    if (!KOM) { setKids(komEl, h('div', { class: 'empty', text: '正在读取 Komari 监控…' })); return; }
    if (KOM.configured === false) {
      setKids(komEl, h('div', { class: 'group-head' }, h('span', { class: 'group-title', text: '实时监控' }), h('span', { class: 'group-sum', text: '接入 Komari 探针后，这里显示每台机器的 CPU、内存、硬盘、流量、网速和延迟' })), komSetup());
      return;
    }
    const nodes = KOM.nodes || [], on = nodes.filter(n => n.online);
    const speedUp = nodes.reduce((a, n) => a + n.netOut, 0), speedDown = nodes.reduce((a, n) => a + n.netIn, 0);
    const total = nodes.reduce((a, n) => a + n.totalUp + n.totalDown, 0);
    let showSetup = false;
    const head = h('div', { class: 'group-head' }, h('span', { class: 'group-title', text: '实时监控' }),
      h('span', { class: 'pill ' + (on.length === nodes.length ? 'pos' : 'warn'), text: on.length + ' / ' + nodes.length + ' 在线' }),
      h('span', { class: 'group-sum' }, h('span', null, '网速 ', h('b', { class: 'kup', text: '↑ ' + fmtSpeed(speedUp) }), ' ', h('b', { class: 'kdown', text: '↓ ' + fmtSpeed(speedDown) })),
        h('span', null, '累计流量 ', h('b', { text: fmtBytes(total) })),
        KOM.error ? h('span', { class: 'neg', text: KOM.error }) : null,
        komSyncEl(),
        h('a', { href: KOM.url, target: '_blank', rel: 'noopener', text: '打开 Komari' }),
        h('button', { class: 'btn ghost small', type: 'button', text: '换地址', onclick: () => { showSetup = !showSetup; setup.hidden = !showSetup; } })));
    const setup = komSetup(); setup.hidden = true;
    setKids(komEl, head, setup, nodes.length ? h('div', { class: 'kgrid' }, nodes.map(komCard)) : h('div', { class: 'empty', text: 'Komari 里还没有公开的节点。' }));
  }
  document.addEventListener('visibilitychange', () => { if (!document.hidden && view.tab === 'vps') komLoad(); });
  function komLinkMenu(btn, v) {
    const nodes = (KOM && KOM.nodes) || [];
    if (!nodes.length) return alertBox(KOM && KOM.configured === false ? '先在上面「实时监控」里填 Komari 网址。' : 'Komari 里还没有节点。');
    menu(btn, [{ text: (v.komari ? '' : '✓ ') + '按名字自动匹配', run: () => { delete v.komari; touch(); render(); } }, '-']
      .concat(nodes.map(n => ({ text: (v.komari === n.uuid ? '✓ ' : '') + n.name + (n.region ? ' ' + n.region : ''), run: () => { v.komari = n.uuid; touch(); render(); } }))));
  }
  function vpsMenu(btn, v) {
    const addr = v.ip ? v.ip + (v.port ? ':' + v.port : '') : '';
    menu(btn, [
      addr ? { text: '复制 ' + addr, run: () => copyQuiet(addr) } : null,
      v.ip ? { text: '复制 SSH 登录命令', run: () => copyQuiet('ssh ' + (v.port ? '-p ' + v.port + ' ' : '') + 'root@' + v.ip) } : null,
      v.site ? { text: '打开官网', run: () => window.open(fixUrl(v.site), '_blank', 'noopener') } : null,
      { text: '关联 Komari 监控节点…', run: () => komLinkMenu(btn, v) },
      komNodeOf(v) ? { text: '复制 Komari 探针安装命令', run: () => copyInstall(v) } : null,
      '-',
      { text: '删除这台 VPS', danger: true, run: async () => {
        if (await confirmBox('删除 VPS', '删除 “' + (v.host || '未命名') + '”？', '删除', true)) { S.vps.splice(S.vps.indexOf(v), 1); touch(); render(); }
      } },
    ]);
  }
  function vpsTiles() {
    const v = [0, 1, 2, 3].map(() => h('div', { class: 'v' })), sub = [0, 1, 2, 3].map(() => h('div', { class: 's' }));
    const t = ['主机', '价格合计（美元）', '折合人民币', '下一台到期'].map((k, i) => h('div', { class: 'tile' + (i === 3 ? ' tile-next' : '') }, h('div', { class: 'k', text: k }), v[i], sub[i]));
    updaters.push(() => {
      const priced = S.vps.map(x => priceUsd(x.price)).filter(x => x != null), usd = priced.reduce((a, b) => a + b, 0), cny = usdToCny(usd);
      v[0].textContent = S.vps.length + ' 台'; sub[0].textContent = priced.length + ' 台填了价格';
      v[1].textContent = '$' + usd.toLocaleString('zh-CN', { maximumFractionDigits: 2 }); sub[1].textContent = '价格列的第一个数字，按美元算';
      v[2].textContent = cny == null ? '—' : money(cny);
      sub[2].textContent = RATES ? '1 USD = ' + RATES.rates.CNY.toFixed(4) + ' CNY · 每天更新' : '正在取汇率…';
      const next = S.vps.map(x => ({ x, d: daysUntil(x.renew) })).filter(o => o.d != null).sort((a, b) => a.d - b.d)[0];
      v[3].textContent = next ? (next.x.host || '未命名') : '—';
      const soon = S.vps.filter(x => { const d = daysUntil(x.renew); return d != null && d <= VPS_DUE_DAYS; }).length;
      sub[3].textContent = next ? dateText(next.x.renew) + ' · ' + relText(next.d) + (soon ? ' · 30 天内共 ' + soon + ' 台' : '') : '还没有填续费日期';
      t[3].classList.toggle('warn', !!next && next.d >= 0 && next.d <= VPS_DUE_DAYS);
      t[3].classList.toggle('bad', !!next && next.d < 0);
    });
    return h('div', { class: 'tiles' }, t);
  }
  function vpsView() {
    ensureRates();
    komBadges = [];
    if (!KOM) komLoad(); else if (KOM.configured !== false) { clearTimeout(komTimer); komTimer = setTimeout(komLoad, 10000); }
    const cols = [['主机', 0], ['官网', 86], ['IP', 152], ['端口', 64], ['密码', 104], ['部署', 236], ['流量及重置', 88], ['续费', 150], ['价格', 112], ['邮箱', 196], ['登录密码', 104], ['', 40]];
    const body = S.vps.map(v => {
      const cnyEl = h('div', { class: 'cny' });
      updaters.push(() => { const u = priceUsd(v.price), c = u == null ? null : usdToCny(u); cnyEl.textContent = c == null ? '' : '≈ ' + money(c); });
      const d = daysUntil(v.renew);
      return tinted(h('tr', { class: d == null ? '' : d < 0 ? 'overdue' : d <= VPS_DUE_DAYS ? 'due-soon' : '' },
        h('td', null, h('div', { class: 'hostcell' }, h('span', { class: 'avatar ' + hashColor(v.host || '?'), text: (Array.from(v.host || '?')[0] || '?').toUpperCase(), 'aria-hidden': 'true' }),
          h('div', { class: 'hoststack' }, cell(v, 'host', { cls: 'strong', label: '主机', placeholder: '主机名', title: v.host }), (() => { const el = h('div', { class: 'kbadge' }); komBadges.push({ v, el }); return el; })()))),
        h('td', null, siteField(v)),
        h('td', null, copyField(v, 'ip', { mono: true, label: ' IP', placeholder: 'IP' })),
        h('td', null, cell(v, 'port', { cls: 'mono', label: '端口', placeholder: '端口' })),
        h('td', null, copyField(v, 'password', { mask: true, label: '密码', placeholder: '密码' })),
        h('td', null, tagsField(v)),
        h('td', null, cell(v, 'traffic', { label: '流量及重置' })),
        h('td', null, dateCell(v, 'renew', false, VPS_DUE_DAYS, true)),
        h('td', null, h('div', { class: 'price' }, cell(v, 'price', { right: true, label: '价格', placeholder: '$0' }), cnyEl)),
        h('td', null, cell(v, 'email', { label: '注册邮箱', placeholder: '注册邮箱', title: v.email })),
        h('td', null, copyField(v, 'loginPassword', { mask: true, label: '登录密码', placeholder: '登录密码' })),
        h('td', null, h('button', { class: 'btn ghost icon', type: 'button', 'aria-label': '更多操作', onclick: e => vpsMenu(e.currentTarget, v) }, icon('more')))), vpsTint(v, d));
    });
    const out = [
      vpsTiles(),
      komEl,
      h('div', { class: 'group vps' },
        h('div', { class: 'group-head' }, h('span', { class: 'group-title', text: '全部主机' }), h('span', { class: 'pill', text: S.vps.length + ' 台' }),
          h('span', { class: 'group-sum' }, h('span', { class: 'due-key' }), '30 天内要续费 · 点 IP、密码复制 · 部署项目回车添加')),
        S.vps.length ? h('div', { class: 'scroll' }, h('table', { class: 'grid', style: 'min-width:1540px;table-layout:fixed' },
          h('colgroup', null, cols.map(c => h('col', { style: c[1] ? 'width:' + c[1] + 'px' : '' }))),
          h('thead', null, h('tr', null, cols.map(c => h('th', { class: c[0] === '价格' ? 'r' : '', text: c[0] })))), h('tbody', null, body))) : h('div', { class: 'empty', text: '还没有 VPS。' }),
        h('div', { class: 'group-foot' }, h('button', { class: 'btn ghost small', type: 'button', onclick: () => { S.vps.push(newVps()); touch(); render(); const ins = document.querySelectorAll('.vps tbody tr:last-child input'); if (ins[0]) ins[0].focus(); } }, icon('plus', 15), '添加 VPS'))),
    ];
    komPaint();
    return out;
  }

  // ---------- 总览 ----------
  function tagOrText(b) { return b.color ? h('span', { class: 'tag', style: 'background:' + b.color + ';color:' + (b.text || '#fff'), text: b.label }) : h('b', { text: b.label }); }
  function dueList() {
    const items = [];
    for (const sh of S.sheets) for (const r of S.months[view.month].rows[sh.id]) {
      const d = daysUntil(r.renew); if (r.stopped || d == null || d > 7) continue;
      const g = sh.grouped ? groupOf(sh, r.group) : null, it = issuerById(r.issuerId), c = cardById(r.cardId);
      items.push({ d, title: r.account || '未填账号', kind: g ? g.name : (sh.grouped ? sh.name + ' · 未分组' : sh.name), color: rowTint(sh, r),
        meta: [it ? it.name : '', c ? cardLabel(c) : ''].filter(Boolean).join(' · '), cost: money(r.cost),
        action: h('button', { class: 'btn small', type: 'button', text: '已续费', title: '续费日期顺延一个月', onclick: () => { r.renew = shiftMonth(r.renew, 1); touch(); render(); } }) });
    }
    for (const v of S.vps) {
      const d = daysUntil(v.renew); if (d == null || d > VPS_DUE_DAYS) continue;
      items.push({ d, title: v.host || '未命名 VPS', kind: 'VPS', color: '#0f766e', meta: tagNames(v).join('、'), cost: v.price || '', action: h('button', { class: 'btn ghost small', type: 'button', text: '去修改', onclick: () => { view.tab = 'vps'; render(); } }) });
    }
    items.sort((a, b) => a.d - b.d);
    return h('div', { class: 'group' },
      h('div', { class: 'group-head' }, h('span', { class: 'group-title', text: '待续费' }), h('span', { class: 'pill', text: items.length + ' 项' }), h('span', { class: 'group-sum', text: '账号 7 天内、VPS 30 天内到期' })),
      items.length ? items.map(x => h('div', { class: 'due' }, h('span', { class: 'd-rel ' + (x.d < 0 ? 'late' : 'soon'), text: relText(x.d) }),
        h('div', { style: 'min-width:0' }, h('div', { class: 't', text: x.title }), h('div', { class: 'm' }, h('span', { class: 'kind', style: '--k:' + x.color, text: x.kind }), x.meta)), h('span', { class: 'cost num muted', text: x.cost }), x.action))
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
    if (!await confirmBox('归档并开始下个月', '把 ' + ymLabel(last) + ' 归档，并开始 ' + ymLabel(next) + '？\n\n· 账号、收费金额、成本和续费卡会复制到新月份，之后两个月各改各的\n· 续费日期早于新月份的会顺延到新月份\n· 收款状态全部重置为“未收”，代充表的单数清零\n· 标记为停止的账号不会带过去\n· ' + ymLabel(last) + ' 变成只读存档，需要时可以解锁修改', '归档并开始')) return;
    const src = S.months[last], rows = {}, floor = next + '-01';
    for (const sh of S.sheets) rows[sh.id] = (src.rows[sh.id] || []).filter(r => !r.stopped).map(r => {
      const c = fixRow(JSON.parse(JSON.stringify(r))); c.id = uid();
      for (let i = 0; i < 36 && isISO(c.renew) && c.renew < floor; i++) c.renew = shiftMonth(c.renew, 1);
      c.members.forEach(m => { m.paid = false; });
      if (sh.mode === 'resale') c.count = 0;
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
      if (!(key in found)) found[key] = r.groupName ? createGroup(ai, r.groupName) : null;
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
    for (const sh of S.sheets) {
      const gOrder = id => { const i = sheetGroups(sh).findIndex(g => g.id === id); return i < 0 ? 9999 : i; };
      const members = sh.mode === 'members', rows = [];
      for (const ym of months) {
        let list = (S.months[ym].rows[sh.id] || []).slice();
        if (sh.grouped) list = list.map((r, i) => [r, i]).sort((a, b) => gOrder(a[0].group) - gOrder(b[0].group) || a[1] - b[1]).map(x => x[0]);
        for (const r of list) {
          const g = sh.grouped ? groupOf(sh, r.group) : null, it = issuerById(r.issuerId), c = cardById(r.cardId), inc = income(sh, r);
          rows.push(M(ym).concat(sh.grouped ? [g ? g.name : '未分组'] : [], [r.account, D(r.renew), it ? it.name : '', it ? it.country || '' : '', c ? cardLabel(c, true) : ''],
            members ? [r.members.map(m => (m.name || '') + plain(m.amount)).join(' + '), r.members.length] : [num(r.unitPrice), num(r.count)],
            sh.mode === 'resale' ? [num(r.unitCost), inc, rowCost(sh, r), inc - rowCost(sh, r), r.note] : [inc, num(r.cost), inc - num(r.cost), r.note, r.stopped ? '已停止' : '']));
        }
      }
      out.push({ name: sh.name, head: MH.concat(sh.grouped ? ['分组'] : [], [sh.mode === 'resale' ? '项目' : '账号', '续费日期', sh.mode === 'resale' ? '付款渠道' : '续费卡信息', '国家 / 地区', '卡号'], members ? ['收费情况（每人）', '收费人数'] : sh.mode === 'resale' ? ['售价', '数量'] : ['单价', '人数'], sh.mode === 'resale' ? ['成本/份', '收费', '成本', '利润', '备注'] : ['收费', '续费成本', '利润', '备注', '状态']), rows });
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
    for (const it of S.issuers) { const own = cardsOf(it.id); if (!own.length) cardRows.push([it.name, it.country || '', '', '', '', '']); own.forEach(c => cardRows.push([it.name, it.country || '', c.number || '', c.expiry || '', c.cvc || '', c.note || ''])); }
    out.push({ name: '支付卡', head: ['卡信息', '国家 / 地区', '卡号', '有效期', 'CVC', '备注'], rows: cardRows });
    out.push({ name: 'VPS', head: ['主机', '官网', 'IP', '端口', '密码', '部署', '流量及重置', '续费', '价格', '邮箱', '登录密码'], rows: S.vps.map(v => [v.host, v.site, v.ip, v.port, v.password, tagNames(v).join('，'), v.traffic, D(v.renew), v.price, v.email, v.loginPassword]) });
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
      h('div', { class: 'muted', text: '按年导出会多一张“年度汇总”，其余各表把全年每个月的数据排在一起。\n文件里的卡号、有效期、CVC 和 VPS 密码是完整的，注意保管。' })],
      [{ text: '取消' }, { text: '导出', cls: 'primary', value: true }]);
    if (!ok) return;
    const yearly = mode.value === 'year', months = yearly ? keys.filter(k => k.slice(0, 4) === year.value) : [month.value];
    download(makeXlsx(exportSheets(months, yearly)), '合租管理-' + (yearly ? year.value + '年' : ymLabel(month.value).replace(/\s/g, '')) + '.xlsx');
  }


  // ---------- 页面 ----------
  // 左侧的表可以拖动调整顺序（顺序存在账本里，验证码页面的导航也跟着变）
  // 左侧导航的拖动排序和分类改名在 navdrag.js（各页共用）；这里接住表的新顺序，改账本再保存
  document.addEventListener('hz-sheet-order', e => {
    e.preventDefault();
    const pos = new Map(e.detail.map((id, i) => [id, i]));
    S.sheets.sort((a, b) => (pos.has(a.id) ? pos.get(a.id) : 1e9) - (pos.has(b.id) ? pos.get(b.id) : 1e9));
    touch(); render();
  });
  document.addEventListener('hz-nav-order', e => { NAV = Object.assign({}, NAV, e.detail, { labels: Object.assign({}, NAV.labels, e.detail.labels), names: e.detail.names || NAV.names, collapsed: e.detail.collapsed || NAV.collapsed, colors: Object.assign({}, NAV.colors, e.detail.colors) }); });
  // 左侧导航里给表改名：就是改账本里表的名字
  document.addEventListener('hz-sheet-rename', e => {
    const sh = S.sheets.find(x => x.id === e.detail.id);
    if (!sh) return;
    e.preventDefault();
    sh.name = e.detail.name; touch(); render();
  });
  // 左侧导航的四个大分类，按 NAV 里存的顺序和名字画；小项可以在分类之间拖。和服务器画的 templates/_shell.html 保持一致（hezu.py 的 _resolve）
  function navSections(nav, link, M) {
    const drag = el => { el.draggable = true; el.title = '拖动可以调整顺序，也能拖到别的分类'; return el; };
    const items = {
      cards: () => nav('cards', '支付卡', 'card', S.cards.length), vps: () => nav('vps', 'VPS', 'server', S.vps.length),
      gpt: () => link('/admin/gpt', 'GPT 账号', 'brain'),
      vault: () => link('/admin/vault', '密码本', 'lock', VC.items), notes: () => link('/admin/notes', '备忘录', 'note', VC.notes),
      dashboard: () => link('/admin/dashboard', '验证码账号', 'key', A.length), logs: () => link('/admin/logs', '访问记录', 'list'), settings: () => link('/admin/settings', '设置', 'gear'),
    };
    const defaults = { accounts: [], backend: ['cards', 'vps', 'gpt'], backup: ['vault', 'notes'], totp: ['dashboard', 'logs', 'settings'] };
    const labels = { accounts: '账号', backend: '后台', backup: '备份', totp: '验证码' };
    const secs = (NAV.sections || []).filter(k => labels[k]);
    Object.keys(labels).forEach(k => { if (!secs.includes(k)) secs.push(k); });
    const sheetById = new Map(S.sheets.map(s => [s.id, s])), used = new Set(), place = {};
    secs.forEach(k => { place[k] = ((NAV.items || {})[k] || []).filter(x => (items[x] || sheetById.has(x)) && !used.has(x) && used.add(x)); });
    Object.keys(defaults).forEach(k => defaults[k].forEach(x => { if (!used.has(x)) place[k].push(x); }));
    S.sheets.forEach(s => { if (!used.has(s.id)) place.accounts.push(s.id); });
    return secs.map(k => {
      const kids = place[k].map(id => {
        const s = sheetById.get(id);
        const el = drag(s ? nav(s.id, s.name, s.grouped ? 'users' : s.mode === 'resale' ? 'bolt' : 'play', M.rows[s.id].length) : items[id]());
        el.dataset.item = id; if (s) el.dataset.sheet = '1';
        // 名字可以改（navdrag.js）：表改的是账本里表的名字，固定页面的名字存在 NAV.names
        const txt = el.querySelector('svg + span');
        txt.classList.add('nav-text'); txt.dataset.default = txt.textContent;
        if (!s && (NAV.names || {})[id]) txt.textContent = NAV.names[id];
        el.append(h('span', { class: 'nav-edit', role: 'button', tabindex: '-1', title: '改名', 'aria-label': '给「' + txt.textContent + '」改名' }, icon('edit', 14)));
        return el;
      });
      if (k === 'accounts') kids.push(h('button', { class: 'nav', type: 'button', title: '新建一张表', onclick: () => sheetForm(null) }, icon('plus'), h('span', { text: '新建表' })));
      const name = ((NAV.labels || {})[k]) || labels[k], folded = (NAV.collapsed || []).includes(k);
      const color = (NAV.colors || {})[k] || { accounts: 'purple', backend: 'blue', backup: 'amber', totp: 'teal' }[k];
      return h('div', { class: 'nav-sec' + (folded ? ' collapsed' : ''), 'data-sec': k, 'data-color': color }, h('div', { class: 'nav-label', draggable: 'true', role: 'button', tabindex: '0', 'aria-expanded': folded ? 'false' : 'true', title: '点一下折叠 / 展开，拖动调整分类顺序，双击改名' },
        h('span', { class: 'nav-fold' }, icon('chev', 14)), h('span', { class: 'nav-label-text', text: name }), h('span', { class: 'nav-fold-count', text: String(place[k].length) }), h('button', { class: 'nav-rename', type: 'button', title: '改名', 'aria-label': '给「' + name + '」改名' }, icon('edit', 13))), kids);
    });
  }
  function render() {
    closePop(); updaters = []; searchRows = []; codes.els = []; codes.timers = [];
    saveView();
    if (location.hash.slice(1) !== view.tab && !location.search) history.replaceState(null, '', '#' + view.tab);
    const M = S.months[view.month], keys = monthKeys(), isLatest = view.month === keys[keys.length - 1], i = keys.indexOf(view.month);
    const go = ym => { view.month = ym; render(); };
    const sheet = S.sheets.find(s => s.id === view.tab);
    const monthBound = view.tab !== 'vps';
    statusEl = h('div', { class: 'status save-status' + (lastStatus.err ? ' err' : ''), text: lastStatus.text });
    const nav = (id, text, ic, count) => h('button', { class: 'nav' + (view.tab === id ? ' on' : ''), type: 'button', 'aria-current': view.tab === id ? 'page' : undefined, onclick: () => { view.tab = id; view.q = ''; render(); } },
      icon(ic), h('span', { text }), count != null ? h('span', { class: 'count', text: String(count) }) : null);
    const link = (href, text, ic, count) => h('a', { class: 'nav', href, onclick: e => { e.preventDefault(); leave(href); } },
      icon(ic), h('span', { text }), count != null ? h('span', { class: 'count', text: String(count) }) : null);
    const side = h('nav', { class: 'side', 'aria-label': '主导航' },
      h('div', { class: 'brand' }, h('div', { class: 'logo', text: '租' }), h('span', { text: '合租管理' })),
      nav('home', '总览', 'grid'),
      navSections(nav, link, M),
      h('div', { class: 'side-foot' }, statusEl,
        h('button', { class: 'nav', type: 'button', 'data-fx-toggle': '1', title: '汇率计算器' }, icon('fx'), h('span', { text: '汇率计算器' })),
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
    const top = h('div', { class: 'top' }, h('h1', { text: title }), h('span', { class: 'top-status save-status' + (lastStatus.err ? ' err' : /^已保存/.test(lastStatus.text) ? ' ok' : ''), text: lastStatus.text }), h('span', { class: 'spacer' }));
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
    if (window.hzFx) window.hzFx.sync();
  }
  load().catch(e => {
    console.error(e);
    setKids(document.getElementById('app'), h('div', { class: 'login' }, h('form', null, h('h1', { text: '合租账本' }),
      h('div', { class: 'err', text: '加载失败：' + e.message }), h('a', { class: 'btn primary', href: '/admin/hezu', text: '重试' }))));
  });
})();
