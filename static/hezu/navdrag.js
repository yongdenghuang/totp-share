'use strict';
// 左侧导航拖动排序：拖分类名调整大分类的顺序，拖某一项调整它在本分类里的位置（不能拖到别的分类）。
// 用事件委托挂在 document 上：账本页每次重画导航也不用重新绑定。
// 「账号」分类里是账本的表：账本页自己处理（hz-sheet-order 事件），其他页面直接请求服务器改账本里的顺序。
(function () {
  const API = '/admin/hezu/api/';
  let drag = null;   // { el, kind: 'sec' | 'item', sec }
  const clear = () => document.querySelectorAll('.side .drop-before, .side .drop-after').forEach(x => x.classList.remove('drop-before', 'drop-after'));
  const horizontal = () => window.innerWidth <= 880;

  function target(e) {
    if (!drag) return null;
    if (drag.kind === 'sec') {
      const sec = e.target.closest && e.target.closest('.side .nav-sec');
      return sec && sec !== drag.el ? sec : null;
    }
    const it = e.target.closest && e.target.closest('.side .nav[data-item]');
    return it && it !== drag.el && it.closest('.nav-sec') === drag.sec ? it : null;
  }
  function after(e, el) {
    const r = el.getBoundingClientRect();
    return horizontal() ? e.clientX > r.left + r.width / 2 : e.clientY > r.top + r.height / 2;
  }
  function mark(el) { return drag.kind === 'sec' ? el.querySelector('.nav-label') || el : el; }

  document.addEventListener('dragstart', e => {
    const label = e.target.closest && e.target.closest('.side .nav-sec > .nav-label');
    const item = !label && e.target.closest && e.target.closest('.side .nav[data-item]');
    if (!label && !item) return;
    drag = label ? { el: label.parentElement, kind: 'sec' } : { el: item, kind: 'item', sec: item.closest('.nav-sec') };
    (label || item).classList.add('dragging');
    e.dataTransfer.effectAllowed = 'move';
    e.dataTransfer.setData('text/plain', label ? label.textContent : item.dataset.item);
  });
  document.addEventListener('dragend', () => {
    document.querySelectorAll('.side .dragging').forEach(x => x.classList.remove('dragging'));
    clear(); drag = null;
  });
  document.addEventListener('dragover', e => {
    const t = target(e);
    if (!t) return;
    e.preventDefault();
    clear();
    mark(t).classList.add(after(e, t) ? 'drop-after' : 'drop-before');
  });
  document.addEventListener('drop', e => {
    const t = target(e);
    if (!t) return;
    e.preventDefault();
    const a = after(e, t), d = drag;
    clear();
    t.parentElement.insertBefore(d.el, a ? t.nextSibling : t);
    if (d.kind === 'sec') return saveNav();
    const secId = d.sec.dataset.sec;
    const ids = Array.from(d.sec.querySelectorAll('.nav[data-item]')).map(x => x.dataset.item);
    if (secId === 'accounts') {
      const ev = new CustomEvent('hz-sheet-order', { detail: ids, cancelable: true });
      if (document.dispatchEvent(ev)) post('sheet-order', { order: ids });   // 没人接手（不在账本页）就自己存
    } else saveNav();
  });

  function currentOrder() {
    const secs = Array.from(document.querySelectorAll('.side .nav-sec'));
    const items = {};
    secs.forEach(s => { if (s.dataset.sec !== 'accounts') items[s.dataset.sec] = Array.from(s.querySelectorAll('.nav[data-item]')).map(x => x.dataset.item); });
    return { sections: secs.map(s => s.dataset.sec), items };
  }
  function saveNav() {
    const order = currentOrder();
    document.dispatchEvent(new CustomEvent('hz-nav-order', { detail: order }));   // 账本页记下来，重画导航时用
    post('nav-order', order);
  }

  function csrf() {
    const el = document.querySelector('[data-csrf]');
    return el ? el.dataset.csrf : '';
  }
  // 一个接一个发：连着拖两次时，后一次的顺序一定最后到服务器
  let queue = Promise.resolve();
  function post(path, body) { queue = queue.then(() => send1(path, body)); return queue; }
  async function send1(path, body) {
    const send = token => fetch(API + path, { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json', 'X-CSRFToken': token }, body: JSON.stringify(body) });
    try {
      let r = await send(csrf());
      if (r.status === 400) {   // 防伪令牌过期了：换一个再试
        const c = await fetch(API + 'context', { credentials: 'same-origin' });
        if (c.ok) { const d = await c.json(); document.querySelectorAll('[data-csrf]').forEach(x => { x.dataset.csrf = d.csrf; }); r = await send(d.csrf); }
      }
      if (!r.ok) throw new Error(r.status === 401 ? '登录已过期' : '没保存上');
    } catch (err) {
      alert('导航顺序' + err.message + '，刷新页面后会恢复原来的顺序。');
    }
  }
})();
