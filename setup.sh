#!/bin/sh
# Sets up everything on this Mac that can be scripted. Safe to re-run. The README lists the steps
# that need clicks (loading the extension, its shortcuts, allowing the helper's Accessibility).
set -eu
here=$(cd "$(dirname "$0")" && pwd)

[ -n "$(ls -d /Applications/Google\ Chrome*.app /Applications/Chromium.app 2>/dev/null)" ] || { echo "Install Google Chrome first: https://www.google.com/chrome/"; exit 1; }

# 1. Chrome menu shortcuts (macOS App Shortcuts), for each Chrome installed: ⌘S collapses/expands the
#    vertical tab sidebar like the sidebar; Save Page As moves to ⇧⌘S so the two don't clash; ⌥⌘↓ / ⌥⌘↑
#    move down / up the tab list. Takes effect next time Chrome starts. (\357\234\201 and \357\234\200
#    are the UTF-8 for the down/up arrow key characters, U+F701 / U+F700.)
for chrome in "Google Chrome:com.google.Chrome" "Google Chrome Beta:com.google.Chrome.beta" "Google Chrome Dev:com.google.Chrome.dev" \
              "Google Chrome Canary:com.google.Chrome.canary" "Chromium:org.chromium.Chromium"; do
  [ -d "/Applications/${chrome%%:*}.app" ] || continue
  domain=${chrome#*:}
  defaults write "$domain" NSUserKeyEquivalents -dict-add \
    "Collapse Vertical Tabs" "@s" \
    "Save Page As…" '@$s' \
    "Select Next Tab" "$(printf '@~\357\234\201')" \
    "Select Previous Tab" "$(printf '@~\357\234\200')"
  # Chrome would otherwise ask to be made the default browser on every start; the helper app is.
  defaults write "$domain" DefaultBrowserSettingEnabled -bool false
  echo "${chrome%%:*} menu shortcuts: set"
done

# 2. The helper app: ⌃Tab switcher, Chrome's launch flags (login item and Dock icon), default browser
#    for links from other apps, sidebar mini player.
"$here/helper/install.sh"

# 3. Make it the default browser (a system dialog asks you to confirm).
open -W -a "$HOME/Applications/Monochrome.app" --args --make-default

# Karabiner was how ⌃Tab used to get through; a rule from an earlier version is removed if present.
karabiner="$HOME/.config/karabiner/karabiner.json"
if [ -f "$karabiner" ]; then
  python3 -I - "$karabiner" <<'EOF'
import json, os, sys
path = sys.argv[1]
cfg = json.load(open(path))
changed = False
for p in cfg.get('profiles', []):
    rules = p.get('complex_modifications', {}).get('rules')
    if rules is not None:
        kept = [r for r in rules if not r.get('description', '').startswith('Chrome: Ctrl+Tab / Ctrl+Shift+Tab')]
        changed |= len(kept) != len(rules)
        rules[:] = kept
if changed:
    with open(path + '.tmp', 'w') as f:
        json.dump(cfg, f, indent=2)
    os.replace(path + '.tmp', path)
    print('karabiner: old rule removed (Karabiner itself can be uninstalled)')
EOF
  rm -f "$HOME/.config/karabiner/assets/complex_modifications/arc-for-chrome.json"
fi
# Likewise Chrome Launcher.
launcher_agent="$HOME/Library/LaunchAgents/local.arc-for-chrome.launcher.plist"
if [ -e "$launcher_agent" ] || [ -d "$HOME/Applications/Chrome Launcher.app" ]; then
  launchctl bootout "gui/$(id -u)" "$launcher_agent" 2>/dev/null || true
  rm -rf "$HOME/Applications/Chrome Launcher.app" "$launcher_agent"
  echo "chrome launcher: removed (the helper app does that now)"
fi

cat <<'EOF'

Done with the scripted part. Continue with step 3 of "Set up on a new Mac" in README.md:
allow Monochrome under Accessibility, reopen Chrome from the Dock, load the extension, set its shortcuts.
EOF
