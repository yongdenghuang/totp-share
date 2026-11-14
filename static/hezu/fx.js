'use strict';
// 汇率计算器：整个后台共用的浮动面板。左侧导航里带 data-fx-toggle 的按钮打开 / 关上它，
// 开着的状态、金额、币种记在浏览器里，换页面后还在。汇率由服务器去取并缓存（/admin/hezu/api/rates）。
(function () {
  const RATES_URL = '/admin/hezu/api/rates';
  const KEY = 'hezu-fx';
  const FX = [['CNY', '人民币', '¥'], ['USD', '美元', '$'], ['PHP', '菲律宾比索', '₱'], ['NGN', '尼日利亚奈拉', '₦'],
    ['EUR', '欧元', '€'], ['HKD', '港币', 'HK$'], ['GBP', '英镑', '£'], ['SGD', '新加坡元', 'S$']];
  const st = { open: false, amount: '20', from: 'USD' };
  try { Object.assign(st, JSON.parse(localStorage.getItem(KEY) || '{}')); } catch (e) { /* 浏览器不让存就算了 */ }
  if (!FX.some(c => c[0] === st.from)) st.from = 'USD';
  let data = null, loading = false, err = '', panel = null;

  const save = () => { try { localStorage.setItem(KEY, JSON.stringify({ open: st.open, amount: st.amount, from: st.from })); } catch (e) { /* 忽略 */ } };
  const p2 = n => String(n).padStart(2, '0');
  const num = v => { const n = parseFloat(String(v || '').replace(/[,，¥$\s]/g, '')); return isFinite(n) ? n : 0; };
  const fmt = (v, max) => Number(v).toLocaleString('zh-CN', { minimumFractionDigits: 0, maximumFractionDigits: max == null ? 2 : max });
  const digits = r => r >= 100 ? 2 : r >= 1 ? 4 : 6;
  function el(tag, attrs, ...kids) {
    const e = document.createElement(tag);
    for (const k in attrs || {}) {
      const v = attrs[k];
      if (v == null || v === false) continue;
      if (k === 'class') e.className = v; else if (k === 'text') e.textContent = v;
      else if (k.startsWith('on')) e.addEventListener(k.slice(2), v); else e.setAttribute(k, v);
    }
    kids.flat().forEach(c => { if (c != null && c !== false) e.append(c); });
    return e;
  }

  async function load() {
    if (loading) return;
    loading = true; err = '';
    try {
      const r = await fetch(RATES_URL, { credentials: 'same-origin' }), d = await r.json().catch(() => ({}));
      if (r.ok && d.ok) data = d;
      else err = r.status === 401 ? '登录已过期，请刷新页面' : (d.error || '暂时取不到汇率，请稍后再试');
    } catch (e) { err = '连不上服务器，请稍后再试'; }
    loading = false;
    draw();
  }

  function draw() {
    if (!panel) return;
    panel.classList.toggle('open', st.open);
    document.querySelectorAll('[data-fx-toggle]').forEach(b => { b.classList.toggle('on', st.open); b.setAttribute('aria-expanded', String(st.open)); });
    if (!st.open) return;
    if (!data && !loading && !err) load();
    const head = el('div', { class: 'fxw-head' }, el('b', { text: '汇率计算器' }));
    if (data) {
      const t = new Date(data.updated * 1000);
      head.append(el('span', { class: 'fxw-pill', text: (t.getMonth() + 1) + ' 月 ' + t.getDate() + ' 日 ' + p2(t.getHours()) + ':' + p2(t.getMinutes()) + ' 更新' }));
    }
    head.append(el('button', { class: 'fxw-x', type: 'button', 'aria-label': '关闭汇率计算器', onclick: () => toggle(false), text: '✕' }));
    const body = el('div', { class: 'fxw-body' });
    if (!data) {
      body.append(el('div', { class: 'fxw-note' }, err ? [el('span', { class: 'fxw-err', text: err }), ' ',
        el('button', { class: 'fxw-retry', type: 'button', text: '重试', onclick: () => { err = ''; draw(); } })] : '正在取汇率…'));
      panel.replaceChildren(head, body);
      return;
    }
    const amount = el('input', { type: 'text', inputmode: 'decimal', 'aria-label': '金额', autocomplete: 'off', spellcheck: 'false' });
    amount.value = st.amount;
    const from = el('select', { 'aria-label': '币种' }, FX.map(c => el('option', { value: c[0], text: c[0] + ' ' + c[1] })));
    from.value = st.from;
    const list = el('div', { class: 'fxw-list' });
    const msg = el('span', { class: 'fxw-copied', 'aria-live': 'polite' });
    const rows = () => {
      const a = num(amount.value), base = data.rates[st.from];
      list.replaceChildren(...FX.filter(c => c[0] !== st.from && data.rates[c[0]]).map(c => {
        const unit = data.rates[c[0]] / base, v = a * unit;
        return el('button', { class: 'fxw-row', type: 'button', title: '点一下复制金额', onclick: async () => {
          try { await navigator.clipboard.writeText(String(Math.round(v * 100) / 100)); msg.textContent = '已复制 ' + c[2] + fmt(v); }
          catch (e) { msg.textContent = '浏览器不让自动复制'; }
          clearTimeout(msg._t); msg._t = setTimeout(() => { msg.textContent = ''; }, 1500);
        } },
          el('span', { class: 'fxw-cur' }, el('b', { text: c[0] }), el('small', { text: c[1] })),
          el('span', { class: 'fxw-val' }, el('b', { text: c[2] + fmt(v) }), el('small', { text: '1 ' + st.from + ' = ' + fmt(unit, digits(unit)) + ' ' + c[0] })));
      }));
    };
    amount.addEventListener('input', () => { st.amount = amount.value; save(); rows(); });
    amount.addEventListener('focus', () => amount.select());
    from.addEventListener('change', () => { st.from = from.value; save(); rows(); });
    rows();
    body.append(el('div', { class: 'fxw-input' }, amount, from), list,
      el('div', { class: 'fxw-note' },
        data.stale ? el('span', { class: 'fxw-err', text: '取最新汇率失败，显示的是上次的。' }) : null,
        '参考中间价，每天更新一次；Wise、Revolut、银行卡实际扣款有手续费和汇差。来源 ',
        el('a', { href: data.sourceUrl, target: '_blank', rel: 'noopener noreferrer', text: data.source }), '。 ', msg));
    panel.replaceChildren(head, body);
  }

  function toggle(on) {
    st.open = on == null ? !st.open : !!on;
    save(); draw();
    if (st.open) { const i = panel.querySelector('input'); if (i) i.focus(); }
  }

  function init() {
    panel = el('aside', { class: 'fxw', 'aria-label': '汇率计算器' });
    document.body.append(panel);
    document.addEventListener('click', e => { const b = e.target.closest('[data-fx-toggle]'); if (b) { e.preventDefault(); toggle(); } });
    document.addEventListener('keydown', e => { if (e.key === 'Escape' && st.open && panel.contains(document.activeElement)) toggle(false); });
    draw();
  }
  // 账本页的导航是脚本画的，画完后用这个把按钮的开 / 关状态补上
  window.hzFx = { isOpen: () => st.open, toggle, sync: () => { if (panel) document.querySelectorAll('[data-fx-toggle]').forEach(b => b.classList.toggle('on', st.open)); } };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
