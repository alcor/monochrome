# TLDR spike

Anchored summary bullets from one article with Apple's on-device model. See [the plan](../tldr.md#spike-anchored-bullets-from-apples-model) for the results.

1. Save an article's HTML as `page.html`, then `python3 extract.py page.html <url> > blocks.json`. This is a regex stand-in for the plan's extractor: headings and paragraphs in document order, each with an id.
2. `swiftc -parse-as-library -O summarize.swift -o summarize && ./summarize < blocks.json > summary.json` (macOS 26.4 or later with Apple Intelligence on). Availability, token counts, timings and anchor checks go to stderr.

`run.log` is the stderr of the run on 2026-11-10: macOS 27.2, Apple M5 Ultra, the Cloudflare post "How we built Pingora, the proxy that connects Cloudflare to the Internet". The article's text and the binary are not kept here.
