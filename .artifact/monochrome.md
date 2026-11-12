---
title: Monochrome
date: 2026-11
category: product
tags: [macos, browser-extension]
url: https://github.com/arfct/monochrome
links:
  source: https://github.com/arfct/monochrome
media:
  - src: switcher.jpg
    caption: The switcher, shown while Control is held, with the five most recent tabs of the window as thumbnails
    alt: Five rounded page thumbnails in a row on a glass panel, each with a favicon and a title beneath, the last one outlined
  - src: profiles.jpg
    caption: The profile display, which names each Chrome profile by an initial on a color derived from its name
    alt: A small glass panel with three lettered circles labelled Work, Personal and Geist, the middle one marked
credits: [ericmigi, alcor]
unconfirmed: [date, credits]
---

Chrome gives an extension no Tab key, no event when Control is released and no way to draw over a window, so Monochrome comes in two parts. An extension keeps track of locked tabs, tab order and recent use, while a Mac app reads the keys through an event tap and draws its panels over Chrome. Together they make Google Chrome on a Mac keep tabs the way the Arc browser did.

A locked tab that is closed reopens in place, at the address it had when it was locked; pinned tabs are locked, and so are the tabs in one named group. New tabs open at the top of the list, under the locked ones. Control-Tab goes to the tab last used, and holding Control shows the five most recent tabs of the window as thumbnails. Only the tab landed on counts as used, so pressing Control-Tab twice returns to the tab where the walk started. The app also draws a mini player at the foot of the tab sidebar for nine music sites, and it shows Chrome's profiles as initials on a color derived from each name, because Chrome's Profiles menu carries no avatar images.

The app is the default browser as well, so a link from another app reaches it first and opens in a mini browser, a Chrome popup window with no tab strip, unless a rule sends it to a named profile, window, tab group or app. Monochrome is a fork of Eric Migicovsky's Arc for Chrome, which was an extension set up by a script, with a player app, a launcher app and a Karabiner rule for Control-Tab. The fork does the work of all four in one Mac app, and adds the thumbnail switcher, the link rules, profile hotkeys and a Safari extension with fewer features. Notarized builds are on GitHub and require macOS 13.

Swift, JavaScript. 2026.
