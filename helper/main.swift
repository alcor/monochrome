// Monochrome.app: one binary, picked by argument.
//   (none)          the app: login item, Dock stand-in for Chrome, default browser, ⌃Tab tap, panels;
//                   installs itself at launch (Install.swift)
//   --portable      the app without the login item, Dock tile, default browser or App Shortcuts: only the
//                   native messaging host is registered, for a test run from the build folder
//   --host          native messaging host, spawned by Chrome for the extension (Host.swift)
//   --make-default  ask macOS to make this the default browser (a system dialog), then quit
//   --unregister    remove the login item, then quit
//   --register-host write the native messaging host manifests for this copy of the app, then quit
//   --demo          show the ⌃Tab switcher with sample tabs, to look at it (nothing else runs); prints
//                   the panel's rectangle on stderr for screencapture -R
//   --demo-shade    the peek browser shade over Chrome's second window, ordered below its first; prints its rectangle
//   --demo-profiles the profile HUD on Chrome's real Profiles menu, nothing pressed; prints its rectangle
//   --status        the keycodes the current layout gives the shortcut keys, whether the app half is up and
//                   the extension's host is connected
//   --routes [url [sender]]  the link rules (Routes.swift) and, for a URL, the rule it would take
//   --settings      open the settings window of the running app (started if it is not)
//   --demo-omnibox <out.png> [dark]  the ⌘L/⌘T box on sample history, drawn into a PNG
//   --omnibox-snapshot <out.png>  the open ⌘L/⌘T box as on screen, into a PNG
//   --omnibox chrome|safari [query] [--show] [--current] [--commit] [--profile=<name, Safari id prefix, @last, or @all to ask each connection for data>]  the
//                   ⌘L/⌘T box's model for that browser's profile, typed into without showing it (--show: the panel shown, typed into through
//                   its field; it takes the keyboard); the running app logs the rows (Omnibox.swift)
//   --check-safari <json>  the Safari readers' pure parts on given input, for the tests (Safari.swift)
//   --prefs [--defaults]  the `prefs` message the app sends the extension, as JSON: the current values, or
//                   the defaults (Prefs.swift), which the tests compare with the extension's PREF_DEFAULTS
//   --demo-settings [tab] [out.png] [dark]  the settings window on a tab (general, browser, tabs, mini,
//                   address, player, router, or 0 to 6; Router when none) over a scratch defaults suite,
//                   with sample rules and profiles; with out.png, drawn into that file from the view and quit
// Log: log stream --info --predicate 'subsystem == "com.artifact.monochrome"' (Accessibility shows there; asking
// from a shell would report the terminal's grant, not the app's)
import AppKit
import ServiceManagement

switch CommandLine.arguments.dropFirst().first {
case "--host":
  Host.run()
case "--demo":
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  showBackdropIfAsked()
  let switcher = Switcher()
  switcher.demo()
  app.run()
case "--demo-profiles":
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let backdrop = showBackdropIfAsked()
  let profiles = Profiles()
  profiles.demo(sample: backdrop != nil)
  app.run()
case "--demo-settings":
  // The settings window on a tab with sample rules and profiles, on scratch defaults; active over the
  // backdrop, or drawn into a PNG.
  let app = NSApplication.shared
  Prefs.useDemoStore()
  let rest = CommandLine.arguments.dropFirst(2).filter { !$0.hasPrefix("--") }
  let tab = rest.first { !$0.hasSuffix(".png") && $0 != "dark" }.flatMap(SettingsWindow.tabIndex) ?? SettingsWindow.tabNames.count - 1
  let out = rest.first { $0.hasSuffix(".png") }
  if out != nil { app.setActivationPolicy(.accessory) }
  let backdrop = out == nil ? showBackdropIfAsked() : nil
  backdrop?.level = .normal
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
    SettingsWindow.shared.demo(tab: tab, out: out, dark: rest.contains("dark"))
    if CommandLine.arguments.contains("--extension") { InstallExtensionPanel.shared.show() }
  }
  app.run()
case "--demo-shade":
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let overlays = MiniBrowsers()
  overlays.demoShade()
  app.run()
case "--status":
  print("layout: n=\(Keyboard.code(for: "n", qwerty: 45)) o=\(Keyboard.code(for: "o", qwerty: 31)) l=\(Keyboard.code(for: "l", qwerty: 37)) .=\(Keyboard.code(for: ".", qwerty: 47)) ,=\(Keyboard.code(for: ",", qwerty: 43)) (keycodes under the current keyboard layout)")
  print("browser:", Browser.current.name)
  print("app:", NSRunningApplication.runningApplications(withBundleIdentifier: App.bundleId).isEmpty ? "not running" : "running")
  print("host:", Socket.connect(Socket.path).map { close($0); return "socket up" } ?? "socket down")
  exit(0)
case "--prefs":
  Prefs.printPayload(defaults: CommandLine.arguments.contains("--defaults"))
  exit(0)
case "--check-safari":
  exit(SafariCheck.run(CommandLine.arguments.dropFirst(2).first))
case "--routes":
  let rest = CommandLine.arguments.dropFirst(2)
  Routes.print(url: rest.first, from: rest.dropFirst().first)
  exit(0)
case "--settings":
  func ask(_ tries: Int) {
    if let fd = Socket.connect(Socket.path) {
      let line = Data("{\"settings\":true}\n".utf8)
      _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
      close(fd)
      exit(0)
    }
    guard tries > 0 else { FileHandle.standardError.write(Data("Monochrome is not running\n".utf8)); exit(1) }
    if tries == 12 {
      let open = Process()
      open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      open.arguments = ["-g", "-b", App.bundleId]
      try? open.run()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { ask(tries - 1) }
  }
  ask(12)
  RunLoop.main.run()
case "--demo-omnibox":
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let omnibox = OmniboxController()
  omnibox.demo(out: CommandLine.arguments.dropFirst(2).first ?? "omnibox.png", dark: CommandLine.arguments.contains("dark"))
  app.run()
case "--omnibox", "--omnibox-snapshot":
  let rest = Array(CommandLine.arguments.dropFirst(2))
  let message: [String: Any] = CommandLine.arguments[1] == "--omnibox-snapshot"
    ? ["omniboxSnapshot": rest.first ?? "omnibox.png"]
    : ["omniboxTest": ["browser": rest.first ?? "chrome", "show": rest.contains("--show"), "newTab": !rest.contains("--current"), "commit": rest.contains("--commit"),
                       "profile": rest.first { $0.hasPrefix("--profile=") }.map { String($0.dropFirst(10)) } ?? "",
                       "query": rest.dropFirst().filter { !$0.hasPrefix("--") }.joined(separator: " ")]]
  guard let fd = Socket.connect(Socket.path), var line = try? JSONSerialization.data(withJSONObject: message) else {
    FileHandle.standardError.write(Data("Monochrome is not running\n".utf8))
    exit(1)
  }
  line.append(10)
  _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
  sleep(4) // the app answers to this connection's lifetime; the rows go to the log
  close(fd)
  exit(0)
case "--unregister":
  try? SMAppService.mainApp.unregister()
  exit(0)
case "--make-default":
  Install.makeDefaultBrowser { exit(0) }
  RunLoop.main.run()
case "--register-host":
  // The host manifests alone, for the tests and for a build that is not opened.
  Install.registerHosts()
  exit(0)
default:
  let app = NSApplication.shared
  let delegate = App()
  app.delegate = delegate
  app.run()
}

// --backdrop: a plain 1280 by 800 window behind the panel, for a screenshot that shows nothing else;
// its screen rectangle goes to stderr for screencapture -R.
@discardableResult
func showBackdropIfAsked() -> NSWindow? {
  guard CommandLine.arguments.contains("--backdrop") else { return nil }
  let backdrop = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
  backdrop.level = .floating
  backdrop.contentView = GradientView()
  backdrop.center()
  backdrop.orderFrontRegardless()
  Chrome.demoAnchor = backdrop.frame
  let f = backdrop.frame, top = (NSScreen.screens.first?.frame.height ?? 0) - f.maxY
  FileHandle.standardError.write(Data("backdrop \(Int(f.minX)),\(Int(top)),\(Int(f.width)),\(Int(f.height))\n".utf8))
  return backdrop
}

final class GradientView: NSView {
  override func draw(_ dirtyRect: NSRect) {
    NSGradient(colors: [NSColor(red: 0.85, green: 0.89, blue: 0.93, alpha: 1), NSColor(red: 0.95, green: 0.93, blue: 0.89, alpha: 1),
                        NSColor(red: 0.90, green: 0.87, blue: 0.84, alpha: 1)])!.draw(in: bounds, angle: -35)
  }
}
