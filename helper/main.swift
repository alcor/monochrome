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
  // The settings window on the Router tab with sample rules, active, over the backdrop.
  let app = NSApplication.shared
  let backdrop = showBackdropIfAsked()
  backdrop?.level = .normal
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
    SettingsWindow.shared.demo(tab: CommandLine.arguments.contains("--general") ? 0 : 1)
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
  print("app:", NSRunningApplication.runningApplications(withBundleIdentifier: App.bundleId).isEmpty ? "not running" : "running")
  print("host:", Socket.connect(Socket.path).map { close($0); return "socket up" } ?? "socket down")
  exit(0)
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
