#!/usr/bin/env python3
# Spike stand-in for the extractor: heading and paragraph text from saved HTML, in document order.
# usage: extract.py page.html <url> > blocks.json
# Output: {"url", "title", "blocks": [{"id", "kind": "h"|"p", "text"}]}; a summary of what it kept goes
# to stderr. This is a regex pass, not the plan's extractor: it exists to give the model real article
# text with stable block ids.
import html
import json
import re
import sys

src = open(sys.argv[1], encoding="utf-8", errors="replace").read()
src = re.sub(r"(?is)<(script|style|noscript|svg|nav|footer|header|aside|form)\b.*?</\1>", " ", src)
title = re.search(r"(?is)<title[^>]*>(.*?)</title>", src)
blocks = []
for m in re.finditer(r"(?is)<(p|h[1-4]|li|blockquote)\b[^>]*>(.*?)</\1>", src):
    text = html.unescape(re.sub(r"(?s)<[^>]+>", "", m.group(2)))
    text = re.sub(r"\s+", " ", text).strip()
    kind = "h" if m.group(1).lower().startswith("h") else "p"
    if len(text) < (3 if kind == "h" else 60):
        continue
    blocks.append({"id": len(blocks), "kind": kind, "text": text})
json.dump({"url": sys.argv[2], "title": html.unescape(title.group(1)).strip() if title else "", "blocks": blocks},
          sys.stdout, ensure_ascii=False)
chars = sum(len(b["text"]) for b in blocks)
words = sum(len(b["text"].split()) for b in blocks)
sys.stderr.write(f"{len(blocks)} blocks, {chars} characters, {words} words\n")
