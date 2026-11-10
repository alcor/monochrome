#!/usr/bin/env python3
# The Safari extension's manifest, from manifest.json: usage  safari-manifest.py <manifest.json> <out>
# Safari refuses or ignores what is Chrome's alone: the key (Safari signs the app extension instead),
# minimum_chrome_version, and the tabGroups, search and favicon permissions, whose APIs it lacks
# (background.js, helper.js and mini-browser.js check for each). open_in_tab is dropped as Safari
# does not read it. The Xcode project's Safari extension target runs this at build time; it is Python,
# not Node, because Xcode's run scripts have python3 on their PATH and may not have node.
import json
import sys

CHROME_ONLY_KEYS = ["key", "minimum_chrome_version"]
CHROME_ONLY_PERMISSIONS = {"tabGroups", "search", "favicon"}


def safari(manifest):
    m = dict(manifest)
    for key in CHROME_ONLY_KEYS:
        m.pop(key, None)
    m["permissions"] = [p for p in m.get("permissions", []) if p not in CHROME_ONLY_PERMISSIONS]
    m["description"] = m.get("description", "").replace("for Chrome", "for Safari")
    if "options_ui" in m:
        m["options_ui"] = {k: v for k, v in m["options_ui"].items() if k != "open_in_tab"}
    return m


if __name__ == "__main__":
    source, out = sys.argv[1:3]
    with open(source) as f:
        manifest = json.load(f)
    with open(out, "w") as f:
        json.dump(safari(manifest), f, ensure_ascii=False, indent=2)
        f.write("\n")
