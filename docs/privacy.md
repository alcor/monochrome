# Monochrome privacy policy

Monochrome is a Chrome extension and a companion macOS app. The extension sends nothing off your computer. The app makes the few requests listed under Where it goes, and nothing it sends identifies you.

## What the extension reads

- Tab addresses and titles, to keep locked tabs at their address, order tabs, walk them by recent use, and name windows and groups.
- A picture of the tab in front, taken after you switch to it, when it loads and after you scroll, for the ⌃Tab switcher's thumbnails. The picture is scaled down and passed to the Monochrome app on your Mac, which keeps it in memory only and discards it when the tab closes or Chrome restarts.
- Site icons, for the switcher and the mini browser bar.
- On nine music sites (Spotify, YouTube Music, SoundCloud, Apple Music, Tidal, Bandcamp, Pandora, Amazon Music, Deezer), the title, artist and artwork address of the track the site reports to the browser, for the sidebar player.
- In locked tabs only, clicks on links that would open a new tab, so they open as a peek browser instead. No page content is read.

## Where it goes

Over Chrome's native messaging port to the Monochrome app on the same Mac, and nowhere else. The app's own requests are these:

- **Google suggestions in the address box.** What you type into the address box (⌘L, ⌘T) is sent to Google's suggestion service as you type, as Chrome's own address bar does, so the box can list Google's suggestions. Turn it off in Settings → Address Box → Google suggestions; then nothing typed leaves the Mac.
- **Site icons on Safari.** Safari gives extensions no site icons, so with Safari the app asks Google's favicon service for the icon of each site the address box lists.
- **Artwork** for the sidebar player, from the address the music site gave.
- **Update checks.** Once a day, and from Check for Updates…, the app reads `appcast.xml` from GitHub and, when there is a newer version, downloads it. Turn the daily check off in Settings → General.

There are no servers, no accounts, no analytics, no crash reporting, and no remote code.

## What is stored

In Chrome's extension storage on your computer: locked tabs' addresses, the recent-tab order, and the settings the app sent it (which switches are on, the locked group's title). The app keeps its settings in its own preferences and its link rules in `~/Library/Application Support/Monochrome/routes.json`. Removing the extension and the app removes all of it; `uninstall.sh` in the repository does both.

## Changes

The Web Store listing links Artifact's shared policy, https://artifact.com/privacy?Monochrome, which this statement details. This file is kept in the repository and its history is the record of changes.

Last updated November 10, 2026.
