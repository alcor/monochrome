// What the helper knows about Chrome: starting it with the launch flags its flags page doesn't offer,
// whether it's in front, and where its front window is.
//
// OmniboxForceAllowedToBeDefault lets a history page be the address bar's Enter target even when what
// you typed isn't the start of its address ("acme/commits" -> github.com/acme-corp/app/commits).
// Chrome reads --enable-features only at startup, so a Chrome started some other way runs without it
// until it's quit and reopened through this app; the Dock icon and the login item both come here.
import AppKit
import UserNotifications

enum Chrome {
  static let bundleId = "com.google.Chrome"
  static let features = ["OmniboxForceAllowedToBeDefault"]

  static var running: NSRunningApplication? { NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first }

  // Kept from the workspace's activation notices rather than asked per event: the tap consults it on
  // every keystroke and click.
  static var isFrontmost: Bool { _ = frontmostObserver; return frontmost }
  private static var frontmost = false
  private static let frontmostObserver: Void = {
    frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleId
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
      frontmost = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == bundleId
    }
  }()

  // Launches with the flags, or hands URLs to the running one (which opens them as tabs: the extension
  // turns those into mini browsers). activate: bring it to the front either way.
  static func open(_ urls: [URL] = [], activate: Bool) {
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = activate
    if running == nil { configuration.arguments = ["--enable-features=" + features.joined(separator: ",")] }
    if urls.isEmpty {
      NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    } else {
      NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration)
    }
  }

  // A Chrome that was started some other way is missing its flags. Say so, once per Chrome launch,
  // instead of silently doing nothing.
  static var warnedPid: pid_t = 0
  static func warnIfStartedWithoutFlags() {
    guard let running, running.processIdentifier != warnedPid, runningWithFlags() == false else { return }
    warnedPid = running.processIdentifier
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert]) { granted, _ in
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = "Chrome is running without its launch flags"
      content.body = "Quit Chrome (⌘Q) and open it from the Dock to turn the address-bar fix back on."
      center.add(UNNotificationRequest(identifier: "launch-flags", content: content, trigger: nil))
    }
  }

  // nil: not running. false: started some other way, without the flags.
  static func runningWithFlags() -> Bool? {
    guard let running else { return nil }
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
  }

  // Chrome's windows on screen, front to back, in window-list coordinates (down from the top of the
  // main screen). Window bounds need no permission; only window titles would.
  static func windows() -> [Window] {
    guard let running else { return [] }
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return windows
      .filter { $0[kCGWindowOwnerPID as String] as? pid_t == running.processIdentifier && $0[kCGWindowLayer as String] as? Int == 0 }
      .compactMap { w -> Window? in
        guard let id = w[kCGWindowNumber as String] as? CGWindowID,
              let frame = (w[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) }),
              frame.width > 120, frame.height > 80 else { return nil }
        return Window(id: id, frame: frame)
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
  // " - Google Chrome", then " - " and the profile's name when there is more than one profile.
  static func frontWindowTitle() -> (tab: String, profile: String)? {
    guard let running else { return nil }
    var window: AnyObject?
    guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(running.processIdentifier), kAXFocusedWindowAttribute as CFString, &window) == .success,
          let window, let full = axTitle(window as! AXUIElement)
    else { return nil }
    return split(title: full)
  }

  // A window's title is "tab - Google Chrome - profile" for a normal window and "tab - profile" for a
  // popup, the profile part only when Chrome has more than one; the names come from its Profiles menu.
  static func split(title full: String) -> (tab: String, profile: String) {
    if let mark = full.range(of: " - Google Chrome", options: .backwards) {
      let rest = full[mark.upperBound...]
      return (String(full[..<mark.lowerBound]), rest.hasPrefix(" - ") ? String(rest.dropFirst(3)) : "")
    }
    for name in Profiles.names() where full.hasSuffix(" - " + name) {
      return (String(full.dropLast(name.count + 3)), name)
    }
    return (full, "")
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
