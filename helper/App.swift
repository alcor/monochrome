// The app half: launched at login (it registers itself as a login item) and from the Dock, where it
// takes Chrome's place so that opening Chrome goes through it and gets the launch flags. Also the
// default browser: links from other apps arrive here and go to the extension over the bridge, which
// opens them as mini browsers without a tab ever passing through the main window. If the extension isn't
// connected, the link goes to Chrome the ordinary way and the extension catches it there.
//
// Chrome runs one copy of the extension per profile, each with its own port, so there is one
// connection per profile here. Tab and window ids are unique across a Chrome process, so lists merge;
// what needs routing is which connection gets a message: the owner of a tab or mini browser, or the
// one whose front window is the window in front on screen.
import AppKit
import ServiceManagement

final class Connection {
  let peer: LineSocket
  var tabs: [TabInfo] = []
  var front: (id: Int, frame: CGRect, title: String)?
  var profile: String? // the name Chrome puts in this profile's window titles, once seen
  var minis: [MiniBrowser] = []
  var targets: [Target] = []
  init(peer: LineSocket) { self.peer = peer }
}

final class App: NSObject, NSApplicationDelegate {
  static let bundleId = "local.monochrome"
  let switcher = Switcher()
  let player = Player()
  let minis = MiniBrowsers()
  let profiles = Profiles()
  let tap = Tap()
  let tracker = WindowTracker()
  var server: SocketServer?
  var connections: [Connection] = []
  var playerOwner: Connection?
  var sessions = Set<String>()
  var scrollTimer: Timer?

  func applicationDidFinishLaunching(_ notification: Notification) {
    signal(SIGPIPE, SIG_IGN)
    NSApp.setActivationPolicy(.accessory)
    try? SMAppService.mainApp.register()
    NSApp.mainMenu = mainMenu()
    SettingsWindow.shared.connectionsSummary = { [weak self] in
      guard let self, !connections.isEmpty else { return "Not connected" }
      let names = connections.compactMap(\.profile)
      let count = "\(connections.count) profile\(connections.count == 1 ? "" : "s")"
      return "Connected in " + (names.count == connections.count ? names.joined(separator: ", ") : count)
    }

    tap.switcher = switcher
    tap.useSwitcher = { [weak self] in
      guard let self else { return false }
      switcher.frontWindow = frontConnection?.front?.id ?? -1
      return !connections.isEmpty && switcher.inFront.count > 1
    }
    switcher.onActivate = { [weak self] id in
      guard let self else { return }
      send(["activate": id], to: connections.first { c in c.tabs.contains { $0.id == id } } ?? frontConnection)
    }
    player.onAction = { [weak self] action in self?.send(["player": ["action": action]], to: self?.playerOwner) }
    minis.onAction = { [weak self] action in
      guard let self else { return }
      let window = action["window"] as? Int
      send(["mini": action], to: connections.first { c in c.minis.contains { $0.id == window } } ?? frontConnection)
    }
    tap.onScroll = { [weak self] in
      guard let self else { return }
      scrollTimer?.invalidate()
      scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in self?.send(["scrolled": true], to: self?.frontConnection) }
    }
    tap.onAltCommandClick = { [weak self] in self?.send(["miniNext": true], to: self?.frontConnection) }
    tap.onMouse = { [weak self] down in
      self?.minis.mouseDown = down
      self?.tracker.fast = down
    }
    tap.onCommandL = { [weak self] in
      guard let self, let front = minis.frontWindow else { return false }
      minis.showAddress(front.id)
      return true
    }
    tap.onNewMiniBrowser = { [weak self] in
      guard let self, let front = frontConnection else { return false }
      send(["miniNew": true], to: front)
      return true
    }
    tap.onMiniBrowserOpen = { [weak self] pick in
      guard let self, !connections.isEmpty, let front = minis.frontWindow else { return false }
      if pick { minis.showMenu(front.id) } else { minis.onAction(["window": front.id, "action": "open"]) }
      return true
    }
    tap.onProfile = { [weak self] step, index in
      guard let self else { return }
      if let index { profiles.go(to: index) } else { profiles.cycle(step) }
    }
    tracker.needed = { [weak self] in
      guard let self else { return false }
      return !minis.windows.isEmpty || player.wantsFollowing
    }
    tracker.onTick = { [weak self] windows, front in
      self?.minis.follow(windows, front: front)
      self?.player.follow(windows, front: front)
    }
    tracker.start()

    server = SocketServer(path: Socket.path, queue: .main)
    if server == nil { log.error("socket: could not listen at \(Socket.path, privacy: .public)") }
    server?.onConnection = { [weak self] peer in
      guard let self else { return }
      let connection = Connection(peer: peer)
      connections.append(connection)
      log.info("host: connected (\(self.connections.count))")
      send(["resend": true], to: connection) // this app may have restarted under a host that is already up
      peer.onLine = { [weak self, weak connection] line in
        guard let connection, let message = JSONLine.decode(line) else { return }
        self?.receive(message, from: connection)
      }
      peer.onClose = { [weak self, weak connection] in
        guard let self, let connection else { return }
        connections.removeAll { $0 === connection }
        log.info("host: disconnected (\(self.connections.count) left)")
        if playerOwner === connection { playerOwner = nil; player.apply(nil) }
        merge()
      }
    }

    whenTrusted { [weak self] in
      let installed = self?.tap.install() ?? false
      log.info("tap: \(installed ? "installed" : "could not be created", privacy: .public)")
    }
    if Chrome.running == nil { Chrome.open(activate: false) } else { Chrome.warnIfStartedWithoutFlags() }
  }

  // A reopen from the Dock, where the tile stands in for Chrome, opens Chrome. From anywhere else
  // (the app double-clicked in the Finder, `open -a Monochrome`) it opens the settings window.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    let from = Self.currentEventSender()
    log.info("reopen from \(from ?? "?", privacy: .public)")
    if from == "com.apple.dock" {
      Chrome.open(activate: true)
      Chrome.warnIfStartedWithoutFlags()
    } else {
      SettingsWindow.shared.show()
    }
    return false
  }

  // The bundle id of the app that sent the Apple event being handled, when it is still running.
  static func currentEventSender() -> String? {
    let pid = NSAppleEventManager.shared().currentAppleEvent?.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
    return pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
  }

  // Links from other apps, as the default browser. The open event names the sender; a rule
  // (Routes.swift) may send the link to another app or profile; otherwise it goes to the profile whose
  // window is in front, with the rule's destination inside it, or as a mini browser.
  func application(_ application: NSApplication, open urls: [URL]) {
    let web = urls.filter { ["http", "https"].contains($0.scheme?.lowercased()) }
    guard !web.isEmpty else { return }
    let sender = Self.currentEventSender()
    for url in web { route(url, from: sender) }
  }

  func route(_ url: URL, from sender: String?) {
    let rule = Routes.route(url, from: sender)
    log.notice("route: \(url.host ?? "", privacy: .public) from \(sender ?? "?", privacy: .public): \(rule?.description ?? "no rule", privacy: .public)")
    let to = rule?.to ?? [:]
    if let app = to["app"] as? String {
      guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) else {
        log.error("route: no app \(app, privacy: .public); opening in Chrome instead")
        return deliver(url, to: [:], over: frontConnection)
      }
      return NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
    if let profile = to["profile"] as? String { return deliver(url, to: to, profile: profile) }
    deliver(url, to: to, over: frontConnection)
  }

  // Over a profile's connection when there is one; else Chrome gets the URL as a tab in the profile it
  // last used and the extension there, if any, makes a mini browser of it.
  func deliver(_ url: URL, to: [String: Any], over connection: Connection?) {
    if let connection {
      log.notice("route: over \(connection.profile ?? "the unnamed connection", privacy: .public)")
      send(["open": url.absoluteString, "to": to.filter { !["profile", "app"].contains($0.key) }], to: connection)
      Chrome.running?.activate()
    } else {
      log.notice("route: no connection; Chrome opens it")
      Chrome.open([url], activate: true)
    }
  }

  // A named profile: its connection when it is known by name. Otherwise Chrome's own switch (the
  // Profiles menu item) brings that profile's window forward, opening one if it has none, and the
  // extension there connects and reports a window carrying the name. Up to three seconds for that;
  // then the URL goes to Chrome, which opens it in the profile now in front.
  func deliver(_ url: URL, to: [String: Any], profile name: String, tries: Int = 12) {
    learnProfiles()
    if let known = connections.first(where: { $0.profile == name }) { return deliver(url, to: to, over: known) }
    if tries == 12 {
      let list = Profiles.read()
      guard let index = list.firstIndex(where: { $0.name == name }) else {
        log.error("route: no profile named \(name, privacy: .public); using the front one")
        return deliver(url, to: to, over: frontConnection)
      }
      profiles.go(to: index, in: list)
    }
    guard tries > 0 else { return Chrome.open([url], activate: true) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.deliver(url, to: to, profile: name, tries: tries - 1) }
  }

  // Every Chrome window's title names its profile; a connection whose reported front window is the
  // only one matching a window, by tab title or by frame, learns that name. The title the extension
  // sent can be behind the page, and the frame behind a move, so either one counts.
  var lastLearn = Date.distantPast
  func learnProfiles(force: Bool = false) {
    // At most every two seconds unless forced: with a single profile the titles carry no name, and
    // this would read the window list on every message for nothing.
    guard connections.contains(where: { $0.profile == nil && $0.front != nil }), force || Date().timeIntervalSince(lastLearn) > 2,
          let running = Chrome.running else { return }
    lastLearn = Date()
    var list: AnyObject?
    guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(running.processIdentifier), kAXWindowsAttribute as CFString, &list) == .success,
          let windows = list as? [AXUIElement] else { return }
    for window in windows {
      guard let full = Chrome.axTitle(window) else { continue }
      let (tab, profile) = Chrome.split(title: full)
      guard !profile.isEmpty, !connections.contains(where: { $0.profile == profile }) else { continue }
      let frame = Chrome.axFrame(window)
      let candidates = connections.filter { c in
        guard c.profile == nil, let front = c.front else { return false }
        return front.title == tab || frame.map { Chrome.match(front.frame, in: [Chrome.Window(id: 0, frame: $0)]) != nil } ?? false
      }
      if candidates.count == 1 {
        candidates[0].profile = profile
        log.notice("profile: connection learned as \(profile, privacy: .public)")
      }
    }
  }

  // The connection of the profile whose window is in front on screen: the window's title names the
  // profile, and the connection that has learned that name (learnProfiles) is it. Nil when no
  // connection has: that profile has no extension running, or its name is not known yet, and a link
  // sent over another profile's connection would open there. A title with no name means Chrome has
  // one profile, and the front window's frame picks among connections, if there are several.
  var frontConnection: Connection? {
    guard let front = Chrome.windows().first else { return connections.first }
    guard let title = Chrome.frontWindowTitle(), !title.profile.isEmpty else {
      return connections.first { c in c.front.map { Chrome.match($0.frame, in: [front]) != nil } ?? false } ?? connections.first
    }
    if let known = connections.first(where: { $0.profile == title.profile }) { return known }
    learnProfiles(force: true)
    if let known = connections.first(where: { $0.profile == title.profile }) { return known }
    log.notice("profile: no connection for \(title.profile, privacy: .public) in front")
    return nil
  }

  func send(_ message: [String: Any], to connection: Connection?) {
    guard let connection, let line = JSONLine.encode(message) else { return }
    connection.peer.send(line)
  }

  func receive(_ message: [String: Any], from connection: Connection) {
    if let hello = message["hello"] as? [String: Any], let session = hello["session"] as? String, !sessions.contains(session) {
      // A session id this app hasn't seen: Chrome restarted, and tab ids with it.
      if !sessions.isEmpty { switcher.thumbs = [:] }
      sessions.insert(session)
    }
    if let mru = message["mru"] as? [[String: Any]] {
      log.info("mru: \(mru.count) tabs")
      let had = Dictionary(connection.tabs.map { ($0.id, $0.favicon) }, uniquingKeysWith: { a, _ in a })
      connection.tabs = mru.compactMap { tab in
        guard let id = tab["id"] as? Int, let windowId = tab["windowId"] as? Int else { return nil }
        // A favicon comes once per tab and page; after that the message leaves it out.
        let favicon = tab["favicon"] is NSNull ? nil : (tab["favicon"] as? String).map(image) ?? had[id] ?? nil
        return TabInfo(id: id, windowId: windowId, title: tab["title"] as? String ?? "", favicon: favicon)
      }
      if let id = message["window"] as? Int, let front = message["front"] as? [String: Any], let frame = rect(front) {
        connection.front = (id, frame, front["title"] as? String ?? "")
      }
      merge()
      let listed = Set(connections.flatMap(\.tabs).map(\.id))
      switcher.thumbs = switcher.thumbs.filter { listed.contains($0.key) } // a tab that drops off every list is captured again when next in front
    }
    if let thumb = message["thumb"] as? [String: Any], let id = thumb["id"] as? Int, let image = image(thumb["data"] as? String) {
      log.info("thumb: tab \(id)")
      switcher.thumbs[id] = image
    }
    if let closed = message["closed"] as? Int { switcher.forget(tab: closed) }
    if let targets = message["targets"] as? [[String: Any]] {
      connection.targets = targets.compactMap { t -> Target? in
        guard let windowId = t["windowId"] as? Int else { return nil }
        let groups = (t["groups"] as? [[String: Any]] ?? []).compactMap { g -> (id: Int, title: String, color: String)? in
          guard let id = g["id"] as? Int else { return nil }
          return (id, g["title"] as? String ?? "", g["color"] as? String ?? "grey")
        }
        return Target(windowId: windowId, title: t["title"] as? String ?? "", groups: groups)
      }
    }
    if let minis = message["minis"] as? [[String: Any]] {
      log.info("minis: \(minis.count)")
      connection.minis = minis.compactMap { w -> MiniBrowser? in
        guard let id = w["id"] as? Int, let frame = rect(w) else { return nil }
        return MiniBrowser(id: id, frame: frame, url: w["url"] as? String ?? "", title: w["title"] as? String ?? "",
                           over: (w["over"] as? [String: Any]).flatMap(rect), targets: connection.targets)
      }
      merge()
    }
    if let shortcuts = message["shortcuts"] as? [String: String] {
      log.info("shortcuts: \(shortcuts.count)")
      minis.shortcuts = shortcuts
    }
    if let menu = message["miniMenu"] as? Int { minis.showMenu(menu) }
    if message["settings"] != nil { SettingsWindow.shared.show() } // --settings, over the socket
    if message.keys.contains("player") {
      let state = (message["player"] as? [String: Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        .flatMap { try? JSONDecoder().decode(PlayerState.self, from: $0) }
      if state != nil { playerOwner = connection }
      if state != nil || playerOwner === connection { player.apply(state) }
    }
  }

  // The menu bar, seen while the settings window has the app in the Dock: Settings and Quit, and an
  // Edit menu so the rule fields take the standard keys.
  func mainMenu() -> NSMenu {
    let main = NSMenu()
    let app = NSMenu()
    app.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
    app.addItem(.separator())
    app.addItem(withTitle: "Quit Monochrome", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    let file = NSMenu(title: "File")
    file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(.separator())
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    for menu in [app, file, edit] {
      let item = NSMenuItem()
      item.submenu = menu
      main.addItem(item)
    }
    return main
  }

  @objc func showSettings() { SettingsWindow.shared.show() }

  // The switcher and the bars see every profile's tabs and mini browsers together; each mini browser
  // carries its profile's name for its bar, once learned.
  func merge() {
    learnProfiles()
    switcher.tabs = connections.flatMap(\.tabs)
    minis.windows = connections.flatMap { c in c.minis.map { var m = $0; m.profile = c.profile; return m } }
  }

  // Window bounds arrive as Chrome sends them: left, top, width, height.
  func rect(_ b: [String: Any]) -> CGRect? {
    guard let left = b["left"] as? Double, let top = b["top"] as? Double, let width = b["width"] as? Double, let height = b["height"] as? Double
    else { return nil }
    return CGRect(x: left, y: top, width: width, height: height)
  }

  // Images arrive as data: URLs.
  func image(_ dataURL: String?) -> NSImage? {
    guard let dataURL, let comma = dataURL.firstIndex(of: ","), dataURL.hasPrefix("data:"),
          let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]))
    else { return nil }
    return NSImage(data: data)
  }

  // The event tap needs Accessibility. Ask once, then wait for the switch to be flipped.
  func whenTrusted(_ then: @escaping () -> Void) {
    let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    if AXIsProcessTrustedWithOptions(prompt) { return then() }
    log.info("accessibility: not granted yet, waiting")
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
      if AXIsProcessTrusted() {
        timer.invalidate()
        then()
      }
    }
  }
}
