#!/usr/bin/env python3
"""Builds the product website from site-src/index.template.html and the static files in site/.

The template holds every sentence in all languages as adjacent <span class="en|ko|ja|zh"> groups. One page is written per
language, each containing only that language's text, so search engines and AI agents read clean single-language pages:
  /  (English)   /ko/   /ja/   /zh/
Each page gets its own <head> (title, description, canonical, hreflang, Open Graph, JSON-LD). Also written: sitemap.xml,
llms.txt and llms-full.txt. {{VERSION}} and {{SIZE}} are filled by Scripts/deploy-site.sh afterwards.

Usage: Scripts/build-site.py OUTPUT_DIR [--allow-missing]
  --allow-missing  a sentence without a translation falls back to English instead of failing the build
"""
import html
import json
import re
import shutil
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = "https://ieum.calmwork.today"
LANGS = ["en", "ko", "ja", "zh"]
PATH = {"en": "/", "ko": "/ko/", "ja": "/ja/", "zh": "/zh/"}
HREFLANG = {"en": "en", "ko": "ko", "ja": "ja", "zh": "zh-Hans"}
OG_LOCALE = {"en": "en_US", "ko": "ko_KR", "ja": "ja_JP", "zh": "zh_CN"}
NATIVE = {"en": "English", "ko": "한국어", "ja": "日本語", "zh": "中文"}

# Strings the page script needs, and the <head> of each page.
T = {
    "en": {
        "share": "Ieum: live captions and translation for meetings on Mac (English, Korean, Japanese, Chinese). Free, 100% on-device.",
        "copied": "Link copied", "downloads": "{n} downloads", "idle": "Press Start or ⌃⌥S",
        "play": "Play", "pause": "Pause", "listening": "Ieum · listening", "stopped": "Ieum · stopped",
    },
    "ko": {
        "share": "Ieum 이음: 회의에 실시간 자막과 번역을 띄워 주는 Mac 앱 (영·한·일·중, 무료, 100% 기기 내 처리)",
        "copied": "링크를 복사했습니다", "downloads": "{n}회 다운로드", "idle": "시작을 누르거나 ⌃⌥S를 누르세요",
        "play": "재생", "pause": "일시정지", "listening": "이음 · 듣는 중", "stopped": "이음 · 중지됨",
    },
    "ja": {
        "share": "Ieum（イウム）：Macの会議にリアルタイムの字幕と翻訳を表示（英語・韓国語・日本語・中国語、無料、端末内で完結）",
        "copied": "リンクをコピーしました", "downloads": "{n} 回ダウンロード", "idle": "「開始」または ⌃⌥S を押してください",
        "play": "再生", "pause": "一時停止", "listening": "Ieum · 聞き取り中", "stopped": "Ieum · 停止中",
    },
    "zh": {
        "share": "Ieum：为 Mac 上的会议实时显示字幕与翻译（英语、韩语、日语、中文，免费，全程在本机处理）",
        "copied": "链接已复制", "downloads": "已下载 {n} 次", "idle": "点击“开始”或按 ⌃⌥S",
        "play": "播放", "pause": "暂停", "listening": "Ieum · 正在聆听", "stopped": "Ieum · 已停止",
    },
}

HEAD = {
    "en": {
        "title": "Ieum 이음 · Live captions and translation for Mac (EN, KO, JA, ZH)",
        "description": "Live meeting captions and translation between English, Korean, Japanese and Chinese, fully on your Mac. Offline, no account, free and open source.",
        "og_title": "Ieum 이음 · Live captions and translation for meetings, in your language",
        "og_description": "Read the other side in your language while they read you in theirs. Fully on-device, free for Mac.",
    },
    "ko": {
        "title": "Ieum 이음 · Mac에서 영어·한국어·일본어·중국어 회의 실시간 자막과 번역",
        "description": "Ieum(이음)은 회의 중 상대의 말을 Mac 화면에 실시간 자막으로 띄우고 영어·한국어·일본어·중국어로 번역합니다. 인식과 번역은 모두 기기 안에서 처리되며 계정도 클라우드도 필요 없는 무료 오픈소스 앱입니다.",
        "og_title": "Ieum 이음 · 내 언어로 읽는 회의 실시간 자막과 번역",
        "og_description": "상대는 내 말을 상대의 언어로, 나는 상대의 말을 내 언어로 읽습니다. 100% 기기 안에서 동작하는 무료 Mac 앱.",
    },
    "ja": {
        "title": "Ieum（イウム）· Macで会議をリアルタイム字幕と翻訳に：英語・韓国語・日本語・中国語",
        "description": "Ieum（イウム）は、会議中の発言をMacの画面にリアルタイムで字幕表示し、英語・韓国語・日本語・中国語の間で翻訳します。音声認識も翻訳も端末内で完結。アカウント不要、クラウド不要、無料のオープンソースです。",
        "og_title": "Ieum（イウム）· 日本と韓国、中国、世界をつなぐ会議の字幕と翻訳",
        "og_description": "相手の言葉は自分の言語で、自分の言葉は相手の言語で。すべてMacの中で動く、無料の字幕・翻訳アプリ。",
    },
    "zh": {
        "title": "Ieum · 在 Mac 上为会议实时生成字幕与翻译：英语、韩语、日语、中文",
        "description": "Ieum（韩语“이음”，意为“连接”）在会议中把发言实时显示为 Mac 屏幕上的字幕，并在英语、韩语、日语和中文之间互译。语音识别与翻译全部在本机完成，无需账号、无需云端，免费开源。",
        "og_title": "Ieum · 连接中国、日本、韩国与世界的会议字幕与翻译",
        "og_description": "对方的话用你的语言读，你的话让对方用他们的语言读。全部在 Mac 本机运行，免费。",
    },
}

SPAN_OPEN = re.compile(r'<span class="(en|ko|ja|zh)"([^>]*)>')
TAG = re.compile(r"<(/?)span\b[^>]*>")


def find_groups(text):
    """Top-level language spans as (start, end, lang, inner), nesting-aware, and runs of adjacent ones as groups."""
    spans = []
    pos = 0
    while True:
        m = SPAN_OPEN.search(text, pos)
        if not m:
            break
        depth, end = 1, m.end()
        for t in TAG.finditer(text, m.end()):
            depth += -1 if t.group(1) else 1
            if depth == 0:
                end = t.end()
                inner = text[m.end():t.start()]
                break
        else:
            raise SystemExit(f"unclosed span near: {text[m.start():m.start() + 80]!r}")
        spans.append((m.start(), end, m.group(1), inner))
        pos = end
    groups, current = [], []
    for sp in spans:
        # a sentence in several languages: spans next to each other (only whitespace between), each language once
        touching = current and not text[current[-1][1]:sp[0]].strip()
        if touching and sp[2] not in {c[2] for c in current}:
            current.append(sp)
        else:
            if current:
                groups.append(current)
            current = [sp]
    if current:
        groups.append(current)
    return groups


def localize(text, lang, allow_missing, missing):
    out, last = [], 0
    for group in find_groups(text):
        by_lang = {sp[2]: sp for sp in group}
        chosen = by_lang.get(lang)
        if chosen is None:
            if not allow_missing:
                missing.append(by_lang.get("en", group[0])[3][:70])
            chosen = by_lang.get("en", group[0])
        out.append(text[last:group[0][0]])
        out.append(chosen[3])
        last = group[-1][1]
    out.append(text[last:])
    return "".join(out)


def plain(fragment):
    return html.unescape(re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", fragment))).strip()


def faq(page):
    items = re.findall(r"<details[^>]*>\s*<summary>(.*?)</summary>\s*<p>(.*?)</p>\s*</details>", page, flags=re.S)
    return [(plain(q), plain(a)) for q, a in items]


def json_ld(lang, page):
    head = HEAD[lang]
    app = {
        "@context": "https://schema.org",
        "@type": "SoftwareApplication",
        "name": "Ieum",
        "alternateName": ["이음", "イウム", "Ieum 이음"],
        "description": head["description"],
        "url": SITE + PATH[lang],
        "applicationCategory": "BusinessApplication",
        "applicationSubCategory": "Live captions and translation",
        "operatingSystem": "macOS 14 or later (Apple silicon)",
        "softwareVersion": "{{VERSION}}",
        "inLanguage": ["en", "ko", "ja", "zh-Hans"],
        "downloadUrl": "https://github.com/stoneidev/ieum/releases/latest/download/Ieum.dmg",
        "installUrl": "https://github.com/stoneidev/ieum/releases/latest/download/Ieum.dmg",
        "fileSize": "{{SIZE}}",
        "license": "https://www.apache.org/licenses/LICENSE-2.0",
        "isAccessibleForFree": True,
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
        "image": SITE + "/og.png",
        "sameAs": ["https://github.com/stoneidev/ieum"],
        "featureList": [
            "Live captions for meetings", "Translation between English, Korean, Japanese and Chinese (Simplified)",
            "Runs fully on the device, works offline", "No account, no cloud", "Saved transcripts",
            "System audio or microphone input", "Free and open source (Apache-2.0)",
        ],
    }
    graph = [app]
    questions = faq(page)
    if questions:
        graph.append({
            "@context": "https://schema.org",
            "@type": "FAQPage",
            "inLanguage": HREFLANG[lang],
            "mainEntity": [
                {"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in questions
            ],
        })
    return "\n".join(f'<script type="application/ld+json">{json.dumps(g, ensure_ascii=False, separators=(",", ":"))}</script>' for g in graph)


def head_block(lang, page):
    h = HEAD[lang]
    e = html.escape
    lines = [
        f"<title>{e(h['title'])}</title>",
        f'<meta name="description" content="{e(h["description"])}">',
        '<meta name="robots" content="index,follow,max-image-preview:large,max-snippet:-1">',
        f'<link rel="canonical" href="{SITE}{PATH[lang]}">',
    ]
    for code in LANGS:
        lines.append(f'<link rel="alternate" hreflang="{HREFLANG[code]}" href="{SITE}{PATH[code]}">')
    lines.append(f'<link rel="alternate" hreflang="x-default" href="{SITE}/">')
    lines.append('<link rel="alternate" type="text/markdown" href="/llms-full.txt" title="Ieum documentation for AI agents">')
    lines += [
        f'<meta property="og:title" content="{e(h["og_title"])}">',
        f'<meta property="og:description" content="{e(h["og_description"])}">',
        '<meta property="og:type" content="website">',
        '<meta property="og:site_name" content="Ieum">',
        f'<meta property="og:url" content="{SITE}{PATH[lang]}">',
        f'<meta property="og:locale" content="{OG_LOCALE[lang]}">',
    ]
    lines += [f'<meta property="og:locale:alternate" content="{OG_LOCALE[c]}">' for c in LANGS if c != lang]
    lines += [
        f'<meta property="og:image" content="{SITE}/og.png">',
        '<meta property="og:image:width" content="1200">',
        '<meta property="og:image:height" content="630">',
        '<meta name="twitter:card" content="summary_large_image">',
        f'<meta name="twitter:title" content="{e(h["og_title"])}">',
        f'<meta name="twitter:description" content="{e(h["og_description"])}">',
        f'<meta name="twitter:image" content="{SITE}/og.png">',
        json_ld(lang, page),
    ]
    return "\n".join(lines)


def lang_picker(lang):
    items = "".join(
        f'<li><a href="{PATH[c]}" hreflang="{HREFLANG[c]}" lang="{HREFLANG[c]}"'
        + (' aria-current="true"' if c == lang else "")
        + f">{NATIVE[c]}</a></li>"
        for c in LANGS
    )
    return (
        f'<details class="langpick"><summary class="lang" aria-label="Language: {NATIVE[lang]}">{NATIVE[lang]}</summary>'
        f"<ul>{items}</ul></details>"
    )


def build_page(template, lang, allow_missing):
    missing = []
    page = localize(template, lang, allow_missing, missing)
    page = page.replace("<!--LANGPICK-->", lang_picker(lang))
    page = re.sub(r"<title>.*?</title>\s*", "", page, count=1, flags=re.S)
    page = re.sub(r'<meta name="description"[^>]*>\s*', "", page, count=1)
    page = re.sub(r'<meta property="og:[^>]*>\s*', "", page)
    page = re.sub(r'<meta name="twitter:[^>]*>\s*', "", page)
    page = page.replace('<html lang="en" data-lang="en">', f'<html lang="{HREFLANG[lang]}" data-lang="{lang}">', 1)
    # asset paths are absolute (/fonts/...), so the same markup works at every depth
    marker = '<meta name="theme-color"'
    page = page.replace(marker, head_block(lang, page) + "\n" + marker, 1)
    page = page.replace("<script>\n(function(){", "<script>\nvar T=" + json.dumps(T[lang], ensure_ascii=False) + ";\n(function(){", 1)
    return page, missing


def markdown(page, lang):
    """A readable plain-text version of a built page, for AI agents."""
    body = page[page.index("<main") if "<main" in page else page.index("<body"):]
    body = re.sub(r"<(script|style|svg)\b.*?</\1>", "", body, flags=re.S)
    body = re.sub(r"</(h1|h2|h3)>", "\n\n", body)
    body = re.sub(r"<h1[^>]*>", "# ", body)
    body = re.sub(r"<h2[^>]*>", "## ", body)
    body = re.sub(r"<h3[^>]*>", "### ", body)
    body = re.sub(r"</(p|li|div|summary|details|section|tr)>", "\n", body)
    body = re.sub(r"<li[^>]*>", "- ", body)
    body = re.sub(r"<[^>]+>", "", body)
    body = html.unescape(body)
    lines = [re.sub(r"[ \t]+", " ", ln).strip() for ln in body.splitlines()]
    out, blank = [], False
    for ln in lines:
        if not ln:
            blank = True
            continue
        if blank and out:
            out.append("")
        blank = False
        out.append(ln)
    return "\n".join(out)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    allow_missing = "--allow-missing" in sys.argv
    if len(args) != 1:
        raise SystemExit(__doc__)
    out = Path(args[0])
    if out.exists():
        shutil.rmtree(out)
    shutil.copytree(ROOT / "site", out, ignore=shutil.ignore_patterns(".omc"))
    template = (ROOT / "site-src" / "index.template.html").read_text(encoding="utf-8")
    problems, pages = [], {}
    for lang in LANGS:
        page, missing = build_page(template, lang, allow_missing)
        problems += [f"[{lang}] missing: {m}" for m in missing]
        dest = out / PATH[lang].strip("/") / "index.html"
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(page, encoding="utf-8")
        pages[lang] = page
    if problems:
        raise SystemExit("untranslated sentences:\n" + "\n".join(problems[:40]) + (f"\n... {len(problems)} in total" if len(problems) > 40 else ""))

    today = date.today().isoformat()
    urls = "".join(
        f"<url><loc>{SITE}{PATH[l]}</loc><lastmod>{today}</lastmod>"
        + "".join(f'<xhtml:link rel="alternate" hreflang="{HREFLANG[c]}" href="{SITE}{PATH[c]}"/>' for c in LANGS)
        + f'<xhtml:link rel="alternate" hreflang="x-default" href="{SITE}/"/></url>'
        for l in LANGS
    )
    (out / "sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" '
        f'xmlns:xhtml="http://www.w3.org/1999/xhtml">{urls}</urlset>\n',
        encoding="utf-8",
    )
    full = "\n\n---\n\n".join(f"<!-- {NATIVE[l]} ({SITE}{PATH[l]}) -->\n\n{markdown(pages[l], l)}" for l in LANGS)
    (out / "llms-full.txt").write_text(
        "# Ieum (이음) — full text of the website\n\nSource: " + SITE + "/ . The same page in English, Korean, Japanese and Chinese.\n\n" + full + "\n",
        encoding="utf-8",
    )
    print(f"built {len(LANGS)} pages into {out}")


if __name__ == "__main__":
    main()
