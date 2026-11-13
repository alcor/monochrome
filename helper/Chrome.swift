// What the helper knows about Chrome: starting it with the launch flags its flags page doesn't offer,
// whether it's in front, and where its front window is.
//
// OmniboxForceAllowedToBeDefault lets a history page be the address bar's Enter target even when what
// you typed isn't the start of its address ("acme/commits" -> github.com/acme-corp/app/commits).
// Chrome reads --enable-features only at startup, so a Chrome started some other way runs without it
// until it's quit and reopened through this app; the Dock icon and the login item both come here.
import AppKit
import UserNotifications

// Both browsers' extensions connect at once. `active` is the one the app works with at a given moment:
// the browser in front, or the one that was in front before this app's own panels or settings window
// came forward. Everything that follows "Chrome" below (the front app check, its windows over the
// window list and Accessibility, opening links) follows Safari instead while that is Safari, and
// profiles come from Safari's File menu (Safari.swift).
// `current` is the setting on the settings window's Browser tab: the browser links from other apps open
// in, and the one started at login. The launch flags and the Dock tile stay Chrome's. Kept in the app's
// defaults; Chrome until changed.
//
// Microsoft Edge is Chromium too: its variants sit beside Chrome's in Chrome.chromiumVariants, its
// extension is the same folder and its windows and connections are handled the same way. `.edge` as
// the setting makes Edge the one links open in, the one started at login and the one the Dock tile and
// the launch flags are for; `isChromium` is what most of the app asks.
enum Browser: String, CaseIterable, Identifiable {
  case chrome, edge, safari
  var id: String { rawValue }
  var name: String {
    switch self {
    case .chrome: "Chrome"
    case .edge: "Edge"
    case .safari: "Safari"
    }
  }
  var isChromium: Bool { self != .safari }
  // The scheme of the browser's own pages: chrome://extensions, edge://extensions.
  var scheme: String { self == .edge ? "edge" : "chrome" }
  // The Chromium the Chrome-only settings rows are about: this one, or Chrome while Safari is chosen.
  var chromium: Browser { isChromium ? self : .chrome }

  static var current: Browser {
    get { Prefs.store.string(forKey: "browser").flatMap(Browser.init(rawValue:)) ?? .chrome }
    set {
      let before = active
      Prefs.store.set(newValue.rawValue, forKey: "browser")
      if active != before { Chrome.onBrowserChange() }
    }
  }

  static var active: Browser { _ = Chrome.watchFront; return Chrome.frontBrowser ?? current }
}

enum Chrome {
  // Every Chrome the extension runs in, each with its own profiles, extension copy and native
  // messaging host folder (Install.swift registers with each one that has run). Their windows and
  // connections are handled together; stable comes first and is what the Dock icon and the login
  // item start when none is running. `name` is what their window titles carry; `hostFolder` is where,
  // under Application Support, that browser reads native messaging host manifests.
  struct Variant { let bundleId: String, name: String, family: Browser, hostFolder: String }
  static let chromiumVariants = [
    Variant(bundleId: "com.google.Chrome", name: "Google Chrome", family: .chrome, hostFolder: "Google/Chrome"),
    Variant(bundleId: "com.google.Chrome.beta", name: "Google Chrome Beta", family: .chrome, hostFolder: "Google/Chrome Beta"),
    Variant(bundleId: "com.google.Chrome.dev", name: "Google Chrome Dev", family: .chrome, hostFolder: "Google/Chrome Dev"),
    Variant(bundleId: "com.google.Chrome.canary", name: "Google Chrome Canary", family: .chrome, hostFolder: "Google/Chrome Canary"),
    Variant(bundleId: "org.chromium.Chromium", name: "Chromium", family: .chrome, hostFolder: "Chromium"),
    // Edge on Windows puts a zero-width space after "Microsoft" in its titles; split(title:) drops it.
    Variant(bundleId: "com.microsoft.edgemac", name: "Microsoft Edge", family: .edge, hostFolder: "Microsoft Edge"),
    Variant(bundleId: "com.microsoft.edgemac.Beta", name: "Microsoft Edge Beta", family: .edge, hostFolder: "Microsoft Edge Beta"),
    Variant(bundleId: "com.microsoft.edgemac.Dev", name: "Microsoft Edge Dev", family: .edge, hostFolder: "Microsoft Edge Dev"),
    Variant(bundleId: "com.microsoft.edgemac.Canary", name: "Microsoft Edge Canary", family: .edge, hostFolder: "Microsoft Edge Canary"),
  ]
  static let safari = Variant(bundleId: Safari.bundleId, name: "Safari", family: .safari, hostFolder: "")
  // Every Chromium, the chosen one's family first, so what starts when none is running is the
  // Browser setting's stable (Edge when Edge is chosen), and the others in their order after it.
  static var chromeVariants: [Variant] {
    let first = Browser.current.chromium
    return chromiumVariants.filter { $0.family == first } + chromiumVariants.filter { $0.family != first }
  }
  static func variant(_ bundleId: String?) -> Variant? { chromiumVariants.first { $0.bundleId == bundleId } ?? (bundleId == Safari.bundleId ? safari : nil) }
  // The browsers in play: every Chromium, or Safari alone.
  static var variants: [Variant] { Browser.active == .safari ? [safari] : chromeVariants }
  static var bundleIds: [String] { variants.map(\.bundleId) }
  static let features = ["OmniboxForceAllowedToBeDefault"]
  // The flags Chrome is started with: none when Settings → Browser → Address bar opens the matching
  // history page is off.
  static var launchArguments: [String] { Prefs.launchFlags ? ["--enable-features=" + features.joined(separator: ",")] : [] }

  static func isChrome(_ bundleId: String?) -> Bool { bundleId.map(bundleIds.contains) ?? false }
  static func name(of app: NSRunningApplication) -> String { variants.first { $0.bundleId == app.bundleIdentifier }?.name ?? "Chrome" }

  static var runningApps: [NSRunningApplication] { bundleIds.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) } }

  // The Chrome the launch flags are about, whichever browser is active.
  static var runningChrome: NSRunningApplication? {
    chromeVariants.lazy.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleId) }.first
  }

  // The one to ask when one is needed: the one in front, else the owner of the Chrome window highest
  // on screen, else whichever runs.
  static var running: NSRunningApplication? {
    let apps = runningApps
    guard apps.count > 1 else { return apps.first }
    if let front = NSWorkspace.shared.frontmostApplication, let app = apps.first(where: { $0.processIdentifier == front.processIdentifier }) { return app }
    if let pid = windows().first?.pid, let app = apps.first(where: { $0.processIdentifier == pid }) { return app }
    return apps.first
  }

  // Kept from the workspace's activation notices rather than asked per event: the tap consults it on
  // every keystroke and click.
  // (The front app's id is kept, not the answer, so a change of browser in settings counts at once.)
  static var isFrontmost: Bool { _ = watchFront; return isChrome(frontmost) }
  private static var frontmost: String?
  // The browser behind Browser.active: set when one comes forward, kept while this app is in front,
  // cleared when any other app is.
  private(set) static var frontBrowser: Browser?
  static var onBrowserChange: () -> Void = {}
  // IMPORTANT: the first state is not a change. onBrowserChange reads Browser.active, which waits on
  // this initializer: calling it from here traps (dispatch_once re-entered), which 1.2 did at launch
  // whenever the browser in front was not the Browser setting.
  static let watchFront: Void = {
    activated(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, notify: false)
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
      activated((note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier, notify: true)
    }
  }()
  // Reads frontBrowser directly, not Browser.active, for the same reason.
  private static func activated(_ bundleId: String?, notify: Bool) {
    frontmost = bundleId
    let before = frontBrowser ?? Browser.current
    if bundleId == Safari.bundleId { frontBrowser = .safari }
    else if let variant = chromiumVariants.first(where: { $0.bundleId == bundleId }) { frontBrowser = variant.family }
    else if bundleId != Bundle.main.bundleIdentifier { frontBrowser = nil }
    if notify && frontBrowser ?? Browser.current != before { onBrowserChange() }
  }

  // Launches with the flags, or hands URLs to the running one (which opens them as tabs: the extension
  // turns those into mini browsers). activate: bring it to the front either way.
  static func open(_ urls: [URL] = [], activate: Bool) {
    let running = running
    guard let appURL = running?.bundleURL ?? bundleIds.lazy.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = activate
    if running == nil && Browser.active.isChromium { configuration.arguments = launchArguments }
    if urls.isEmpty {
      NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    } else {
      NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration)
    }
  }

  // Quits the Chrome that is missing its flags and starts the same one again with them. terminate() is
  // an ordinary quit, so Chrome can still stop it (a download in progress asks first); after 30 seconds
  // the relaunch is dropped rather than forcing it.
  static func relaunchWithFlags() {
    guard let app = runningChrome, let appURL = app.bundleURL else { return }
    app.terminate()
    func start(after attempt: Int) {
      guard app.isTerminated else {
        if attempt < 120 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { start(after: attempt + 1) } }
        else { log.info("relaunch: \(name(of: app), privacy: .public) did not quit within 30 seconds") }
        return
      }
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.arguments = launchArguments
      NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }
    start(after: 0)
  }

  // A Chrome that was started some other way is missing its flags. Say so, once per Chrome launch,
  // instead of silently doing nothing.
  static var warnedPid: pid_t = 0
  static func warnIfStartedWithoutFlags() {
    guard Browser.current.isChromium, Prefs.launchFlags, let running = runningChrome, running.processIdentifier != warnedPid, runningWithFlags() == false else { return }
    warnedPid = running.processIdentifier
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert]) { granted, _ in
      guard granted else { return }
      let content = UNMutableNotificationContent()
      let name = variant(running.bundleIdentifier)?.family.name ?? "Chrome"
      content.title = "\(name) is running without its launch flags"
      content.body = "Quit \(name) (⌘Q) and open it from the Dock to turn the address-bar fix back on."
      center.add(UNNotificationRequest(identifier: "launch-flags", content: content, trigger: nil))
    }
  }

  // nil: not running. false: started some other way, without the flags. With the flags turned off in
  // Settings there is nothing missing, so a running Chrome counts as having them.
  static func runningWithFlags() -> Bool? {
    guard let running = runningChrome else { return nil }
    if !Prefs.launchFlags { return true }
    let ps = Process()
    ps.executableURL = URL(fileURLWithPath: "/bin/ps")
    ps.arguments = ["-o", "args=", "-p", String(running.processIdentifier)]
    let out = Pipe()
    ps.standardOutput = out
    guard (try? ps.run()) != nil else { return nil }
    let args = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let have = args.split(whereSeparator: { $0 == " " || $0 == "\n" })
      .first { $0.hasPrefix("--enable-features=") }?.dropFirst("--enable-features=".count).split(separator: ",").map(String.init) ?? []
    return !features.contains { !have.contains($0) }
  }

  struct Window {
    let id: CGWindowID // the window server's number, the same one NSWindow calls windowNumber
    let frame: CGRect
    var pid: pid_t = 0
  }

  // Chrome's windows on screen, front to back, in window-list coordinates (down from the top of the
  // main screen). Window bounds need no permission; only window titles would.
  // Every running Chrome's windows, front to back.
  static func windows() -> [Window] {
    let pids = Set(runningApps.map(\.processIdentifier))
    guard !pids.isEmpty else { return [] }
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.compactMap { w -> Window? in
      guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid), w[kCGWindowLayer as String] as? Int == 0,
            let id = w[kCGWindowNumber as String] as? CGWindowID,
            let frame = (w[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) }),
            frame.width > 120, frame.height > 80 else { return nil }
      return Window(id: id, frame: frame, pid: pid)
    }
  }

  static func windowFrames() -> [CGRect] { windows().map(\.frame) }

  // The on-screen window a frame the extension sent refers to: the same size (it is being dragged) or
  // the same corner (being resized).
  static func match(_ sent: CGRect, in windows: [Window]) -> Window? {
    let near = { (a: CGFloat, b: CGFloat) in abs(a - b) < 2 }
    return windows.first { (near($0.frame.width, sent.width) && near($0.frame.height, sent.height)) || (near($0.frame.minX, sent.minX) && near($0.frame.minY, sent.minY)) }
  }

  // Window-list coordinates to AppKit's, which count up from the bottom of the main screen.
  static func appKit(_ frame: CGRect) -> NSRect {
    let height = NSScreen.screens.first?.frame.height ?? 0
    return NSRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
  }

  static var demoAnchor: NSRect? // --demo --backdrop: the panels center on this instead of Chrome's window
  static var frontWindowFrame: NSRect? { demoAnchor ?? windowFrames().first { $0.width > 200 && $0.height > 200 }.map(appKit) }

  // The focused window's title over Accessibility, split as Chrome composes it: the tab's title, then
  // the browser's name, then " - " and the profile's name when there is more than one profile.
  static func frontWindowTitle() -> (tab: String, profile: String, browser: String)? {
    guard let running else { return nil }
    var window: AnyObject?
    guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(running.processIdentifier), kAXFocusedWindowAttribute as CFString, &window) == .success,
          let window, let full = axTitle(window as! AXUIElement)
    else { return nil }
    let (tab, profile) = split(title: full)
    return (tab, profile, name(of: running))
  }

  // A window's title is "tab - Google Chrome - profile" for a normal window (Beta, Dev, Canary and
  // Chromium put their own names there) and "tab - profile" for a popup, the profile part only when
  // that Chrome has more than one profile; the names come from the Profiles menus. Edge 157 on the Mac
  // writes "tab - Microsoft Edge - profile", Chrome's order, measured. On Windows it writes
  // "tab - profile - Microsoft\u{200B} Edge" (a zero-width space after Microsoft); that order and the
  // space are read too, in case a Mac build follows.
  static func split(title raw: String, profiles: [String]? = nil) -> (tab: String, profile: String) {
    let full = raw.replacingOccurrences(of: "\u{200B}", with: "")
    // Safari puts no profile in its titles, so a page title ending in a profile's name is just a title.
    let names = profiles ?? (Browser.active.isChromium ? Profiles.names() : [])
    func trailingProfile(_ title: String) -> (tab: String, profile: String) {
      for name in names.sorted(by: { $0.count > $1.count }) where title.hasSuffix(" - " + name) {
        return (String(title.dropLast(name.count + 3)), name)
      }
      return (title, "")
    }
    // Longest name first, so " - Google Chrome" is not found inside " - Google Chrome Beta".
    for variant in variants.sorted(by: { $0.name.count > $1.name.count }) {
      guard let mark = full.range(of: " - " + variant.name, options: .backwards) else { continue }
      let rest = full[mark.upperBound...], tab = String(full[..<mark.lowerBound])
      if rest.hasPrefix(" - ") { return (tab, String(rest.dropFirst(3))) }
      return variant.family == .edge ? trailingProfile(tab) : (tab, "")
    }
    return trailingProfile(full)
  }

  static func axTitle(_ window: AXUIElement) -> String? {
    var title: AnyObject?
    guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success else { return nil }
    return title as? String
  }

  // In window-list coordinates, like windows().
  static func axFrame(_ window: AXUIElement) -> CGRect? {
    var position: AnyObject?, size: AnyObject?
    var origin = CGPoint.zero, extent = CGSize.zero
    guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
          AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
          AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent)
    else { return nil }
    return CGRect(origin: origin, size: extent)
  }
}

// One read of the window list per tick, shared by everything that follows a Chrome window: the mini
// browser bars, the peek shade and the mini player. It reads only while one of them has something to
// follow and Chrome is in front, at 10 Hz, or 60 Hz while the mouse button is down, since a drag is
// the one time a window's position matters per frame.
final class WindowTracker {
  var needed: () -> Bool = { false }
  var onTick: ([Chrome.Window], Bool) -> Void = { _, _ in } // Chrome's windows front to back, and whether Chrome is in front
  var fast = false { didSet { if fast != oldValue { schedule() } } }
  private var timer: Timer?

  func start() { schedule() }

  private func schedule() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: fast ? 1.0 / 60 : 1.0 / 10, repeats: true) { [weak self] _ in self?.tick() }
  }

  private func tick() {
    let front = Chrome.isFrontmost
    onTick(front && needed() ? Chrome.windows() : [], front)
  }
}

// --check-chrome <json>: the pure parts above on given input, printed as {"result": ...}, for test.mjs.
//   {"op": "split", "title": "...", "profiles": [...]}  a window title split into tab and profile
//   {"op": "variants"}                                  every Chromium: bundle id, title name, family, host folder
//   {"op": "shortcuts", "family": "chrome"|"edge"}      the App Shortcuts that family's browsers are given
enum ChromeCheck {
  static func run(_ json: String?) -> Int32 {
    guard let json, let request = JSONLine.decode(json), let op = request["op"] as? String else {
      FileHandle.standardError.write(Data("usage: --check-chrome '{\"op\": ...}'\n".utf8))
      return 2
    }
    var out: Any = NSNull()
    switch op {
    case "split":
      let (tab, profile) = Chrome.split(title: request["title"] as? String ?? "", profiles: request["profiles"] as? [String] ?? [])
      out = [tab, profile]
    case "variants":
      out = Chrome.chromiumVariants.map { ["bundleId": $0.bundleId, "name": $0.name, "family": $0.family.rawValue, "hostFolder": $0.hostFolder] }
    case "shortcuts":
      let edge = request["family"] as? String == Browser.edge.rawValue
      out = Install.split(edge ? [:] : Install.sidebarShortcuts, Install.tabShortcuts).want
    default:
      FileHandle.standardError.write(Data("unknown op \(op)\n".utf8))
      return 2
    }
    guard let data = try? JSONSerialization.data(withJSONObject: ["result": out], options: [.sortedKeys]) else { return 1 }
    print(String(decoding: data, as: UTF8.self))
    return 0
  }
}
