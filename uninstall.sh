#!/bin/sh
# Undoes `make install` and what the app installs at launch: removes the helper app (login item, Dock icon, Chrome registration, the app itself),
# this project's Chrome and Safari App Shortcuts (other App Shortcuts stay), the app's settings, the
# Safari relay's app group folder, and anything left from earlier versions (Chrome Launcher, the
# Karabiner rule; Karabiner itself stays installed).
# The Chrome extension is removed by hand in chrome://extensions; the Safari extension goes with the
# app. If the helper was your default browser, macOS falls back to asking next time a link is opened;
# pick a browser in System Settings → Desktop & Dock.
set -eu
[ -n "${HOME:-}" ] && [ -d "$HOME" ] || { echo "HOME is not set" >&2; exit 1; }
app="$HOME/Applications/Monochrome.app"
group_id="TVA9Z8LD95.com.artifact.monochrome"
group="$HOME/Library/Group Containers/$group_id"
chromes="Google/Chrome|Google/Chrome Beta|Google/Chrome Dev|Google/Chrome Canary|Chromium"

pkill -x Monochrome 2>/dev/null || true
pkill -x Monochrome 2>/dev/null || true
[ -x "$app/Contents/MacOS/Monochrome" ] && "$app/Contents/MacOS/Monochrome" --unregister 2>/dev/null || true
rm -rf "$app" "$HOME/Library/Application Support/Monochrome" "$HOME/Applications/Arc for Chrome.app" "$HOME/Library/Application Support/Arc for Chrome"
echo "$chromes" | tr '|' '\n' | while IFS= read -r chrome; do
  hosts="$HOME/Library/Application Support/$chrome/NativeMessagingHosts"
  rm -f "$hosts/monochrome_helper.json" "$hosts/erics_arc_player.json"
done

launcher_agent="$HOME/Library/LaunchAgents/local.arc-for-chrome.launcher.plist"
launchctl bootout "gui/$(id -u)" "$launcher_agent" 2>/dev/null || true
rm -rf "$HOME/Applications/Chrome Launcher.app" "$launcher_agent"

# The Safari relay's app group folder (its socket). Removed only when the path is exactly the app's
# group container under this home folder and is a real directory, not a link. macOS may ask first,
# since group containers are guarded; if it refuses, the folder stays and holds nothing but the socket.
case "$group" in
  "$HOME/Library/Group Containers/TVA9Z8LD95.com.artifact.monochrome")
    if [ -d "$group" ] && [ ! -L "$group" ]; then rm -rf -- "$group" 2>/dev/null || echo "could not remove $group" >&2; fi ;;
  *) echo "unexpected group container path: $group" >&2 ;;
esac

# The app's own settings: the browser choice, learned Safari profile names, Dock tile and
# default-browser bookkeeping.
defaults delete com.artifact.monochrome 2>/dev/null || true

python3 -I - <<'EOF'
import json, os, plistlib, subprocess

def edit_defaults(domain, change):
    raw = subprocess.run(['defaults', 'export', domain, '-'], capture_output=True).stdout
    if not raw:
        return # no such domain
    prefs = plistlib.loads(raw)
    if change(prefs):
        subprocess.run(['defaults', 'import', domain, '-'], input=plistlib.dumps(prefs), check=True)

def drop_dock_tile(dock):
    tiles = dock.get('persistent-apps', [])
    keep = [t for t in tiles if t.get('tile-data', {}).get('file-label') not in ('Chrome Launcher', 'Arc for Chrome', 'Monochrome')]
    dock['persistent-apps'] = keep
    return len(keep) != len(tiles)

# Safari's App Shortcuts (SafariShortcuts in helper/Safari.swift) live in Safari's guarded container.
# Only the one key is rewritten, not the whole domain; when macOS refuses the read, nothing changes.
SAFARI_SHORTCUTS = ('Show Sidebar', 'Hide Sidebar', 'Save As…', 'Show Next Tab', 'Show Previous Tab')

def drop_safari_shortcuts(domain='com.apple.Safari'):
    raw = subprocess.run(['defaults', 'export', domain, '-'], capture_output=True).stdout
    if not raw:
        return
    keys = plistlib.loads(raw).get('NSUserKeyEquivalents', {})
    if not any(k in keys for k in SAFARI_SHORTCUTS):
        return
    for k in SAFARI_SHORTCUTS:
        keys.pop(k, None)
    if keys:
        xml = plistlib.dumps(keys, fmt=plistlib.FMT_XML).decode()
        subprocess.run(['defaults', 'write', domain, 'NSUserKeyEquivalents', xml], check=False)
    else:
        subprocess.run(['defaults', 'delete', domain, 'NSUserKeyEquivalents'], check=False)

def drop_chrome_prefs(chrome):
    keys = chrome.get('NSUserKeyEquivalents', {})
    removed = [k for k in ('Collapse Vertical Tabs', 'Save Page As…', 'Select Next Tab', 'Select Previous Tab') if keys.pop(k, None) is not None]
    return bool(removed) | (chrome.pop('DefaultBrowserSettingEnabled', None) is not None)

edit_defaults('com.apple.dock', drop_dock_tile)
for domain in ('com.google.Chrome', 'com.google.Chrome.beta', 'com.google.Chrome.dev', 'com.google.Chrome.canary', 'org.chromium.Chromium'):
    edit_defaults(domain, drop_chrome_prefs)
drop_safari_shortcuts()

path = os.path.expanduser('~/.config/karabiner/karabiner.json')
if os.path.exists(path):
    cfg = json.load(open(path))
    for p in cfg.get('profiles', []):
        rules = p.get('complex_modifications', {}).get('rules')
        if rules is not None:
            rules[:] = [r for r in rules if not r.get('description', '').startswith('Chrome: Ctrl+Tab / Ctrl+Shift+Tab')]
    with open(path + '.tmp', 'w') as f:
        json.dump(cfg, f, indent=2)
    os.replace(path + '.tmp', path)
EOF
rm -f "$HOME/.config/karabiner/assets/complex_modifications/arc-for-chrome.json"
killall Dock
echo "Uninstalled. Remove the extension in chrome://extensions; quit and reopen Chrome to drop its launch flags."
echo "Safari: quit and reopen Safari to drop its App Shortcuts."
