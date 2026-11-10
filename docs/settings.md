# Every feature gets a row in the settings window

Naming: the ⌘L/⌘T box is the command bar (Arc's name) in every user-facing string; the code keeps `Omnibox` and the `omnibox` keys.

A plan for the settings window (`helper/Settings.swift`): which tabs it has, which control each feature gets, where each value is stored, and how the extension hears about the ones it must obey. Written November 10, 2026 against `origin/main` at `34f9ee4`. Nothing here is built.

## Summary

The settings window has two tabs and two switches (`profileHotkeys`, `omnibox`). The README describes about thirty features. The plan gives each feature that can be switched a row, so the window is both the list of what Monochrome does and the place to turn a part of it off.

- **Eight tabs:** General, Browser, Profiles, Tabs, Mini Browsers, Command Bar, Player, Router. 36 controls outside Router, which keeps its rules editor.
- **25 settings keys**, all in the app's defaults. 16 are read by the app alone. 9 are behaviour of the extension, and the app sends those to every connected copy as one `prefs` message.
- **Every row carries its keys in the label and one descriptive line.** That is settled, below.
- **The app is the one place settings are edited.** The extension's options page keeps the connection status, the Keyboard Shortcuts button and, only while the app is not connected, the locked group's title.
- Every default is today's behaviour. A Mac that updates and touches nothing behaves as before.

This document does not cover the Router's rule format (`docs/link-routing.md`), new features, or the look of the panels the settings control.

## Settled

1. **Each row may carry a single descriptive line, under or beside its control. Longer explanatory footers stay out.** This replaces the "no explanatory footers" rule in the header comment of `helper/Settings.swift`, which changes to say so. The line is how a row advertises its feature; a tooltip would not, since it shows only to someone already pointing at the row. The limit holds the original rule's intent: no paragraph under a section, no wrapped text, no "learn more" link. Every description in the tables below is one line of at most 60 characters.
2. **Defaults are today's behaviour.** No setting in this plan changes what a current install does until someone flips it.

## What I checked

`make build` in this worktree succeeded on November 10, 2026. `Monochrome --demo-settings --backdrop` started and printed the backdrop's rectangle. `screencapture -R` on that rectangle answered `could not create image from rect`, so I did not see the current window; what this document says about its layout is a reading of `Settings.swift`. Step 7 of the order of work removes the dependence on screen capture.

## Inventory: what a person can see or press today

"Setting today" is where the feature can be turned off or changed now.

| # | Feature | Keys | Built in | Chrome | Safari | Setting today |
|---|---|---|---|---|---|---|
| 1 | Locked tabs: a pinned tab closed comes back at its locked address | ⌘W, middle-click; ⌃R resets | extension (`background.js`) | yes | yes | none |
| 2 | Locked group: tabs in a tab group with a set title lock too | same | extension | yes | no tab groups | options page, `lockedGroup` in `chrome.storage.local` |
| 3 | Replace pinned URL with current | a command with no default key | extension | yes | no shortcuts page | `chrome://extensions/shortcuts` |
| 4 | New tabs open at the top, under the locked tabs | ⌘T | extension | yes | unmeasured | none |
| 5 | ⌃Tab goes to the last used tab of the window | ⌃Tab, ⌃⇧Tab | app tap (`Tap.swift`); extension keeps the list; ⌃. ⌃⇧. ⌃, as fallback commands | yes | yes | none |
| 6 | Switcher panel: the five most recent tabs while ⌃ is held | hold ⌃, Esc | app (`Switcher.swift`) | yes | yes | none |
| 7 | Thumbnails in the switcher | none | extension captures (`helper.js`), app holds them in memory | yes | needs "every website" | none |
| 8 | New mini browser | ⌥⇧N, from any app | app tap; `mini-new` command as fallback | yes | needs the app | none |
| 9 | Link into a mini browser | ⌥⌘-click | app tap, then extension | yes | yes | none |
| 10 | Links from other apps open as mini browsers | none | app as default browser, then extension | yes | yes | a catch-all rule on the Router tab |
| 11 | Mini browser bar: address field, Open in Chrome, pick a window, group or profile | ⌘L, ⌘O, ⇧⌘O | app panel (`MiniBrowser.swift`); in-page bar as fallback | yes | unmeasured | none |
| 12 | A mini browser unfocused for 12 hours closes | none | extension (`mini-browser.js`) | yes | yes | none |
| 13 | Peek browsers: a new-tab link from a locked tab opens over the window, shaded | none | extension scripts, app shade | yes | unmeasured | none |
| 14 | Link router | none | app (`Routes.swift`), extension (`routes.js`) | yes | no group destination | Router tab |
| 15 | Profile hotkeys | ⌃⌥→, ⌃⌥←, ⌃⌥1 to ⌃⌥9 | app (`Profiles.swift`) | yes | yes | `profileHotkeys` |
| 16 | Profile HUD, 1.2 seconds | none | app | yes | yes | none |
| 17 | Mini player on the tab sidebar, nine music sites | none | extension (`player.js`, `music.js`), app panel (`Player.swift`) | yes | Safari 27.3 or later | none |
| 18 | Chrome's own pop-out player stopped on those sites | none | extension (`music.js`) | yes | unmeasured | none |
| 19 | Command bar | ⌘L, ⌘T; ⌥Return does the other | app (`Omnibox.swift`), data from the extension | yes | yes | `omnibox`, one switch for both keys |
| 20 | Google suggestions in the command bar | none | app | yes | yes | none |
| 21 | Safari history and bookmarks in the command bar | none | app reads `~/Library/Safari` | no | needs Full Disk Access | none |
| 22 | App Shortcuts | ⌘S, ⇧⌘S, ⌥⌘↓, ⌥⌘↑ | app writes `NSUserKeyEquivalents` (`Install.swift`, `Safari.swift`) | every launch | when Browser is Safari | none |
| 23 | Address bar opens the matching history page | none | app passes `OmniboxForceAllowedToBeDefault` (`Chrome.swift`) | yes | no | none |
| 24 | Dock tile in Chrome's place | none | app | yes | no | none; placed once per app location |
| 25 | Chrome started when the app starts | none | app (`App.swift`) | yes | no | none |
| 26 | Default browser | none | app | | | General row; asked once per app location |
| 27 | Login item | none | app | | | General toggle |
| 28 | Updates through Sparkle, daily | none | app | | | Check for Updates… only |
| 29 | Browser the app works with | none | app | | | `browser` |
| 30 | Extension fallback commands | ⌃R, ⌃., ⌃⇧., ⌃, and unbound ones | extension | shortcuts page | no page | `chrome://extensions/shortcuts` |

## The app owns the settings and sends the extension its share

The usual place for an extension's settings is its options page, backed by `chrome.storage`. That works for a single-profile extension. Here it relies on one copy of the extension, and there is one copy per profile per browser: a switch set on an options page would have to be set again in every Chrome profile and again in Safari. The app already holds the settings the event tap reads, and it already has a connection to every copy. So the app's defaults are the source, and the extension keeps a copy.

**App side.** A new `helper/Prefs.swift` holds every key, its default, a typed accessor and the store. Readers call `Prefs.switcher` and the like at the moment of use, as `Tap.swift` reads `profileHotkeys` today, so a flipped switch needs no restart of the app. The store is `UserDefaults.standard`, replaceable for `--demo-settings` (step 7).

**The message.** The app sends the whole set, never a delta:

```json
{ "prefs": { "lockedTabs": true, "lockedGroup": "CoreCore", "newTabsAtTop": true,
             "peek": true, "miniIdleHours": 12, "routeDefault": "mini",
             "thumbnails": true, "player": true, "playerStopPopout": true } }
```

It goes to a connection each time that connection says `hello` (which covers a new connection, the app's `resend` after its own restart, and Safari), and to every connection in `allConnections` when a sent key changes. The key is `prefs`, not `settings`: `App.receive` already treats an incoming `settings` as "open the settings window".

**Extension side.** `background.js` gets `PREF_DEFAULTS` and a `PREFS` object. `helperMessage` (`helper.js`) gains `else if (msg.prefs) applyPrefs(msg.prefs)`, which copies the known keys over the defaults, writes the result to `chrome.storage.local` under `prefs`, and runs the side effects in the table below. At worker start `PREFS` is read back before `ready` resolves. `chrome.storage.local` is the store because the value must be there when the browser starts before the app does; `storage.session` is emptied at restart and `storage.sync` belongs to a Google account.

**Without the app.** A copy that has never heard from the app runs on `PREF_DEFAULTS`, which is today's behaviour. A copy that has heard keeps the last set it was sent.

**Version skew.** The app and the extension update separately. An older extension ignores `prefs`. A newer extension under an older app keeps its defaults. Unknown keys are dropped and missing keys keep their default, in both directions.

**The locked group's title moves.** It is the one setting the extension holds today. `hello` gains the title when the legacy `lockedGroup` key exists: `{ "hello": { "session": "…", "lockedGroup": "Work" } }`. The app takes it only if its own `lockedGroup` has never been set, and the extension deletes the legacy key when its first `prefs` arrives. After that there is one title for every profile, where there could be one per profile before.

## Tabs and controls

Eight tabs in the toolbar, in this order. Keys go in each row's label, in the README's notation. Every row has an SF Symbol left of its title, and no two rows share one. There is no Keyboard tab: it would list every row a second time, and the README's Shortcuts table is already that list.

- **General** is the app itself and what macOS grants it.
- **Browser** is what the app sets up around the browser: which one, its extension, how Chrome starts. It is split from General because together they are 12 controls.
- **Profiles** is the connected profiles and the keys that switch between them.
- **Tabs** is the tab sidebar: locked tabs, tab order, ⌃Tab, and the App Shortcuts, which are all sidebar keys.
- **Mini Browsers** holds mini and peek browsers, which are the same windows.
- **Command Bar** is ⌘L and ⌘T.
- **Player** has two switches and the list of sites. It is its own tab because the site list is the advertisement and has no other home.
- **Router** is unchanged apart from its empty-state text.

"Sent" in the Key column marks the nine keys in the `prefs` message. Type T is a toggle, P a picker, B a button, S a status row that shows a state or the button that fixes it.

### General: 5 controls

| Label | Type | Default | Key | Read by | Description |
|---|---|---|---|---|---|
| Open at login | T | on | none (`SMAppService`); `loginItemFor` records the first registration | `GeneralModel.setLaunchAtLogin` | Monochrome starts with the Mac |
| Check for updates automatically | T | on | Sparkle's `SUEnableAutomaticChecks` | `updater.automaticallyChecksForUpdates` | Once a day, from the appcast on GitHub |
| Version 1.2.1 | B Check for Updates… | | none | `SettingsWindow.checkForUpdates` | none |
| Default browser | S Make Default… | | none | `GeneralModel.makeDefault` | Links from other apps reach Monochrome first |
| Accessibility | S Open Settings… | | none | `AXIsProcessTrusted` | For ⌃Tab, ⌥⌘-click, ⌘L, ⌘T and the profile hotkeys |

### Browser: 7 controls

| Label | Type | Default | Key | Read by | Description |
|---|---|---|---|---|---|
| Browser | P Chrome, Safari | Chrome | `browser` | `Browser.current` | Where links from other apps open |
| Open Chrome with Monochrome | T | on | `openBrowserAtLaunch` | `App.applicationDidFinishLaunching` | So Chrome starts at login with its launch flags |
| Address bar opens the matching history page | T | on | `launchFlags` | `Chrome.open`, `relaunchWithFlags`, `runningWithFlags`, `warnIfStartedWithoutFlags` | A launch flag, for Chrome started from the Dock tile |
| Dock tile | S Add to Dock | placed once | `dockTileFor` | `Install.dockHasTile`, `placeDockTile` | Takes Chrome's tile and starts Chrome with the flags |
| Extension: Install Extension… (Safari: Extension Settings…) | B | | none | `GeneralModel.installExtension` | Connects each browser profile to Monochrome |
| Extension shortcuts: Open… | B, Chrome only | | none | opens `chrome://extensions/shortcuts` | Chrome's own page for the extension's keys |
| Relaunch Chrome: Relaunch… | B, shown when Chrome runs without the flags | | none | `GeneralModel.relaunchChrome` | Chrome is running without Monochrome's flags |

The Extension section's header carries the warning triangle when Chrome runs without the flags.

### Profiles: 3 controls

| Label | Type | Default | Key | Read by | Description |
|---|---|---|---|---|---|
| Step through profiles ⌃⌥→, ⌃⌥← | T | on | `profileArrows` | `Tap.handle` | Off if a window manager uses these keys |
| Profile by number ⌃⌥1 to ⌃⌥9 | T | on | `profileDigits` | `Tap.handle` | By place in the browser's profile menu |
| Profile HUD | T | on | `profileHUD` | `Profiles.go` | Shows the profiles for 1.2 seconds on a switch |

The Browser Profiles list (each connected profile with its browser's icon and letter avatar) and its warning triangle move here from General. With no profile connected it says to install the extension on Browser.

### Tabs: 10 controls

| Label | Type | Default | Key | Read by | Description |
|---|---|---|---|---|---|
| Locked tabs come back when closed | T | on | `lockedTabs`, sent | `lockedTabs()` in `background.js` | Pinned tabs reopen at their locked address; ⌃R resets one |
| Locked group | text field, prompt "none" | CoreCore | `lockedGroup`, sent | `LOCKED_GROUPS` in `background.js` | Tabs in a Chrome tab group with this title lock too |
| New tabs open at the top | T | on | `newTabsAtTop`, sent | `tabs.onCreated` in `background.js`; `moveToMain`; `routeOpen` | Directly under the locked tabs |
| Collapse the tab sidebar ⌘S | T | on | `shortcutSidebar` | `Install.setChromeShortcuts`, `SafariShortcuts.write` | Save Page As moves to ⇧⌘S, after a browser restart |
| Next and previous tab ⌥⌘↓, ⌥⌘↑ | T | on | `shortcutTabs` | same | Steps down and up the tab list, after a browser restart |
| ⌃Tab goes to the last used tab | T | on | `switcher` | `Tap.handle` | By recent use in this window; off leaves the browser's order |
| Switcher panel | T | on | `switcherPanel` | `tap.useSwitcher` in `App.swift` | Hold ⌃ to pick from recent tabs; release to go |
| Thumbnails | T | on | `thumbnails`, sent | `helperThumbSoon` in `helper.js`; the app empties `switcher.thumbs` | A picture of each tab, kept in memory only |
| Panel appears after | P 0.1, 0.15, 0.3, 0.5 s | 0.15 s | `switcherDelay` | `Switcher.step` (today `showAfter`) | A quicker tap switches without the panel |
| Tabs shown | P 3 to 7 | 5 | `switcherCount` | `Switcher.step` (today `maxVisible`) | Fewer on a narrow screen |

Notes on what each does when off:

- `lockedTabs` off: nothing is locked, a closed tab stays closed, and the saved order is emptied, so turning it back on locks each tab at the address it then has.
- `lockedGroup` empty: only pinned tabs lock. Today an empty title falls back to CoreCore.
- `newTabsAtTop` off: new tabs, a mini browser moved into the browser and routed links land where the browser puts them. A new tab the browser drops into the locked group is still taken out.
- `switcher` off: the tap passes ⌃Tab through and the browser's own order applies.
- `switcherPanel` off: `useSwitcher` answers false, so the tap rewrites the keys to the extension's commands and tabs switch live, the path used today when the extension is not connected. It needs ⌃., ⌃⇧. and ⌃, bound in the browser.
- `shortcutSidebar` or `shortcutTabs` off: the app removes those entries from `NSUserKeyEquivalents`, only where they still hold Monochrome's values.
- `switcherCount`: the extension sends the 12 most recent tabs across all windows (`MRU_SENT`), so with several windows the front one's share can be fewer than the count. Unchanged by this plan.

### Mini Browsers: 5 controls

| Label | Type | Default | Key | Read by | Description |
|---|---|---|---|---|---|
| New mini browser ⌥⇧N | T | on | `miniHotkey` | `Tap.handle` | From any app: a small window with a search box |
| ⌥⌘-click opens a mini browser | T | on | `miniClick` | `Tap.handle` | On any page in the browser |
| Links from other apps open as | P Mini browser, New tab in the front window, Tab already on that site | Mini browser | `routeDefault`, sent | `App.route`; the `start_page` listener in `mini-browser.js` | When no Router rule claims the link |
| Close when unused for | P Never, 1 hour, 12 hours, 1 day, 1 week | 12 hours | `miniIdleHours`, sent (0 is never) | `archiveMiniBrowsers` in `mini-browser.js` | A mini browser left unfocused closes itself |
| Peek browsers from locked tabs | T | on | `peek`, sent | `injectPeekCatch` and `tabs.onCreated` in `background.js` | A link from a locked tab opens over the window, shaded |

`peek` off: the extension tells every locked tab's catch script to stand down (the existing `{ mini: 'locked', value: false }` message), stops injecting it, and a foreground link from a locked tab becomes a new tab at the top. On again: it injects into every locked tab.

### Command Bar: 4 controls

| Label | Type | Default | Key | Read by | Description |
|---|---|---|---|---|---|
| ⌘L edits the front tab's address | T | on | `omniboxL` | `App.openOmnibox(newTab: false)` | In the command bar; ⌥Return opens a new tab |
| ⌘T opens a new tab | T | on | `omniboxT` | `App.openOmnibox(newTab: true)` | From the command bar, with the most used sites listed |
| Google suggestions | T | on | `omniboxSuggestions` | `model.onSuggest` in `App.setUpOmnibox` | What is typed goes to Google as it is typed |
| Full Disk Access | S Open Settings…, shown when Browser is Safari or a Safari profile is connected | | none | whether `SafariHistory.databaseURL` is readable | For Safari's history and bookmarks |

⌘L inside a mini browser is the bar's address field, not the command bar, and follows neither switch.

### Player: 2 controls

| Label | Type | Default | Key | Read by | Description |
|---|---|---|---|---|---|
| Mini player on the tab sidebar | T | on | `player`, sent | `playerState` in `player.js` | Artwork, title and controls while a music tab plays behind |
| Stop the browser's pop-out player | T, disabled when the mini player is off | on | `playerStopPopout`, sent | `music.js`, told by `music-relay.js` | On the listed sites, when their tab is left |

Beside them, the nine sites as a plain list: Spotify, YouTube Music, SoundCloud, Apple Music, Tidal, Bandcamp, Pandora, Amazon Music, Deezer.

`music.js` runs in the page's world and cannot read extension storage. `music-relay.js` reads `prefs` from `chrome.storage.local`, watches it for changes, and posts `{ monochromeMusicPrefs: { stopPopout } }` to the page. `music.js` always holds a site's `enterpictureinpicture` handler back, and registers it when told the setting is off, because the site may register before the relay's read returns. The effective value is `player && playerStopPopout`.

### Router: unchanged

The rules list, add and remove, Show File, and the selected rule's fields stay as they are. The empty list's text, "Links from other apps open as mini browsers.", is replaced by the current `routeDefault` in words.

## Cleanup of what exists

1. **General splits.** Browser, the Browser Profiles list, Install Extension… and Relaunch Chrome… move to the Browser tab. Profile hotkeys moves there and becomes two toggles. "Command bar for ⌘L and ⌘T" moves to Command Bar and becomes two toggles.
2. **Old keys are read as fallbacks, not migrated.** `omniboxL` and `omniboxT` fall back to `omnibox` when unset; `profileArrows` and `profileDigits` fall back to `profileHotkeys`. Nothing writes the old keys again.
3. **"Open at login" does not hold today.** `App.swift` line 73 registers the login item on every launch, so the toggle turned off is back on after the app next starts. The registration moves to once per app location, recorded in `loginItemFor`, the way `dockTileFor` and `defaultBrowserAskedFor` work.
4. **Dead code goes.** `GeneralModel.extensions`, its `connections` closure and `SettingsWindow.connectionsSummary` (set in `App.swift` line 79) feed no view.
5. **Labels follow the README.** Command bar, mini browser, peek browser, locked tabs, mini player, switcher, profile HUD, App Shortcuts. Keys are written as the Shortcuts table writes them: "⌃⌥→, ⌃⌥←" and "⌃⌥1 to ⌃⌥9", where the current label has "⌃⌥← →" and "⌃⌥1–9". The header comment's "Routes" becomes Router.
6. **Layout rules.**
   - The window is 760 points wide on every tab. Height is per tab, fitted so no tab scrolls, and set from the step 9 screenshots; I have no measured heights to give.
   - Every tab but Router is two columns of grouped forms. The left column holds the feature's main switches, the right its dependents, status rows or list.
   - A section header is one or two words. No section has a footer.
   - A row is a title with its keys, then its one description line in caption size and secondary color, one line, never wrapped. A shared `SettingRow` view draws it so every tab matches. Buttons carry no description.
   - A dependent row is disabled while its parent is off: Switcher panel, Thumbnails, Panel appears after and Tabs shown under ⌃Tab; Locked group under Locked tabs; the pop-out row under the mini player.
   - A Chrome-only row says Chrome in its label or description and stays visible, since both browsers can be in use at once. The one Safari-only row appears only when Safari is in play.
7. **`Settings.swift` splits by job.** It is 606 lines with two tabs. `Settings.swift` keeps the window, the tab controller and `SettingRow`; `SettingsTabs.swift` holds the six forms; `SettingsRouter.swift` takes `Rule`, `RulesModel` and `RoutesSettings` unchanged; `InstallPanel.swift` takes `InstallExtensionPanel` and `FolderDragView`. `project.yml` compiles everything under `helper/`, so no project change.

## The options page keeps three things

1. The connection status and the Get the app link, as now.
2. The locked group's title: editable while the app is not connected, where it writes `prefs.lockedGroup` locally; read-only with "Set in Monochrome's settings" while it is. The extension runs without the app, and a title is data that a default cannot stand in for.
3. Keyboard Shortcuts…, as now, and a new Monochrome Settings… button shown when connected. It sends `{ "settings": true }` over the port, which `App.receive` already answers by showing the window.

It does not mirror the other eight sent settings. A second editor per profile is the arrangement this plan removes, and without the app the defaults apply.

## What gets no setting

Nothing on the requested list was dropped: each item can be honoured with a guard at one or two call sites. The three that cost more than a guard are the pop-out switch (the relay above), peek (it must reach scripts already in pages) and the App Shortcuts (turning them off means removing entries, not only ceasing to write them).

These get no row, with the reason:

- **Per-site switches for the mini player.** The nine sites are static `content_scripts` matches in `manifest.json`; a per-site switch means registering the scripts at run time.
- **Mini browser size and position.** One fixed inset in `mini-browser.js`.
- **Search engine.** Chrome's default through `chrome.search`; Google on Safari, decided in `docs/safari.md`.
- **⌘L, ⌘O, ⇧⌘O inside a mini browser, and the bar itself.** They act only in windows Monochrome made, and the bar is the only way to move a page into the browser.
- **⌃R, ⌘W through the extension, Replace pinned URL, and the fallback commands.** The browser owns those bindings. Extension Shortcuts… opens its page.
- **Favicons from Google's service on Safari.** Safari gives extensions no icons; off would mean no icons.
- **HUD duration, switcher dimensions, the 20-second ping, removal of earlier versions, the Arc import.** Constants or one-time steps, not asked for.
- **Removing the Dock tile.** The row adds it; dragging it out removes it.

## Verification

**`--demo-settings` per tab.** It becomes `--demo-settings [tab] [out.png] [dark]`, where `tab` is `general`, `browser`, `profiles`, `tabs`, `mini`, `command`, `player` or `router`, or its index 0 to 7. With no tab it shows Router, so the command in `store/listing.md` still makes `3-router.jpg`; `--general` goes. With `out.png` the window's content view is drawn into the file from the view itself, as `--demo-omnibox` does, so no screen recording is needed; the toolbar is not part of that view and the sidebar material may not draw. In demo mode `Prefs` uses a scratch defaults suite emptied at start, and the Browser Profiles list shows three sample profiles, so a demo run changes no real setting. One PNG per tab, light, looked at before the PR.

**`npm test` additions**, each driving the service worker as the suite already does:

1. With no `prefs` message, `PREFS` equals `PREF_DEFAULTS`, and every existing check passes unchanged.
2. `helperMessage({ prefs })` stores the set under `prefs` in `chrome.storage.local`; an unknown key is dropped.
3. `newTabsAtTop` false: a new tab stays where Chromium puts it. True again: it goes under the locked tabs.
4. `lockedTabs` false: a closed pinned tab stays closed.
5. `lockedGroup` "Work": a tab in a Work group comes back and one in CoreCore does not. Empty: only pinned tabs lock.
6. `peek` false: a `target="_blank"` link from a locked tab makes a tab and no popup window.
7. `miniIdleHours` 0: `archiveMiniBrowsers` 13 hours on closes nothing. 1: two hours on closes it.
8. `thumbnails` false: `helperThumbSoon` schedules nothing.
9. `player` false: `playerState()` is null. `playerStopPopout` false: the page's `enterpictureinpicture` handler runs when sent that action; true: it does not.
10. `hello` carries a legacy `lockedGroup`, and the key is gone after the first `prefs`.
11. The options page disables the group field when `helperUp()`.
12. With the app built, `Monochrome --prefs --defaults` prints the default `prefs` payload and it deep-equals `PREF_DEFAULTS`, so the two lists cannot drift.

**Not covered by the suite.** The 16 app-only keys act in the event tap, the installer and Sparkle, which the tests cannot drive. Each needs a hand check: switch off, press the keys, see the browser get them. Nothing in Safari has been tried, as `docs/safari.md` records for every Safari feature.

**Documents to update in the same PR.**

- README: the Shortcuts table's two "Turn off in Settings → General" cells; the paragraph that begins "The settings window has two tabs"; Install steps 5 and 7 and the Safari list where they name the options page as the home of the group title; Safari step 5's "General → Browser"; `--demo-settings` under Commands.
- README corrections found on the way: "Size and position are remembered" for mini browsers, where `mini-browser.js` opens each at one size and deletes the size earlier versions kept; and "Esc, in a mini browser: Close it", which the code does only on the new mini browser's search page.
- `docs/privacy.md` says neither part sends anything off the computer and that the app has no network access beyond artwork. The command bar sends what is typed to Google. The statement gains the suggestions, Safari's favicon lookups and the update check, and names the Google suggestions switch. `store/listing.md`'s privacy answers follow.
- `docs/safari.md`: the options page line under extension feature 2.
- The header comments of `Settings.swift`, `Tap.swift` and `background.js`.

## Order of work, one PR

1. `helper/Prefs.swift`: keys, defaults, accessors, the replaceable store, the fallbacks to `omnibox` and `profileHotkeys`, the `prefs` payload, and `--prefs --defaults` in `main.swift`.
2. App readers: `Tap.handle` (five guards), `App.openOmnibox`, `setUpOmnibox`, `useSwitcher`, `App.route`, the launch of Chrome, `Switcher.step`, `Profiles.go`, `Chrome.open` and the three flag functions, `Install.setChromeShortcuts` and `SafariShortcuts.write` with removal, the once-per-location login item.
3. Extension: `PREF_DEFAULTS`, `PREFS`, `applyPrefs` and the readers in `background.js`, `mini-browser.js`, `routes.js`, `helper.js`, `player.js`; the relay in `music-relay.js` and `music.js`; `hello`'s legacy title.
4. The push: send `prefs` on each `hello`, and to all connections when a sent key changes; adopt a legacy title once.
5. Split `Settings.swift` into the four files with no change in behaviour, and remove the dead code.
6. `SettingRow`, then the six forms, tab by tab in toolbar order; Router's empty-state text.
7. `--demo-settings [tab] [out.png] [dark]` with the scratch store and sample profiles.
8. The options page.
9. Tests 1 to 12; `make build && npm test`; one PNG per tab, looked at; set each tab's height from them.
10. README, `docs/privacy.md`, `store/listing.md`, `docs/safari.md`, header comments. Regenerate `store/screenshots/3-router.jpg` only if the Router tab's look changed.

## Open

Each has a proposed default, which is what step 1 builds unless changed.

1. **Google suggestions default.** Proposed: on, which is today's behaviour and Chrome's own. Off by default would be the stricter reading of `docs/privacy.md`.
2. **One locked group title for all profiles.** Proposed: one, with the first legacy title a copy reports adopted. Two profiles with different titles lose the second.
3. **Switcher panel off means live switching through the extension's commands.** Proposed: yes. The alternative is a walk with nothing on screen until ⌃ is released.
4. **Player as its own tab with two switches.** Proposed: yes, for the site list. The alternative folds it into Tabs, which then has 12 controls.
5. **The launch flag row sits on Browser, not Command Bar.** Proposed: Browser, beside the Dock tile and the relaunch button it depends on.
6. **App Shortcuts off removes entries only when they still hold Monochrome's values.** Proposed: yes, so a shortcut someone reassigned is left alone.
7. **Rows whose feature needs Accessibility or a connected extension that is missing.** Proposed: they stay enabled with no per-row warning; General and Browser show the two states.
8. **Open Chrome when Monochrome starts, as a setting.** Proposed: keep it, default on. It is one guard and the only way to keep the login item without Chrome opening.
9. **The options page keeps an editable group title while the app is away.** Proposed: yes. The alternative is a read-only page and CoreCore for anyone without the app.
10. **Switcher choices.** Proposed: 3 to 7 tabs and 0.1 to 0.5 seconds. `MRU_SENT` stays 12.

## What would reopen this

- A setting that has to differ between profiles. The single `prefs` set assumes none does.
- The extension shipping to people without the app in numbers, through the Web Store. The options page would then need the eight switches it does not mirror.
- A row whose description cannot be said in one line. That is a sign the feature needs its own document, and the row a shorter claim.

With this built, a feature that can be switched has a row, and a new feature is not done until it has one.
