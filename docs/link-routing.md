# Links from other apps are routed by rules, with mini browser as the default

What happens to a URL handed to Monochrome as the default browser: which Chrome profile, which window, and whether it opens as a mini browser, a tab, or in a tab already on that site. This was the design; it is built as of November 6, 2026 (`helper/Routes.swift`, `routes.js`), with these departures from the text below:

- Profiles are named as Chrome's Profiles menu shows them, not by directory. The app learns which connection is which profile from Chrome's window titles, which end in the profile's name, so the extension reports nothing about its profile and Chrome's data folder is never read. An unconnected profile is reached by pressing its menu item, not by `--profile-directory`.
- Destinations name a tab group, not a window. The picker's window names are made from the active tab and change constantly; a group title is stable.
- `--routes` prints the rules and the match for a given URL. It does not count matches, since the counts live in the running app and the command is a separate process.
- The README holds the rule format. This document keeps the reasoning.

## Summary

Today every link from another app becomes a mini browser in whatever Chrome profile the extension runs in. The plan adds a small routing layer in Monochrome, before the extension sees the link: a list of rules matched against the URL and the sending app, each naming a destination. Unmatched links keep today's behavior. Profiles are a hard boundary: the extension can only act inside its own, so a link bound for another profile is handed to Chrome with that profile's directory and loses the mini browser treatment unless the extension is installed there too.

## What routing has to decide

A link arrives with three facts: the URL, the app that sent it (Launch Services tells the helper the sending process), and the state of Chrome (which profiles are running, which windows exist, what they contain). It leaves with one of five destinations:

1. **Mini browser** in the front profile. Today's behavior.
2. **Tab in a given window**, at the top of its list, the way Open in Chrome places it.
3. **Existing tab**, when a tab on that URL or that site is already open: activate it and navigate if the URL differs.
4. **A specific profile**, by its directory name, as a tab or mini browser there.
5. **Another app**, when the URL is one Chrome shouldn't get, such as a Zoom or Figma link that has a native app.

Destinations 1 to 3 are the extension's; 4 and 5 are the helper's, since only it can launch a profile or another app.

## The rules live in the helper, in one JSON file

A rule is a match and a destination:

```json
{ "match": { "host": "*.atlassian.net" }, "to": { "profile": "Profile 1", "window": "same-site" } }
{ "match": { "from": "com.tinyspeck.slackmacgap", "host": "docs.google.com" }, "to": { "mini": true } }
{ "match": { "host": "zoom.us", "path": "/j/*" }, "to": { "app": "us.zoom.xos" } }
{ "match": { "host": "github.com" }, "to": { "window": "same-site", "group": "Code" } }
```

Match fields: `host` (glob), `path` (glob), `from` (sending app's bundle id), `scheme`. Destination fields: `mini`, `window` (`same-site`, `front`, or a window name as the picker shows it), `group` (a tab group title), `profile` (a Chrome profile directory), `app` (a bundle id). First matching rule wins; the file is read when it changes. The file sits in `~/Library/Application Support/Monochrome/routes.json`, and Monochrome's `--routes` prints it with each rule's match count since launch so a rule that never fires is visible.

The helper decides `app` and `profile` itself. Everything else it sends to the extension as `{ open: url, to: {...} }`, and the extension resolves `same-site` against its own tabs, picks the window, places the tab, or makes the mini browser.

## Profiles are the boundary

The extension is installed per profile and its port belongs to that profile's Chrome. The helper can know which profiles exist (the directories under `~/Library/Application Support/Google/Chrome/` with a `Preferences` file, and the display name inside it) and which one is in front (Chrome's window titles don't say; the extension reports its own profile name over the port, and the helper keeps one port per connected profile). A link bound for a profile that is running and connected goes over that profile's port. A link bound for a profile that isn't running goes to Chrome with `--profile-directory=<name>` and the URL, which starts that profile; it lands as a tab, through the `start_page` path, with the flash. Whether the mini browser treatment follows depends on the extension being loaded in that profile, which is the user's setup, not the router's.

What this does not cover: a single mini browser window shared across profiles. A popup window belongs to one profile's Chrome.

## Order of work

1. **Same-site in the front profile.** The extension gains a resolver: given a URL, find a tab on the same host (then same URL), prefer the front window, else the most recently used. Rules with only `host` and `window: same-site` work. No helper changes beyond passing `to`.
2. **Sending app and the rule file.** The helper reads `routes.json`, matches on `from` and the URL, and forwards the destination. `--routes` for inspection.
3. **Other apps.** `app` destinations: the helper opens the URL with that bundle id and never involves Chrome.
4. **Profiles.** The extension reports its profile; the helper keeps a port per profile and launches profiles that aren't running.

Each step leaves unmatched links on today's path.

## The alternative: rules in the extension

Chrome's extension API can read the URL and the tabs, so the rules could live in the extension's options page with a UI, and the helper would stay a dumb relay. That is the usual place for a browser feature, and it would work for destinations 1 to 3.

It relies on the extension seeing every link, and it doesn't: links for other apps and other profiles have to be decided before Chrome is involved, which only the helper can do, and the sending app's identity is only known to the helper. Splitting rules between two places, with two formats, is worse than one file the helper owns.

## What is uncertain

- Whether Launch Services reliably reports the sending app for every open. `NSAppleEventManager` carries the sender's process in the event; some apps open URLs through intermediaries. Unverified until built.
- Whether a profile's display name can be read without Chrome running. The `Preferences` file is JSON and has a `profile.name` key; its exact shape across Chrome versions isn't checked.
- How often `same-site` is what the user wanted versus a fresh mini browser. The default stays mini browser until a rule says otherwise, so a wrong guess costs one rule.

## What would reopen this

- Chrome adding a profile-aware URL handoff, or a way for an extension in one profile to reach another.
- The user wanting rules editable from Chrome rather than a file, which moves the UI, not the routing.
- Mini browser windows becoming per-profile in a way that needs the helper to track more than frames.

Links keep arriving as mini browsers until a rule in one file says where else they go.
