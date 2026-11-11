# Monochrome

Monochrome makes Google Chrome on macOS keep tabs the way Arc did: locked tabs that come back when closed, new tabs at the top, ⌃Tab by recent use with a thumbnail switcher, mini browsers for links from other apps, peek browsers for links from locked tabs, profile hotkeys, and a mini player over the tab sidebar. Chrome's own vertical tab bar is the sidebar; nothing is added to the window.

It has two parts:

- **The extension**, in this folder, does what an extension can: locked tabs, tab order, the recent-tab list, mini and peek browser windows, the music hooks.
- **The app**, Monochrome.app, built from `helper/`, does what an extension cannot: it reads ⌃Tab and the other hotkeys through an event tap, draws the switcher, the mini browser bar, the peek shade, the profile HUD and the mini player as panels over Chrome, starts Chrome with its launch flags, and is the default browser, so links from other apps reach the extension without passing through Chrome's main window.

The two talk over Chrome's native messaging. Each runs without the other: every extension feature except ⌥⌘-click has a fallback when the app is not running.

Monochrome does not touch Chrome's data folder, sync or passwords, and does not replace the tab bar, the address bar or the New Tab page. The one exception is the optional Arc import under Install, which runs once.

Safari is supported as well, from the same app and the same extension files, with fewer features: see [Safari](#safari) below. The app works with one browser at a time, chosen on its settings window.

## Install

Requires macOS 13 or later and Google Chrome. Chrome Beta, Dev, Canary and Chromium count as Chrome throughout.

1. **Get the app.** Either download `Monochrome-app-<version>.zip` from https://github.com/arfct/monochrome/releases/latest, unzip it and move Monochrome.app to Applications, or build it from source (next section). The release is signed with the Artifact Creative Foundation's Developer ID and notarized by Apple, so it opens like any downloaded app. Move it to Applications before the first open: at launch it registers its own location with Chrome.

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

5. **Load the extension** in each Chrome profile: `chrome://extensions` → Developer mode → Load unpacked → this folder, or the copy inside the app: Install Extension… on the settings window's Browser tab shows a small floating panel with the folder to drag onto that page and the steps, and the panel's button opens the page; it is the same extension (same key, same ID) from the build the app shipped with. The Web Store listing (ID `liabjepobglgnnddhlohohipjjbbdjjo`) is not public yet. The manifest carries a public key, so the unpacked extension's ID is the same from any folder, and the app's host registration names it. After pulling changes, click reload on the extension's card: Chrome does not re-read an unpacked extension on relaunch. The options page opens on install and shows whether the app is connected; while the app is not, it also sets the locked group's title (with the app, that title is set in Settings → Tabs, and the page has a Monochrome Settings… button).

6. **Chrome settings.** Right-click the tab bar → Show Tabs Vertically. Settings → On startup → Continue where you left off. Optionally `chrome://flags/#browser-initiated-automatic-picture-in-picture` → Enabled, for video that pops out when its tab is left.

7. **Lock tabs.** Pin the tabs that should be locked, and put everyday tabs in a tab group named `CoreCore` (or the title set in Settings → Tabs → Locked group).

8. **Optional, once:** `migrate/arc-to-chrome.sh` merges Arc's last 90 days of history and its form autofill into Chrome, backing up both databases first. It quits and reopens Chrome.

The extension's fallback commands are in `chrome://extensions/shortcuts`. Chrome pre-fills ⌃R, ⌃., ⌃⇧. and ⌃, on a fresh load. ⌥⇧N (scope Global), ⌘O and ⇧⌘O have no defaults and matter only when the app is not running.

## Safari

Monochrome.app carries a Safari Web Extension built from the same files (`safari/`, the `MonochromeSafari` target in `project.yml`). To use Monochrome with Safari:

1. **Install and open the app** as in steps 1 to 3 above. Opening it once registers its Safari extension with Safari.
2. **Turn the extension on** in Safari → Settings → Extensions → Monochrome. The settings window's Safari Extension Settings… button opens that page.
3. **Allow it on every website**: in the same page, Edit Websites… → Other Websites → Allow, which Safari also offers as "Always Allow on Every Website". Peek, ⌃Tab thumbnails, switcher favicons and the music hooks need it.
4. **Pin the tabs that should be locked.**
5. **Optionally, choose Safari** in Monochrome's settings window: Browser → Browser → Safari. That setting is where links from other apps open and which browser starts at login; it also writes Safari's App Shortcuts (below).

Chrome and Safari can be used at the same time. Both browsers' extensions stay connected, and the event tap, the switcher, the mini browser bar, the peek shade, the profile hotkeys and the mini player follow whichever browser is in front.

Safari differences:

- Only pinned tabs are locked. Safari gives extensions no tab groups, so there is no `CoreCore` group, the locked group title has no effect, and a route to a tab group opens a new tab in the front window instead. The Router tab does not offer "Tab group" on Safari.
- The mini browser's search box searches Google. Safari has no search API and does not tell extensions its search engine.
- Switcher favicons come from Google's favicon service (`www.google.com/s2/favicons`) by the page's origin. Chrome uses its own favicon cache.
- Mini browsers are popup windows, as on Chrome. Whether Safari draws them without its toolbar has not been checked.
- Safari reports no window moves or resizes to extensions, so the extension reads the mini browser windows once a second while one is open.
- Profiles come from Safari's File → New Window submenu, which has a "New <name> Window" item per profile. The profile hotkeys (⌃⌥→, ⌃⌥←, ⌃⌥1 to 9) bring forward a window of a profile whose extension is connected, and otherwise press that item, which opens a new window in the profile. Safari tells extensions a profile id, not a name, so the app learns each name the first time it opens that profile's window this way, and keeps it. A `profile` route destination goes over the profile's connection once its name is known, and otherwise opens its window first.
- The mini player needs Safari's vertical tabs, which arrive in Safari 27.3. On 27.3 or later the app looks for the tab list over Accessibility and puts the player at its bottom; with Safari 27.2, or no tab list found, there is no mini player.
- App Shortcuts are written to Safari's preferences when the Browser setting is Safari: ⌘S shows and hides the sidebar, ⇧⌘S is Save As…, ⌥⌘↓ and ⌥⌘↑ are the next and previous tab. Quit and reopen Safari once for them to apply. macOS may refuse the write, since Safari's preferences are in its container; the app logs it.
- No launch flags, no Dock tile and no Arc import. The app does not start Safari at login.
- There is no shortcuts page for the extension's fallback commands, and no Global scope, so ⌥⇧N from another app needs the app.
- The extension talks to the app through its app extension: the extension's messages go to the app over a socket in the app group container (`~/Library/Group Containers/TVA9Z8LD95.com.artifact.monochrome`), and the app answers through Safari. Details are in `docs/safari.md`.

None of the Safari behavior has been tried in Safari yet; `docs/safari.md` lists what is unmeasured, including the Accessibility shape of Safari's profile menu and of 27.3's tab sidebar.

## Build from source

Requires git, Xcode and XcodeGen (`brew install xcodegen`), the same setup as the other Artifact apps: `project.yml` describes the app, `make project` generates `Monochrome.xcodeproj` from it (the project is not committed), and the Makefile has the rest.

```bash
git clone https://github.com/arfct/monochrome.git ~/Code/monochrome
cd ~/Code/monochrome && make install
```

Clone to a permanent folder, not Downloads: Chrome loads the unpacked extension from it. `make install` builds the Release configuration into `build/`, makes `~/Applications/Monochrome.app` a symlink to it (a copy would be a second Safari extension, and Safari refuses one of the two) and opens it; from there the app installs itself as in step 2 above. Re-running is safe. `make run` opens the build as it is with `--portable`, which registers the host only: no login item, Dock tile, App Shortcuts or default-browser question. `Monochrome --register-host` writes the host registration and quits.

The Safari extension target's run script copies the same files into the app extension's Resources, with `manifest.json` written by `store/safari-manifest.py` (no `key`, `minimum_chrome_version`, or `tabGroups`, `search` and `favicon` permissions). The app's run script copies the extension's files (`store/files`) into the app's `Contents/Resources/extension`, makes `host.sh` executable, and writes the extension IDs the app registers its host for to `Contents/Resources/extension-ids.json`: the unpacked one, derived from the manifest key, and the store's from `store/id`. Sparkle comes in as a Swift package. `helper/Info.plist` is generated from `project.yml` and ignored by git.

**Signing.** macOS ties the Accessibility grant to the app's signature. The project signs automatically with the Artifact team, so the grant survives rebuilds on a Mac with that team's certificate; without one, Xcode's ad-hoc fallback makes each rebuild a new app to macOS and Accessibility has to be allowed again. Releases are signed with Developer ID instead, a different certificate from the Apple Development one `make install` uses, so moving between a release and a local build asks for Accessibility again.

## Shortcuts

| Keys | Effect | Handled by |
|---|---|---|
| ⌃Tab, ⌃⇧Tab | Last used tab in this window. Hold ⌃ for the switcher; release to pick; Esc cancels. Turn off in Settings → Tabs | app; extension commands as fallback |
| ⌃R | Reset the current locked tab to its locked URL | extension command |
| ⌘W, middle-click | Close. A locked tab comes back at its locked URL | Chrome; ⌘W optionally the extension |
| ⌥⇧N, from any app | New mini browser. Turn off in Settings → Mini Browsers | app; extension command as fallback |
| ⌥⌘-click | Open the link in a mini browser. Turn off in Settings → Mini Browsers | app only |
| ⌘L, in a mini browser | Address field, URL selected. Enter goes; Esc closes the field | app; in-page bar as fallback |
| ⌘L, ⌘T | The command bar: edit the front tab's address, or open a new tab. ⌥Return does the other. Turn off in Settings → Command Bar, each key on its own | app; the browser's own when off or not connected |
| ⌘O, ⇧⌘O, in a mini browser | Move it into Chrome as a tab; pick the window, tab group or another profile | app; extension commands as fallback |
| ⌥⇧R | The reader: the page's content with a summary first. Again, or Esc, goes back to the page; in a mini browser Esc closes the reader and the mini browser stays. Turn off in Settings → Command Bar; while it is on, ⌥⇧R in the browser no longer types ‰ | app; extension command as fallback |
| Esc, on a new mini browser's search page | Close it | extension |
| ⌃⌥→, ⌃⌥← | Next, previous Chrome profile (Safari profile on Safari). On by default; turn off in Settings → Profiles if Rectangle or another window manager uses them | app |
| ⌃⌥1 to ⌃⌥9 | Profile by its place in Chrome's Profiles menu (Safari's File → New Window submenu on Safari). Turn off in Settings → Profiles | app |
| ⌘S | Collapse or show the vertical tab bar. Turn off in Settings → Tabs | macOS App Shortcut, set by the app |
| ⇧⌘S | Save Page As, moved off ⌘S | macOS App Shortcut, set by the app |
| ⌥⌘↓, ⌥⌘↑ | Next, previous tab in the list. Turn off in Settings → Tabs | macOS App Shortcut, set by the app |

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

A mini browser is a popup window: no tab strip, no sidebar, ⌘[ for back. Each opens at the same size, inset from the screen's edges. One left unfocused for 12 hours closes itself (Settings → Mini Browsers → Close when unused for).

- ⌥⇧N from any app opens one with a search box: a URL, or a search in Chrome's default engine, then Enter.
- A link from another app opens one. The app is the default browser, so the link reaches it, and it asks the extension to open the window directly. When the extension is not connected, the app hands the link to Chrome, where it shows in the main window briefly before becoming a mini browser.
- ⌥⌘-click on any page opens the link in one. The tap sees the click; there is no fallback.
- The bar, top right over the title bar, is a panel of the app: a link button or ⌘L for the address field, Open in Chrome or ⌘O to move the page into the main window, a caret or ⇧⌘O for the list of windows and groups, each window named by its active tab, and under them the other profiles, where the page opens as a new tab in the front window and the mini browser closes. The bar hides while the window is dragged and while the mini browser is not the key window. Without the app, the same bar is drawn inside the page.

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

⌃⌥→ and ⌃⌥← go to the next and previous profile, ⌃⌥1 to 9 to one by position. The app reads Chrome's Profiles menu over Accessibility and presses the item (`helper/Profiles.swift`), so this works in a profile without the extension; every other feature needs the extension loaded there. A HUD shows the profiles as initials on a color derived from the name, the chosen one marked, for 1.2 seconds. The menu carries no avatar images, which is why initials. Safari's profiles come from its File menu instead; see [Safari](#safari).

## The mini player sits on the tab sidebar

When a music tab has a track loaded and another tab is in front, a panel at the bottom of the sidebar shows artwork, title, artist and transport controls. Clicking the track goes to its tab, and the close button hides the panel until the music tab has been visited and left again. It hides when the music tab is in front, when the sidebar is collapsed and when Chrome is not frontmost. On these sites the extension also stops Chrome's own pop-out player when the tab is left. Sites: Spotify, YouTube Music, SoundCloud, Apple Music, Tidal, Bandcamp, Pandora, Amazon Music, Deezer. Adding one is two entries in `manifest.json`, `music.js` and `music-relay.js`.

The panel is the app's (`helper/Player.swift`), because an extension cannot draw in the tab strip. It covers the last tabs of a long list and trails the window during a drag.

## ⌘L and ⌘T open the command bar, in Quicksilver's style

In Chrome and Safari, ⌘L and ⌘T open the app's command bar (Arc's name for it) over the front window in place of the browser's address bar: ⌘L with the front tab's address selected, ⌘T empty with the most used sites under it. It is the lower half of Quicksilver's panel (`apple/Quicksilver/Sources/CommandView.swift` in the alchemy repository), with its measurements: a 72-point capsule of clear glass with the label scrim, and 62-point rows with 48-point favicon tiles and one selection fill that slides between them (`helper/OmniboxView.swift`).

What it lists comes from the profile whose window is in front (`helper/Omnibox.swift`):

- Inline completion, in gray after what is typed: the most used host the typing starts, or with a slash, the most used page whose address it starts, once it has been typed, bookmarked or visited twice. Tab, → or End takes it; deleting it does not bring it straight back.
- What was typed, as an address (the mini browser's rules: a scheme, or a dot before a two-letter ending, localhost or an IP address) or as a search.
- Open tabs that match, as Switch to tab.
- History and bookmarks: every word in the title or the address, ranked by where they match (the start of the address, then the start of a word in the title, then anywhere) and by visits, typed visits and how recent, from the last 90 days, up to 5000 pages.
- Google's search suggestions, queries and sites, as Chrome's address bar gets them. What is typed goes to Google as it is typed.

On Chrome the extension sends the history, bookmarks, tabs and favicons (`omnibox.js`; the `history` and `bookmarks` permissions) and searches with Chrome's default search engine. Safari gives extensions none of these: the app reads the profile's `History.db` and the shared `Bookmarks.plist` from `~/Library/Safari`, which needs Full Disk Access for Monochrome, takes favicons from Google's favicon service, and searches Google. Without a connected extension in the front profile, or with the setting off, the keys go to the browser.

`Monochrome --demo-omnibox out.png [dark]` draws the box on sample history into a PNG; `Monochrome --omnibox chrome|safari <text>` types into the running app's box for a connected profile without showing it and logs the rows.

## The reader opens with a summary

⌥⇧R, the `tldr` command, or the ¶ button on a mini browser's bar draws the page in front as an article: a summary card, then the page's own text with its images, video, tables and code, and without its ads, navigation, sign-up boxes and comments. Esc or "Original page" puts the page back as it was. The plan, with what is built and what is not, is `docs/tldr.md`.

- **Nothing runs until asked.** No script is on a page before the reader is asked for. Then the worker (`tldr-background.js`) injects `tldr/core`, which finds the article with Mozilla's Readability on a copy of the document, walks the live page into a list of blocks, and draws them in a closed shadow root over the page. The page is hidden, not changed.
- **The summary comes from the Mac.** The blocks' text goes over the bridge to the app, which asks Apple's on-device model (FoundationModels, macOS 26 and later) for five points and six facts, each naming the block that states it. Each one is checked against that block in the page before it is drawn, and a click on it scrolls there. Without the app or the model the card is an outline: the lead sentence, the sentences that carry numbers, and the headings.
- **Embeds wait for a click.** A YouTube or other listed player is a placeholder until clicked, so its host hears nothing before that. Frames from other hosts are left out.

## The address bar opens the matching page from history

Typing words and pressing Enter opens the history entry that matches them rather than a search. Chrome allows this only with `--enable-features=OmniboxForceAllowedToBeDefault`, which is not on `chrome://flags`, so the app passes it when it starts Chrome. A search made before for the same words can still outrank the page. The flag list is `features` in `helper/Chrome.swift`; a change takes effect after a rebuild and a restart of Chrome from the Dock.

## The app is one binary in several roles

- **The app** (no arguments): installs itself at launch, owns the event tap and every panel, the Dock tile and the default-browser role, and listens on a Unix socket in `~/Library/Application Support/Monochrome`. A click on its Dock tile opens Chrome; a double-click in the Finder, or the ▾ menu of any mini browser's bar, opens the settings window.
- **The host** (`--host`): what Chrome spawns for the extension's native messaging port. It relays between the port and the app's socket, and pings the extension every 20 seconds so Chrome does not stop the service worker for idleness. Each Chrome profile gets its own host process and connection; the app routes tab actions to the connection that owns the tab and front-window actions to the connection whose front window matches Chrome's.
- **The Safari extension** (`Contents/PlugIns/Monochrome Extension.appex`): what the extension's native port reaches in Safari. It relays each message to the app over a socket in the app group container, with the Safari profile it came from; the app answers through `SFSafariApplication.dispatchMessage`.
- **Commands:** `--portable` (the app, registering the host only), `--register-host`, `--status` (the chosen browser, the layout's keycodes, whether the app is running, whether the socket is up), `--routes [url [sender]]`, `--settings`, `--make-default`, `--unregister` (removes the login item), `--check-safari <json>` (the Safari readers on given input, for the tests), `--check-tldr` (a reader request on stdin, the model's answer on stdout, for the tests), `--prefs [--defaults]` (the settings sent to the extension, as JSON), and `--demo`, `--demo-profiles`, `--demo-shade` for the panels over sample data. `--demo-settings [tab] [out.png] [dark]` shows the settings window on a tab (`general`, `browser`, `profiles`, `tabs`, `mini`, `command`, `player`, `router`, or 0 to 7; Router when none) with sample rules and profiles over scratch defaults, so no real setting changes; with `out.png` it draws the tab into that file and quits, no screen recording needed.

The settings window has a row for every feature that can be switched, each with an SF Symbol and one line saying what it does, on eight tabs: General (open at login, automatic updates, the version with Check for Updates…, default browser, Accessibility), Browser (Chrome or Safari, whether Chrome opens when the app starts, the launch flag, the Dock tile; Install Extension…, which shows the floating panel with the extension folder to drag onto chrome://extensions, Extension Shortcuts…, and a warning triangle and Relaunch… when Chrome runs without its launch flags), Profiles (each connected profile with its browser's icon and a letter avatar, the profile keys and the HUD), Tabs (locked tabs and the locked group's title, new tabs at the top, the two App Shortcuts, ⌃Tab, the switcher panel, its thumbnails, delay and size), Mini Browsers (⌥⇧N, ⌥⌘-click, peek browsers, where links from other apps open when no rule claims them, when an unused one closes), Command Bar (⌘L and ⌘T each, Google suggestions, Full Disk Access when Safari is in play, the reader's ⌥⇧R and the state of the model that writes its summary), Player (the mini player, stopping the sites' own pop-out, the nine sites) and Router (the rules). Every default is the behaviour before the settings existed. The app keeps them all and sends the extension the nine it obeys (`{"prefs": {…}}` on each connection and on every change), which it stores and uses even before the app starts; without the app the extension runs on the defaults. `docs/settings.md` has the list. While the window is open the app shows in the Dock with a menu bar; when it closes the app goes back to running without either.

Logs go to the unified log under subsystem `com.artifact.monochrome`:

```bash
/usr/bin/log stream --info --predicate 'subsystem == "com.artifact.monochrome"'
```

## Uninstall

```bash
~/Code/monochrome/uninstall.sh
```

It removes the app, its login item, Dock tile, settings, support folder and host registration, the Safari relay's app group folder, this project's Chrome and Safari App Shortcuts, and what earlier versions installed. Karabiner itself and other App Shortcuts stay. The Safari extension goes with the app. Then remove the extension in `chrome://extensions`, restart Chrome (and Safari, for its App Shortcuts), and choose a default browser in System Settings → Desktop & Dock.

## Releases and the Web Store

- **The app** is released as a zip on GitHub by `make release VERSION=<version>`: it sets the version in `project.yml` and `manifest.json`, archives, has Xcode sign the archive with the team's cloud-managed Developer ID certificate and submit it to Apple's notary service, waits for the stapled app, checks it with `spctl`, writes `dist/Monochrome-app-<version>.zip` and regenerates `appcast.xml`, then prints the `gh release create` and the commit that publish. The v1.0 zip predates the app installing itself, so it does not register the native messaging host; a release built from this version does.
- **Updates** come through Sparkle: the app checks `appcast.xml` on `main` (raw.githubusercontent.com) once a day and from Check for Updates… in its menu and on the General tab (Check for updates automatically turns the daily check off), and installs the zip the appcast names. Entries are signed with an EdDSA key in the keychain of the Mac that releases, made by Sparkle's `generate_keys`; its public half is `SUPublicEDKey` in `project.yml`, so a release from another Mac needs that key exported from this one. Sparkle 2.10.1 is a Swift package dependency in `project.yml`; `generate_appcast` comes from its checkout under `build/SourcePackages`. An update found by the daily check brings the app forward for its alert, since it has no windows otherwise.
- **The extension** is packed by `store/pack.sh` into `dist/store/monochrome-extension-<version>.zip`, without the app, tests, docs, scripts or the manifest's `key`, which the store refuses. The store assigned the ID in `store/id` on the first upload. To make the unpacked extension the same extension as the store's, install the store's copy once and run `store/adopt-key.sh <id>`, which copies the store's key into this manifest and reinstalls the app.
- `store/listing.md` holds the listing text, permission justifications and privacy answers. The listing links Artifact's shared policy at artifact.com/privacy?Monochrome; `docs/privacy.md` is the detailed statement. `store/screenshots/` holds the switcher, profile HUD and Router tab from `--demo --backdrop`, `--demo-profiles --backdrop` and `--demo-settings --backdrop`, and the promo tiles from `swift store/tiles.swift`, all JPEG.

## Tests

```bash
npm install && npx playwright-core install chromium && make build && npm test
```

The suite drives headless Chromium with the extension loaded. With the app built, it also spawns it in host mode against a private socket, has the app write its host registration into a fresh Chromium profile and checks that the extension there reaches a socket standing in for the app, and runs the app's Safari readers on sample input (`--check-safari`), writing the Safari App Shortcuts to a scratch preferences domain that it deletes afterwards. `HEADFUL=1 npm test` adds the link hand-off from another app, which headless Chromium cannot receive.

`npm test` then runs `test-tldr.mjs`, the reader's tests: verification on its own, the reader on three synthetic pages in `tldr/fixtures` with no model, and, with the app built, the message path through the host to a socket standing in for the app and one run of the on-device model on two fixtures (`--check-tldr`), which is skipped on a Mac without the model. `node tldr/shots.mjs <folder> [address …]` saves screenshots of the reader.

## Not verified

I am an automated contributor, and this is what I did not exercise by hand: the app's install at launch on a Mac (Dock tile, App Shortcuts, default-browser question, removal of earlier versions; the host registration is covered by the tests); two profiles connected to the app at once; dragging a peek browser with its shade; a profile switch by hotkey beyond reading the menu; a rule with a `profile` destination for a profile that is not running; whether every app's open event names the sender; the command bar in a Chrome profile with more than 5000 history pages in 90 days; whether Chrome matches the ⌃. and ⌃, fallback commands by typed character or by key position on Dvorak; and whether reading Chrome's menu bar and window titles over Accessibility changes Chrome's own accessibility mode.

## What would change this design

A Chrome API for the Tab key, for drawing over the window, or for native panels in the tab strip would remove the app's reason to exist for the switcher and player. Native messaging that Chrome could initiate would remove the 20-second ping. Avatar images in the Profiles menu, or a sanctioned way to read the profile list, would replace the initials.

Until then, the extension does the bookkeeping and the app does the drawing.

## License

MIT. See `LICENSE`. The reader includes Mozilla's Readability.js, unmodified, under the Apache License 2.0: `tldr/vendor/LICENSE`.
