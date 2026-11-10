// What installing used to do from shell scripts, done by the app when it starts, so a
// copy taken from the release zip or the build folder works once it is opened:
//
//   every launch   the native messaging host manifest for each Chrome (written only when it differs, so
//                  a moved app fixes its own path), Chrome's App Shortcuts, Launch Services registration,
//                  and removal of what earlier versions installed (Arc for Chrome, Chrome Launcher, the
//                  Karabiner rule)
//   once per path  the Dock tile in Chrome's place and the default-browser question
//
// The login item is registered by App at launch, as before. Launched with --portable, the app does the
// host manifests only: no login item, Dock tile, default browser or App Shortcuts, for a test run that
// leaves the Mac as it was apart from Chrome's NativeMessagingHosts folders.
import AppKit
import CoreServices

enum Install {
  static let hostName = "monochrome_helper"
  static var portable: Bool { CommandLine.arguments.contains("--portable") }
  static let home = FileManager.default.homeDirectoryForCurrentUser
  static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
  static let defaults = UserDefaults.standard

  static func atLaunch() {
    registerHosts()
    guard !portable else { return log.notice("install: portable, host manifests only") }
    LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
    setChromeShortcuts()
    removeEarlierVersions()
    let path = Bundle.main.bundleURL.path
    // The tile is there to start Chrome with its flags; Safari takes none.
    if Browser.current == .chrome && defaults.string(forKey: "dockTileFor") != path { placeDockTile(path: path) }
    if defaults.string(forKey: "defaultBrowserAskedFor") != path {
      defaults.set(path, forKey: "defaultBrowserAskedFor")
      makeDefaultBrowser {}
    }
  }

  // Both schemes: the system's browser picker follows http, and https is where links actually go.
  // macOS shows its own confirmation dialog.
  static func makeDefaultBrowser(then: @escaping () -> Void) {
    let group = DispatchGroup()
    for scheme in ["http", "https"] {
      group.enter()
      NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme) { _ in group.leave() }
    }
    group.notify(queue: .main, execute: then)
  }

  // MARK: Native messaging host

  // The folder each Chrome reads host manifests from, relative to Application Support. Stable always
  // (it may not have run yet); the others only when they have run on this Mac.
  static let hostFolders = ["Google/Chrome", "Google/Chrome Beta", "Google/Chrome Dev", "Google/Chrome Canary", "Chromium"]

  // The extension IDs allowed to connect, written to Resources/extension-ids.json by the project's run
  // script: the unpacked extension's (from the manifest key) and the Web Store's (store/id).
  static var extensionIds: [String] {
    guard let url = Bundle.main.url(forResource: "extension-ids", withExtension: "json"), let data = try? Data(contentsOf: url) else { return [] }
    return (try? JSONSerialization.jsonObject(with: data) as? [String]) ?? []
  }

  static func registerHosts() {
    let ids = extensionIds
    guard !ids.isEmpty else { return log.error("install: no extension-ids.json in the app; host not registered") }
    let host = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/host.sh").path
    let manifest: [String: Any] = ["name": hostName, "description": "Monochrome: helper app", "path": host, "type": "stdio",
                                   "allowed_origins": ids.map { "chrome-extension://\($0)/" }]
    guard let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return }
    let fm = FileManager.default
    // MONOCHROME_HOSTS names one NativeMessagingHosts folder to use instead, for the tests: Chrome also
    // reads one inside a --user-data-dir.
    let folders = ProcessInfo.processInfo.environment["MONOCHROME_HOSTS"].map { [$0] } ?? hostFolders.compactMap { folder -> String? in
      let chrome = support.appendingPathComponent(folder)
      guard folder == hostFolders[0] || fm.fileExists(atPath: chrome.path) else { return nil }
      return chrome.appendingPathComponent("NativeMessagingHosts").path
    }
    for folder in folders {
      let hosts = URL(fileURLWithPath: folder)
      let file = hosts.appendingPathComponent("\(hostName).json")
      for old in ["erics_arc_player.json", "erics_arc_helper.json"] { try? fm.removeItem(at: hosts.appendingPathComponent(old)) }
      if (try? Data(contentsOf: file)) == data { continue }
      do {
        try fm.createDirectory(at: hosts, withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        log.notice("install: host registered with \(folder, privacy: .public) for \(ids.joined(separator: ", "), privacy: .public)")
      } catch {
        log.error("install: host for \(folder, privacy: .public): \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  // MARK: Chrome's App Shortcuts

  // ⌘S collapses and expands the vertical tab sidebar, as in Arc; Save Page As moves to ⇧⌘S; ⌥⌘↓ and
  // ⌥⌘↑ move down and up the tab list (U+F701 and U+F700 are the arrow keys' characters). Chrome reads
  // them when it starts. Chrome's own "make me the default browser" prompt is turned off, since this
  // app holds that role.
  static let chromeDomains = ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary", "org.chromium.Chromium"]
  static let shortcuts = ["Collapse Vertical Tabs": "@s", "Save Page As…": "@$s",
                          "Select Next Tab": "@~\u{F701}", "Select Previous Tab": "@~\u{F700}"]

  static func setChromeShortcuts() {
    for (domain, variant) in zip(chromeDomains, Chrome.chromeVariants) {
      guard domain == chromeDomains[0] || NSWorkspace.shared.urlForApplication(withBundleIdentifier: variant.bundleId) != nil,
            let prefs = UserDefaults(suiteName: domain) else { continue }
      var keys = prefs.dictionary(forKey: "NSUserKeyEquivalents") as? [String: String] ?? [:]
      if shortcuts.allSatisfy({ keys[$0.key] == $0.value }), prefs.object(forKey: "DefaultBrowserSettingEnabled") as? Bool == false { continue }
      keys.merge(shortcuts) { _, new in new }
      prefs.set(keys, forKey: "NSUserKeyEquivalents")
      prefs.set(false, forKey: "DefaultBrowserSettingEnabled")
      log.notice("install: App Shortcuts set for \(domain, privacy: .public)")
    }
  }

  // MARK: Dock

  // A pinned Google Chrome tile would start Chrome without the launch flags, so this app's tile takes
  // its place. The Dock writes its old tiles back over a change made in its first seconds, so the
  // change waits until the Dock has been up 15 seconds, and is checked and retried up to five times.
  static func placeDockTile(path: String, attempt: Int = 1) {
    let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
    let up = dockApp?.launchDate.map { -$0.timeIntervalSinceNow } ?? 999
    if up < 15 { return DispatchQueue.main.asyncAfter(deadline: .now() + 15 - up) { placeDockTile(path: path, attempt: attempt) } }
    guard var dock = dockPrefs() else { return log.error("install: could not read the Dock's preferences") }
    let backup = home.appendingPathComponent("Library/Preferences/com.apple.dock.plist.pre-monochrome.bak")
    if !FileManager.default.fileExists(atPath: backup.path) {
      try? FileManager.default.copyItem(at: home.appendingPathComponent("Library/Preferences/com.apple.dock.plist"), to: backup)
    }
    let tiles = dock["persistent-apps"] as? [[String: Any]] ?? []
    var keep = tiles.filter { tile in
      let data = tile["tile-data"] as? [String: Any] ?? [:]
      return data["bundle-identifier"] as? String != "com.google.Chrome"
        && !["Chrome Launcher", "Arc for Chrome", "Monochrome"].contains(data["file-label"] as? String ?? "")
    }
    keep.append(["tile-type": "file-tile", "tile-data": [
      "file-label": "Monochrome",
      "file-data": ["_CFURLString": Bundle.main.bundleURL.absoluteString, "_CFURLStringType": 15],
    ]])
    dock["persistent-apps"] = keep
    guard writeDockPrefs(dock) else { return log.error("install: could not write the Dock's preferences") }
    run("/usr/bin/killall", "Dock")
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
      if dockHasTile(path: path) {
        defaults.set(path, forKey: "dockTileFor")
        log.notice("install: Dock tile in place")
      } else if attempt < 5 {
        placeDockTile(path: path, attempt: attempt + 1)
      } else {
        log.error("install: Dock tile didn't stick; drag the app into the Dock")
      }
    }
  }

  static func dockHasTile(path: String) -> Bool {
    let tiles = dockPrefs()?["persistent-apps"] as? [[String: Any]] ?? []
    return tiles.contains { tile in
      let file = (tile["tile-data"] as? [String: Any])?["file-data"] as? [String: Any]
      return (file?["_CFURLString"] as? String).flatMap { URL(string: $0)?.path ?? $0 }.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 } == path
    }
  }

  // Through `defaults`, which goes by way of cfprefsd, rather than the plist file the Dock may rewrite.
  static func dockPrefs() -> [String: Any]? {
    guard let raw = run("/usr/bin/defaults", "export", "com.apple.dock", "-") else { return nil }
    return try? PropertyListSerialization.propertyList(from: raw, format: nil) as? [String: Any]
  }

  static func writeDockPrefs(_ dock: [String: Any]) -> Bool {
    guard let raw = try? PropertyListSerialization.data(fromPropertyList: dock, format: .binary, options: 0) else { return false }
    return run("/usr/bin/defaults", "import", "com.apple.dock", "-", input: raw) != nil
  }

  // MARK: Earlier versions

  // Arc for Chrome (the app's earlier name), Chrome Launcher (a launch agent that started Chrome with
  // the flags) and the Karabiner rule that once turned ⌃Tab into keys the extension could read.
  static func removeEarlierVersions() {
    let fm = FileManager.default
    let old = home.appendingPathComponent("Applications/Arc for Chrome.app")
    if fm.fileExists(atPath: old.path) {
      NSRunningApplication.runningApplications(withBundleIdentifier: "local.arc-for-chrome.helper").forEach { $0.terminate() }
      run(old.appendingPathComponent("Contents/MacOS/ArcHelper").path, "--unregister")
      try? fm.removeItem(at: old)
      try? fm.removeItem(at: support.appendingPathComponent("Arc for Chrome"))
      log.notice("install: removed Arc for Chrome")
    }
    let agent = home.appendingPathComponent("Library/LaunchAgents/local.arc-for-chrome.launcher.plist")
    let launcher = home.appendingPathComponent("Applications/Chrome Launcher.app")
    if fm.fileExists(atPath: agent.path) || fm.fileExists(atPath: launcher.path) {
      run("/bin/launchctl", "bootout", "gui/\(getuid())", agent.path)
      try? fm.removeItem(at: agent)
      try? fm.removeItem(at: launcher)
      log.notice("install: removed Chrome Launcher")
    }
    let karabiner = home.appendingPathComponent(".config/karabiner/karabiner.json")
    if let data = try? Data(contentsOf: karabiner), var config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       var profiles = config["profiles"] as? [[String: Any]] {
      var changed = false
      for i in profiles.indices {
        guard var mods = profiles[i]["complex_modifications"] as? [String: Any], let rules = mods["rules"] as? [[String: Any]] else { continue }
        let kept = rules.filter { !($0["description"] as? String ?? "").hasPrefix("Chrome: Ctrl+Tab / Ctrl+Shift+Tab") }
        guard kept.count != rules.count else { continue }
        mods["rules"] = kept
        profiles[i]["complex_modifications"] = mods
        changed = true
      }
      if changed, let out = try? JSONSerialization.data(withJSONObject: { config["profiles"] = profiles; return config }(), options: .prettyPrinted) {
        try? out.write(to: karabiner, options: .atomic)
        log.notice("install: removed the old Karabiner rule")
      }
    }
    try? fm.removeItem(at: home.appendingPathComponent(".config/karabiner/assets/complex_modifications/arc-for-chrome.json"))
  }

  // Runs a tool and returns its standard output, or nil when it fails or can't start.
  @discardableResult
  static func run(_ tool: String, _ args: String..., input: Data? = nil) -> Data? {
    let p = Process(), out = Pipe(), inPipe = Pipe()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    if input != nil { p.standardInput = inPipe }
    guard (try? p.run()) != nil else { return nil }
    if let input { inPipe.fileHandleForWriting.write(input); try? inPipe.fileHandleForWriting.close() }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return p.terminationStatus == 0 ? data : nil
  }
}
