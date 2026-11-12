// Every setting the settings window edits: its key, its default, a typed accessor. The app's defaults
// are the one place they are kept (docs/settings.md); readers ask at the moment of use, so a switch
// flipped in the window takes effect at once, with no restart.
//
// Nine keys are behaviour of the extension. The app sends them to every connected copy as one
// `prefs` message (`payload`), the whole set every time: when a connection says hello, and to every
// connection when one of them changes (App.swift). The extension keeps the last set it was sent in
// chrome.storage.local and runs on PREF_DEFAULTS (background.js) until it hears one, so the two
// default lists must agree; `Monochrome --prefs --defaults` prints this side's and the tests compare.
//
// Every default is the behaviour before the settings existed, except three: ⌘L and ⌘T are off until
// switched on, so the browser's own address bar stays until someone asks for the command bar, and the
// locked group is titled "Locked", not "CoreCore" (the extension renames a CoreCore group to match).
// Two older switches are read as
// fallbacks, not migrated: `omnibox` for omniboxL and omniboxT, `profileHotkeys` for profileArrows and
// profileDigits. Nothing writes them again.
//
// `store` is UserDefaults.standard, swapped for a scratch suite by --demo-settings so a demo run
// changes no real setting.
import Foundation

enum Pref: String, CaseIterable {
  // Sent to the extension.
  case lockedTabs, lockedGroup, newTabsAtTop, peek, miniIdleHours, routeDefault, thumbnails, player, playerStopPopout
  // The app's alone.
  case openBrowserAtLaunch, launchFlags, profileArrows, profileDigits, profileHUD
  case shortcutSidebar, shortcutTabs, switcher, switcherPanel, switcherDelay, switcherCount
  case miniHotkey, miniClick, omniboxL, omniboxT, omniboxSuggestions, tldr, pinnedSleep

  static let sent: [Pref] = [.lockedTabs, .lockedGroup, .newTabsAtTop, .peek, .miniIdleHours, .routeDefault, .thumbnails, .player, .playerStopPopout]

  var defaultValue: Any {
    switch self {
    case .lockedGroup: "Locked"
    case .miniIdleHours: 12
    case .routeDefault: "mini"
    case .switcherDelay: 0.15
    case .switcherCount: 5
    case .omniboxL, .omniboxT: false
    default: true
    }
  }

  // An older key read while this one is unset.
  var fallback: String? {
    switch self {
    case .omniboxL, .omniboxT: "omnibox"
    case .profileArrows, .profileDigits: "profileHotkeys"
    default: nil
    }
  }
}

enum Prefs {
  static var store = UserDefaults.standard

  // The scratch suite --demo-settings works on, emptied at start.
  static func useDemoStore() {
    let name = "com.artifact.monochrome.demo-settings"
    UserDefaults().removePersistentDomain(forName: name)
    store = UserDefaults(suiteName: name) ?? .standard
  }

  static func bool(_ pref: Pref) -> Bool {
    if let value = store.object(forKey: pref.rawValue) as? Bool { return value }
    if let old = pref.fallback, let value = store.object(forKey: old) as? Bool { return value }
    return pref.defaultValue as? Bool ?? true
  }

  static func set(_ pref: Pref, _ value: Any) { store.set(value, forKey: pref.rawValue) }
  static func isSet(_ pref: Pref) -> Bool { store.object(forKey: pref.rawValue) != nil }

  // Typed accessors, named as the keys are.
  static var lockedTabs: Bool { bool(.lockedTabs) }
  static var lockedGroup: String { store.string(forKey: Pref.lockedGroup.rawValue) ?? "Locked" }
  static var newTabsAtTop: Bool { bool(.newTabsAtTop) }
  static var peek: Bool { bool(.peek) }
  static var miniIdleHours: Int { store.object(forKey: Pref.miniIdleHours.rawValue) as? Int ?? 12 }
  static var routeDefault: RouteDefault { store.string(forKey: Pref.routeDefault.rawValue).flatMap(RouteDefault.init(rawValue:)) ?? .mini }
  static var thumbnails: Bool { bool(.thumbnails) }
  static var player: Bool { bool(.player) }
  static var playerStopPopout: Bool { bool(.playerStopPopout) }
  static var openBrowserAtLaunch: Bool { bool(.openBrowserAtLaunch) }
  static var launchFlags: Bool { bool(.launchFlags) }
  static var profileArrows: Bool { bool(.profileArrows) }
  static var profileDigits: Bool { bool(.profileDigits) }
  static var profileHUD: Bool { bool(.profileHUD) }
  static var shortcutSidebar: Bool { bool(.shortcutSidebar) }
  static var shortcutTabs: Bool { bool(.shortcutTabs) }
  static var switcher: Bool { bool(.switcher) }
  static var switcherPanel: Bool { bool(.switcherPanel) }
  static var switcherDelay: Double { store.object(forKey: Pref.switcherDelay.rawValue) as? Double ?? 0.15 }
  static var switcherCount: Int { min(7, max(3, store.object(forKey: Pref.switcherCount.rawValue) as? Int ?? 5)) }
  static var miniHotkey: Bool { bool(.miniHotkey) }
  static var miniClick: Bool { bool(.miniClick) }
  static var omniboxL: Bool { bool(.omniboxL) }
  static var omniboxT: Bool { bool(.omniboxT) }
  static var omniboxSuggestions: Bool { bool(.omniboxSuggestions) }
  static var tldr: Bool { bool(.tldr) } // ⌥⇧R opens the reader (docs/tldr.md)
  static var pinnedSleep: Bool { bool(.pinnedSleep) } // ⌘W on a pinned Chrome tab sleeps it (Tap.swift)

  // What goes to the extension: the nine sent keys with their current values.
  static var payload: [String: Any] {
    [
      "lockedTabs": lockedTabs, "lockedGroup": lockedGroup, "newTabsAtTop": newTabsAtTop, "peek": peek,
      "miniIdleHours": miniIdleHours, "routeDefault": routeDefault.rawValue, "thumbnails": thumbnails,
      "player": player, "playerStopPopout": playerStopPopout,
    ]
  }

  static var defaultPayload: [String: Any] {
    Dictionary(uniqueKeysWithValues: Pref.sent.map { ($0.rawValue, $0.defaultValue) })
  }

  static func json(_ payload: [String: Any]) -> String {
    (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
  }

  // --prefs [--defaults]: the payload as it would be sent now, or the defaults.
  static func printPayload(defaults: Bool) {
    print(json(defaults ? defaultPayload : payload))
  }
}

// Where a link from another app goes when no Router rule claims it. The raw values are what the
// extension's routes.js reads.
enum RouteDefault: String, CaseIterable, Identifiable {
  case mini, front, sameSite = "same-site"
  var id: String { rawValue }
  var title: String {
    switch self {
    case .mini: "Mini browser"
    case .front: "New tab in the front window"
    case .sameSite: "Tab already on that site"
    }
  }
  // What a rule with no destination would send the extension.
  var to: [String: Any] {
    switch self {
    case .mini: [:]
    case .front: ["window": "front"]
    case .sameSite: ["window": "same-site"]
    }
  }
}
