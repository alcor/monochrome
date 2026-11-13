#!/usr/bin/env python3
"""Writes a release's version into project.yml and manifest.json, for `make release`.

    scripts/set-version.py <version> [build]

<version> is what people see: 1.5, or 1.6-beta.1 for a beta. It becomes MARKETING_VERSION
(CFBundleShortVersionString) and the extension's version_name.

[build] is CFBundleVersion, the number Sparkle compares to decide what is newer: a whole number
that goes up by one on every release, betas included (Primer, deployment.md, "Sparkle"). Left out,
it is the current one plus one. Releases up to 1.4 used the version as the build ("1.4"); Sparkle
reads any whole number of 2 or more as newer than those, so the first numbered build is given by
hand (6) and the rest count from it.

The extension's `version` must be dotted numbers that rise with every upload, so it is the numeric
part padded to three places plus the build (1.5 build 6 is 1.5.0.6; 1.6-beta.1 build 7 is 1.6.0.7, and
1.6 build 8 is 1.6.0.8, above it), and `version_name` carries what people see.
"""
import json
import re
import sys

version = sys.argv[1] if len(sys.argv) > 1 else ''
if not re.fullmatch(r'\d+(\.\d+){0,2}(-beta\.\d+)?', version):
    sys.exit(f'version {version!r}: want 1.5 or 1.6-beta.1')

yml = open('project.yml').read()
found = re.search(r'^    CURRENT_PROJECT_VERSION: "(.*)"', yml, re.M)
if not found:
    sys.exit('project.yml has no CURRENT_PROJECT_VERSION')
current = found.group(1)
if len(sys.argv) > 2:
    build = sys.argv[2]
elif current.isdigit():
    build = str(int(current) + 1)
else:
    sys.exit(f'build: the current one is {current!r}, not a whole number; give the first one: BUILD=6')
if not build.isdigit() or (current.isdigit() and int(build) <= int(current)):
    sys.exit(f'build {build!r}: want a whole number above {current}')

yml = re.sub(r'^    MARKETING_VERSION: ".*"', f'    MARKETING_VERSION: "{version}"', yml, flags=re.M)
yml = re.sub(r'^    CURRENT_PROJECT_VERSION: ".*"', f'    CURRENT_PROJECT_VERSION: "{build}"', yml, flags=re.M)
open('project.yml', 'w').write(yml)

numeric = version.split('-')[0]
parts = (numeric.split('.') + ['0', '0'])[:3]
m = json.load(open('manifest.json'))
m['version'] = '.'.join(parts + [build])
m['version_name'] = version
with open('manifest.json', 'w') as f:
    json.dump(m, f, ensure_ascii=False, indent=2)
    f.write('\n')
print(f'version {version}, build {build}, extension {m["version"]}')
