# Monochrome

Monochrome makes Google Chrome on macOS keep tabs the way Arc did: locked tabs that come back when closed, new tabs at the top, ⌃Tab by recent use with a thumbnail switcher, mini browsers for links from other apps, peek browsers for links from locked tabs, profile hotkeys, and a mini player over the tab sidebar. Chrome's own vertical tab bar is the sidebar; nothing is added to the window.

It has two parts:

- **The extension**, in this folder, does what an extension can: locked tabs, tab order, the recent-tab list, mini and peek browser windows, the music hooks.
- **The app**, Monochrome.app, built from `helper/`, does what an extension cannot: it reads ⌃Tab and the other hotkeys through an event tap, draws the switcher, the mini browser bar, the peek shade, the profile HUD and the mini player as panels over Chrome, starts Chrome with its launch flags, and is the default browser, so links from other apps reach the extension without passing through Chrome's main window.

The two talk over Chrome's native messaging. Each runs without the other: every extension feature except ⌥⌘-click has a fallback when the app is not running.

Monochrome does not touch Chrome's data folder, sync or passwords, and does not replace the tab bar, the address bar or the New Tab page. The one exception is the optional Arc import under Install, which runs once.

## Install

Requires macOS 13 or later and Google Chrome. Chrome Beta, Dev, Canary and Chromium count as Chrome throughout.

1. **Get the app.** Either download `Monochrome-app-<version>.zip` from https://github.com/arfct/monochrome/releases/latest, unzip it and move Monochrome.app to Applications, or build it from source (next section). The release is signed with an Apple Development certificate and not notarized, so the first open is a right-click and Open.

2. **Open the app.** It installs itself on launch (`helper/Install.swift`):
   - registers itself as the extension's native messaging host with each Chrome that has run on this Mac;
   - adds itself as a login item;
   - sets Chrome's App Shortcuts: ⌘S collapses the tab sidebar, ⇧⌘S is Save Page As, ⌥⌘↓ and ⌥⌘↑ step through the tab list;
   - replaces a pinned Google Chrome tile in the Dock with its own, which starts Chrome with the launch flags;
   - asks macOS to make it the default browser (macOS shows a confirmation);
   - removes what earlier versions installed: the Arc for Chrome app, Chrome Launcher and a Karabiner rule.

   The host registration and the App Shortcuts are rewritten on every launch, so an app that has moved fixes its own path. The Dock tile and the default-browser question happen once per app location.

3. **Allow Accessibility** when the app asks: System Settings → Privacy & Security (Device Control and Data Access on newer macOS) → Accessibility → Monochrome. The event tap needs it for ⌃Tab, ⌥⌘-click and the profile hotkeys.

4. **Restart Chrome from the Dock.** Quit Chrome and open it from the Monochrome tile. Only that start carries the launch flags; Chrome started any other way runs without them, and Monochrome posts a notification saying so.

5. **Load the extension** in each Chrome profile: `chrome://extensions` → Developer mode → Load unpacked → this folder. The Web Store listing (ID `liabjepobglgnnddhlohohipjjbbdjjo`) is not public yet. The manifest carries a public key, so the unpacked extension's ID is the same from any folder, and the app's host registration names it. After pulling changes, click reload on the extension's card: Chrome does not re-read an unpacked extension on relaunch. The options page opens on install, shows whether the app is connected, and sets the locked group's title.

6. **Chrome settings.** Right-click the tab bar → Show Tabs Vertically. Settings → On startup → Continue where you left off. Optionally `chrome://flags/#browser-initiated-automatic-picture-in-picture` → Enabled, for video that pops out when its tab is left.

7. **Lock tabs.** Pin the tabs that should be locked, and put everyday tabs in a tab group named `CoreCore` (or the title set on the options page).

8. **Optional, once:** `migrate/arc-to-chrome.sh` merges Arc's last 90 days of history and its form autofill into Chrome, backing up both databases first. It quits and reopens Chrome.

The extension's fallback commands are in `chrome://extensions/shortcuts`. Chrome pre-fills ⌃R, ⌃., ⌃⇧. and ⌃, on a fresh load. ⌥⇧N (scope Global), ⌘O and ⇧⌘O have no defaults and matter only when the app is not running.

## Build from source

Requires git and the Xcode command line tools (`xcode-select --install`). Xcode itself is needed only for the app icon; without it the app uses Chrome's.

```bash
git clone https://github.com/arfct/monochrome.git ~/Code/monochrome
~/Code/monochrome/setup.sh
```

Clone to a permanent folder, not Downloads: Chrome loads the unpacked extension from it. `setup.sh` runs `helper/install.sh`, which builds the app, copies it to `~/Applications` and opens it; from there the app installs itself as in step 2 above. Re-running is safe.

The scripts in `helper/`:

- `build.sh` compiles the Swift into `helper/build/Monochrome.app`, writes the extension IDs (the unpacked one from the manifest key and the store's from `store/id`) into its `Info.plist`, and signs it. It installs nothing.
- `install.sh` runs `build.sh`, copies the app to `~/Applications` and opens it.

**Signing.** macOS ties the Accessibility grant to the app's signature. `build.sh` signs with a certificate from the keychain, a Developer ID or Apple Development one, so the grant survives rebuilds; `MONOCHROME_SIGN_IDENTITY` picks one by name, and the choice is remembered in `~/Library/Application Support/Monochrome/identity`. With no certificate the build is signed ad hoc, macOS treats each rebuild as a new app, and `install.sh` resets the stale grant so the app can ask again.

**Trying a build without installing it.** `open helper/build/Monochrome.app --args --portable` runs the app with the host registration only: no login item, Dock tile, App Shortcuts or default-browser question. `Monochrome --register-host` writes the host registration and quits.

## Shortcuts

| Keys | Effect | Handled by |
|---|---|---|
| ⌃Tab, ⌃⇧Tab | Last used tab in this window. Hold ⌃ for the switcher; release to pick; Esc cancels | app; extension commands as fallback |
| ⌃R | Reset the current locked tab to its locked URL | extension command |
| ⌘W, middle-click | Close. A locked tab comes back at its locked URL | Chrome; ⌘W optionally the extension |
| ⌥⇧N, from any app | New mini browser | app; extension command as fallback |
| ⌥⌘-click | Open the link in a mini browser | app only |
| ⌘L, in a mini browser | Address field, URL selected. Enter goes; Esc closes the field | app; in-page bar as fallback |
| ⌘O, ⇧⌘O, in a mini browser | Move it into Chrome as a tab; pick the window or tab group | app; extension commands as fallback |
| Esc, in a mini browser | Close it | extension |
| ⌃⌥→, ⌃⌥← | Next, previous Chrome profile | app |
| ⌃⌥1 to ⌃⌥9 | Profile by its place in Chrome's Profiles menu | app |
| ⌘S | Collapse or show the vertical tab bar | macOS App Shortcut, set by the app |
| ⇧⌘S | Save Page As, moved off ⌘S | macOS App Shortcut, set by the app |
| ⌥⌘↓, ⌥⌘↑ | Next, previous tab in the list | macOS App Shortcut, set by the app |

Hotkeys are resolved through the active keyboard layout: ⌥⇧N is the key that types N, on Dvorak as on QWERTY (`helper/Keyboard.swift`).

## Locked tabs come back when closed

A pinned tab, or a tab in the `CoreCore` group, remembers the URL it had when it was locked. Closing it reopens it in place at that URL; unpinning it or dragging it out of the group closes it for good. ⌃R resets it in place. The command "Replace pinned URL with current" makes the current page the locked URL.

Locked URLs survive a restart by position: tabs are matched in order within the pinned area and within each group. When Chrome restores them in another order, the URLs land on the wrong tabs, and the fix is to re-lock or replace. Closing a window with locked tabs and then quitting is the known way to shift them by one.

## New tabs open at the top

A new tab lands directly under the locked tabs, including ⌘T and a mini browser moved into Chrome. A link opened in a new tab from an ordinary tab lands after that tab. From a locked tab, a background link (⌘-click) goes to the top without joining the group, and a foreground link becomes a peek browser. Other groups and session restore are not reordered.

## ⌃Tab walks tabs by recent use, per window

The first ⌃Tab goes to the tab last used in the front window. Holding ⌃ shows the switcher: the five most recent tabs of that window, most recent first, each as a thumbnail with favicon and title. ⌃Tab moves the selection on, ⌃⇧Tab back, both wrapping; Esc cancels; releasing ⌃ goes to the selection. A tap-and-release never shows the switcher. Only the tab landed on counts as used, so ⌃Tab twice returns to the starting tab. A link opened in a background tab is next in line.

Chrome gives extensions no Tab key, no ⌃-release event and no way to draw over the window, so the event tap in `helper/Tap.swift` takes ⌃Tab while Chrome is in front and `helper/Switcher.swift` draws the panel. The extension supplies the recent-tab list and thumbnails (`helper.js`): a thumbnail is captured when a tab comes to the front, when it finishes loading and after a scroll the tap reports, and lives only in the app's memory. Restored tabs have none until visited; `chrome://` pages never do.

Without the app connected, the tap rewrites the keys to the extension's commands (first ⌃Tab to ⌃., further ones to ⌃⇧., ⌃⇧Tab to ⌃,) and the extension switches live with no switcher. Without the app at all, Chrome's own ⌃Tab applies.

## Mini browsers are Chrome popup windows

A mini browser is a popup window: no tab strip, no sidebar, ⌘[ for back. Size and position are remembered. One left unfocused for 12 hours closes itself.

- ⌥⇧N from any app opens one with a search box: a URL, or a search in Chrome's default engine, then Enter.
- A link from another app opens one. The app is the default browser, so the link reaches it, and it asks the extension to open the window directly. When the extension is not connected, the app hands the link to Chrome, where it shows in the main window briefly before becoming a mini browser.
- ⌥⌘-click on any page opens the link in one. The tap sees the click; there is no fallback.
- The bar, top right over the title bar, is a panel of the app: a link button or ⌘L for the address field, Open in Chrome or ⌘O to move the page into the main window, a caret or ⇧⌘O for the list of windows and groups, each window named by its active tab. The bar hides while the window is dragged and while the mini browser is not the key window. Without the app, the same bar is drawn inside the page.

## Links from other apps follow rules

A link from Slack, Mail or a terminal reaches the app first, with the sending app's identity from the open event. The app checks it against `~/Library/Application Support/Monochrome/routes.json`, an array of rules where the first match wins; a link no rule claims opens as a mini browser in the profile whose window is in front. The file is re-read when it changes. The Router tab of the settings window edits the same file. The design and its departures are in `docs/link-routing.md`.

```json
[
  { "match": { "host": "atlassian.net" },                     "to": { "profile": "Work", "window": "same-site" } },
  { "match": { "from": "com.tinyspeck.slackmacgap" },         "to": { "mini": true } },
  { "match": { "host": "zoom.us", "path": "/j/*" },           "to": { "app": "us.zoom.xos" } },
  { "match": { "host": "github.com" },                        "to": { "group": "Code" } },
  { "match": { "url": "https://docs.google.com/document/*" },  "to": { "window": "same-site" } }
]
```

Match fields, all of which must hold: `host` (a bare name matches it and its subdomains; `*` is a wildcard anywhere), `path`, `url` (the whole address), `from` (the sender's bundle id). A rule with no `match` matches everything. Destination fields: `app` (a bundle id; Chrome never sees the link), `profile` (a name as Chrome's Profiles menu shows it), and inside the profile one of `mini` (the default), `window: "same-site"` (a tab already on that host, the front window's first, navigated to the link; with none, a new tab at the top of the front window), `window: "front"` (that new tab) or `group` (a tab group's title; the tab joins it in whatever window has it, and the group is made in the front window if none does).

A profile destination goes over that profile's connection when the app knows it by name, which it learns from Chrome's window titles. Otherwise the app presses the profile's item in Chrome's Profiles menu, which brings that profile forward or opens it, waits up to three seconds for its extension to connect, and failing that hands the URL to Chrome, which opens it as a tab in the profile now in front.

```bash
~/Applications/Monochrome.app/Contents/MacOS/Monochrome --routes https://github.com/arfct/monochrome com.tinyspeck.slackmacgap
```

prints the rules and the one that URL would take; the sender argument is optional. Without the app, links from other apps land in the main window and become mini browsers; no rule applies.

## Peek browsers catch links from locked tabs

A link from a locked tab that would open a new tab opens as a mini browser over the window, with the window behind it shaded. A click on the shade or on another window closes it; ⌘O keeps the page as a tab. The shade is a panel the size of the parent window, ordered directly below the peek browser, and fades in.

The catch is two scripts the extension injects into locked tabs only (`peek-click.js`, `peek-open.js`): links with `target="_blank"` and calls to the page's `window.open` are taken before Chrome makes a tab, so the main window never shows the page. Anything else that opens a tab from a locked tab, a form post for one, passes through the main window first and is visible for a moment. No other page gets a content script, apart from the music sites below.

## Profiles switch through Chrome's own menu

⌃⌥→ and ⌃⌥← go to the next and previous profile, ⌃⌥1 to 9 to one by position. The app reads Chrome's Profiles menu over Accessibility and presses the item (`helper/Profiles.swift`), so this works in a profile without the extension; every other feature needs the extension loaded there. A HUD shows the profiles as initials on a color derived from the name, the chosen one marked, for 1.2 seconds. The menu carries no avatar images, which is why initials.

## The mini player sits on the tab sidebar

When a music tab has a track loaded and another tab is in front, a panel at the bottom of the sidebar shows artwork, title, artist and transport controls. Clicking the track goes to its tab, and the close button hides the panel until the music tab has been visited and left again. It hides when the music tab is in front, when the sidebar is collapsed and when Chrome is not frontmost. On these sites the extension also stops Chrome's own pop-out player when the tab is left. Sites: Spotify, YouTube Music, SoundCloud, Apple Music, Tidal, Bandcamp, Pandora, Amazon Music, Deezer. Adding one is two entries in `manifest.json`, `music.js` and `music-relay.js`.

The panel is the app's (`helper/Player.swift`), because an extension cannot draw in the tab strip. It covers the last tabs of a long list and trails the window during a drag.

## The address bar opens the matching page from history

Typing words and pressing Enter opens the history entry that matches them rather than a search. Chrome allows this only with `--enable-features=OmniboxForceAllowedToBeDefault`, which is not on `chrome://flags`, so the app passes it when it starts Chrome. A search made before for the same words can still outrank the page. The flag list is `features` in `helper/Chrome.swift`; a change takes effect after a rebuild and a restart of Chrome from the Dock.

## The app is one binary in several roles

- **The app** (no arguments): installs itself at launch, owns the event tap and every panel, the Dock tile and the default-browser role, and listens on a Unix socket in `~/Library/Application Support/Monochrome`. A click on its Dock tile opens Chrome; a double-click in the Finder, or the ▾ menu of any mini browser's bar, opens the settings window.
- **The host** (`--host`): what Chrome spawns for the extension's native messaging port. It relays between the port and the app's socket, and pings the extension every 20 seconds so Chrome does not stop the service worker for idleness. Each Chrome profile gets its own host process and connection; the app routes tab actions to the connection that owns the tab and front-window actions to the connection whose front window matches Chrome's.
- **Commands:** `--portable` (the app, registering the host only), `--register-host`, `--status` (the layout's keycodes, whether the app is running, whether the socket is up), `--routes [url [sender]]`, `--settings`, `--make-default`, `--unregister` (removes the login item), and `--demo`, `--demo-profiles`, `--demo-settings`, `--demo-shade` for the panels over sample data.

The settings window has two tabs: General (login item, default browser, Accessibility, Chrome's launch flags, which profiles are connected) and Router (the rules). While it is open the app shows in the Dock with a menu bar; when it closes the app goes back to running without either.

Logs go to the unified log under subsystem `local.monochrome`:

```bash
/usr/bin/log stream --info --predicate 'subsystem == "local.monochrome"'
```

## Uninstall

```bash
~/Code/monochrome/uninstall.sh
```

It removes the app, its login item, Dock tile, support folder and host registration, this project's App Shortcuts, and what earlier versions installed. Karabiner itself and other App Shortcuts stay. Then remove the extension in `chrome://extensions`, restart Chrome, and choose Chrome as the default browser in System Settings → Desktop & Dock.

## Releases and the Web Store

- **The app** is released as a zip on GitHub: `ditto -c -k --keepParent helper/build/Monochrome.app dist/Monochrome-app-<version>.zip` after `helper/build.sh`. The v1.0 zip predates the app installing itself, so it does not register the native messaging host; a release built from this version does.
- **The extension** is packed by `store/pack.sh` into `dist/monochrome-extension-<version>.zip`, without the app, tests, docs, scripts or the manifest's `key`, which the store refuses. The store assigned the ID in `store/id` on the first upload. To make the unpacked extension the same extension as the store's, install the store's copy once and run `store/adopt-key.sh <id>`, which copies the store's key into this manifest and reinstalls the app.
- `store/listing.md` holds the listing text, permission justifications and privacy answers. The listing links Artifact's shared policy at artifact.com/privacy?Monochrome; `docs/privacy.md` is the detailed statement. `store/screenshots/` holds the switcher, profile HUD and Router tab from `--demo --backdrop`, `--demo-profiles --backdrop` and `--demo-settings --backdrop`, and the promo tiles from `swift store/tiles.swift`, all JPEG.

## Tests

```bash
npm install && npx playwright-core install chromium && helper/build.sh && npm test
```

The suite drives headless Chromium with the extension loaded. With the app built, it also spawns it in host mode against a private socket, and has the app write its host registration into a fresh Chromium profile and checks that the extension there reaches a socket standing in for the app. `HEADFUL=1 npm test` adds the link hand-off from another app, which headless Chromium cannot receive.

## Not verified

I am an automated contributor, and this is what I did not exercise by hand: the app's install at launch on a Mac (Dock tile, App Shortcuts, default-browser question, removal of earlier versions; the host registration is covered by the tests); two profiles connected to the app at once; dragging a peek browser with its shade; a profile switch by hotkey beyond reading the menu; a rule with a `profile` destination for a profile that is not running; whether every app's open event names the sender; whether Chrome matches the ⌃. and ⌃, fallback commands by typed character or by key position on Dvorak; and whether reading Chrome's menu bar and window titles over Accessibility changes Chrome's own accessibility mode.

## What would change this design

A Chrome API for the Tab key, for drawing over the window, or for native panels in the tab strip would remove the app's reason to exist for the switcher and player. Native messaging that Chrome could initiate would remove the 20-second ping. Avatar images in the Profiles menu, or a sanctioned way to read the profile list, would replace the initials.

Until then, the extension does the bookkeeping and the app does the drawing.

## License

MIT. See `LICENSE`.
