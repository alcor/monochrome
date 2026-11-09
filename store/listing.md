# Chrome Web Store listing

Everything the developer dashboard asks for, in the order its pages ask. The extension package is `store/pack.sh`'s zip in `dist/`; the app's zip on the release comes from `helper/release.sh <version>`, which also writes the Sparkle appcast.

## Store listing

**Name:** Monochrome

**Summary** (from the manifest, 119 of 132 characters): Locked tabs, new tabs at the top, a ⌃Tab switcher with thumbnails, mini and peek browsers, and link routing for Chrome.

**Category:** Productivity › Workflow & Planning

**Language:** English

**Description:**

Tabs that come back. Pin a tab, or put it in your locked group, and closing it brings it back where it was, on the page you chose.

⌃Tab the way you remember it. Hold Control and step through the tabs you used last, newest first. With the free Monochrome app for Mac (github.com/arfct/monochrome/releases), you see them as thumbnails.

Windows for a quick look. ⌥⇧N opens a small browser from any app. Links from Slack and Mail open in one too, and one click moves the page into Chrome when it's worth keeping.

Links that know where to go. With the app, rules send each link to the right profile, tab group, or app.

Works with Chrome's vertical tabs. Nothing is added to the window, and nothing leaves your Mac.

**Icon:** `store/icon-128.png`, 96 by 96 artwork on a 128 by 128 canvas, from `swift store/icon.swift store/icon-source.png store/icon-128.png`

**Screenshots** (1280×800 JPEG), in order: `store/screenshots/1-switcher.jpg`, `2-profiles.jpg`, `3-router.jpg`, made with `Monochrome --demo --backdrop`, `--demo-profiles --backdrop` and `--demo-settings --backdrop`

**Small promo tile** (440×280): `store/screenshots/small-tile.jpg`; **marquee** (1400×560): `store/screenshots/marquee-tile.jpg`, both from `swift store/tiles.swift store/icon-source.png <out dir>`, then saved as JPEG

**Homepage URL:** https://github.com/arfct/monochrome

**Support URL:** https://github.com/arfct/monochrome/issues

## Privacy practices

**Single purpose:** Monochrome changes how Chrome's tabs behave: which tabs come back when closed, where new tabs go, how ⌃Tab orders them, and how links from other apps and from locked tabs open. Every feature is a tab behavior; none reads or changes page content.

**Permission justifications:**

- `tabs`: read tab addresses and titles to keep locked tabs at their address, order new tabs, walk tabs by recent use, and name windows for the mini browser's picker.
- `tabGroups`: recognize the locked group by title, put tabs back into it, and offer groups as places to move a mini browser's page.
- `storage`: keep locked addresses, the recent-tab order and the locked group's title on the user's computer.
- `webNavigation`: notice a navigation in a locked tab, to re-apply the peek catch in that tab's frames, and notice a link handed to Chrome by another app, to open it as a mini browser.
- `scripting`: inject the peek catch into locked tabs only, and the fallback bar and shade into mini browser pages when the companion app is not running.
- `search`: run what the user types in a mini browser's box through their default search engine.
- `alarms`: reconnect to the companion app and close mini browsers left unused for 12 hours while the service worker is otherwise idle.
- `nativeMessaging`: talk to the Monochrome app on the user's Mac, which draws the switcher, bars and player, and routes links. The extension works without it.
- `favicon`: show site icons in the switcher and the mini browser bar.
- Host permission `<all_urls>`: capture a scaled-down picture of the tab in front for the switcher's thumbnails, which happens on activation without a click, and inject the peek catch into locked tabs on any site. No page content is read or stored; the picture is kept in the companion app's memory only.

**Remote code:** No.

**Data usage:** The extension does not collect or transmit user data. Tab addresses, titles and a picture of the front tab are passed to a companion app on the same computer over Chrome's native messaging port and are not sent anywhere else. Certify: not sold, not used for unrelated purposes, not used for creditworthiness.

**Privacy policy URL:** https://artifact.com/privacy?Monochrome, the shared policy for Artifact apps with no tracking and no server; `docs/privacy.md` is the detailed statement for this one.

## Distribution

**Visibility:** Unlisted, until the companion app has a release page to link to.

**Regions:** All.

**Pricing:** Free.

## Test instructions

```
No account is needed. On its own the extension does locked tabs (pin a tab, close it, it comes back), ⌃Tab by recent use (⌃.) and mini browsers.

The thumbnail switcher, the mini browser bar, the peek shade, profile switching and link routing need the free companion app for macOS, which talks to the extension over native messaging: https://github.com/arfct/monochrome/releases/latest. Unzip, move Monochrome.app to Applications, open it, allow Accessibility, then quit Chrome and reopen it from the app's Dock icon. Hold Control after ⌃Tab for the switcher; ⌥⇧N from any app opens a mini browser.

Without the app, nothing errors; the app's features are simply absent.
```

## Before submitting

- After the first upload, install the store's copy once and run `store/adopt-key.sh <id>` so the unpacked extension takes the store's ID.
