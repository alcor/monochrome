# Safari: what carries over, what doesn't

A plan for running Monochrome on Safari as well as Chrome, written November 9, 2026 against `main` at `7322655`. Nothing in it is built. API support comes from MDN's browser-compat-data 8.1.8 (November 2, 2026); every Safari behavior marked **unmeasured** has not been tried on a Safari build, and phase 0 exists to try it. The test Mac runs macOS 27.2 with Safari 27.2.

## Summary

About two thirds of the extension maps onto Safari's web extension API as written: locked pinned tabs, new tabs at the top, the recent-tab list with thumbnails, peek, the music hooks and the fallback commands. Four things have no Safari API: tab groups (so the `CoreCore` locked group and the `group` route destination), the search API, favicons, and window move/resize events. The app side carries over except for what is Chrome by name: launch flags, the Profiles menu, the Arc import and the native messaging host. Native messaging is the largest change: Safari talks only to an app extension inside the containing app, so the bridge is rewritten, not retargeted. The one unknown that decides whether mini browsers survive is whether Safari draws a `type: 'popup'` window without its toolbar.

## Extension features

Feature, the APIs it uses, and the Safari status.

1. **Locked tabs, pinned.** `tabs.pinned`, `tabs.create({pinned})`, `tabs.onRemoved`, `tabs.onUpdated`, `storage.session`: all supported (Safari 14, `storage.session` 16.4). Safari shows pinned tabs in every window, where Chrome pins per window; how the API reports that (one tab ID per window or one shared) is **unmeasured**, and the restore-by-position logic in `background.js` depends on it.
2. **Locked tabs, `CoreCore` group.** `tabGroups.*`, `tabs.group`, `tabs.ungroup`, `Tab.groupId`: not supported. Safari's Tab Groups are invisible to extensions. Only pinned tabs can be locked.
3. **New tabs at the top.** `tabs.move`: Safari 27. `Tab.openerTabId`: Safari 14. Carries over.
4. **⌃Tab by recent use.** `tabs.onActivated`, `windows.onFocusChanged`: supported. `Tab.lastAccessed`: not supported, so restored tabs have no order until visited (Chrome seeds from it in `background.js`). Thumbnails: `tabs.captureVisibleTab`, Safari 14, needs host access to the page.
5. **Switcher favicons.** `/_favicon/` (`helper.js`): Chrome only. `Tab.favIconUrl`: not supported in Safari. The switcher has no favicons unless the app fetches them itself.
6. **Mini browsers.** `windows.create({type: 'popup'})`: the call is supported; whether Safari drops the toolbar and tab bar for it is **unmeasured**. If it draws a normal window, the mini browser is a small Safari window with full chrome. `windows.onBoundsChanged`: not supported, so remembered size and position need the app's AX frame reads instead.
7. **Mini browser search.** `search.query` (`mini-browser.js`): not supported. Safari exposes no default search engine, so the extension builds a search URL for a fixed engine.
8. **Open in window or tab group.** Windows carry over; groups go.
9. **Peek.** `scripting.executeScript({world: 'MAIN'})`: Safari 15.4. `windows.create({tabId})`: Safari 27. Carries over, with the permission caveat below.
10. **Music hooks.** Content scripts with `world: 'MAIN'`: Safari 18. Carries over.
11. **Fallback commands.** Manifest `commands`: Safari 26. No `global` scope, so ⌥⇧N from another app has no fallback without the app. No shortcuts page (`commands.update` and `openShortcutSettings` are unsupported), so the options page's `chrome://extensions/shortcuts` link goes.

Safari applies content scripts and `captureVisibleTab` only on sites the person has granted. Peek, thumbnails and the music hooks need "Always Allow on Every Website" in Safari's extension settings, a step the install has to show.

## App features

1. **Event tap, switcher, mini browser bar, peek shade.** Generic AppKit and Accessibility. They check for Chrome as the front app and read Chrome's windows over AX; retargeting means accepting `com.apple.Safari` as well. The bar and shade positions over Safari's windows are **unmeasured**.
2. **Default browser and link routing.** Carries over. Routes gain a browser choice; `group` destinations have nothing to open into on Safari.
3. **Profiles.** `helper/Profiles.swift` reads Chrome's "Profiles" menu. Safari's profiles live elsewhere in its menus (**unmeasured** which items, and whether they can switch the front profile). Safari passes the profile to the native handler with each message (`SFExtensionProfileKey`), which replaces learning profile names from window titles.
4. **Mini player.** It sits on Chrome's vertical tab sidebar. Safari's vertical tabs arrive in 27.3, in developer beta since November 3, 2026; on 27.2 there is no sidebar to sit on.
5. **Address bar opens the history match.** A Chrome launch flag (`OmniboxForceAllowedToBeDefault`). Safari takes no launch flags. Does not carry over.
6. **App Shortcuts.** `NSUserKeyEquivalents` works per app, but Safari's menu titles differ and its preferences live in its sandbox container; whether writing them from Monochrome takes effect is **unmeasured**.
7. **Dock tile that starts Chrome with flags.** Not needed for Safari.
8. **Arc import.** Writes Chrome's databases. Does not apply.

## Native messaging is rewritten

Chrome starts the app binary as a native messaging host per connection, found through the `NativeMessagingHosts` manifests `Install.swift` writes. Safari has no host manifests. A Safari web extension is an app extension (`.appex`) inside the containing app, and:

- the extension's `runtime.connectNative` and `sendNativeMessage` reach the appex's `SafariWebExtensionHandler`, a separate process from Monochrome.app;
- the app reaches the extension with `SFSafariApplication.dispatchMessage`, which arrives on the extension's native port.

So `helper/Host.swift` and `helper/Bridge.swift` get a second transport: the appex relays extension messages to the running app (XPC or a shared app group), and the app answers through `dispatchMessage`. The message format in `helper.js` can stay as it is.

## Packaging

Monochrome.app gains a Safari Web Extension target in `project.yml`, built from the same extension files with a Safari manifest: no `key`, `minimum_chrome_version`, `tabGroups`, `search` or `favicon`. The person enables it in Safari Settings → Extensions. The Developer ID signing and notarization the app already has should carry the appex; this is **unmeasured** until a notarized build is enabled in a Safari that does not allow unsigned extensions.

## Phases

0. **Measure.** Convert the extension with `xcrun safari-web-extension-converter` into a scratch project, sign it with the Artifact team, enable it in Safari, and record: the popup window's look, pinned tab IDs across two windows, `tabs.move` under the pinned tabs, `captureVisibleTab` timing, a native message round-trip through the appex, and Safari's profile menu items over AX. Exit: one screenshot and one logged value per item, in this file.
1. **Extension runs on both.** Feature-detect `tabGroups`, `search` and `/_favicon/` and skip what is absent; a generated Safari manifest. Exit: `npm test` passes on Chrome, and the extension loads in Safari with no errors in its background console.
2. **Appex and bridge.** The target, the relay, the second transport. Exit: the options page reads "connected" in Safari.
3. **App retarget.** Tap, switcher, bar, shade, routing and profiles accept Safari. Exit: ⌃Tab with thumbnails, a mini browser from Slack, and a peek, in Safari, each with a screenshot.
4. **Mini player**, after Safari 27.3 ships vertical tabs.

## Open

1. One app for both browsers, with a browser setting, or a separate Safari build. Proposed: one app, because routing, the tap and the settings window are shared and the default-browser registration can only belong to one app.
2. A replacement for the locked group. Proposed: pinned tabs only, as Safari gives no group to read.
3. The mini browser's search engine. Proposed: a setting with Google as the default.
4. If phase 0 shows popup windows keep Safari's toolbar: ship mini browsers as small normal windows, or drop them on Safari.
