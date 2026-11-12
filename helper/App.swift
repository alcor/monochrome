// The app half: launched at login (it registers itself as a login item once per location, and does
// the rest of the install at each launch: Install.swift) and from the Dock, where it
// takes Chrome's place so that opening Chrome goes through it and gets the launch flags. Also the
// default browser: links from other apps arrive here and go to the extension over the bridge, which
// opens them as mini browsers without a tab ever passing through the main window. If the extension isn't
// connected, the link goes to Chrome the ordinary way and the extension catches it there.
//
// Chrome runs one copy of the extension per profile, each with its own port, so there is one
// connection per profile here. Tab and window ids are unique across a Chrome process, so lists merge;
// what needs routing is which connection gets a message: the owner of a tab or mini browser, or the
// one whose front window is the window in front on screen.
//
// Safari's copies of the extension reach the app through its app extension instead (Bridge.swift,
// Safari.swift): one connection per Safari profile, made when that profile's first message arrives and
// dropped when it has been quiet for 150 seconds (the extension says it is alive every minute) or
// Safari quits. Only the connections of the browser chosen in settings take part. A Safari connection
// is known by Safari's profile id; its name is learned when the app opens that profile's window from
// Safari's File menu (learnSafariProfile) and kept across launches (SafariProfiles.learned).
//
// The settings (Prefs.swift) the extension must obey go to each connection as one `prefs` message when
// it says hello, and to every connection when one of them changes.
import AppKit
import Sparkle

final class Connection {
  let peer: Peer
  var tabs: [TabInfo] = []
  var front: (id: Int, frame: CGRect, title: String)?
  var frontPinned = false // the front window's active tab is pinned (⌘W sleeps it)
  var profile: String? // the name Chrome puts in this profile's window titles, once seen; on Safari, the learned name
  var browser: String? // which Chrome (Chrome.Variant.name), learned with the profile
  var app: NSRunningApplication? { Chrome.runningApps.first { Chrome.name(of: $0) == browser } ?? Chrome.running }
  var minis: [MiniBrowser] = []
  var targets: [Target] = []
  var safari: SafariPeer? { peer as? SafariPeer }
  init(peer: Peer) { self.peer = peer }
}

// The app has no Dock tile or windows most of the time, so an update found by a scheduled check would
// show its alert behind whatever is in front. Sparkle asks background apps to handle that; here the app
// comes forward for it.
final class UpdateReminders: NSObject, SPUStandardUserDriverDelegate {
  var supportsGentleScheduledUpdateReminders: Bool { true }

  func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
    if !state.userInitiated { NSApp.activate(ignoringOtherApps: true) }
  }
}

final class App: NSObject, NSApplicationDelegate {
  static let bundleId = "com.artifact.monochrome"
  let switcher = Switcher()
  let reminders = UpdateReminders()
  lazy var updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: reminders)
  let player = Player()
  let minis = MiniBrowsers()
  let profiles = Profiles()
  let tap = Tap()
  let tracker = WindowTracker()
  let omnibox = OmniboxController()
  let reader = Reader()
  var omniboxConnection: Connection?
  var omniboxRequest = 0
  var server: SocketServer?
  var safariServer: SocketServer?
  var safariSockets: [ObjectIdentifier: LineSocket] = [:] // the app extension's open sockets
  var allConnections: [Connection] = []
  // The active browser's (Browser.active); allConnections holds both browsers'.
  var connections: [Connection] { allConnections.filter { ($0.safari != nil) == (Browser.active == .safari) } }
  var playerOwner: Connection?
  var sessions = Set<String>()
  var scrollTimer: Timer?
  var prefsSent = "" // the last `prefs` payload sent to every connection, as JSON

  func applicationDidFinishLaunching(_ notification: Notification) {
    signal(SIGPIPE, SIG_IGN)
    NSApp.setActivationPolicy(.accessory)
    Install.atLaunch()
    NSApp.mainMenu = mainMenu()
    updater.startUpdater()
    SettingsWindow.shared.checkForUpdates = { [weak self] in self?.updater.checkForUpdates(nil) }
    SettingsWindow.shared.connectedProfiles = { [weak self] in self?.allConnections.compactMap(ConnectedProfile.init) ?? [] }
    SettingsWindow.shared.automaticUpdates = (get: { [weak self] in self?.updater.updater.automaticallyChecksForUpdates ?? true },
                                              set: { [weak self] in self?.updater.updater.automaticallyChecksForUpdates = $0 })
    prefsSent = Prefs.json(Prefs.payload)
    NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: Prefs.store, queue: .main) { [weak self] _ in self?.prefsChanged() }

    Chrome.onBrowserChange = { [weak self] in self?.merge() }
    tap.switcher = switcher
    tap.useSwitcher = { [weak self] in
      guard let self else { return false }
      // Settings → Tabs → Switcher panel off: the keys go to the extension's commands, which switch live.
      guard Prefs.switcherPanel else { return false }
      switcher.frontWindow = frontConnection?.front?.id ?? -1
      return !connections.isEmpty && switcher.inFront.count > 1
    }
    switcher.onActivate = { [weak self] id in
      guard let self else { return }
      send(["activate": id], to: connections.first { c in c.tabs.contains { $0.id == id } } ?? frontConnection)
    }
    player.onAction = { [weak self] action in self?.send(["player": ["action": action]], to: self?.playerOwner) }
    minis.profileNames = { Profiles.names() }
    minis.onAction = { [weak self] action in
      guard let self else { return }
      let window = action["window"] as? Int
      let owner = connections.first { c in c.minis.contains { $0.id == window } } ?? frontConnection
      // Another profile: the page goes there as a new tab, the way a routed link does, and the mini browser closes.
      if action["action"] as? String == "openIn", let profile = action["profile"] as? String,
         let url = URL(string: action["url"] as? String ?? "") {
        deliver(url, to: ["window": "front"], profile: profile)
        return send(["mini": ["window": window ?? 0, "action": "close"]], to: owner)
      }
      send(["mini": action], to: owner)
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
      guard let self else { return false }
      guard let front = minis.frontWindow else { return openOmnibox(newTab: false) }
      minis.showAddress(front.id)
      return true
    }
    tap.onCommandT = { [weak self] in self?.openOmnibox(newTab: true) ?? false }
    // Chrome asks before it closes a pinned tab; ⌘W on one sleeps it instead (sleepFront in
    // background.js). Only Chrome, only a pinned tab in a normal window: a mini browser and anything
    // else close as before.
    tap.onCommandW = { [weak self] in
      guard let self, Prefs.pinnedSleep, Browser.active.isChromium, minis.frontWindow == nil,
            let connection = frontConnection, connection.frontPinned else { return false }
      send(["sleepFront": true], to: connection)
      return true
    }
    tap.omniboxShown = { [weak self] in self?.omnibox.isVisible ?? false }
    // ⌥⇧R: the reader in the tab in front, when the setting is on and that profile's extension is connected.
    tap.onReader = { [weak self] in
      guard let self, let front = frontConnection else { return false }
      send(["tldr": ["op": "toggle"]], to: front)
      return true
    }
    setUpOmnibox()
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
    profiles.onSafari = { [weak self] profile in self?.switchSafari(to: profile) }
    SafariProfiles.current = { [weak self] in self?.frontConnection?.profile }
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
      allConnections.append(connection)
      log.info("host: connected (\(self.allConnections.count))")
      send(["resend": true], to: connection) // this app may have restarted under a host that is already up
      peer.onLine = { [weak self, weak connection] line in
        guard let connection, let message = JSONLine.decode(line) else { return }
        self?.receive(message, from: connection)
      }
      peer.onClose = { [weak self, weak connection] in
        guard let self, let connection else { return }
        drop(connection)
        log.info("host: disconnected (\(self.allConnections.count) left)")
      }
    }
    startSafari()

    whenTrusted { [weak self] in
      let installed = self?.tap.install() ?? false
      log.info("tap: \(installed ? "installed" : "could not be created", privacy: .public)")
    }
    // Chrome is started at login to get its launch flags (unless Settings → Browser says not to);
    // Safari takes none and starts when wanted.
    if Browser.current.isChromium && Prefs.openBrowserAtLaunch {
      if Chrome.running == nil { Chrome.open(activate: false) } else { Chrome.warnIfStartedWithoutFlags() }
    }
  }

  // ⌘L and ⌘T in the browser in front (Omnibox.swift): for the profile whose window is in front, when
  // its extension is connected and the key's setting (Settings → Command Bar) is on; otherwise the keys
  // go to the browser.
  func openOmnibox(newTab: Bool, connection given: Connection? = nil, display: Bool = true) -> Bool {
    guard given != nil || (newTab ? Prefs.omniboxT : Prefs.omniboxL) else { return false }
    guard let connection = given ?? frontConnection else {
      log.info("omnibox: \(newTab ? "⌘T" : "⌘L", privacy: .public) left to the browser: no connection for the front window")
      return false
    }
    let browser: Browser = connection.safari != nil ? .safari : .chrome
    log.info("omnibox: \(newTab ? "⌘T" : "⌘L", privacy: .public) in \(browser.name, privacy: .public), \(connection.profile ?? connection.safari?.label ?? "unnamed profile", privacy: .public)")
    omniboxConnection = connection
    omniboxRequest += 1
    if display { omnibox.show(newTab: newTab, browser: browser, over: Chrome.frontWindowFrame) } else { omnibox.model.reset(newTab: newTab, browser: browser) }
    send(["omnibox": ["op": "data", "id": omniboxRequest]], to: connection)
    if let safari = connection.safari {
      SafariHistory.load(profile: safari.profile) { [weak self, weak connection] pages in
        guard let self, let connection, omniboxConnection === connection else { return }
        omnibox.model.pages = pages
        omnibox.model.dataArrived()
      }
    }
    return true
  }

  func setUpOmnibox() {
    let model = omnibox.model
    model.onDismiss = { [weak self] in self?.omnibox.hide() }
    model.onGo = { [weak self] go in
      guard let self else { return }
      log.info("omnibox: go \(go.keys.sorted().joined(separator: ","), privacy: .public)")
      send(["omnibox": go.merging(["op": "go"]) { a, _ in a }], to: omniboxConnection)
      omnibox.hide()
    }
    // Google's suggestions, unless Settings → Command Bar → Google suggestions is off: then nothing typed
    // leaves the Mac.
    model.onSuggest = { [weak model] text in
      guard Prefs.omniboxSuggestions else { return }
      Omnibox.suggest(text) { model?.receive(suggestions: $0, for: text) }
    }
    model.onNeedIcons = { [weak self, weak model] pages in
      guard let self, let connection = omniboxConnection else { return }
      if connection.safari != nil {
        Omnibox.googleFavicons(pages) { page, image in model?.icons[page] = image }
      } else {
        send(["omnibox": ["op": "favicons", "id": omniboxRequest, "urls": pages]], to: connection)
      }
    }
  }

  // --omnibox: the box's model for a profile of the given browser, fed and typed into without showing
  // the panel, its rows logged. The panel is left alone, since it would take the keyboard from whatever
  // is in front.
  func testOmnibox(_ test: [String: Any]) {
    let safari = test["browser"] as? String == "safari"
    // Browsers' connections only: they have reported tabs. (This command's own socket is a connection too.)
    let candidates = allConnections.filter { ($0.safari != nil) == safari && (!$0.tabs.isEmpty || $0.front != nil) }
    let wanted = (test["profile"] as? String ?? "").lowercased()
    if wanted == "@all" {
      for (i, c) in candidates.enumerated() {
        log.info("omnibox test: asking connection \(i): \(c.profile ?? "unnamed", privacy: .public) in \(c.browser ?? "?", privacy: .public), \(c.tabs.count) tabs")
        send(["omnibox": ["op": "data", "id": -1 - i]], to: c)
      }
      return
    }
    let named = wanted == "@last" ? candidates.last : wanted.isEmpty ? nil : candidates.first { ($0.safari?.profile ?? $0.profile ?? "").lowercased().hasPrefix(wanted) || ($0.profile ?? "").lowercased().hasPrefix(wanted) }
    guard let connection = named ?? candidates.first(where: { $0.profile != nil }) ?? candidates.first else { return log.info("omnibox test: no \(safari ? "Safari" : "Chrome", privacy: .public) connection") }
    let show = test["show"] as? Bool ?? false
    _ = openOmnibox(newTab: test["newTab"] as? Bool ?? true, connection: connection, display: show)
    let query = test["query"] as? String ?? ""
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
      let model = omnibox.model
      if show { omnibox.field.typeForTest(query) } else { model.update(query: query, allowCompletion: true) }
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
        log.info("omnibox test: \(model.pages.count) pages, \(model.tabs.count) tabs, current \(model.current?.url ?? "none", privacy: .public)")
        log.info("omnibox test: \(query, privacy: .public)[\(model.completion, privacy: .public)]")
        if show, let editor = omnibox.field.currentEditor() {
          log.info("omnibox test: field \(editor.string, privacy: .public), selected \(NSStringFromRange(editor.selectedRange), privacy: .public), panel key \(self.omnibox.isKey)")
        }
        for (i, row) in model.rows.enumerated() {
          log.info("omnibox test: \(i) \(row.id, privacy: .public) | \(row.title, privacy: .public) | \(row.detail ?? "", privacy: .public) | icon \(row.page.map { model.icons[$0] != nil } ?? false)")
        }
        if test["commit"] as? Bool == true { model.commit() } // Return on the top row
      }
    }
  }

  func receiveOmnibox(_ data: [String: Any], from connection: Connection) {
    guard connection === omniboxConnection, data["id"] as? Int == omniboxRequest else {
      return log.info("omnibox: dropped data for request \(data["id"] as? Int ?? -1) (current \(self.omniboxRequest)), \(connection === self.omniboxConnection ? "same" : "another", privacy: .public) connection")
    }
    let model = omnibox.model
    if connection.safari == nil {
      let history = (data["history"] as? [[String: Any]] ?? []).compactMap { h -> OmniboxPage? in
        guard let url = h["url"] as? String else { return nil }
        return OmniboxPage(url: url, title: h["title"] as? String ?? "", visits: h["visits"] as? Int ?? 0, typed: h["typed"] as? Int ?? 0,
                           last: Date(timeIntervalSince1970: (h["last"] as? Double ?? 0) / 1000), bookmarked: false)
      }
      let bookmarks = (data["bookmarks"] as? [[String: Any]] ?? []).compactMap { b in (b["url"] as? String).map { ($0, b["title"] as? String ?? "") } }
      model.pages = Omnibox.merge(history: history, bookmarks: bookmarks)
      log.info("omnibox: \(history.count) history pages, \(bookmarks.count) bookmarks")
    }
    let tab = { (t: [String: Any]) -> OmniboxTab? in
      guard let id = t["id"] as? Int, let url = t["url"] as? String else { return nil }
      return OmniboxTab(id: id, url: url, title: t["title"] as? String ?? "")
    }
    model.tabs = (data["tabs"] as? [[String: Any]] ?? []).compactMap(tab)
    model.current = (data["current"] as? [String: Any]).flatMap(tab)
    model.dataArrived()
    if let url = model.current?.url { omnibox.showCurrent(url) }
  }

  func drop(_ connection: Connection) {
    allConnections.removeAll { $0 === connection }
    if playerOwner === connection { playerOwner = nil; player.apply(nil) }
    reader.drop(connection)
    merge()
  }

  // Safari: the app extension's socket, one line per message with its profile; pings to keep each
  // profile's service worker up, as Chrome's host does; and a resend at launch and when Safari starts,
  // since messages sent while the app was down are lost.
  func startSafari() {
    safariServer = SocketServer(path: SafariSocket.path, queue: .main)
    if safariServer == nil { log.error("safari: could not listen at \(SafariSocket.path, privacy: .public)") }
    safariServer?.onConnection = { [weak self] socket in
      guard let self else { return }
      let key = ObjectIdentifier(socket)
      safariSockets[key] = socket
      socket.onClose = { [weak self] in self?.safariSockets[key] = nil }
      socket.onLine = { [weak self] line in
        guard let envelope = JSONLine.decode(line), let message = envelope["message"] as? [String: Any] else { return }
        self?.receiveSafari(message, profile: envelope["profile"] as? String ?? "")
      }
    }
    Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
      guard let self else { return }
      for c in allConnections where c.safari != nil && Date().timeIntervalSince(c.safari!.lastHeard) > 150 {
        log.info("safari: \(c.safari!.label, privacy: .public) gone quiet")
        drop(c)
      }
      if Safari.isRunning { allConnections.filter { $0.safari != nil }.forEach { self.send(["ping": true], to: $0) } }
    }
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
      guard let self, (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == Safari.bundleId else { return }
      allConnections.filter { $0.safari != nil }.forEach(drop)
    }
    center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
      guard (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == Safari.bundleId else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 3) { Safari.dispatch(["resend": true]) }
    }
    if Safari.isRunning { Safari.dispatch(["resend": true]) }
  }

  func receiveSafari(_ message: [String: Any], profile: String) {
    let connection: Connection
    if let known = allConnections.first(where: { $0.safari?.profile == profile }) {
      connection = known
    } else {
      connection = Connection(peer: SafariPeer(profile: profile))
      connection.profile = SafariProfiles.learned[profile]
      allConnections.append(connection)
      log.info("safari: \(connection.safari!.label, privacy: .public) connected (\(self.allConnections.count))")
      if message["hello"] == nil { send(["resend": true], to: connection) } // the app started after it said hello
    }
    connection.safari?.lastHeard = Date()
    receive(message, from: connection)
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
    // No rule: Settings → Mini Browsers → Links from other apps open as.
    let to = rule?.to ?? Prefs.routeDefault.to
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
      connection.app?.activate()
    } else {
      log.notice("route: no connection; Chrome opens it")
      Chrome.open([url], activate: true)
    }
  }

  // A named profile: its connection when it is known by name. Otherwise Chrome's own switch (the
  // Profiles menu item) brings that profile's window forward, opening one if it has none, and the
  // extension there connects and reports a window carrying the name. Up to three seconds for that;
  // then the URL goes to Chrome, which opens it in the profile now in front.
  // On Safari the switch is the profile's File → New Window item, which opens a window of that
  // profile; the connection that reports it learns the name (learnSafariProfile), and the link goes
  // over that connection. Safari gets eight seconds, since a profile's extension may start with it.
  func deliver(_ url: URL, to: [String: Any], profile name: String, tries: Int? = nil) {
    learnProfiles()
    if let known = connection(profile: name, browser: nil) { return deliver(url, to: to, over: known) }
    if tries == nil {
      let list = Profiles.read()
      guard let index = list.firstIndex(where: { $0.name == name }) else {
        log.error("route: no profile named \(name, privacy: .public); using the front one")
        return deliver(url, to: to, over: frontConnection)
      }
      profiles.go(to: index, in: list)
    }
    let left = tries ?? (Browser.active == .safari ? 32 : 12)
    guard left > 0 else { return Chrome.open([url], activate: true) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.deliver(url, to: to, profile: name, tries: left - 1) }
  }

  // A Safari profile picked by hotkey or by a route. When its extension is connected and has a window,
  // that copy of the extension focuses its last focused window. Otherwise the app presses the
  // profile's File → New Window item and waits for a connection to report a new front window: that
  // connection is the profile. **Unmeasured**: whether each profile's copy of the extension sees only
  // that profile's windows, which this relies on.
  var pendingSafari: (name: String, at: Date, fronts: [ObjectIdentifier: Int])?
  func switchSafari(to profile: Profile) {
    if let known = connection(profile: profile.name, browser: nil), known.front != nil {
      send(["focusFront": true], to: known)
      NSRunningApplication.runningApplications(withBundleIdentifier: Safari.bundleId).first?.activate()
      return
    }
    pendingSafari = (profile.name, Date(), Dictionary(connections.map { (ObjectIdentifier($0), $0.front?.id ?? -1) }, uniquingKeysWith: { a, _ in a }))
    AXUIElementPerformAction(profile.item, kAXPressAction as CFString)
  }

  // After switchSafari pressed a New Window item: the first Safari connection, within ten seconds,
  // whose front window is not the one it had before (or that is new) takes the profile's name.
  func learnSafariProfile(_ connection: Connection) {
    guard let pending = pendingSafari, let peer = connection.safari, let front = connection.front else { return }
    guard Date().timeIntervalSince(pending.at) < 10 else { pendingSafari = nil; return }
    if pending.fronts[ObjectIdentifier(connection)] == front.id { return }
    pendingSafari = nil
    for other in allConnections where other !== connection && other.safari != nil && other.profile == pending.name { other.profile = nil }
    connection.profile = pending.name
    SafariProfiles.remember(pending.name, for: peer.profile)
    log.notice("profile: Safari profile \(peer.label, privacy: .public) learned as \(pending.name, privacy: .public)")
  }

  // The connection learned as a profile of a Chrome: a popup's title has no browser name, so a
  // profile named alike in two Chromes is told apart only by a normal window's title.
  func connection(profile: String, browser: String?) -> Connection? {
    connections.first { $0.profile == profile && (browser == nil || $0.browser == browser) }
  }

  // Every Chrome window's title names its profile; a connection whose reported front window is the
  // only one matching a window, by tab title or by frame, learns that name and which Chrome it is in.
  // The title the extension sent can be behind the page, and the frame behind a move, so either one
  // counts.
  var lastLearn = Date.distantPast
  func learnProfiles(force: Bool = false) {
    // At most every two seconds unless forced: with a single profile the titles carry no name, and
    // this would read the window list on every message for nothing. Safari names no profile in its
    // titles; its connections are told apart by Safari's own profile id instead.
    guard Browser.active.isChromium, connections.contains(where: { $0.profile == nil && $0.front != nil }), force || Date().timeIntervalSince(lastLearn) > 2 else { return }
    lastLearn = Date()
    for app in Chrome.runningApps {
      let browser = Chrome.name(of: app)
      var list: AnyObject?
      guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute as CFString, &list) == .success,
            let windows = list as? [AXUIElement] else { continue }
      // A frame says which window only when no other window has it: two maximized windows of two
      // profiles share one, and a frame match there named the other profile's connection.
      let frames = windows.map(Chrome.axFrame)
      for (index, window) in windows.enumerated() {
        guard let full = Chrome.axTitle(window) else { continue }
        let (tab, profile) = Chrome.split(title: full)
        guard !profile.isEmpty, connection(profile: profile, browser: browser) == nil else { continue }
        let frame = frames[index]
        let frameIsUnique = frame.map { f in frames.enumerated().allSatisfy { $0.offset == index || $0.element.map { Chrome.match(f, in: [Chrome.Window(id: 0, frame: $0)]) == nil } ?? true } } ?? false
        let unnamed = connections.filter { $0.profile == nil && $0.front != nil }
        let byTitle = unnamed.filter { $0.front?.title == tab }
        let candidates = !byTitle.isEmpty || !frameIsUnique ? byTitle : unnamed.filter { c in
          frame.map { Chrome.match(c.front!.frame, in: [Chrome.Window(id: 0, frame: $0)]) != nil } ?? false
        }
        if candidates.count == 1 {
          candidates[0].profile = profile
          candidates[0].browser = browser
          log.notice("profile: connection learned as \(profile, privacy: .public) in \(browser, privacy: .public)")
        } else if force {
          let fronts = connections.map { "\($0.profile ?? "?"): \($0.front.map { "\"\($0.title)\" \($0.frame)" } ?? "no front")" }
          log.notice("profile: \(candidates.count) matches for \"\(tab, privacy: .public)\" \(profile, privacy: .public) \(frame.map { "\($0)" } ?? "no frame", privacy: .public); connections: \(fronts.joined(separator: "; "), privacy: .public)")
        }
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
    if let known = connection(profile: title.profile, browser: title.browser) { return known }
    learnProfiles(force: true)
    if let known = connection(profile: title.profile, browser: title.browser) { return known }
    log.notice("profile: no connection for \(title.profile, privacy: .public) in \(title.browser, privacy: .public) in front")
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
    if let hello = message["hello"] as? [String: Any] {
      // The locked group's title, from a copy that kept one on its options page before the app held it:
      // taken once, while this app's own has never been set.
      if let legacy = hello["lockedGroup"] as? String, !Prefs.isSet(.lockedGroup) {
        Prefs.set(.lockedGroup, legacy)
        log.notice("prefs: locked group title \(legacy, privacy: .public) adopted from an extension")
      }
      send(["prefs": Prefs.payload], to: connection)
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
        connection.frontPinned = front["pinned"] as? Bool ?? false
        learnSafariProfile(connection)
      }
      merge()
      let listed = Set(connections.flatMap(\.tabs).map(\.id))
      switcher.thumbs = switcher.thumbs.filter { listed.contains($0.key) } // a tab that drops off every list is captured again when next in front
    }
    if Prefs.thumbnails, let thumb = message["thumb"] as? [String: Any], let id = thumb["id"] as? Int, let image = image(thumb["data"] as? String) {
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
    if let data = message["omniboxData"] as? [String: Any] { receiveOmnibox(data, from: connection) }
    if let favicons = message["omniboxFavicons"] as? [String: Any], connection === omniboxConnection, let icons = favicons["icons"] as? [String: Any] {
      for (page, data) in icons { if let icon = image(data as? String) { omnibox.model.icons[page] = icon } }
    }
    if let tldr = message["tldr"] as? [String: Any] { // the reader's model requests (Reader.swift)
      reader.receive(tldr, from: connection) { [weak self, weak connection] in self?.send($0, to: connection) }
    }
    if message["settings"] != nil { SettingsWindow.shared.show() } // --settings, over the socket
    if let test = message["omniboxTest"] as? [String: Any] { testOmnibox(test) } // --omnibox, over the socket
    if let path = message["omniboxSnapshot"] as? String { omnibox.snapshot(to: path) } // --omnibox-snapshot
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
    app.addItem(withTitle: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "").target = updater
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

  // A setting changed: when it is one the extension obeys, the whole set goes to every connection.
  func prefsChanged() {
    let now = Prefs.json(Prefs.payload)
    guard now != prefsSent else { return }
    prefsSent = now
    if !Prefs.thumbnails { switcher.thumbs = [:] }
    log.info("prefs: sent to \(self.allConnections.count) connections")
    for connection in allConnections { send(["prefs": Prefs.payload], to: connection) }
  }

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
