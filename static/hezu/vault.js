'use strict';
// 密码本 + 备忘录。数据都在服务器上加密保存，一条一条地存；密码本的列表里不带密码，点复制或编辑时才去取。
(function () {
  const root = document.getElementById('vault');
  if (!root) return;
  const PAGE = root.dataset.page;
  let CSRF = root.dataset.csrf;
  const API = '/admin/vault/api/';
  const ICONS = {
    plus: '<path d="M12 5v14M5 12h14"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/>',
    more: '<circle cx="5" cy="12" r="1.2"/><circle cx="12" cy="12" r="1.2"/><circle cx="19" cy="12" r="1.2"/>',
    link: '<path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>',
    eye: '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
    pen: '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/>',
    trash: '<path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M19 6l-1 14H6L5 6"/>',
    pin: '<path d="M12 17v5"/><path d="M9 10.8V4h6v6.8l3 3.2H6z"/>',
    copy: '<rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>',
    back: '<path d="m15 18-6-6 6-6"/>',
    gear: '<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M2 12h3M19 12h3M4.9 19.1 7 17M17 7l2.1-2.1"/>',
    up: '<path d="m18 15-6-6-6 6"/>', down: '<path d="m6 9 6 6 6-6"/>', x: '<path d="M18 6 6 18M6 6l12 12"/>',
    dice: '<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8.5" cy="8.5" r="1"/><circle cx="15.5" cy="15.5" r="1"/><circle cx="15.5" cy="8.5" r="1"/><circle cx="8.5" cy="15.5" r="1"/>',
  };

  // ---------- 小工具（和账本页同一套写法） ----------
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
  function add(el, c) { if (c == null || c === false) return; if (Array.isArray(c)) c.forEach(x => add(el, x)); else el.append(c); }
  function setKids(el) { el.replaceChildren(); for (let i = 1; i < arguments.length; i++) add(el, arguments[i]); }
  function icon(name, size) {
    const s = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    const a = { viewBox: '0 0 24 24', width: size || 16, height: size || 16, fill: 'none', stroke: 'currentColor', 'stroke-width': 1.9, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'aria-hidden': 'true' };
    for (const k in a) s.setAttribute(k, a[k]);
    s.innerHTML = ICONS[name];
    return s;
  }
  const fixUrl = u => { u = String(u || '').trim(); return !u || /^https?:\/\//i.test(u) ? u : 'https://' + u; };
  function textOn(hex) {   // 标签底色上用黑字还是白字
    const m = /^#?([0-9a-f]{6})$/i.exec(hex || ''); if (!m) return '#fff';
    const n = parseInt(m[1], 16), r = n >> 16, g = (n >> 8) & 255, b = n & 255;
    return (0.299 * r + 0.587 * g + 0.114 * b) > 160 ? '#141826' : '#fff';
  }
  const collator = new Intl.Collator('zh-Hans-CN', { numeric: true, sensitivity: 'base' });

  async function api(method, path, body) {
    const send = () => fetch(API + path, {
      method, credentials: 'same-origin',
      headers: Object.assign(method !== 'GET' ? { 'X-CSRFToken': CSRF } : {}, body != null ? { 'Content-Type': 'application/json' } : {}),
      body: body == null ? undefined : JSON.stringify(body),
    });
    let r = await send();
    // 页面开久了防伪令牌会过期：换个新的再试一次；真的没登录了就提示重新登录
    if (method !== 'GET' && (r.status === 400 || r.status === 401)) {
      const c = await fetch(API + 'context', { credentials: 'same-origin' }).catch(() => null);
      if (c && c.ok) { CSRF = (await c.json()).csrf; r = await send(); }
      else if (c && c.status === 401) r = new Response('{}', { status: 401 });
    }
    if (r.status === 401) { showRelogin(); throw new Error('登录已过期，请重新登录'); }
    const d = await r.json().catch(() => ({}));
    if (d.csrf) CSRF = d.csrf;
    d.status = r.status;
    return d;
  }
  let reloginBar = null;
  function showRelogin() {
    if (reloginBar) return;
    reloginBar = h('div', { class: 'relogin' }, h('span', { text: '登录已过期。没保存的内容还在页面上，重新登录后会自动接着保存。' }),
      h('a', { class: 'btn small primary', href: '/admin/login?next=' + encodeURIComponent(location.pathname), target: '_blank', text: '在新窗口登录' }),
      h('button', { class: 'btn small', type: 'button', text: '我已登录', onclick: () => { reloginBar.remove(); reloginBar = null; if (PAGE === 'notes') N.flush(); } }));
    document.body.append(reloginBar);
  }

  // 弹层、菜单、对话框
  let pop = null;
  function closePop() {
    if (!pop) return;
    const p = pop; pop = null; p.el.remove();
    document.removeEventListener('mousedown', p.down, true); document.removeEventListener('keydown', p.key, true);
  }
  function openPop(anchor, content) {
    closePop();
    const el = h('div', { class: 'pop' }, content);
    document.body.append(el);
    const r = anchor.getBoundingClientRect();
    const left = Math.max(8, Math.min(r.left, window.innerWidth - el.offsetWidth - 8));
    let top = r.bottom + 4;
    if (top + el.offsetHeight > window.innerHeight - 8 && r.top - el.offsetHeight - 4 > 8) top = r.top - el.offsetHeight - 4;
    el.style.left = (left + window.scrollX) + 'px'; el.style.top = (top + window.scrollY) + 'px';
    const p = { el };
    p.down = e => { if (!el.contains(e.target)) closePop(); };
    p.key = e => { if (e.key === 'Escape') closePop(); };
    document.addEventListener('mousedown', p.down, true); document.addEventListener('keydown', p.key, true);
    pop = p;
    return el;
  }
  function menu(anchor, items) {
    openPop(anchor, items.filter(Boolean).map(it => it === '-' ? h('div', { class: 'sep' })
      : h('button', { class: 'item' + (it.danger ? ' danger' : ''), type: 'button', text: it.text, onclick: () => { closePop(); it.run(); } })));
  }
  function dialog(title, body, buttons, cls) {
    const d = h('dialog', { class: 'dlg' + (cls ? ' ' + cls : '') });
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

  // 复制
  function flash(el, text) {
    if (!el || el.dataset.flash != null) return;
    el.dataset.flash = '1';
    const keep = Array.from(el.childNodes);
    el.replaceChildren(text); el.classList.add('ok');
    setTimeout(() => { el.replaceChildren(...keep); delete el.dataset.flash; el.classList.remove('ok'); }, 900);
  }
  async function copyNow(text, el) {
    try { await navigator.clipboard.writeText(text); flash(el, '已复制'); }
    catch (e) { alertBox('浏览器不让自动复制，请手动复制：\n' + text); }
  }
  // 要先向服务器取的内容（密码）：Safari 只允许在点击那一刻发起复制，所以把“还没取回来的内容”直接交给剪贴板
  async function copyLater(textPromise, el) {
    try {
      if (window.ClipboardItem && navigator.clipboard && navigator.clipboard.write) {
        try { await navigator.clipboard.write([new ClipboardItem({ 'text/plain': textPromise.then(t => new Blob([t], { type: 'text/plain' })) })]); }
        catch (e) { if (e && e.name === 'NotAllowedError') throw e; await navigator.clipboard.writeText(await textPromise); }
      } else await navigator.clipboard.writeText(await textPromise);
      flash(el, '已复制');
    } catch (e) {
      try { await textPromise; } catch (e2) { return alertBox(e2.message); }
      alertBox('浏览器不让自动复制，请点小眼睛查看后手动复制。');
    }
  }

  const N = {};   // 备忘录对外的几个动作（重新登录后补存）
  if (PAGE === 'vault') Vault(); else Notes();

  // =====================================================================
  // 密码本
  // =====================================================================
  function Vault() {
    let types = [], typesRev = 0, items = [], trashCount = 0;
    const VIEW_KEY = 'vault-view';
    let view = { type: '', q: '', trash: false };
    try { Object.assign(view, JSON.parse(localStorage.getItem(VIEW_KEY) || '{}'), { q: '', trash: false }); } catch (e) { /* 用默认 */ }
    const saveView = () => { try { localStorage.setItem(VIEW_KEY, JSON.stringify({ type: view.type })); } catch (e) { /* 无痕模式 */ } };
    const typeOf = id => types.find(t => t.id === id);
    const revealCache = new Map();   // 取过的完整内容只在内存里留一会儿

    async function load() {
      const d = await api('GET', 'items' + (view.trash ? '?trash=1' : ''));
      if (!d.ok) throw new Error(d.error || '加载失败');
      if (d.types) { types = d.types; typesRev = d.typesRev; }
      items = d.entries;
      if (!view.trash) trashCount = d.trashCount || 0;
      if (view.type && !typeOf(view.type)) view.type = '';
      render();
    }
    function reveal(it) {
      const c = revealCache.get(it.id);
      if (c && c.rev === it.rev && Date.now() - c.at < 60000) return Promise.resolve(c.entry);
      return api('POST', 'items/' + it.id + '/reveal', {}).then(d => {
        if (!d.ok) throw new Error(d.error || '取不到内容，请刷新页面');
        revealCache.set(it.id, { rev: d.entry.rev, at: Date.now(), entry: d.entry });
        return d.entry;
      });
    }
    setInterval(() => { const now = Date.now(); revealCache.forEach((v, k) => { if (now - v.at > 60000) revealCache.delete(k); }); }, 30000);

    function match(it, q) {
      if (!q) return true;
      const t = typeOf(it.type);
      return [it.title, it.account, it.phone, it.site, it.note, t && t.name, ...(it.extras || []).map(x => x.label + ' ' + (x.secret ? '' : x.value))]
        .join('\n').toLowerCase().includes(q);
    }
    function typeChip(t, small) {
      const c = t ? t.color : '#6c757d';
      return h('span', { class: 'vt-chip' + (small ? ' small' : ''), style: '--tb:' + c + ';--tf:' + textOn(c), text: t ? t.name : '未分类' });
    }

    function render() {
      closePop();
      saveView();
      if (!view.trash) navCount(items.length);
      const q = view.q.trim().toLowerCase();
      const search = h('input', { type: 'search', placeholder: '搜索账号、名称、备注…', value: view.q, autocomplete: 'off', spellcheck: false });
      search.addEventListener('input', () => { view.q = search.value; drawBody(); });
      const top = h('div', { class: 'top' }, h('h1', { text: '密码本' }),
        h('span', { class: 'sub', text: view.trash ? '最近删除' : items.length + ' 条 · 加密保存' }), h('span', { class: 'spacer' }),
        view.trash ? null : h('label', { class: 'search' }, icon('search', 15), search),
        view.trash ? h('button', { class: 'btn', type: 'button', text: '‹ 返回密码本', onclick: () => { view.trash = false; load(); } }) : [
          h('button', { class: 'btn', type: 'button', onclick: typesDialog }, icon('gear', 15), '类型管理'),
          h('button', { class: 'btn primary', type: 'button', onclick: () => editItem(null, view.type) }, icon('plus', 15), '添加')]);
      const counts = {}; items.forEach(it => { counts[it.type] = (counts[it.type] || 0) + 1; });
      const chips = view.trash ? null : h('div', { class: 'chipset gchips vchips' },
        h('button', { class: 'fchip' + (!view.type ? ' on' : ''), type: 'button', onclick: () => { view.type = ''; render(); } }, '全部 ', h('b', { text: String(items.length) })),
        types.map(t => h('button', { class: 'fchip' + (view.type === t.id ? ' on' : ''), type: 'button', onclick: () => { view.type = view.type === t.id ? '' : t.id; render(); } },
          h('span', { class: 'gdot', style: 'background:' + t.color }), t.name, counts[t.id] ? h('b', { text: String(counts[t.id]) }) : null)),
        trashCount ? h('button', { class: 'fchip trash-chip', type: 'button', onclick: () => { view.trash = true; load(); } }, icon('trash', 13), '最近删除 ', h('b', { text: String(trashCount) })) : null);
      const body = h('div', { class: 'vbody' });
      setKids(root, top, h('div', { class: 'view' }, chips, body));
      function drawBody() {
        const q2 = view.q.trim().toLowerCase();
        if (view.trash) return setKids(body, trashView());
        const list = items.filter(it => (!view.type || it.type === view.type) && match(it, q2));
        if (!items.length) return setKids(body, h('div', { class: 'group' }, h('div', { class: 'empty vempty' },
          h('div', { text: '还没有保存任何账号。' }), h('div', { class: 'faint', text: 'Apple、Google、邮箱、电话卡、银行卡……都可以存在这里，账号、密码点一下就能复制。' }),
          h('button', { class: 'btn primary', type: 'button', onclick: () => editItem(null, view.type) }, icon('plus', 15), '添加第一条'))));
        if (!list.length) return setKids(body, h('div', { class: 'group' }, h('div', { class: 'empty', text: '没有符合条件的记录。' })));
        const order = types.map(t => t.id);
        const groups = new Map();
        list.forEach(it => { const k = order.includes(it.type) ? it.type : ''; if (!groups.has(k)) groups.set(k, []); groups.get(k).push(it); });
        const keys = [...order.filter(k => groups.has(k)), ...(groups.has('') ? [''] : [])];
        setKids(body, keys.map(k => typeGroup(typeOf(k), groups.get(k))));
      }
      drawBody();
      if (q) search.focus();
    }

    function typeGroup(t, list) {
      list.sort((a, b) => collator.compare(a.title || '', b.title || '') || collator.compare(a.account || '', b.account || '') || a.id - b.id);
      const site = t && t.site ? fixUrl(t.site) : '';
      return h('section', { class: 'group vgroup' },
        h('div', { class: 'group-head' }, typeChip(t), h('span', { class: 'faint', text: list.length + ' 条' }),
          site ? h('a', { class: 'site-link small', href: site, target: '_blank', rel: 'noopener noreferrer', title: '打开 ' + site }, h('span', { text: '官网' }), icon('link', 12)) : null,
          h('span', { class: 'spacer' }),
          h('button', { class: 'btn small ghost', type: 'button', onclick: () => editItem(null, t ? t.id : '') }, icon('plus', 14), '添加')),
        h('div', { class: 'scroll' }, h('table', { class: 'grid vtable' },
          h('colgroup', null, h('col', { style: 'width:15%' }), h('col', { style: 'width:22%' }), h('col', { style: 'width:180px' }), h('col', { style: 'width:170px' }), h('col', { style: 'width:110px' }), h('col'), h('col', { style: 'width:44px' })),
          h('thead', null, h('tr', null, ['名称', '账号', '密码', '绑定手机', '官网', '备注', ''].map(x => h('th', { text: x })))),
          h('tbody', null, list.map(it => itemRow(it, t))))));
    }

    // ---- 表格里直接改：有内容时点一下复制、旁边的小笔改；空着的格子直接是输入框（和账本页一样） ----
    async function patch(it, changes, cellEl) {
      if (cellEl) cellEl.classList.add('saving');
      try {
        const d = await api('PUT', 'items/' + it.id, { rev: it.rev, patch: true, force: true, data: changes });
        if (!d.ok) throw new Error(d.error || '没保存上');
        revealCache.delete(it.id);
        Object.assign(it, d.entry);
        toast('已保存');
        return true;
      } catch (e) { alertBox('没保存上：' + e.message); return false; }
      finally { if (cellEl) cellEl.classList.remove('saving'); }
    }
    // 编辑框：回车或离开保存，Esc 放弃
    function editor(value, opts, onSave, onCancel) {
      const inp = h('input', { class: 'cell' + (opts.mono ? ' mono' : '') + (opts.strong ? ' strong' : ''), type: 'text', value: value || '', placeholder: opts.placeholder || '', autocomplete: 'off', spellcheck: false, 'aria-label': opts.label });
      let done = false;
      const finish = async save => {
        if (done) return; done = true;
        const v = opts.raw ? inp.value : inp.value.trim();
        if (!save || v === (value || '')) return onCancel();
        if (!await onSave(v)) { done = false; inp.focus(); }
      };
      inp.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); finish(true); } else if (e.key === 'Escape') { e.preventDefault(); finish(false); } });
      inp.addEventListener('blur', () => finish(true));
      return inp;
    }
    function penBtn(label, run) {
      return h('button', { class: 'cf-edit', type: 'button', title: '修改' + label, 'aria-label': '修改' + label, onclick: run }, icon('pen', 13));
    }
    // 普通文字格：账号、手机号、名称、备注
    function textCell(it, key, opts) {
      const wrap = h('div', { class: 'cf' });
      const draw = edit => {
        const v = it[key] || '';
        if (edit || !v) {
          const inp = editor(v, opts, async nv => { if (await patch(it, { [key]: nv }, wrap)) { draw(false); return true; } return false; }, () => draw(false));
          setKids(wrap, inp);
          if (edit) { inp.focus(); inp.select(); }
          return;
        }
        let shown;
        if (opts.title) shown = h('button', { class: 'vtitle', type: 'button', title: '点一下复制名称\n' + v, onclick: () => copyNow(v, shown) }, v);
        else shown = h('button', { class: 'cf-val' + (opts.mono ? ' mono' : '') + (opts.soft ? ' soft' : ''), type: 'button', title: '点一下复制' + opts.label + '\n' + v, onclick: () => copyNow(v, shown) }, opts.oneLine ? v.split('\n')[0] + (v.includes('\n') ? ' …' : '') : v);
        setKids(wrap, shown, opts.oneLine && v.includes('\n') ? penBtn(opts.label, () => editItem(it)) : penBtn(opts.label, () => draw(true)));
      };
      draw(false);
      return wrap;
    }
    function pwCell(it) {
      const wrap = h('div', { class: 'cf pwcell' });
      const draw = (edit, current) => {
        if (edit || !it.hasPassword) {
          const inp = editor(current || '', { mono: true, raw: true, placeholder: '密码', label: '密码' },
            async nv => { if (await patch(it, { password: nv }, wrap)) { draw(false); return true; } return false; }, () => draw(false));
          setKids(wrap, inp);
          if (edit) { inp.focus(); inp.select(); }
          return;
        }
        const val = h('button', { class: 'cf-val mono', type: 'button', title: '点一下复制密码', onclick: () => copyLater(reveal(it).then(e => e.password), val) }, '••••••••');
        let timer = null;
        const eye = h('button', { class: 'vbtn', type: 'button', title: '显示密码（10 秒后自动隐藏）', 'aria-label': '显示密码', onclick: async () => {
          if (timer) { clearTimeout(timer); timer = null; val.textContent = '••••••••'; eye.classList.remove('on'); return; }
          try { const e = await reveal(it); val.textContent = e.password; eye.classList.add('on'); timer = setTimeout(() => { val.textContent = '••••••••'; eye.classList.remove('on'); timer = null; }, 10000); }
          catch (err) { alertBox(err.message); }
        } }, icon('eye', 14));
        setKids(wrap, val, eye, penBtn('密码', async () => { try { draw(true, (await reveal(it)).password); } catch (err) { alertBox(err.message); } }));
      };
      draw(false);
      return wrap;
    }
    function siteCell(it, t) {
      const wrap = h('div', { class: 'cf' });
      const draw = edit => {
        const own = it.site || '', site = fixUrl(own || (t && t.site) || '');
        if (edit) {
          const inp = editor(own, { placeholder: t && t.site ? '留空用类型的官网' : '官网网址', label: '官网网址' },
            async nv => { if (await patch(it, { site: fixUrl(nv) }, wrap)) { draw(false); return true; } return false; }, () => draw(false));
          setKids(wrap, inp); inp.focus(); inp.select();
          return;
        }
        setKids(wrap, site ? h('a', { class: 'site-link', href: site, target: '_blank', rel: 'noopener noreferrer', title: '打开 ' + site + (own ? '' : '（类型的官网）') }, h('span', { text: '官网' }), icon('link', 12))
          : h('button', { class: 'cell faint vadd', type: 'button', text: '＋ 网址', onclick: () => draw(true) }),
          site ? penBtn('官网网址', () => draw(true)) : null);
      };
      draw(false);
      return wrap;
    }
    function extrasChips(it) {
      return (it.extras || []).map((x, i) => {
        const label = x.label || '附加信息';
        const b = h('button', { class: 'xchip' + (x.secret ? ' secret' : ''), type: 'button', title: x.secret ? '点一下复制「' + label + '」（保密）' : '点一下复制「' + label + '」\n' + x.value,
          onclick: () => x.secret ? copyLater(reveal(it).then(e => (e.extras[i] || {}).value || ''), b) : copyNow(x.value, b) },
          h('span', { class: 'xl', text: label }), x.secret ? h('span', { class: 'xv', text: '••••' }) : x.value && x.value !== label ? h('span', { class: 'xv', text: x.value }) : null);
        return b;
      });
    }
    function itemRow(it, t) {
      return h('tr', null,
        h('td', null, textCell(it, 'title', { label: '名称', placeholder: '名称', strong: true, title: true })),
        h('td', null, textCell(it, 'account', { label: '账号', placeholder: '账号' })),
        h('td', null, pwCell(it)),
        h('td', null, textCell(it, 'phone', { label: '手机号', placeholder: '手机号', mono: true })),
        h('td', null, siteCell(it, t)),
        h('td', { class: 'vnote' }, h('div', { class: 'vnote-in' }, textCell(it, 'note', { label: '备注', placeholder: '备注', soft: true, oneLine: true, raw: true }), extrasChips(it))),
        h('td', null, h('button', { class: 'btn ghost icon', type: 'button', 'aria-label': '更多', onclick: e => menu(e.currentTarget, [
          { text: '编辑全部（类型、附加信息…）', run: () => editItem(it) },
          { text: '复制全部信息', run: () => copyAll(it) },
          { text: '复制一份', run: () => duplicate(it) },
          '-',
          { text: '删除', danger: true, run: () => removeItem(it) },
        ]) }, icon('more', 16))));
    }
    async function copyAll(it) {
      const t = typeOf(it.type);
      const text = reveal(it).then(e => [
        (t ? t.name : '') + (e.title ? ' · ' + e.title : ''),
        e.account && '账号：' + e.account, e.password && '密码：' + e.password, e.phone && '绑定手机：' + e.phone,
        (e.site || (t && t.site)) && '官网：' + fixUrl(e.site || t.site),
        ...(e.extras || []).map(x => (x.label || '附加信息') + '：' + x.value), e.note && '备注：' + e.note,
      ].filter(Boolean).join('\n'));
      await copyLater(text, null);
      toast('已复制「' + (it.title || it.account || '这一条') + '」的全部信息');
    }
    async function duplicate(it) {
      try {
        const e = await reveal(it);
        editItem(null, e.type, Object.assign({}, e, { title: (e.title || '') + ' 副本' }));
      } catch (err) { alertBox(err.message); }
    }
    async function removeItem(it) {
      if (!await confirmBox('删除这一条？', '「' + (it.title || it.account || '未命名') + '」会移到「最近删除」，30 天内可以恢复。', '删除', true)) return;
      const d = await api('DELETE', 'items/' + it.id);
      if (!d.ok) return alertBox(d.error || '没删掉，请刷新页面再试');
      items = items.filter(x => x.id !== it.id); trashCount++;
      revealCache.delete(it.id);
      render(); toast('已移到「最近删除」');
    }

    function trashView() {
      if (!items.length) return h('div', { class: 'group' }, h('div', { class: 'empty', text: '「最近删除」是空的。' }));
      return h('section', { class: 'group' },
        h('div', { class: 'group-head' }, h('span', { class: 'muted', text: '删除的记录保留 30 天，之后自动彻底删除。' })),
        h('div', { class: 'scroll' }, h('table', { class: 'grid vtable' },
          h('thead', null, h('tr', null, ['类型', '名称', '账号', '删除时间', ''].map(x => h('th', { text: x })))),
          h('tbody', null, items.map(it => h('tr', null,
            h('td', null, typeChip(typeOf(it.type), true)), h('td', { text: it.title || '—' }), h('td', { text: it.account || '—' }), h('td', { class: 'faint', text: it.deleted }),
            h('td', { class: 'r nowrap' },
              h('button', { class: 'btn small', type: 'button', text: '恢复', onclick: async () => {
                const d = await api('POST', 'items/' + it.id + '/restore', {});
                if (!d.ok) return alertBox(d.error || '没恢复成功');
                trashCount = Math.max(0, trashCount - 1); items = items.filter(x => x.id !== it.id); render(); toast('已恢复');
              } }), ' ',
              h('button', { class: 'btn small danger', type: 'button', text: '彻底删除', onclick: async () => {
                if (!await confirmBox('彻底删除？', '「' + (it.title || it.account || '未命名') + '」会被永久删除，不能再恢复。', '彻底删除', true)) return;
                const d = await api('DELETE', 'items/' + it.id + '?purge=1');
                if (!d.ok) return alertBox(d.error || '没删掉');
                trashCount = Math.max(0, trashCount - 1); items = items.filter(x => x.id !== it.id); render();
              } }))))))));
    }

    // 添加 / 编辑
    async function editItem(it, typeId, preset) {
      let full = preset || null;
      if (it) { try { full = await reveal(it); } catch (e) { return alertBox(e.message); } }
      const d = full || {};
      const typeSel = h('select', null, types.map(t => h('option', { value: t.id, text: t.name, selected: t.id === (d.type || typeId || (types[0] && types[0].id)) })));
      const inp = (v, ph, extra) => h('input', Object.assign({ type: 'text', value: v || '', placeholder: ph || '', autocomplete: 'off', spellcheck: false }, extra || {}));
      const title = inp(d.title, '比如：土区、主力号、移动主卡、已购 iPhone12');
      const account = inp(d.account, '邮箱、用户名、卡号、手机号…');
      const password = inp(d.password, '没有密码可以不填', { class: 'mono' });
      const phone = inp(d.phone, '可不填');
      const site = inp(d.site, '');
      const note = h('textarea', { rows: 3, placeholder: '可不填，比如：已封、已购 iPad Air', value: d.note || '' });
      const sitePh = () => { const t = typeOf(typeSel.value); site.placeholder = t && t.site ? '不填就用类型的官网：' + t.site : 'https://… 可不填'; };
      typeSel.addEventListener('change', sitePh); sitePh();
      const gen = h('button', { class: 'btn small', type: 'button', title: '生成一个 16 位随机密码', onclick: () => { password.value = randomPassword(16); } }, icon('dice', 14), '生成');
      const extras = (d.extras || []).map(x => Object.assign({}, x));
      const extrasBox = h('div', { class: 'xlist' });
      const drawExtras = () => setKids(extrasBox, extras.map((x, i) => {
        const l = inp(x.label, '名称，如：密保问题 1、生日'), v = inp(x.value, '内容'), s = h('input', { type: 'checkbox', checked: !!x.secret });
        l.addEventListener('input', () => { x.label = l.value; }); v.addEventListener('input', () => { x.value = v.value; });
        s.addEventListener('change', () => { x.secret = s.checked; });
        return h('div', { class: 'xrow' }, l, v, h('label', { class: 'check small', title: '保密的内容在列表里显示成 ••••，复制时才取' }, s, '保密'),
          h('button', { class: 'btn ghost icon', type: 'button', 'aria-label': '删掉这一项', onclick: () => { extras.splice(i, 1); drawExtras(); } }, icon('x', 14)));
      }), h('button', { class: 'btn small ghost', type: 'button', onclick: () => { extras.push({ label: '', value: '', secret: false }); drawExtras(); extrasBox.querySelector('.xrow:last-of-type input').focus(); } }, icon('plus', 14), '添加一项（密保问题、生日、PIN 码…）'));
      drawExtras();
      const err = h('div', { class: 'neg' });
      const field = (label, el) => h('label', { class: 'field' }, label, el);
      const ok = await dialog(it ? '编辑' : '添加', [
        h('div', { class: 'vform' },
          field('类型', typeSel), field('名称', title),
          field('账号', account), h('label', { class: 'field' }, '密码', h('div', { class: 'pwrow' }, password, gen)),
          field('绑定手机', phone), field('官网网址', site)),
        field('备注', note),
        h('div', { class: 'field' }, '附加信息', extrasBox),
        err,
      ], [{ text: '取消' }, { text: '保存', cls: 'primary', value: true, run: async () => {
        const data = {
          type: typeSel.value, title: title.value, account: account.value, password: password.value,
          phone: phone.value, site: fixUrl(site.value), note: note.value,
          extras: extras.filter(x => (x.label || '').trim() || (x.value || '').trim()),
        };
        const r = it ? await api('PUT', 'items/' + it.id, { rev: it.rev, data }) : await api('POST', 'items', { data });
        if (r.conflict) {
          if (!await confirmBox('这一条刚在别处改过', '在别的窗口或设备上，这一条刚被修改过。\n要用你现在填的内容覆盖吗？', '覆盖')) return false;
          const r2 = await api('PUT', 'items/' + it.id, { rev: it.rev, data, force: true });
          if (!r2.ok) { err.textContent = r2.error || '保存失败'; return false; }
          return done(r2.entry);
        }
        if (!r.ok) { err.textContent = r.error || '保存失败，请重试'; return false; }
        return done(r.entry);
      } }], 'vdlg');
      function done(entry) {
        revealCache.delete(entry.id);
        const i = items.findIndex(x => x.id === entry.id);
        if (i >= 0) items[i] = entry; else items.push(entry);
        render(); toast(it ? '已保存' : '已添加');
        return true;
      }
      return ok;
    }

    // 类型管理
    async function typesDialog() {
      const list = types.map(t => Object.assign({}, t));
      const counts = {}; items.forEach(it => { counts[it.type] = (counts[it.type] || 0) + 1; });
      const box = h('div', { class: 'tlist' });
      const draw = () => setKids(box, list.map((t, i) => {
        const color = h('input', { type: 'color', value: t.color, title: '标签颜色' });
        const name = h('input', { type: 'text', value: t.name, placeholder: '类型名称' });
        const site = h('input', { type: 'text', value: t.site, placeholder: '官网网址，可不填', spellcheck: false });
        color.addEventListener('input', () => { t.color = color.value; });
        name.addEventListener('input', () => { t.name = name.value; });
        site.addEventListener('input', () => { t.site = site.value; });
        const n = counts[t.id] || 0;
        return h('div', { class: 'trow' }, color, name, site,
          h('button', { class: 'btn ghost icon', type: 'button', 'aria-label': '上移', disabled: i === 0, onclick: () => { list.splice(i - 1, 0, list.splice(i, 1)[0]); draw(); } }, icon('up', 14)),
          h('button', { class: 'btn ghost icon', type: 'button', 'aria-label': '下移', disabled: i === list.length - 1, onclick: () => { list.splice(i + 1, 0, list.splice(i, 1)[0]); draw(); } }, icon('down', 14)),
          h('button', { class: 'btn ghost icon danger', type: 'button', 'aria-label': '删除这个类型', disabled: n > 0, title: n ? '还有 ' + n + ' 条是这个类型，先把它们改到别的类型才能删' : '删除这个类型',
            onclick: () => { list.splice(i, 1); draw(); } }, icon('trash', 14)));
      }), h('button', { class: 'btn small ghost', type: 'button', onclick: () => {
        const used = list.map(t => t.color);
        const palette = ['#2563eb', '#16a34a', '#ea580c', '#7c3aed', '#0d9488', '#db2777', '#a16207', '#0891b2', '#4f46e5', '#4d7c0f', '#57534e', '#dc2626'];
        list.push({ id: 't' + Date.now().toString(36), name: '', color: palette.find(c => !used.includes(c)) || '#6c757d', site: '' });
        draw(); const ins = box.querySelectorAll('.trow input[type=text]'); ins[ins.length - 2].focus();
      } }, icon('plus', 14), '新类型'));
      draw();
      const err = h('div', { class: 'neg' });
      await dialog('类型管理', [h('div', { class: 'muted small', text: '类型显示在密码本里的顺序就是这里的顺序。填了官网的类型，下面的记录没单独填官网时就用它。' }), box, err],
        [{ text: '取消' }, { text: '保存', cls: 'primary', run: async () => {
          const clean = list.map(t => Object.assign(t, { name: t.name.trim(), site: fixUrl(t.site) })).filter(t => t.name);
          if (!clean.length) { err.textContent = '至少要留一个类型'; return false; }
          const d = await api('PUT', 'types', { rev: typesRev, types: clean });
          if (d.conflict) { types = d.types; typesRev = d.typesRev; render(); err.textContent = '类型刚在别处改过，已载入最新的，请重新修改'; return false; }
          if (!d.ok) { err.textContent = d.error || '保存失败'; return false; }
          types = d.types; typesRev = d.typesRev; render(); toast('类型已保存');
        } }], 'vdlg');
    }

    // 回到这个页面时取一次最新的（别的设备可能改过）
    let lastFetch = Date.now();
    window.addEventListener('focus', () => { if (Date.now() - lastFetch > 15000 && !document.querySelector('dialog[open]')) { lastFetch = Date.now(); load().catch(() => {}); } });
    load().catch(e => setKids(root, h('div', { class: 'view' }, h('div', { class: 'group' }, h('div', { class: 'empty', text: '加载失败：' + e.message })))));
  }

  function randomPassword(n) {
    const sets = ['ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '!@#$%&*?-_'];
    const all = sets.join(''), buf = new Uint32Array(n + sets.length);
    crypto.getRandomValues(buf);
    const out = sets.map((s, i) => s[buf[i] % s.length]);
    for (let i = sets.length; i < n; i++) out.push(all[buf[i] % all.length]);
    for (let i = out.length - 1; i > 0; i--) { const j = buf[i] % (i + 1); [out[i], out[j]] = [out[j], out[i]]; }
    return out.join('');
  }

  // 左侧导航上的条数（页面是服务器画的，增删后在这里跟着改）
  function navCount(n) { const el = document.querySelector('.side .nav.on .count'); if (el) el.textContent = String(n); }

  let toastEl = null, toastTimer = null;
  function toast(text) {
    if (!toastEl) { toastEl = h('div', { class: 'vtoast', role: 'status' }); document.body.append(toastEl); }
    toastEl.textContent = text; toastEl.classList.add('show');
    clearTimeout(toastTimer); toastTimer = setTimeout(() => toastEl.classList.remove('show'), 1800);
  }

  // =====================================================================
  // 备忘录
  // =====================================================================
  function Notes() {
    let notes = [], trash = [], trashCount = 0, showTrash = false, q = '';
    let cur = null;          // 正在编辑的那条（新建还没存的 id 是 null）
    let dirty = false, saving = false, timer = null, status = '';
    const LAST_KEY = 'notes-last';
    const listEl = h('div', { class: 'nlist' }), editorEl = h('div', { class: 'neditor' });
    const shell = h('div', { class: 'notes' });

    const titleOf = t => { const l = String(t || '').split('\n').map(x => x.trim()).find(Boolean); return l ? l.slice(0, 80) : '新备忘录'; };
    const previewOf = t => { const ls = String(t || '').split('\n').map(x => x.trim()).filter(Boolean); return (ls[1] || '').slice(0, 80); };
    const sorted = () => notes.slice().sort((a, b) => (b.pinned - a.pinned) || String(b.updatedRaw || '').localeCompare(String(a.updatedRaw || '')) || b.id - a.id);

    async function load() {
      const d = await api('GET', 'notes');
      if (!d.ok) throw new Error(d.error || '加载失败');
      notes = d.entries; trashCount = d.trashCount || 0;
    }
    function remember(id) { try { localStorage.setItem(LAST_KEY, String(id || '')); } catch (e) { /* 无痕模式 */ } }

    function drawList() {
      navCount(notes.length);
      const search = h('input', { type: 'search', placeholder: '搜索备忘录', value: q, autocomplete: 'off' });
      search.addEventListener('input', () => { q = search.value; drawItems(); });
      const items = h('div', { class: 'nitems' });
      function drawItems() {
        const k = q.trim().toLowerCase();
        if (showTrash) {
          return setKids(items, trash.length ? trash.map(n => h('div', { class: 'nitem trashed' },
            h('div', { class: 'nt', text: titleOf(n.text) }), h('div', { class: 'np' }, h('span', { text: '删除于 ' + n.deleted })),
            h('div', { class: 'nrow' },
              h('button', { class: 'btn small', type: 'button', text: '恢复', onclick: async () => {
                const d = await api('POST', 'notes/' + n.id + '/restore', {});
                if (!d.ok) return alertBox(d.error || '没恢复成功');
                trash = trash.filter(x => x.id !== n.id); trashCount--; notes.push(d.entry); drawList(); toast('已恢复');
              } }),
              h('button', { class: 'btn small danger', type: 'button', text: '彻底删除', onclick: async () => {
                if (!await confirmBox('彻底删除？', '「' + titleOf(n.text) + '」会被永久删除，不能再恢复。', '彻底删除', true)) return;
                const d = await api('DELETE', 'notes/' + n.id + '?purge=1');
                if (!d.ok) return alertBox(d.error || '没删掉');
                trash = trash.filter(x => x.id !== n.id); trashCount--; drawList();
              } })))) : h('div', { class: 'nempty', text: '「最近删除」是空的。删除的备忘录保留 30 天。' }));
        }
        const list = sorted().filter(n => !k || String(n.text || '').toLowerCase().includes(k));
        if (cur && cur.id == null && !k) list.unshift(cur);
        setKids(items, list.length ? list.map(n => h('button', { class: 'nitem' + (cur && n === cur || cur && cur.id != null && n.id === cur.id ? ' on' : ''), type: 'button', onclick: () => open(n) },
          h('div', { class: 'nt' }, n.pinned ? icon('pin', 13) : null, h('span', { text: titleOf(n.text) })),
          h('div', { class: 'np' }, h('span', { class: 'nd', text: shortDate(n.updated) }), h('span', { text: previewOf(n.text) || (n.id == null ? '还没保存' : '没有其他内容') })))) :
          h('div', { class: 'nempty', text: k ? '没有找到包含「' + q.trim() + '」的备忘录。' : '还没有备忘录，点右上角的 ＋ 新建一条。' }));
      }
      setKids(listEl,
        h('div', { class: 'nhead' }, h('h1', { text: showTrash ? '最近删除' : '备忘录' }), h('span', { class: 'faint', text: showTrash ? '' : notes.length + ' 条' }), h('span', { class: 'spacer' }),
          showTrash ? h('button', { class: 'btn small', type: 'button', text: '‹ 返回', onclick: () => { showTrash = false; drawList(); } })
            : h('button', { class: 'btn primary icon', type: 'button', title: '新建备忘录', 'aria-label': '新建备忘录', onclick: newNote }, icon('plus', 16))),
        showTrash ? null : h('label', { class: 'search' }, icon('search', 15), search),
        items,
        !showTrash && trashCount ? h('button', { class: 'ntrash', type: 'button', onclick: async () => {
          await flush();
          const d = await api('GET', 'notes?trash=1'); if (!d.ok) return alertBox(d.error || '加载失败');
          trash = d.entries; trashCount = trash.length; showTrash = true; drawList();
        } }, icon('trash', 14), '最近删除 ', h('b', { text: String(trashCount) })) : null);
      drawItems();
    }
    function shortDate(s) {
      if (!s) return '';
      const today = new Date(Date.now() + 8 * 3600e3).toISOString().slice(0, 10);   // 服务器给的是北京时间
      return s.slice(0, 10) === today ? s.slice(11, 16) : s.slice(0, 4) === today.slice(0, 4) ? s.slice(5, 10) : s.slice(0, 10);
    }

    let ta = null, statusEl = null, metaEl = null;
    function drawEditor() {
      if (!cur) {
        setKids(editorEl, h('div', { class: 'nblank' }, h('div', { text: '选一条备忘录，或者新建一条。' }),
          h('button', { class: 'btn primary', type: 'button', onclick: newNote }, icon('plus', 15), '新建备忘录')));
        shell.classList.remove('editing');
        return;
      }
      ta = h('textarea', { class: 'ntext', placeholder: '在这里输入……第一行会作为标题', spellcheck: false, value: cur.text || '' });
      ta.addEventListener('input', () => { cur.text = ta.value; changed(); });
      statusEl = h('span', { class: 'nstatus' });
      metaEl = h('span', { class: 'faint nmeta' });
      setKids(editorEl,
        h('div', { class: 'nbar' },
          h('button', { class: 'btn small nback', type: 'button', onclick: () => { flush(); shell.classList.remove('editing'); } }, icon('back', 15), '备忘录'),
          metaEl, statusEl, h('span', { class: 'spacer' }),
          h('button', { class: 'btn ghost icon' + (cur.pinned ? ' on' : ''), type: 'button', title: cur.pinned ? '取消置顶' : '置顶', 'aria-label': '置顶', onclick: e => { cur.pinned = !cur.pinned; e.currentTarget.classList.toggle('on', cur.pinned); e.currentTarget.title = cur.pinned ? '取消置顶' : '置顶'; changed(true); } }, icon('pin', 16)),
          h('button', { class: 'btn ghost icon', type: 'button', title: '复制全文', 'aria-label': '复制全文', onclick: e => copyNow(cur.text || '', null).then(() => toast('已复制全文')) }, icon('copy', 16)),
          h('button', { class: 'btn ghost icon danger', type: 'button', title: '删除', 'aria-label': '删除', onclick: removeCur }, icon('trash', 16))),
        ta);
      paintStatus();
      shell.classList.add('editing');
    }
    function paintStatus() {
      if (metaEl) metaEl.textContent = cur && cur.updated ? '修改于 ' + cur.updated : '';
      if (statusEl) { statusEl.textContent = status; statusEl.classList.toggle('err', /失败|过期/.test(status)); }
    }
    function setStatus(s) { status = s; paintStatus(); }

    function open(n) {
      if (cur === n) { shell.classList.add('editing'); return; }
      flush();
      if (cur && cur.id == null && !String(cur.text || '').trim()) { /* 空的新备忘录不留 */ }
      cur = n; status = ''; remember(n.id);
      if (n.id != null) history.replaceState(null, '', '#' + n.id);
      drawList(); drawEditor();
      if (window.innerWidth > 880 || shell.classList.contains('editing')) ta.focus();
    }
    function newNote() {
      if (showTrash) { showTrash = false; }
      flush();
      cur = { id: null, rev: 0, text: '', pinned: false, updated: '' }; status = '';
      history.replaceState(null, '', location.pathname);
      drawList(); drawEditor(); ta.focus();
    }
    function changed(now) {
      dirty = true; setStatus('有改动…');
      clearTimeout(timer); timer = setTimeout(save, now ? 0 : 700);
      // 列表里的标题、预览跟着变
      const on = listEl.querySelector('.nitem.on');
      if (on) { on.querySelector('.nt span').textContent = titleOf(cur.text); on.querySelector('.np span:last-child').textContent = previewOf(cur.text) || '没有其他内容'; }
    }
    async function save() {
      clearTimeout(timer);
      if (!dirty || !cur) return;
      if (saving) { timer = setTimeout(save, 400); return; }
      const n = cur;
      if (n.id == null && !String(n.text || '').trim()) { dirty = false; setStatus(''); return; }
      saving = true; dirty = false; setStatus('保存中…');
      const data = { text: n.text, pinned: n.pinned };
      try {
        let d = n.id == null ? await api('POST', 'notes', { data }) : await api('PUT', 'notes/' + n.id, { rev: n.rev, data });
        if (d.conflict) d = await resolveConflict(n, d.entry, data);
        if (!d || !d.ok) throw new Error((d && d.error) || '保存失败');
        const wasNew = n.id == null;
        n.id = d.entry.id; n.rev = d.entry.rev; n.updated = d.entry.updated; n.updatedRaw = d.entry.updatedRaw;
        if (wasNew) { notes.push(n); remember(n.id); if (cur === n) history.replaceState(null, '', '#' + n.id); drawList(); }
        if (cur === n) setStatus(dirty ? '有改动…' : '已保存');
      } catch (e) {
        dirty = true;
        if (cur === n) setStatus(/登录/.test(e.message) ? '登录已过期，没保存' : '保存失败，稍后自动重试');
        clearTimeout(timer); timer = setTimeout(save, 5000);
      } finally { saving = false; }
    }
    async function resolveConflict(n, remote, mine) {
      const keepMine = await dialog('这条备忘录在别处改过了', '在别的窗口或设备上，这条备忘录刚被修改过（' + remote.updated + '）。\n\n要保留哪一个版本？', [
        { text: '用那边的版本' }, { text: '保留我现在的', cls: 'primary', value: true }]);
      if (keepMine) return api('PUT', 'notes/' + n.id, { rev: remote.rev, data: mine, force: true });
      Object.assign(n, { text: remote.text, pinned: remote.pinned, rev: remote.rev, updated: remote.updated, updatedRaw: remote.updatedRaw });
      if (cur === n) drawEditor();
      drawList();
      return { ok: true, entry: remote };
    }
    async function flush() { if (dirty) await save(); }
    N.flush = flush;

    async function removeCur() {
      const n = cur;
      if (n.id == null) { cur = null; dirty = false; drawList(); drawEditor(); return; }
      if (!await confirmBox('删除这条备忘录？', '「' + titleOf(n.text) + '」会移到「最近删除」，30 天内可以恢复。', '删除', true)) return;
      clearTimeout(timer); dirty = false;
      const d = await api('DELETE', 'notes/' + n.id);
      if (!d.ok) return alertBox(d.error || '没删掉，请刷新页面再试');
      notes = notes.filter(x => x.id !== n.id); trashCount++;
      const next = sorted()[0] || null;
      cur = null; if (next && window.innerWidth > 880) open(next); else { drawList(); drawEditor(); }
      toast('已移到「最近删除」');
    }

    // 回到页面时：别处改过、这边又没在改的，直接换成最新的
    let lastFetch = Date.now();
    window.addEventListener('focus', async () => {
      if (Date.now() - lastFetch < 10000 || dirty || saving || document.querySelector('dialog[open]')) return;
      lastFetch = Date.now();
      try {
        const d = await api('GET', 'notes'); if (!d.ok) return;
        const curId = cur && cur.id;
        notes = d.entries; trashCount = d.trashCount || 0;
        if (curId != null) {
          const fresh = notes.find(x => x.id === curId);
          if (fresh && fresh.rev !== cur.rev && !dirty) { cur = fresh; drawEditor(); } else if (fresh) { const i = notes.indexOf(fresh); notes[i] = cur; Object.assign(cur, { updated: fresh.updated }); }
          else { cur = null; drawEditor(); }
        }
        drawList();
      } catch (e) { /* 断网时下次再试 */ }
    });
    window.addEventListener('beforeunload', e => { if (dirty || saving) { save(); e.preventDefault(); e.returnValue = ''; } });
    document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') flush(); });
    document.addEventListener('keydown', e => { if ((e.metaKey || e.ctrlKey) && e.key === 's' && cur) { e.preventDefault(); flush(); } });

    shell.append(listEl, editorEl);
    setKids(root, shell);
    load().then(() => {
      let want = parseInt(location.hash.slice(1), 10);
      if (!want) try { want = parseInt(localStorage.getItem(LAST_KEY), 10); } catch (e) { want = 0; }
      const first = notes.find(n => n.id === want) || (window.innerWidth > 880 ? sorted()[0] : null);
      drawList();
      if (first) open(first); else drawEditor();
    }).catch(e => setKids(root, h('div', { class: 'view' }, h('div', { class: 'group' }, h('div', { class: 'empty', text: '加载失败：' + e.message })))));
  }
})();
