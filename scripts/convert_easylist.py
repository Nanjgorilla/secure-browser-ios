#!/usr/bin/env python3
"""EasyList/EasyPrivacy (ABP構文) → WebKit content-blocker JSON 変換。
対応: ||domain^ / |http / 一般URLパターン / @@例外 / $third-party,$script,$image,$stylesheet,$domain= / 汎用要素隠し ##sel
1ファイル最大 MAX 件で分割。"""
import json, re, sys, urllib.request, os
MAX = 140000
LISTS = {"easylist": "https://easylist.to/easylist/easylist.txt",
         "easyprivacy": "https://easylist.to/easylist/easyprivacy.txt"}
TYPES = {"script":"script","image":"image","stylesheet":"style-sheet","font":"font",
         "media":"media","subdocument":"document","xmlhttprequest":"raw","websocket":"raw","other":"raw","ping":"raw","popup":"popup","document":"document"}
def esc(s): return re.sub(r'([.+?{}()\[\]\\$|])', r'\\\1', s)
def pattern_to_regex(p):
    if p.startswith("/") and p.endswith("/") and len(p) > 2: return None  # ABP regex: skip (WebKit subset differs)
    r = ""
    if p.startswith("||"): r = r"^[^:]+://+([^:/]+\.)?"; p = p[2:]
    elif p.startswith("|"): r = "^"; p = p[1:]
    end = ""
    if p.endswith("|"): end = "$"; p = p[:-1]
    for ch in p:
        if ch == "*": r += ".*"
        elif ch == "^": r += "[/:?=&]"   # 近似 (WebKitは|や$を含む交替不可)
        else: r += esc(ch)
    r += end
    if not r or r in ("^", ".*"): return None
    try: re.compile(r)
    except re.error: return None
    if not r.isascii(): return None
    return r
def convert(text):
    out = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith(("!", "[")): continue
        if "#@#" in line or "#?#" in line or "#$#" in line or "#%#" in line: continue
        if "##" in line:
            dom, sel = line.split("##", 1)
            if dom or not sel.isascii() or ":" in sel and ":not" not in sel: continue
            out.append({"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":sel}})
            continue
        exc = line.startswith("@@")
        if exc: line = line[2:]
        opts = {}
        if "$" in line:
            line, o = line.rsplit("$", 1)
            for kv in o.split(","):
                k, _, v = kv.partition("="); opts[k] = v
        bad = {"csp","redirect","rewrite","removeparam","replace","generichide","elemhide","genericblock","sitekey","header","permissions","match-case","badfilter","important","all","inline-script","inline-font","webrtc","object","object-subrequest","to","method"}
        if any(k.lstrip("~") in bad for k in opts): continue
        rx = pattern_to_regex(line)
        if not rx: continue
        trig = {"url-filter": rx}
        rt = [TYPES[k] for k in opts if k in TYPES]
        if any(k.startswith("~") for k in opts if k.lstrip("~") in TYPES): continue
        if rt: trig["resource-type"] = sorted(set(rt))
        if "third-party" in opts: trig["load-type"] = ["third-party"]
        if "~third-party" in opts: trig["load-type"] = ["first-party"]
        if "domain" in opts:
            inc = [d for d in opts["domain"].split("|") if d and not d.startswith("~")]
            exl = [d[1:] for d in opts["domain"].split("|") if d.startswith("~")]
            if inc and exl: continue
            if not all(d.isascii() for d in inc+exl): continue
            if inc: trig["if-domain"] = ["*"+d.lower() for d in inc]
            if exl: trig["unless-domain"] = ["*"+d.lower() for d in exl]
        out.append({"trigger": trig, "action": {"type": "ignore-previous-rules" if exc else "block"}})
    # 例外ルールは後ろに置く必要がある
    return [r for r in out if r["action"]["type"]!="ignore-previous-rules"] + [r for r in out if r["action"]["type"]=="ignore-previous-rules"]
def main(dest):
    os.makedirs(dest, exist_ok=True)
    for name, url in LISTS.items():
        txt = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}), timeout=60).read().decode("utf-8", "ignore")
        rules = convert(txt)
        blocks = [r for r in rules if r["action"]["type"]!="ignore-previous-rules"]
        excs = [r for r in rules if r["action"]["type"]=="ignore-previous-rules"]
        chunk = MAX - len(excs) if len(excs) < MAX//2 else MAX//2
        parts = [blocks[i:i+chunk] for i in range(0, len(blocks), chunk)] or [[]]
        for i, p in enumerate(parts):
            fn = f"{dest}/{name}-{i+1}.json"
            json.dump(p + excs[:MAX-len(p)], open(fn, "w"), separators=(",", ":"))
            print(fn, len(p) + min(len(excs), MAX-len(p)))
if __name__ == "__main__": main(sys.argv[1] if len(sys.argv) > 1 else "SecureBrowser/Resources/Rules")
