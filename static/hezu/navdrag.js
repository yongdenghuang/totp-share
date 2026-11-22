'use strict';
// 左侧导航：拖分类名调整大分类的顺序；拖某一项调整位置，也能拖到别的分类里（放到分类名上或空白处就接在那个分类最后）。
// 分类名双击或点铅笔可以改名；每一项鼠标移上去右边也有铅笔，点了改这一项的名字
// （表的名字就是账本里表的名字；其他页面的名字存在服务器 nav_order 的 names 里，留空恢复默认）。
// 用事件委托挂在 document 上：账本页每次重画导航也不用重新绑定。
// 账本里的表的先后顺序也跟着存（hz-sheet-order 事件由账本页自己处理，其他页面直接请求服务器）。
(function () {
  const API = '/admin/hezu/api/';
  let drag = null;   // { el, kind: 'sec' | 'item' }
  const clear = () => document.querySelectorAll('.side .drop-before, .side .drop-after, .side .drop-into').forEach(x => x.classList.remove('drop-before', 'drop-after', 'drop-into'));
  const horizontal = () => window.innerWidth <= 880;
  const itemsOf = sec => Array.from(sec.querySelectorAll('.nav[data-item]'));

  // 返回 { el, mode: 'item' | 'sec' }：放到某一项前后，或者接在某个分类的最后
  function target(e) {
    if (!drag || !e.target.closest) return null;
    if (drag.kind === 'sec') {
      const sec = e.target.closest('.side .nav-sec');
      return sec && sec !== drag.el ? { el: sec, mode: 'sec' } : null;
    }
    const it = e.target.closest('.side .nav[data-item]');
    if (it) return it === drag.el ? null : { el: it, mode: 'item' };
    const sec = e.target.closest('.side .nav-sec');
    return sec ? { el: sec, mode: 'end' } : null;
  }
  function after(e, el) {
    const r = el.getBoundingClientRect();
    return horizontal() ? e.clientX > r.left + r.width / 2 : e.clientY > r.top + r.height / 2;
  }
  function show(t, e) {
    if (t.mode === 'sec') return (t.el.querySelector('.nav-label') || t.el).classList.add(after(e, t.el) ? 'drop-after' : 'drop-before');
    if (t.mode === 'item') return t.el.classList.add(after(e, t.el) ? 'drop-after' : 'drop-before');
    const its = itemsOf(t.el).filter(x => x !== drag.el);
    if (its.length) its[its.length - 1].classList.add('drop-after');
    else (t.el.querySelector('.nav-label') || t.el).classList.add('drop-into');
  }

  document.addEventListener('dragstart', e => {
    if (document.querySelector('.side .nav-label input, .side .nav-item-input')) return e.preventDefault();   // 正在改名
    const label = e.target.closest && e.target.closest('.side .nav-sec > .nav-label');
    const item = !label && e.target.closest && e.target.closest('.side .nav[data-item]');
    if (!label && !item) return;
    drag = label ? { el: label.parentElement, kind: 'sec' } : { el: item, kind: 'item' };
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
    clear(); show(t, e);
  });
  document.addEventListener('drop', e => {
    const t = target(e);
    if (!t) return;
    e.preventDefault();
    const d = drag;
    clear();
    if (t.mode === 'sec') {
      t.el.parentElement.insertBefore(d.el, after(e, t.el) ? t.el.nextSibling : t.el);
      return saveNav();
    }
    if (t.mode === 'item') t.el.parentElement.insertBefore(d.el, after(e, t.el) ? t.el.nextSibling : t.el);
    else {
      const its = itemsOf(t.el).filter(x => x !== d.el);
      const ref = its.length ? its[its.length - 1].nextSibling : t.el.querySelector('.nav-label').nextSibling;
      t.el.insertBefore(d.el, ref);
    }
    saveNav();
    if (d.el.dataset.sheet) {   // 账本里表的先后顺序 = 导航上从上到下的顺序
      const ids = Array.from(document.querySelectorAll('.side .nav[data-sheet]')).map(x => x.dataset.item);
      const ev = new CustomEvent('hz-sheet-order', { detail: ids, cancelable: true });
      if (document.dispatchEvent(ev)) post('sheet-order', { order: ids });   // 没人接手（不在账本页）就自己存
    }
  });

  function currentOrder() {
    const secs = Array.from(document.querySelectorAll('.side .nav-sec'));
    const items = {};
    secs.forEach(s => { items[s.dataset.sec] = itemsOf(s).map(x => x.dataset.item); });
    return { sections: secs.map(s => s.dataset.sec), items };
  }
  let navState = null;   // 服务器回来的完整顺序和名字（账本页重画时用）
  function saveNav(extra) {
    document.querySelectorAll('.side .nav-sec').forEach(sec => {   // 折叠时显示的数量
      const c = sec.querySelector('.nav-fold-count'); if (c) c.textContent = String(itemsOf(sec).length);
    });
    const order = Object.assign(currentOrder(), extra || {});
    const local = Object.assign({}, navState || {}, currentOrder());
    if (extra && extra.labels) local.labels = Object.assign({}, (navState || {}).labels, extra.labels);
    if (extra && extra.names) local.names = Object.assign({}, (navState || {}).names, extra.names);
    if (extra && extra.collapsed) local.collapsed = extra.collapsed;
    if (extra && extra.colors) local.colors = Object.assign({}, (navState || {}).colors, extra.colors);
    document.dispatchEvent(new CustomEvent('hz-nav-order', { detail: local }));   // 账本页记下来，重画导航时用
    navState = local;
    post('nav-order', order, d => {
      if (d && d.navOrder) { navState = d.navOrder; document.dispatchEvent(new CustomEvent('hz-nav-order', { detail: d.navOrder })); }
    });
  }

  // ---- 改名、换颜色 ----
  const COLORS = ['purple', 'blue', 'teal', 'amber', 'pink', 'green', 'red', 'gray'];
  const COLOR_NAMES = { purple: '紫', blue: '蓝', teal: '青', amber: '橙', pink: '粉', green: '绿', red: '红', gray: '灰' };
  function rename(label) {
    if (label.querySelector('input')) return;
    const text = label.querySelector('.nav-label-text'), sec = label.parentElement.dataset.sec;
    const old = text.textContent;
    const inp = document.createElement('input');
    inp.className = 'nav-label-input'; inp.value = old; inp.maxLength = 20; inp.setAttribute('aria-label', '分类名');
    label.draggable = false; label.classList.add('editing');
    text.hidden = true; label.insertBefore(inp, text);
    // 改名时下面出一排颜色，点一下就换这个板块的颜色
    const secEl = label.parentElement;
    const dots = document.createElement('div');
    dots.className = 'nav-colors';
    COLORS.forEach(c => {
      const d = document.createElement('button');
      d.type = 'button'; d.className = 'nav-color' + (secEl.dataset.color === c ? ' on' : ''); d.dataset.c = c;
      d.title = COLOR_NAMES[c]; d.setAttribute('aria-label', '颜色：' + COLOR_NAMES[c]);
      d.addEventListener('mousedown', e => e.preventDefault());      // 不让输入框失去焦点
      d.addEventListener('click', e => {
        e.stopPropagation();
        secEl.dataset.color = c;
        dots.querySelectorAll('.nav-color').forEach(x => x.classList.toggle('on', x === d));
        saveNav({ colors: { [sec]: c } });
      });
      dots.appendChild(d);
    });
    label.after(dots);
    inp.focus(); inp.select();
    let done = false;
    const finish = save => {
      if (done) return; done = true;
      const v = inp.value.replace(/\s+/g, ' ').trim();
      inp.remove(); dots.remove(); text.hidden = false; label.draggable = true; label.classList.remove('editing');
      if (!save || v === old) return;
      text.textContent = v || old;   // 留空 = 恢复默认名字，服务器回来后会更新
      const btn = label.querySelector('.nav-rename');
      if (btn) btn.setAttribute('aria-label', '给「' + text.textContent + '」改名');
      saveNav({ labels: { [sec]: v } });
    };
    inp.addEventListener('keydown', e => {
      if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); finish(true); }
      else if (e.key === 'Escape') { e.preventDefault(); finish(false); }
    });
    inp.addEventListener('blur', () => finish(true));
    ['click', 'mousedown', 'dblclick'].forEach(t => inp.addEventListener(t, e => e.stopPropagation()));
  }
  document.addEventListener('click', e => {
    const b = e.target.closest && e.target.closest('.side .nav-rename');
    if (!b) return;
    e.preventDefault(); e.stopPropagation();
    rename(b.closest('.nav-label'));
  });
  // 给某一项改名：输入框放在这一项的位置上（不放进链接/按钮里面，免得点输入框就跳走）
  function renameItem(item) {
    if (document.querySelector('.side .nav-item-input')) return;
    const text = item.querySelector('.nav-text'), id = item.dataset.item, sheet = !!item.dataset.sheet;
    if (!text) return;
    const old = text.textContent;
    const inp = document.createElement('input');
    inp.className = 'nav-item-input'; inp.value = old; inp.maxLength = sheet ? 40 : 20; inp.setAttribute('aria-label', '名字');
    item.hidden = true;
    item.parentElement.insertBefore(inp, item);
    inp.focus(); inp.select();
    let done = false;
    const finish = save => {
      if (done) return; done = true;
      const v = inp.value.replace(/\s+/g, ' ').trim();
      inp.remove(); item.hidden = false;
      if (!save || v === old) return;
      if (sheet) {
        if (!v) return;                                   // 表必须有名字
        text.textContent = v;
        const ev = new CustomEvent('hz-sheet-rename', { detail: { id, name: v }, cancelable: true });
        if (document.dispatchEvent(ev)) post('sheet-rename', { id, name: v });   // 不在账本页就直接改服务器上的账本
      } else {
        text.textContent = v || text.dataset.default || old;
        saveNav({ names: { [id]: v } });
      }
      const b = item.querySelector('.nav-edit');
      if (b) b.setAttribute('aria-label', '给「' + text.textContent + '」改名');
    };
    inp.addEventListener('keydown', e => {
      if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); finish(true); }
      else if (e.key === 'Escape') { e.preventDefault(); finish(false); }
    });
    inp.addEventListener('blur', () => finish(true));
  }
  // 捕获阶段接住：不让点击传到这一项本身（否则会打开那一页）
  document.addEventListener('click', e => {
    const b = e.target.closest && e.target.closest('.side .nav-edit');
    if (!b) return;
    e.preventDefault(); e.stopPropagation();
    renameItem(b.closest('.nav[data-item]'));
  }, true);

  // ---- 折叠 / 展开 ----
  // 点板块名折叠：只留板块名（右边显示有几项），当前打开的那一项照样显示。网页和 App 一起记住。
  function toggleSec(sec) {
    const folded = sec.classList.toggle('collapsed');
    const label = sec.querySelector('.nav-label');
    if (label) label.setAttribute('aria-expanded', folded ? 'false' : 'true');
    const collapsed = Array.from(document.querySelectorAll('.side .nav-sec.collapsed')).map(s => s.dataset.sec);
    saveNav({ collapsed });
  }
  document.addEventListener('click', e => {
    const l = e.target.closest && e.target.closest('.side .nav-sec > .nav-label');
    if (!l || e.target.closest('.nav-rename, input') || l.querySelector('input')) return;
    toggleSec(l.parentElement);
  });
  document.addEventListener('keydown', e => {
    const l = e.target.closest && e.target.closest('.side .nav-sec > .nav-label');
    if (!l || e.target !== l || (e.key !== 'Enter' && e.key !== ' ')) return;
    e.preventDefault(); toggleSec(l.parentElement);
  });

  document.addEventListener('dblclick', e => {
    const l = e.target.closest && e.target.closest('.side .nav-sec > .nav-label');
    if (l) { e.preventDefault(); rename(l); }
  });
  // 服务器画的页面：改名后把新名字同步到页面上（留空恢复默认时用得上）
  document.addEventListener('hz-nav-order', e => {
    const names = e.detail && e.detail.names;
    if (names) document.querySelectorAll('.side .nav[data-item]:not([data-sheet]) .nav-text').forEach(t => {
      t.textContent = names[t.closest('.nav').dataset.item] || t.dataset.default || t.textContent;
    });
    const labels = e.detail && e.detail.labels;
    if (!labels) return;
    document.querySelectorAll('.side .nav-sec').forEach(s => {
      const t = s.querySelector('.nav-label-text');
      if (t && labels[s.dataset.sec] && !s.querySelector('.nav-label input')) t.textContent = labels[s.dataset.sec];
    });
  });

  function csrf() {
    const el = document.querySelector('[data-csrf]');
    return el ? el.dataset.csrf : '';
  }
  // 一个接一个发：连着拖两次时，后一次的顺序一定最后到服务器
  let queue = Promise.resolve();
  function post(path, body, then) { queue = queue.then(() => send1(path, body, then)); return queue; }
  async function send1(path, body, then) {
    const send = token => fetch(API + path, { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json', 'X-CSRFToken': token }, body: JSON.stringify(body) });
    try {
      let r = await send(csrf());
      if (r.status === 400) {   // 防伪令牌过期了：换一个再试
        const c = await fetch(API + 'context', { credentials: 'same-origin' });
        if (c.ok) { const d = await c.json(); document.querySelectorAll('[data-csrf]').forEach(x => { x.dataset.csrf = d.csrf; }); r = await send(d.csrf); }
      }
      if (!r.ok) throw new Error(r.status === 401 ? '登录已过期' : '没保存上');
      if (then) then(await r.json().catch(() => null));
    } catch (err) {
      alert('导航' + err.message + '，刷新页面后会恢复原来的样子。');
    }
  }
})();
