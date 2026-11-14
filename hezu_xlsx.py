#!/usr/bin/env python3
"""把原来的 Excel（合租账号管理.xlsx）转成管理界面能用的数据。只用标准库。

命令行自查（不显示卡号和密码）:  python3 xlsx_import.py 文件.xlsx
"""
import datetime
import io
import re
import sys
import xml.etree.ElementTree as ET
import zipfile

NS = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'
RNS = '{http://schemas.openxmlformats.org/officeDocument/2006/relationships}'
MAX_UNZIPPED = 60 * 1024 * 1024

SECTION_NAMES = {'PRO': 'GPT Pro 20x', 'PLUS': 'GPT Plus'}
UNSORTED = '待分类'
VPS_FIELDS = {'主机': 'host', '官网': 'site', 'IP': 'ip', '端口': 'port', '密码': 'password', '部署': 'deploy',
              '流量及重置': 'traffic', '续费': 'renew', '价格': 'price', '邮箱': 'email'}


# ---------- 读 xlsx ----------

def col_num(letters):
    n = 0
    for ch in letters:
        n = n * 26 + (ord(ch) - 64)
    return n


def split_ref(ref):
    m = re.match(r'^([A-Z]+)(\d+)$', ref)
    return int(m.group(2)), col_num(m.group(1))


def clean_number(text):
    """去掉 Excel 浮点尾巴: 12.130000000000001 -> 12.13"""
    if re.match(r'^-?\d+\.\d{6,}$', text):
        return ('%.4f' % float(text)).rstrip('0').rstrip('.')
    return text


def read_workbook(data):
    z = zipfile.ZipFile(io.BytesIO(data))
    if sum(i.file_size for i in z.infolist()) > MAX_UNZIPPED:
        raise ValueError('文件太大')
    names = set(z.namelist())
    strings = []
    if 'xl/sharedStrings.xml' in names:
        for si in ET.fromstring(z.read('xl/sharedStrings.xml')).findall(NS + 'si'):
            strings.append(''.join(t.text or '' for t in si.iter(NS + 't')))
    rels = {r.get('Id'): r.get('Target')
            for r in ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))}
    sheets = []
    for s in ET.fromstring(z.read('xl/workbook.xml')).find(NS + 'sheets'):
        target = rels[s.get(RNS + 'id')]
        path = target.lstrip('/') if target.startswith('/') else 'xl/' + target
        root = ET.fromstring(z.read(path))
        cells = {}
        for c in root.iter(NS + 'c'):
            t, v = c.get('t'), c.find(NS + 'v')
            if t == 's' and v is not None:
                val = strings[int(v.text)]
            elif t == 'inlineStr':
                val = ''.join(x.text or '' for x in c.iter(NS + 't'))
            elif v is not None and v.text is not None:
                val = clean_number(v.text) if t in (None, 'n') else v.text
            else:
                continue
            val = val.strip()
            if val:
                cells[split_ref(c.get('r'))] = val
        merges = []
        mc = root.find(NS + 'mergeCells')
        if mc is not None:
            for m in mc:
                a, _, b = m.get('ref').partition(':')
                r1, c1 = split_ref(a)
                r2, c2 = split_ref(b or a)
                merges.append((r1, c1, r2, c2))
        sheets.append((s.get('name'), cells, merges))
    return sheets


# ---------- 取值 ----------

def to_num(text):
    try:
        return float(str(text).replace(',', '').replace('¥', '').replace('$', '').strip())
    except (TypeError, ValueError):
        return None


def tidy(n):
    return int(n) if float(n).is_integer() else round(n, 2)


def serial_date(text):
    n = to_num(text)
    if n is not None and 30000 < n < 80000 and float(n).is_integer():
        return (datetime.date(1899, 12, 30) + datetime.timedelta(days=int(n))).isoformat()
    return ''


def parse_md(text, today):
    """'11.14' / '11月14日' -> 离今天最近的那个 11 月 14 日。"""
    m = re.match(r'^(\d{1,2})[./月-](\d{1,2})日?$', (text or '').strip())
    if not m:
        return ''
    mo, d = int(m.group(1)), int(m.group(2))
    best = None
    for y in (today.year - 1, today.year, today.year + 1):
        try:
            dt = datetime.date(y, mo, d)
        except ValueError:
            continue
        if best is None or abs((dt - today).days) < abs((best - today).days):
            best = dt
    return best.isoformat() if best else ''


def parse_amounts(text):
    """'300' -> [300]   '50+30' -> [50, 30]   '700x2' -> [700, 700]"""
    out = []
    for part in re.split(r'[+＋,，、\s]+', str(text).strip()):
        if not part:
            continue
        m = re.match(r'^(\d+(?:\.\d+)?)[xX×*](\d+)$', part)
        if m:
            out += [float(m.group(1))] * min(int(m.group(2)), 50)
            continue
        n = to_num(part)
        if n is None:
            return []
        out.append(n)
    return out


def new_row(**kw):
    row = {'groupName': '', 'account': '', 'renew': '', 'cardInfo': '', 'cardNo': '',
           'members': [], 'unitPrice': 0, 'count': 0, 'cost': 0, 'note': '', 'stopped': False}
    row.update(kw)
    return row


# ---------- 各个表 ----------

def find_header(cells, word, max_row=3):
    for (r, c), v in cells.items():
        if r <= max_row and v == word:
            return r, c
    return None


def import_ai(cells, merges, today, warnings):
    hdr = find_header(cells, '账号')
    hrow, c_acc = hdr
    head = {v: c for (r, c), v in cells.items() if r == hrow}
    c_date = head.get('续费日期', c_acc + 1)
    c_card = head.get('卡信息', c_acc + 3)
    c_no = head.get('卡号', c_card + 1)
    c_use = head.get('使用人数', c_no + 1)
    c_m1 = head.get('收费人数', c_acc + 7)
    c_fee = max(c for v, c in head.items() if v == '收费') if '收费' in head else c_m1 + 5
    c_cost = head.get('成本', c_fee + 1)
    c_seq = head.get('序号', c_acc - 1)

    section = {}
    for (r, c), v in cells.items():
        if c != 1:
            continue
        r2 = r
        for (m1, mc1, m2, _) in merges:
            if mc1 == 1 and m1 == r:
                r2 = m2
        for rr in range(r, r2 + 1):
            section[rr] = v.strip().upper()

    rows, skipped, zero_price = [], [], 0
    for r in sorted({r for (r, _) in cells}):
        acc = cells.get((r, c_acc), '')
        if not acc or acc == '账号':
            continue
        date_text = cells.get((r, c_date), '')
        renew = serial_date(date_text) or parse_md(date_text, today)
        if '@' not in acc and not renew:
            skipped.append(acc)
            continue
        stopped = '停止' in acc or '停止' in date_text
        acc = re.sub(r'\s*停止(续费)?\s*', '', acc).strip()

        sec = section.get(r, '')
        fee_total = to_num(cells.get((r, c_fee)))
        raw = [(c, cells[(r, c)]) for c in range(c_m1, c_fee) if (r, c) in cells]
        amounts = []
        head_count = None
        if sec in SECTION_NAMES and len(raw) == 1 and raw[0][0] == c_m1:
            n = to_num(raw[0][1])
            if n is not None and float(n).is_integer() and 0 < n <= 20:
                head_count = int(n)
        if head_count:
            price = fee_total / head_count if fee_total else 0
            amounts = [price] * head_count
            if not price:
                zero_price += 1
        else:
            for _, text in raw:
                amounts += parse_amounts(text)
            if not amounts and fee_total:
                amounts = [fee_total]

        notes = []
        seq = cells.get((r, c_seq), '')
        if seq and not re.match(r'^\d+号?$', seq):
            notes.append(seq)
        for c in range(c_date + 1, c_card):
            if (r, c) in cells:
                notes.append(cells[(r, c)])
        users = cells.get((r, c_use), '')
        if users and to_num(users) is None:
            notes.append('使用：' + users)

        cost = to_num(cells.get((r, c_cost)))
        rows.append(new_row(
            groupName=SECTION_NAMES.get(sec, sec.title() if sec else UNSORTED),
            account=acc, renew=renew, stopped=stopped,
            cardInfo=cells.get((r, c_card), ''), cardNo=cells.get((r, c_no), ''),
            members=[{'name': '', 'amount': tidy(a), 'paid': True} for a in amounts],
            cost=tidy(cost) if cost else 0, note=' · '.join(notes)))

    if skipped:
        warnings.append('这些行不是账号、也没有续费日期，没有导入，需要的话请手动添加：' + '、'.join(skipped))
    if zero_price:
        warnings.append('有 %d 个账号原表只填了收费人数、没填金额，已按人数建好席位，金额为 0，请补填。' % zero_price)
    if any(r['groupName'] == UNSORTED for r in rows):
        warnings.append('原表里 PRO / PLUS 区块以外的账号放进了“%s”分组，请自己移到对应分组。' % UNSORTED)
    warnings.append('续费日期按“月.日”识别，年份取离今天最近的一年；原表是小数格式，'
                    '10 日、20 日、30 日可能被识别成 1 日、2 日、3 日，请核对。')
    return rows


def import_simple(cells):
    """Netflix / Spotify 这类：每行第一个带 @ 的格子当账号，其余当卡信息和备注。"""
    rows = []
    for r in sorted({r for (r, _) in cells}):
        vals = [cells[(r, c)] for c in sorted(c for (rr, c) in cells if rr == r)]
        idx = next((i for i, v in enumerate(vals) if '@' in v), None)
        if idx is None:
            continue
        rest = vals[:idx] + vals[idx + 1:]
        m = re.search(r'\d{13,19}', ' '.join(rest))
        rows.append(new_row(account=vals[idx], cardInfo=rest[0] if rest else '',
                            cardNo=m.group(0) if m else '', note=' · '.join(rest[1:])))
    return rows


def import_vps(cells, today, warnings):
    hrow = min(r for (r, _) in cells)
    cols = {c: VPS_FIELDS[v] for (r, c), v in cells.items() if r == hrow and v in VPS_FIELDS}
    rows = []
    for r in sorted({r for (r, _) in cells if r > hrow}):
        row = {f: '' for f in VPS_FIELDS.values()}
        for c, field in cols.items():
            row[field] = cells.get((r, c), '')
        if not any(row.values()):
            continue
        raw = row['renew']
        row['renew'] = serial_date(raw) or parse_md(raw, today)
        if raw and not row['renew']:
            warnings.append('VPS “%s” 的续费日期“%s”认不出来，请手动填。' % (row['host'], raw))
        rows.append(row)
    return rows


def parse(data, today=None):
    today = today or datetime.date.today()
    out = {'ai': [], 'sheets': {}, 'vps': [], 'warnings': []}
    for name, cells, merges in read_workbook(data):
        if not cells:
            continue
        header = {v for (r, _), v in cells.items() if r <= 3}
        if name.strip().lower() == 'vps' or ('主机' in header and 'IP' in header):
            out['vps'] += import_vps(cells, today, out['warnings'])
        elif '账号' in header and ('收费' in header or '成本' in header):
            out['ai'] += import_ai(cells, merges, today, out['warnings'])
        else:
            rows = import_simple(cells)
            if rows:
                out['sheets'][name.strip()] = rows
    return out


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    with open(sys.argv[1], 'rb') as f:
        res = parse(f.read())
    by_group = {}
    for r in res['ai']:
        by_group.setdefault(r['groupName'], []).append(r)
    for g, rows in by_group.items():
        income = sum(m['amount'] for r in rows for m in r['members'])
        cost = sum(r['cost'] for r in rows)
        print('AI / %s: %d 行, 收费 %s, 成本 %s, 利润 %s' % (g, len(rows), tidy(income), tidy(cost), tidy(income - cost)))
        for r in rows:
            print('   %-6s 续费 %-10s 卡号%s 席位 %s 成本 %s%s' % (
                r['account'][:3] + '…', r['renew'] or '-', '有' if r['cardNo'] else '无',
                [m['amount'] for m in r['members']], r['cost'], ' [停止]' if r['stopped'] else ''))
    for name, rows in res['sheets'].items():
        print('%s: %d 行' % (name, len(rows)))
    print('VPS: %d 行, 续费日期 %s' % (len(res['vps']), [v['renew'] for v in res['vps']]))
    for w in res['warnings']:
        print('提示:', w)


if __name__ == '__main__':
    main()
