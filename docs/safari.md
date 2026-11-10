# Safari: what carries over, what doesn't

A plan for running Monochrome on Safari as well as Chrome, written November 9, 2026 against `main` at `7322655`, and rewritten the same day after phases 1 to 3 were built on the `safari` branch. API support comes from MDN's browser-compat-data 8.1.8 (November 2, 2026). The test Mac runs macOS 27.2 with Safari 27.2.

**What is built.** The extension runs from the same files on both browsers and checks for each Chrome-only API before using it. Monochrome.app contains a Safari Web Extension (`safari/`, target `MonochromeSafari` in `project.yml`, bundle id `com.artifact.monochrome.extension`) built from those files with a generated Safari manifest. The app has a Browser setting (Chrome or Safari) that its event tap, switcher, mini browser bar, peek shade, link routing and settings window follow. The native messaging bridge has a second transport for Safari.

**What is verified.** `npm test` passes on Chromium, including a check of the Safari manifest and of the search and favicon stand-ins. The app and the app extension build and sign with the Artifact team's Apple Development identity, the app extension with the app sandbox and the app group. Nothing has run in Safari: the extension has not been enabled, and every Safari behavior below marked **unmeasured** is still unmeasured. Phase 0 is still the way to measure it.

## Summary

About two thirds of the extension maps onto Safari's web extension API as written: locked pinned tabs, new tabs at the top, the recent-tab list with thumbnails, peek, the music hooks and the fallback commands. Four things have no Safari API: tab groups (so the `CoreCore` locked group and the `group` route destination), the search API, favicons, and window move/resize events. Each now has a stand-in or is skipped. The app side carries over except for what is Chrome by name: launch flags, the Profiles menu, the Arc import and the native messaging host. Native messaging got a second transport through the app extension. Whether Safari draws a `type: 'popup'` window without its toolbar is still the open question for mini browsers.

## Extension features

Feature, the APIs it uses, and the Safari status.

1. **Locked tabs, pinned.** `tabs.pinned`, `tabs.create({pinned})`, `tabs.onRemoved`, `tabs.onUpdated`, `storage.session`: all supported (Safari 14, `storage.session` 16.4). Built as on Chrome. Safari shows pinned tabs in every window, where Chrome pins per window; how the API reports that (one tab ID per window or one shared) is **unmeasured**, and the restore-by-position logic in `background.js` depends on it.
2. **Locked tabs, `CoreCore` group.** `tabGroups.*`, `tabs.group`, `tabs.ungroup`, `Tab.groupId`: not supported. Built: every group call is behind `HAS_GROUPS` (`!!chrome.tabGroups`), so on Safari only pinned tabs lock and the options page hides the group's title.
3. **New tabs at the top.** `tabs.move`: Safari 27. `Tab.openerTabId`: Safari 14. Carries over unchanged; **unmeasured**.
4. **⌃Tab by recent use.** `tabs.onActivated`, `windows.onFocusChanged`: supported. `Tab.lastAccessed`: not supported; built so restored tabs keep the query's order until visited. Thumbnails: `tabs.captureVisibleTab`, Safari 14, needs host access to the page.
5. **Switcher favicons.** `/_favicon/` and `Tab.favIconUrl`: not in Safari. Built: where the manifest has no `favicon` permission (the Safari manifest), `helper.js` fetches Google's favicon service, `https://www.google.com/s2/favicons?domain_url=<origin>&sz=32`. Chrome keeps its own `/_favicon/` cache. The fetch needs host access to google.com, which "Always Allow on Every Website" gives.
6. **Mini browsers.** `windows.create({type: 'popup'})` on both browsers, as decided. Whether Safari drops the toolbar and tab bar for it is **unmeasured**. `windows.onBoundsChanged`: not supported; built so that without it the extension reads the mini browser windows once a second while one is open and sends them to the app only when they changed.
7. **Mini browser search.** `search.query`: not supported. Built: without `chrome.search`, text that is not an address goes to `https://www.google.com/search?q=<text>`.
8. **Open in window or tab group.** Windows carry over; the group list is empty on Safari.
9. **Peek.** `scripting.executeScript({world: 'MAIN'})`: Safari 15.4. `windows.create({tabId})`: Safari 27. Carries over unchanged; **unmeasured**. Xcode 27.2's `safari-web-extension-converter` warns that `world` is unsupported, which disagrees with MDN; also **unmeasured**.
10. **Music hooks.** Content scripts with `world: 'MAIN'`: Safari 18 by MDN, with the same converter warning. **Unmeasured**.
11. **Fallback commands.** Manifest `commands`: Safari 26. No `global` scope and no shortcuts page; built so the options page hides its Keyboard Shortcuts button outside Chrome, and `commands.getAll` failing leaves the shortcut labels empty.
12. **Links from other apps without the app.** Chrome marks them as `start_page` navigations in `webNavigation.onCommitted`. Whether Safari reports `transitionType` is **unmeasured**; without it such a link stays a tab. With the app running, links go over the bridge and this does not apply.

Safari applies content scripts and `captureVisibleTab` only on sites the person has granted. Peek, thumbnails, favicons and the music hooks need "Always Allow on Every Website" in Safari's extension settings, a step the README's install shows.

## App features

1. **Event tap, switcher, mini browser bar, peek shade.** Built: `Chrome.variants` is Safari alone when the Browser setting says Safari, so the front-app check, the window list and the Accessibility reads follow Safari. The bar and shade positions over Safari's windows are **unmeasured**: the bar's offsets were measured on Chrome's popup title bar.
2. **Default browser and link routing.** Carries over. The Router tab does not offer "Tab group" on Safari; a rule that already names a group opens a new tab in the front window there, which `routes.js` does when it has no tab groups.
3. **Profiles.** Built for Safari without names: each Safari profile's copy of the extension is its own connection, keyed by `SFExtensionProfileKey`, and the app does no window-title learning on Safari. The front profile is the connection whose reported front window matches the window in front on screen. The ⌃⌥ profile hotkeys read Chrome's Profiles menu; Safari has none, so they do nothing on Safari. Which Safari menu items could switch profiles is **unmeasured**.
4. **Mini player.** Unchanged. It needs a vertical tab sidebar, which Safari 27.2 lacks, so it does not show on Safari. Safari's vertical tabs arrive in 27.3.
5. **Address bar opens the history match.** A Chrome launch flag. The app passes flags only to Chrome; on Safari it does not start the browser at login.
6. **App Shortcuts.** Still written for Chrome only. Safari's are **unmeasured**.
7. **Dock tile that starts Chrome with flags.** Placed only when the Browser setting is Chrome at the app's first launch from a location.
8. **Arc import.** Chrome only.

## Native messaging has a second transport

Chrome starts the app binary as a native messaging host per connection, found through the `NativeMessagingHosts` manifests `Install.swift` writes. That is unchanged. Safari has no host manifests. A Safari web extension is an app extension (`.appex`) inside the containing app, and:

- the extension's `runtime.connectNative` and `sendNativeMessage` reach the appex's `SafariWebExtensionHandler`, a separate, sandboxed process;
- the app reaches the extension with `SFSafariApplication.dispatchMessage`, which arrives on the extension's native port.

Built as a relay:

1. The appex (`safari/SafariWebExtensionHandler.swift`) writes each message from the extension as one line, `{"profile": "<SFExtensionProfileKey>", "message": {...}}`, to a Unix socket in the app group container `~/Library/Group Containers/TVA9Z8LD95.com.artifact.monochrome/safari.sock` (`SafariSocket` in `helper/Bridge.swift`). The app group is the one folder both the sandboxed appex and the app can reach. When nothing listens, the appex opens Monochrome.app in the background, at most every ten seconds.
2. The app (`helper/App.swift`, `helper/Safari.swift`) listens on that socket, makes one connection per Safari profile, and answers through `dispatchMessage`. Because `dispatchMessage` names no profile, a message for one profile carries `safariProfile`; each copy of the extension learns its own profile id by asking the appex (`{"whoami": true}` over `sendNativeMessage`) and ignores messages for another.
3. The extension unwraps `dispatchMessage`'s `{name, userInfo}` shape, says it is alive once a minute, and counts the app as connected only when the app has spoken in the last 90 seconds. The app pings each Safari connection every 20 seconds, as Chrome's host does, drops a connection quiet for 150 seconds or when Safari quits, and asks the extension to resend everything at launch and when Safari starts.

The message format in `helper.js` is unchanged; the Safari fields are additions. **Unmeasured**: whether a sandboxed appex may connect to a socket in its app group container, whether it may open its containing app, the exact shape `dispatchMessage` delivers, and whether `dispatchMessage` reaches every profile's copy or only one.

## Packaging

Built. `project.yml` has the `MonochromeSafari` app-extension target, embedded in Monochrome.app's `Contents/PlugIns`, with `NSExtensionPointIdentifier` `com.apple.Safari.web-extension`, the app sandbox and the app group (`safari/Extension.entitlements`). Monochrome.app gets the same app group (`helper/Monochrome.entitlements`) so it can use the container without macOS asking. The target's run script copies the files `store/files` lists into the appex's Resources and writes the Safari manifest with `store/safari-manifest.py`: the Chrome manifest without `key`, `minimum_chrome_version`, the `tabGroups`, `search` and `favicon` permissions, and `options_ui.open_in_tab`. It is Python because Xcode's run scripts have `python3` and may not have `node`. The Chrome flow (`store/files`, `Resources/extension`, `extension-ids.json`, `store/pack.sh`) is unchanged.

The person enables the extension in Safari Settings → Extensions. Whether `make release`'s Developer ID signing and notarization carry the appex and the app group entitlements is **unmeasured** until the next release is built.

## Phases

0. **Measure.** Not done; agents cannot drive Safari's interface on the build Mac. Enable the built extension in Safari and record: the popup window's look, pinned tab IDs across two windows, `tabs.move` under the pinned tabs, `captureVisibleTab` timing, a native message round-trip through the appex, the `dispatchMessage` shape and its reach across profiles, and Safari's profile menu items over AX. Exit: one screenshot and one logged value per item, in this file.
1. **Extension runs on both.** Built. Exit met on Chrome (`npm test` passes); the Safari half of the exit (the extension loads with no errors in its background console) is not checked.
2. **Appex and bridge.** Built. Exit not checked: the options page reading "connected" in Safari.
3. **App retarget.** Built. Exit not checked: ⌃Tab with thumbnails, a mini browser from Slack, and a peek, in Safari, each with a screenshot.
4. **Mini player**, after Safari 27.3 ships vertical tabs.

## Open

Answered:

1. One app for both browsers, with a browser setting. Decided: one app. Built as the Browser setting on the General tab.
2. A replacement for the locked group. Decided: pinned tabs only. `CoreCore` and `group` route destinations are Chrome only and are skipped on Safari.
3. The mini browser's search engine. Decided: Google, with no setting, because Safari has no search API.
4. If phase 0 shows popup windows keep Safari's toolbar: ship mini browsers as small normal windows, or drop them on Safari. Still open. Mini browsers stay `windows.create({type: 'popup'})` until the popup's look is measured.
5. Favicons. Decided: Google's S2 service, on Safari only.
