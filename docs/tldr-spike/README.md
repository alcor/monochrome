# TL;DR spike: anchored bullets from Apple's on-device model

The measurement behind the spike table in `docs/tldr.md`. `summarize.swift` reads `{"title": "...", "paragraphs": ["...", ...]}` on stdin, numbers the paragraphs, asks the on-device model through Foundation Models for three to five bullets that each name their paragraph id, and prints the bullets with the paragraph count, the characters sent and the wall time.

```bash
swiftc -parse-as-library -O summarize.swift -o summarize
CHARS=6000 ./summarize < article.json
```

`CHARS` caps the characters of paragraph text sent (default 6000). Needs macOS 26 or later with Apple Intelligence on; the program prints `available` or the framework's reason on stderr and exits 2 when the model is not available. The article used on 2026-11-10 was the English Wikipedia page on Safari, split on blank lines; it is not committed. The binary is not committed either.
