// The app's side of the Safari transport (see Bridge.swift): messages to the extension go through
// SFSafariApplication.dispatchMessage, which reaches the extension's open native port as
// {name, userInfo}. dispatchMessage names no profile, so a message for one Safari profile carries that
// profile's id as safariProfile and the other profiles' copies of the extension ignore it (helper.js).
//
// Also here, what the app reads of Safari itself: its version, its localized titles (Safari.framework's
// Localizable.strings), its profiles from the File menu, the App Shortcuts written for it, and the
// vertical tab sidebar the mini player sits on.
import AppKit
import SafariServices

enum Safari {
  static let bundleId = "com.apple.Safari"
  static let extensionId = "com.artifact.monochrome.extension"

  static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty }

  static func dispatch(_ message: [String: Any]) {
    SFSafariApplication.dispatchMessage(withName: "monochrome", toExtensionWithIdentifier: extensionId, userInfo: message) { error in
      if let error { log.info("safari: dispatch failed: \(error.localizedDescription, privacy: .public)") }
    }
  }

  // Safari Settings → Extensions with Monochrome selected, where it is turned on and given its websites.
  static func showExtensionSettings() {
    SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionId) { error in
      if let error { log.error("safari: could not open the extension's settings: \(error.localizedDescription, privacy: .public)") }
    }
  }

  // MARK: Version

  // Safari's CFBundleShortVersionString, from the installed app (it lives in the App cryptex and is
  // linked from /Applications).
  static var version: String? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
    return Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
  }

  // Vertical tabs arrive in Safari 27.3 (a developer beta while this is written; the build Mac runs 27.2).
  static let verticalTabsVersion = "27.3"
  static func atLeast(_ version: String?, _ minimum: String) -> Bool {
    guard let version, !version.isEmpty else { return false }
    return version.compare(minimum, options: .numeric) != .orderedAscending
  }
  static var hasVerticalTabs: Bool { atLeast(version, verticalTabsVersion) }

  // MARK: Localized titles

  // Safari takes its titles from Safari.framework's Localizable.strings, in the language Safari runs in:
  // the first of the user's languages the framework has. The key itself (English) when that can't be read.
  static let framework = "/System/Library/PrivateFrameworks/Safari.framework"
  private static let strings: [String: String] = {
    guard let bundle = Bundle(path: framework) else { return [:] }
    let language = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: Locale.preferredLanguages).first ?? "en"
    for lang in [language, "en"] {
      if let url = bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: lang),
         let table = NSDictionary(contentsOf: url) as? [String: String] {
        return table
      }
    }
    return [:]
  }()
  static func localized(_ key: String) -> String { strings[key] ?? key }

  // The title of each per-profile item under File → New Window ("New Work Window"), and Safari's own
  // private window item, which has the same shape and is never a profile.
  static var profileWindowFormat: String { localized("New %@ Window") }
  static var privateWindowTitle: String { localized("New Private Window") }
}

// MARK: Profiles

// Safari's profiles, from its menu bar: with more than one profile, File → New Window is a submenu with
// one item per profile, titled "New <name> Window". Safari has no Profiles menu and no checkmark, so the
// current profile is the one whose connection owns the window in front (App supplies it as `current`).
// **Unmeasured**: the submenu's AX shape. It is read the way Chrome's Profiles menu is
// (AXMenuBarItem, AXMenu, AXMenuItem with an AXMenu child); the titles come from Safari.framework's
// strings ("New %@ Window").
enum SafariProfiles {
  static var current: () -> String? = { nil }

  // The name inside one item's title, or nil when the title is not a profile's: "New Work Window" with
  // "New %@ Window" is Work. The private window item is never a profile.
  static func name(fromTitle title: String, format: String = Safari.profileWindowFormat, privateTitle: String = Safari.privateWindowTitle) -> String? {
    guard title != privateTitle, let mark = format.range(of: "%@") else { return nil }
    let prefix = String(format[..<mark.lowerBound]), suffix = String(format[mark.upperBound...])
    guard title.count > prefix.count + suffix.count, title.hasPrefix(prefix), title.hasSuffix(suffix) else { return nil }
    let name = String(title.dropFirst(prefix.count).dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? nil : name
  }

  static func names(fromTitles titles: [String], format: String = Safari.profileWindowFormat, privateTitle: String = Safari.privateWindowTitle) -> [String] {
    var seen = Set<String>()
    return titles.compactMap { name(fromTitle: $0, format: format, privateTitle: privateTitle) }.filter { seen.insert($0).inserted }
  }

  static func read(_ safari: NSRunningApplication?) -> [Profile] {
    guard let safari else { return [] }
    let app = AXUIElementCreateApplication(safari.processIdentifier)
    guard let bar = AX.element(app, kAXMenuBarAttribute) else { return [] }
    let menus = AX.children(bar)
    // The File menu is the second; the others are searched after it, in case a later Safari moves the item.
    let order = menus.count > 1 ? [menus[1]] + menus.enumerated().filter { $0.offset != 1 }.map(\.element) : menus
    let front = current()
    for menu in order {
      guard let list = AX.children(menu).first else { continue }
      for item in AX.children(list) {
        guard let submenu = AX.children(item).first else { continue }
        var seen = Set<String>()
        let profiles = AX.children(submenu).compactMap { sub -> Profile? in
          guard let title = AX.string(sub, kAXTitleAttribute), let name = name(fromTitle: title), seen.insert(name).inserted else { return nil }
          return Profile(name: name, item: sub, current: name == front)
        }
        if !profiles.isEmpty { return profiles }
      }
    }
    return []
  }

  // Each Safari profile id (SFExtensionProfileKey) the app has learned a name for, kept across launches.
  // A name is learned when the app opens that profile's window from the menu and a connection reports
  // the new window (App.learnSafariProfile); a renamed profile is learned again the next time.
  static var learned: [String: String] {
    get { UserDefaults.standard.dictionary(forKey: "safariProfileNames") as? [String: String] ?? [:] }
    set { UserDefaults.standard.set(newValue, forKey: "safariProfileNames") }
  }

  static func remember(_ name: String, for id: String) {
    guard !id.isEmpty else { return }
    var names = learned.filter { $0.value != name }
    names[id] = name
    learned = names
  }
}

// MARK: App Shortcuts

// What Install.setChromeShortcuts writes for Chrome, in Safari's menu titles (Safari's MainMenu.nib and
// Localizable.strings, English): ⌘S shows and hides the sidebar, Save As… moves to ⇧⌘S, ⌥⌘↓ and ⌥⌘↑
// go to the next and previous tab. Safari 27.2's sidebar holds bookmarks, the reading list and tab
// groups; whether 27.3's vertical tabs live under the same "Show Sidebar" and "Hide Sidebar" items is
// **unmeasured**. The item changes its title as it toggles, so both titles are written.
// Safari's preferences live in its container, which macOS guards: the write may need the app to be
// allowed to reach other apps' data, and is logged when refused. Safari reads them when it starts.
enum SafariShortcuts {
  static let domain = Safari.bundleId
  static let shortcuts = ["Show Sidebar": "@s", "Hide Sidebar": "@s", "Save As…": "@$s",
                          "Show Next Tab": "@~\u{F701}", "Show Previous Tab": "@~\u{F700}"]

  // Through CFPreferences, so cfprefsd puts them where the domain lives (Safari's container for
  // com.apple.Safari) and the result of the write is known. Returns whether they are in place.
  @discardableResult
  static func write(domain: String = domain) -> Bool {
    let key = "NSUserKeyEquivalents" as CFString, app = domain as CFString
    var keys = CFPreferencesCopyAppValue(key, app) as? [String: String] ?? [:]
    if shortcuts.allSatisfy({ keys[$0.key] == $0.value }) { return true }
    keys.merge(shortcuts) { _, new in new }
    CFPreferencesSetAppValue(key, keys as CFDictionary, app)
    let ok = CFPreferencesAppSynchronize(app)
    if ok { log.notice("install: App Shortcuts set for \(domain, privacy: .public); Safari applies them when it next starts") }
    else { log.error("install: could not write App Shortcuts to \(domain, privacy: .public); macOS may be guarding Safari's container") }
    return ok
  }
}

// MARK: Vertical tab sidebar

// Where Safari's vertical tab list is in a window, for the mini player. Safari 27.2 has no vertical
// tabs; 27.3 adds them. **Unmeasured**: the AX shape. The guess, to check on 27.3: an AXOutline, AXList,
// AXTable, AXScrollArea, AXGroup or AXSplitGroup against the window's left edge, at least half its
// height, 120 points to half its width wide, holding tab items (AXRadioButton, AXRow, or the AXTabButton
// subrole) within three levels. Nothing found, or Safari older than 27.3: no sidebar, so no mini player.
enum SafariSidebar {
  struct Candidate { let role: String, frame: CGRect, tabs: Int }
  static let roles = ["AXOutline", "AXList", "AXTable", "AXScrollArea", "AXGroup", "AXSplitGroup"]
  static let listRoles = ["AXOutline", "AXList", "AXTable"]
  static let tabRoles = ["AXRadioButton", "AXRow"], tabSubrole = "AXTabButton"

  // The sidebar among the candidates, in window-list coordinates, or nil. A list role wins over a
  // container, then the taller, then the narrower (the list inside its scroll area).
  static func pick(_ candidates: [Candidate], window: CGRect) -> CGRect? {
    let fits = candidates.filter { c in
      roles.contains(c.role) && c.tabs > 0
        && abs(c.frame.minX - window.minX) < 24
        && c.frame.height >= window.height * 0.5
        && c.frame.width >= 120 && c.frame.width <= window.width * 0.5
        && c.frame.minY >= window.minY - 1 && c.frame.maxY <= window.maxY + 1
    }
    let key = { (c: Candidate) in (listRoles.contains(c.role) ? 0 : 1, -c.frame.height, c.frame.width) }
    return fits.min { key($0) < key($1) }?.frame
  }

  // Read over AX at most once a second per window; between reads the found sidebar moves with the
  // window, kept as an offset from its origin.
  private static var cache: [CGWindowID: (at: Date, size: CGSize, offset: CGRect?)] = [:]

  static func frame(for window: Chrome.Window) -> CGRect? {
    guard Safari.hasVerticalTabs else { return nil }
    if let hit = cache[window.id], Date().timeIntervalSince(hit.at) < 1, hit.size == window.frame.size {
      return hit.offset.map { $0.offsetBy(dx: window.frame.minX, dy: window.frame.minY) }
    }
    let found = read(window)
    cache = cache.filter { Date().timeIntervalSince($0.value.at) < 10 }
    cache[window.id] = (Date(), window.frame.size, found.map { $0.offsetBy(dx: -window.frame.minX, dy: -window.frame.minY) })
    return found
  }

  private static func read(_ window: Chrome.Window) -> CGRect? {
    let app = AXUIElementCreateApplication(window.pid)
    guard let windows = AX.value(app, kAXWindowsAttribute) as? [AXUIElement],
          let ax = windows.first(where: { Chrome.axFrame($0).map { Chrome.match($0, in: [window]) != nil } ?? false })
    else { return nil }
    var candidates: [Candidate] = []
    var queue: [(AXUIElement, Int)] = [(ax, 0)], seen = 0
    while !queue.isEmpty, seen < 400 {
      let (element, depth) = queue.removeFirst()
      seen += 1
      if let role = AX.string(element, kAXRoleAttribute), roles.contains(role), let frame = Chrome.axFrame(element) {
        candidates.append(Candidate(role: role, frame: frame, tabs: hasTabs(element) ? 1 : 0))
      }
      if depth < 6 { queue += AX.children(element).map { ($0, depth + 1) } }
    }
    return pick(candidates, window: window.frame)
  }

  private static func hasTabs(_ element: AXUIElement, depth: Int = 0) -> Bool {
    guard depth < 3 else { return false }
    return AX.children(element).contains { child in
      AX.string(child, kAXRoleAttribute).map(tabRoles.contains) == true || AX.string(child, kAXSubroleAttribute) == tabSubrole
        || hasTabs(child, depth: depth + 1)
    }
  }
}

// Small Accessibility readers for the Safari readers above.
enum AX {
  static func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
  }
  static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    guard let v = value(element, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return (v as! AXUIElement)
  }
  static func children(_ element: AXUIElement) -> [AXUIElement] { value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
  static func string(_ element: AXUIElement, _ name: String) -> String? { value(element, name) as? String }
}

// One Safari profile's copy of the extension, as a connection's peer. profile is Safari's id for it
// (SFExtensionProfileKey), empty when Safari gave none.
final class SafariPeer: Peer {
  let profile: String
  var lastHeard = Date()

  init(profile: String) { self.profile = profile }

  // What goes to Safari for this profile: the message, naming the profile when Safari gave one.
  static func wrap(_ message: [String: Any], profile: String) -> [String: Any] {
    var message = message
    if !profile.isEmpty { message["safariProfile"] = profile }
    return message
  }

  func send(_ line: String) {
    guard let message = JSONLine.decode(line) else { return }
    Safari.dispatch(Self.wrap(message, profile: profile))
  }

  // How the settings window names it before its name is learned: Safari gives an id, not a name.
  var label: String { profile.isEmpty ? "Safari" : "Safari profile \(profile.prefix(8))" }
}

// --check-safari <json>: the pure parts above on given input, printed as {"result": ...}, for test.mjs.
//   {"op": "profiles", "titles": [...], "format"?, "private"?}  names parsed from menu item titles
//   {"op": "version", "version": "27.2"}                        whether that Safari has vertical tabs
//   {"op": "sidebar", "window": [x,y,w,h], "candidates": [{"role", "frame": [x,y,w,h], "tabs"}]}
//   {"op": "wrap", "profile": "...", "message": {...}}           what SafariPeer dispatches
//   {"op": "shortcuts", "domain": "..."}                         writes the App Shortcuts to a scratch domain
//   {"op": "strings"}                                            the localized titles and Safari version in use
enum SafariCheck {
  static func run(_ json: String?) -> Int32 {
    guard let json, let request = JSONLine.decode(json), let op = request["op"] as? String else {
      FileHandle.standardError.write(Data("usage: --check-safari '{\"op\": ...}'\n".utf8))
      return 2
    }
    let rect = { (a: Any?) -> CGRect in
      let n = (a as? [Double]) ?? []
      return n.count == 4 ? CGRect(x: n[0], y: n[1], width: n[2], height: n[3]) : .zero
    }
    var out: Any = NSNull()
    switch op {
    case "profiles":
      out = SafariProfiles.names(fromTitles: request["titles"] as? [String] ?? [],
                                 format: request["format"] as? String ?? Safari.profileWindowFormat,
                                 privateTitle: request["private"] as? String ?? Safari.privateWindowTitle)
    case "version":
      out = Safari.atLeast(request["version"] as? String, Safari.verticalTabsVersion)
    case "sidebar":
      let candidates = (request["candidates"] as? [[String: Any]] ?? []).map {
        SafariSidebar.Candidate(role: $0["role"] as? String ?? "", frame: rect($0["frame"]), tabs: $0["tabs"] as? Int ?? 0)
      }
      out = SafariSidebar.pick(candidates, window: rect(request["window"])).map { [$0.minX, $0.minY, $0.width, $0.height] } ?? NSNull()
    case "wrap":
      out = SafariPeer.wrap(request["message"] as? [String: Any] ?? [:], profile: request["profile"] as? String ?? "")
    case "shortcuts":
      // Never Safari's own domain from here: this is for checking the write against a scratch domain.
      guard let domain = request["domain"] as? String, !domain.isEmpty, domain.lowercased() != SafariShortcuts.domain.lowercased() else {
        FileHandle.standardError.write(Data("shortcuts: name a scratch domain, not Safari's\n".utf8))
        return 2
      }
      out = ["written": SafariShortcuts.write(domain: domain), "shortcuts": SafariShortcuts.shortcuts] as [String: Any]
    case "strings":
      out = ["profileWindow": Safari.profileWindowFormat, "privateWindow": Safari.privateWindowTitle, "version": Safari.version ?? ""]
    default:
      FileHandle.standardError.write(Data("unknown op \(op)\n".utf8))
      return 2
    }
    guard let data = try? JSONSerialization.data(withJSONObject: ["result": out], options: [.sortedKeys]) else { return 1 }
    print(String(decoding: data, as: UTF8.self))
    return 0
  }
}
