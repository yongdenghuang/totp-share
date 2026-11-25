"""合租账本导出 Excel（服务器端）。和网页 app.js 里的 exportSheets / makeXlsx 生成同样的表，
给 iOS App 用（App 里没有浏览器那一套，直接下载这个文件）。只用标准库。

build(state, groups, months, yearly) -> xlsx 的字节
  state  : 账本 JSON（和 hezu_state 里存的一样）
  groups : [{"id", "name"}]，顺序就是分组顺序
  months : 升序的月份列表；yearly 为真时多一张「年度汇总」，各表多一列「月份」
"""
import io
import re
import zipfile
from datetime import date

XML_HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
NSM = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
NSR = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
NSP = "http://schemas.openxmlformats.org/package/2006/relationships"
CT = "application/vnd.openxmlformats-officedocument.spreadsheetml."
ISO = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def num(v):
    if isinstance(v, bool):
        return 0.0
    if isinstance(v, (int, float)):
        return float(v)
    try:
        return float(str(v or "").replace(",", "").replace("，", "").replace("¥", "").strip() or 0)
    except ValueError:
        return 0.0


def plain(v):
    v = round(num(v), 2)
    return str(int(v)) if v == int(v) else str(v)


class D:
    """日期格子"""
    def __init__(self, iso):
        self.iso = iso


class B:
    """加粗格子"""
    def __init__(self, v):
        self.v = v


def d(iso):
    return D(iso) if ISO.match(iso or "") else (iso or "")


def ym_label(ym):
    y, m = ym.split("-")
    return f"{y} 年 {int(m)} 月"


def card_label(c, full=False):
    if not c:
        return ""
    digits = str(c.get("number") or "").replace(" ", "")
    base = c.get("number") or ""
    if not full and re.fullmatch(r"\d{8,}", digits):
        base = "•••• " + digits[-4:]
    s = " · ".join(x for x in (base, c.get("note") or "") if x)
    return s or "未填卡号"


# ---------- 计算（和网页一样） ----------
def income(sh, r):
    if sh.get("mode") == "members":
        return sum(num(m.get("amount")) for m in r.get("members") or [])
    return num(r.get("unitPrice")) * num(r.get("count"))


def row_cost(sh, r):
    return num(r.get("unitCost")) * num(r.get("count")) if sh.get("mode") == "resale" else num(r.get("cost"))


def heads(sh, r):
    return len(r.get("members") or []) if sh.get("mode") == "members" else num(r.get("count"))


def zero():
    return {"n": 0, "heads": 0.0, "income": 0.0, "cost": 0.0, "profit": 0.0}


def stats(sh, rows):
    s = zero()
    for r in rows:
        if not r.get("stopped"):
            s["n"] += 1
        s["heads"] += heads(sh, r)
        s["income"] += income(sh, r)
        s["cost"] += row_cost(sh, r)
    s["profit"] = s["income"] - s["cost"]
    return s


def add(a, b):
    for k in a:
        a[k] += b[k]
    return a


class Book:
    def __init__(self, state, groups):
        self.S = state
        self.G = groups
        self.issuers = state.get("issuers") or []
        self.cards = state.get("cards") or []

    def rows(self, ym, sid):
        return ((self.S["months"].get(ym) or {}).get("rows") or {}).get(sid) or []

    def issuer(self, iid):
        return next((i for i in self.issuers if i.get("id") == iid), None)

    def groups_of(self, sh):
        """分组表自己的分组（sheet.groups）；老数据没有的话用共用的那套。"""
        own = sh.get("groups")
        return own if isinstance(own, list) else self.G

    def card(self, cid):
        return next((c for c in self.cards if c.get("id") == cid), None)

    def breakdown(self, ym):
        out = []
        for sh in self.S["sheets"]:
            rows = self.rows(ym, sh["id"])
            if sh.get("grouped"):
                ids = {g["id"] for g in self.groups_of(sh)}
                for g in self.groups_of(sh):
                    mine = [r for r in rows if r.get("group") == g["id"]]
                    out.append({"key": "g:" + g["id"], "label": g["name"], "sheet": sh["id"], "rows": len(mine), "st": stats(sh, mine)})
                loose = [r for r in rows if r.get("group") not in ids]
                if loose:
                    out.append({"key": "loose:" + sh["id"], "label": "未分组", "sheet": sh["id"], "rows": len(loose), "st": stats(sh, loose)})
            else:
                out.append({"key": "s:" + sh["id"], "label": sh.get("name") or "", "sheet": sh["id"], "rows": len(rows), "st": stats(sh, rows)})
        return out

    def month_total(self, ym):
        t = zero()
        for p in self.breakdown(ym):
            add(t, p["st"])
        return t

    def card_stats(self, ym):
        by_issuer, by_card, none = {}, {}, {"n": 0, "cost": 0.0}
        for sh in self.S["sheets"]:
            for r in self.rows(ym, sh["id"]):
                c = row_cost(sh, r)
                if not r.get("issuerId"):
                    if c:
                        none["n"] += 1
                        none["cost"] += c
                    continue
                a = by_issuer.setdefault(r["issuerId"], {"n": 0, "cost": 0.0})
                a["n"] += 1
                a["cost"] += c
                if r.get("cardId"):
                    b = by_card.setdefault(r["cardId"], {"n": 0, "cost": 0.0})
                    b["n"] += 1
                    b["cost"] += c
        return by_issuer, by_card, none

    # ---------- 各张表 ----------
    def sheets(self, months, yearly):
        out = []
        MH = ["月份"] if yearly else []

        def M(ym):
            return [f"{int(ym.split('-')[1])} 月"] if yearly else []

        if yearly:
            cols = []
            for ym in months:
                for p in self.breakdown(ym):
                    if not any(c["key"] == p["key"] for c in cols):
                        cols.append({"key": p["key"], "label": p["label"]})
            sums = [0.0] * len(cols)
            tot = zero()
            rows = []
            for ym in months:
                bd = self.breakdown(ym)
                t = self.month_total(ym)
                add(tot, t)
                line = [ym_label(ym)]
                for i, c in enumerate(cols):
                    p = next((x for x in bd if x["key"] == c["key"]), None)
                    v = p["st"]["profit"] if p else 0
                    sums[i] += v
                    line.append(v)
                rows.append(line + [t["income"], t["cost"], t["profit"]])
            rows.append([B("全年合计")] + [B(s) for s in sums] + [B(tot["income"]), B(tot["cost"]), B(tot["profit"])])
            out.append({"name": "年度汇总", "head": ["月份"] + [c["label"] + " 利润" for c in cols] + ["收费合计", "续费成本合计", "利润合计"], "rows": rows})

        prof = []
        for ym in months:
            bd = self.breakdown(ym)
            total = zero()
            alln = 0
            for sh in self.S["sheets"]:
                sub = zero()
                n = 0
                for p in (x for x in bd if x["sheet"] == sh["id"]):
                    add(sub, p["st"])
                    n += p["rows"]
                    if sh.get("grouped"):
                        prof.append(M(ym) + [p["label"], p["rows"], p["st"]["heads"], p["st"]["income"], p["st"]["cost"], p["st"]["profit"]])
                line = [(sh.get("name") or "") + (" 小计" if sh.get("grouped") else ""), n, sub["heads"], sub["income"], sub["cost"], sub["profit"]]
                prof.append(M(ym) + ([B(x) for x in line] if sh.get("grouped") else line))
                add(total, sub)
                alln += n
            prof.append(M(ym) + [B(x) for x in ["全部合计", alln, total["heads"], total["income"], total["cost"], total["profit"]]])
        out.append({"name": "各类利润" if yearly else "利润汇总", "head": MH + ["类别", "账号数", "收费人数", "收费", "续费成本", "利润"], "rows": prof})

        for sh in self.S["sheets"]:
            order = {g["id"]: i for i, g in enumerate(self.groups_of(sh))}
            members, resale = sh.get("mode") == "members", sh.get("mode") == "resale"
            rows = []
            for ym in months:
                lst = list(self.rows(ym, sh["id"]))
                if sh.get("grouped"):
                    lst = [r for _, r in sorted(enumerate(lst), key=lambda x: (order.get(x[1].get("group"), 9999), x[0]))]
                for r in lst:
                    g = next((x for x in self.groups_of(sh) if x["id"] == r.get("group")), None)
                    it, c, inc = self.issuer(r.get("issuerId")), self.card(r.get("cardId")), income(sh, r)
                    line = M(ym) + ([g["name"] if g else "未分组"] if sh.get("grouped") else [])
                    line += [r.get("account") or "", d(r.get("renew")), it.get("name") if it else "", (it.get("country") or "") if it else "", card_label(c, True) if c else ""]
                    if members:
                        ms = r.get("members") or []
                        line += [" + ".join((m.get("name") or "") + plain(m.get("amount")) for m in ms), len(ms)]
                    else:
                        line += [num(r.get("unitPrice")), num(r.get("count"))]
                    if resale:
                        line += [num(r.get("unitCost")), inc, row_cost(sh, r), inc - row_cost(sh, r), r.get("note") or ""]
                    else:
                        line += [inc, num(r.get("cost")), inc - num(r.get("cost")), r.get("note") or "", "已停止" if r.get("stopped") else ""]
                    rows.append(line)
            head = MH + (["分组"] if sh.get("grouped") else []) + ["项目" if resale else "账号", "续费日期", "付款渠道" if resale else "续费卡信息", "国家 / 地区", "卡号"]
            head += ["收费情况（每人）", "收费人数"] if members else (["售价", "数量"] if resale else ["单价", "人数"])
            head += ["成本/份", "收费", "成本", "利润", "备注"] if resale else ["收费", "续费成本", "利润", "备注", "状态"]
            out.append({"name": sh.get("name") or "表", "head": head, "rows": rows})

        spend = []
        for ym in months:
            by_issuer, by_card, none = self.card_stats(ym)
            for it in self.issuers:
                st = by_issuer.get(it.get("id"))
                if not st:
                    continue
                spend.append(M(ym) + [B(it.get("name")), it.get("country") or "", B("合计"), B(st["n"]), B(st["cost"])])
                n, cost = st["n"], st["cost"]
                for c in (x for x in self.cards if x.get("issuerId") == it.get("id")):
                    s = by_card.get(c.get("id"))
                    if not s:
                        continue
                    n -= s["n"]
                    cost -= s["cost"]
                    spend.append(M(ym) + [it.get("name"), it.get("country") or "", card_label(c, True), s["n"], s["cost"]])
                if n > 0:
                    spend.append(M(ym) + [it.get("name"), it.get("country") or "", "未指定卡号", n, cost])
            if none["cost"]:
                spend.append(M(ym) + ["没选卡的账号", "", "", none["n"], none["cost"]])
        out.append({"name": "按卡统计", "head": MH + ["卡信息", "国家 / 地区", "卡号", "账号数", "续费成本"], "rows": spend})

        card_rows = []
        for it in self.issuers:
            own = [c for c in self.cards if c.get("issuerId") == it.get("id")]
            if not own:
                card_rows.append([it.get("name"), it.get("country") or "", "", "", "", ""])
            for c in own:
                card_rows.append([it.get("name"), it.get("country") or "", c.get("number") or "", c.get("expiry") or "", c.get("cvc") or "", c.get("note") or ""])
        out.append({"name": "支付卡", "head": ["卡信息", "国家 / 地区", "卡号", "有效期", "CVC", "备注"], "rows": card_rows})

        def tag_names(v):
            return "，".join((t.get("name") if isinstance(t, dict) else str(t)) for t in v.get("tags") or [] if t)
        out.append({"name": "VPS", "head": ["主机", "官网", "IP", "端口", "密码", "部署", "流量及重置", "续费", "价格", "邮箱", "登录密码"],
                    "rows": [[v.get("host"), v.get("site"), v.get("ip"), v.get("port"), v.get("password"), tag_names(v), v.get("traffic"),
                              d(v.get("renew")), v.get("price"), v.get("email"), v.get("loginPassword")] for v in self.S.get("vps") or []]})
        return out


# ---------- 写 xlsx ----------
_BAD = re.compile("[\x00-\x08\x0b\x0c\x0e-\x1f￾￿]")


def esc(s):
    s = _BAD.sub("", str(s))
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


def col_name(i):
    s, i = "", i + 1
    while i > 0:
        i, r = divmod(i - 1, 26)
        s = chr(65 + r) + s
    return s


def date_serial(iso):
    y, m, dd = (int(x) for x in iso.split("-"))
    return (date(y, m, dd) - date(1899, 12, 30)).days


def sheet_xml(sh):
    all_rows = [[("head", t) for t in sh["head"]]] + sh["rows"]
    widths = {}
    parts = []
    for r, row in enumerate(all_rows):
        cells = []
        for i, c in enumerate(row):
            style, v = 0, c
            if isinstance(c, tuple):
                style, v = 1, c[1]
            elif isinstance(c, D):
                style, v = 3, date_serial(c.iso)
            elif isinstance(c, B):
                style, v = 2, c.v
            if v is None or v == "":
                continue
            if isinstance(v, float):
                v = round(v, 2)
                if v == int(v):
                    v = int(v)
            ref = f"{col_name(i)}{r + 1}"
            shown = "2026/12/31" if style == 3 else str(v)
            widths[i] = max(widths.get(i, 0), sum(2 if ord(ch) > 255 else 1 for ch in shown))
            if isinstance(v, (int, float)) and not isinstance(v, bool):
                cells.append(f'<c r="{ref}" s="{style}"><v>{v}</v></c>')
            else:
                cells.append(f'<c r="{ref}" s="{style}" t="inlineStr"><is><t xml:space="preserve">{esc(v)}</t></is></c>')
        parts.append(f'<row r="{r + 1}">' + "".join(cells) + "</row>")
    cols = "".join(f'<col min="{i + 1}" max="{i + 1}" width="{min(60, max(8, widths.get(i, 0) + 3))}" customWidth="1"/>' for i in range(len(sh["head"])))
    return (XML_HEAD + f'<worksheet xmlns="{NSM}"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
            f"<cols>{cols}</cols><sheetData>{''.join(parts)}</sheetData></worksheet>")


STYLES = (XML_HEAD + f'<styleSheet xmlns="{NSM}"><fonts count="2"><font><sz val="11"/><name val="Arial"/></font><font><b/><sz val="11"/><name val="Arial"/></font></fonts>'
          '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFE4E7F5"/><bgColor indexed="64"/></patternFill></fill></fills>'
          '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
          '<cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>'
          '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs>'
          '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>')


def make_xlsx(sheets):
    used = set()
    for sh in sheets:   # 工作表名：最长 31 个字，不能有 []:*?/\，不能重名
        base = re.sub(r"[\[\]:*?/\\]", " ", str(sh["name"])).strip()[:31] or "Sheet"
        n, k = base, 2
        while n.lower() in used:
            n = base[:28] + f" {k}"
            k += 1
        used.add(n.lower())
        sh["safe"] = n
    files = [
        ("[Content_Types].xml", XML_HEAD + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
         f'<Override PartName="/xl/workbook.xml" ContentType="{CT}sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="{CT}styles+xml"/>'
         + "".join(f'<Override PartName="/xl/worksheets/sheet{i + 1}.xml" ContentType="{CT}worksheet+xml"/>' for i in range(len(sheets))) + "</Types>"),
        ("_rels/.rels", XML_HEAD + f'<Relationships xmlns="{NSP}"><Relationship Id="rId1" Type="{NSR}/officeDocument" Target="xl/workbook.xml"/></Relationships>'),
        ("xl/workbook.xml", XML_HEAD + f'<workbook xmlns="{NSM}" xmlns:r="{NSR}"><sheets>'
         + "".join(f'<sheet name="{esc(sh["safe"])}" sheetId="{i + 1}" r:id="rId{i + 1}"/>' for i, sh in enumerate(sheets)) + "</sheets></workbook>"),
        ("xl/_rels/workbook.xml.rels", XML_HEAD + f'<Relationships xmlns="{NSP}">'
         + "".join(f'<Relationship Id="rId{i + 1}" Type="{NSR}/worksheet" Target="worksheets/sheet{i + 1}.xml"/>' for i in range(len(sheets)))
         + f'<Relationship Id="rId{len(sheets) + 1}" Type="{NSR}/styles" Target="styles.xml"/></Relationships>'),
        ("xl/styles.xml", STYLES),
    ] + [(f"xl/worksheets/sheet{i + 1}.xml", sheet_xml(sh)) for i, sh in enumerate(sheets)]
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for name, text in files:
            z.writestr(name, text.encode("utf-8"))
    return buf.getvalue()


def build(state, groups, months, yearly):
    return make_xlsx(Book(state, groups).sheets(months, yearly))
