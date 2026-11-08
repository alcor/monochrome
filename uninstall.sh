#!/bin/sh
# Undoes `make install` and what the app installs at launch: removes the helper app (login item, Dock icon, Chrome registration, the app itself),
# this project's Chrome App Shortcuts (other App Shortcuts stay), and anything left from earlier
# versions (Chrome Launcher, the Karabiner rule; Karabiner itself stays installed).
# The extension is removed by hand in chrome://extensions. If the helper was your default browser,
# macOS falls back to asking next time a link is opened; pick Chrome in System Settings → Desktop & Dock.
set -eu
app="$HOME/Applications/Monochrome.app"
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

def drop_chrome_prefs(chrome):
    keys = chrome.get('NSUserKeyEquivalents', {})
    removed = [k for k in ('Collapse Vertical Tabs', 'Save Page As…', 'Select Next Tab', 'Select Previous Tab') if keys.pop(k, None) is not None]
    return bool(removed) | (chrome.pop('DefaultBrowserSettingEnabled', None) is not None)

edit_defaults('com.apple.dock', drop_dock_tile)
for domain in ('com.google.Chrome', 'com.google.Chrome.beta', 'com.google.Chrome.dev', 'com.google.Chrome.canary', 'org.chromium.Chromium'):
    edit_defaults(domain, drop_chrome_prefs)

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
