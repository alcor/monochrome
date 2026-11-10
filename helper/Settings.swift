// The settings window, laid out as Quicksilver's: tabs in the toolbar with their icons, grouped forms
// on a sidebar-material backdrop. Every feature that can be switched has a row (docs/settings.md), so
// the window is also the list of what Monochrome does. A row is its title with its keys, and at most
// one short descriptive line under it that says what the feature does; a longer explanation, a footer
// under a section, wrapped text or a "learn more" link stay out. Section headers are one or two words.
//
// Seven tabs: General (the app and what macOS grants it), Browser, Tabs, Mini Browsers, Address Box,
// Player (SettingsTabs.swift), and Router, which edits the link rules (SettingsRouter.swift), written
// back to routes.json as they change. The values live in the app's defaults (Prefs.swift).
//
// Monochrome has no Dock presence of its own (LSUIElement); while this window is on screen it is an app
// in the Dock with a menu bar, so the window can be found and switched to, and back to a background app
// when the window closes.
import AppKit
import Combine
import SwiftUI

final class SettingsWindow: NSObject, NSWindowDelegate {
  static let shared = SettingsWindow()
  static let width: CGFloat = 760
  // --demo-settings takes a tab by these names or by index.
  static let tabNames = ["general", "browser", "tabs", "mini", "address", "player", "router"]
  static func tabIndex(_ name: String) -> Int? {
    if let index = Int(name) { return tabNames.indices.contains(index) ? index : nil }
    return tabNames.firstIndex(of: name.lowercased())
  }

  var connectedProfiles: () -> [ConnectedProfile] = { [] }
  var checkForUpdates: () -> Void = {}
  // Sparkle's own setting, set by App; the demo keeps it in its scratch defaults.
  var automaticUpdates: (get: () -> Bool, set: (Bool) -> Void) = (
    get: { Prefs.store.object(forKey: "SUEnableAutomaticChecks") as? Bool ?? true },
    set: { Prefs.store.set($0, forKey: "SUEnableAutomaticChecks") }
  )
  private var window: NSWindow?
  private var tabs: SettingsTabController?
  private var rulesModel: RulesModel?
  private var heights: [CGFloat] = []
  var demoMode = false // --demo-settings: sample rules and profiles, and nothing outside the scratch defaults changes

  func show() {
    if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    if window == nil { window = make() }
    window?.center()
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    window = nil
    if !demoMode { NSApp.setActivationPolicy(.accessory) }
  }

  private func make() -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 400), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
    window.delegate = self
    window.isReleasedWhenClosed = false
    window.titlebarAppearsTransparent = true
    window.toolbarStyle = .preference
    let model = GeneralModel(profiles: connectedProfiles, demo: demoMode)
    let rules = demoMode ? RulesModel(sample: Rule.samples) : RulesModel()
    rulesModel = rules
    let check = { [weak self] in self?.checkForUpdates() ?? () }
    // Heights fitted so no tab scrolls, from the --demo-settings pictures.
    let pages: [(NSViewController, String, String, CGFloat)] = [
      (NSHostingController(rootView: GeneralSettings(model: model, updates: automaticUpdates, onCheckForUpdates: check)), "General", "gearshape", 320),
      (NSHostingController(rootView: BrowserSettings(model: model)), "Browser", "globe", 570),
      (NSHostingController(rootView: TabsSettings(model: model)), "Tabs", "sidebar.left", 500),
      (NSHostingController(rootView: MiniBrowserSettings()), "Mini Browsers", "macwindow.on.rectangle", 320),
      (NSHostingController(rootView: AddressBoxSettings(model: model)), "Address Box", "magnifyingglass", 290),
      (NSHostingController(rootView: PlayerSettings()), "Player", "music.note", 300),
      (NSHostingController(rootView: RoutesSettings(model: rules)), "Router", "arrow.triangle.branch", 500), // the rules beside the selected one's fields
    ]
    heights = pages.map(\.3)
    let tabs = SettingsTabController()
    for (controller, label, symbol, height) in pages {
      controller.preferredContentSize = NSSize(width: Self.width, height: height)
      let item = NSTabViewItem(viewController: controller)
      item.label = label
      item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
      tabs.addTabViewItem(item)
    }
    window.contentViewController = tabs
    window.setContentSize(NSSize(width: Self.width, height: heights[0]))
    window.title = pages[0].1
    self.tabs = tabs
    return window
  }

  // --demo-settings: the window up, active, on a tab, with the first sample rule selected. With `out`,
  // the window is put off screen and its content view drawn into that PNG, as --demo-omnibox does (no
  // screen recording needed); the toolbar is not part of that view, so the tab's name is drawn in its
  // place.
  func demo(tab: Int, out: String? = nil, dark: Bool = false) {
    demoMode = true
    connectedProfiles = { ConnectedProfile.samples }
    if out == nil { show() } else { window = make() }
    guard let window else { return }
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    tabs?.selectedTabViewItemIndex = tab
    window.setContentSize(NSSize(width: Self.width, height: heights[tab]))
    rulesModel?.selection = rulesModel?.rules.first?.id
    guard let out else {
      if let anchor = Chrome.demoAnchor {
        window.setFrameOrigin(NSPoint(x: anchor.midX - window.frame.width / 2, y: anchor.midY - window.frame.height / 2))
      }
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      return
    }
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
    window.orderFrontRegardless()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [self] in
      guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
      view.cacheDisplay(in: view.bounds, to: rep)
      // The backdrop's material does not draw this way: the window's background color stands in for it.
      let picture = NSImage(size: view.bounds.size)
      picture.lockFocus()
      window.effectiveAppearance.performAsCurrentDrawingAppearance {
        NSColor.windowBackgroundColor.setFill()
        view.bounds.fill()
        rep.draw(in: view.bounds)
        let title = tabs?.tabViewItems[tab].label ?? ""
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
        let size = title.size(withAttributes: attributes)
        title.draw(at: NSPoint(x: (view.bounds.width - size.width) / 2, y: view.bounds.height - 30), withAttributes: attributes)
      }
      picture.unlockFocus()
      guard let tiff = picture.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { exit(1) }
      try? png.write(to: URL(fileURLWithPath: out))
      print(out)
      exit(0)
    }
  }
}

// Tabs in the toolbar, the way a Settings window draws them, over the About box's translucency. The
// window takes each tab's preferred height as it is selected.
final class SettingsTabController: NSTabViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    tabStyle = .toolbar
    let backdrop = NSVisualEffectView(frame: view.bounds)
    backdrop.material = .sidebar
    backdrop.blendingMode = .behindWindow
    backdrop.state = .followsWindowActiveState
    backdrop.autoresizingMask = [.width, .height]
    view.addSubview(backdrop, positioned: .below, relativeTo: nil)
  }

  override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
    super.tabView(tabView, didSelect: tabViewItem)
    view.window?.title = tabViewItem?.label ?? "Monochrome"
  }
}

// Redraws the forms when any setting changes, wherever it was changed from.
final class PrefsObserver: ObservableObject {
  static let shared = PrefsObserver()
  private var token: NSObjectProtocol?
  init() {
    token = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
      self?.objectWillChange.send()
    }
  }
}

extension Prefs {
  static func binding(_ pref: Pref, then: @escaping () -> Void = {}) -> Binding<Bool> {
    Binding(get: { bool(pref) }, set: { set(pref, $0); then() })
  }
}

// A row: its title, the keys in the README's notation, and one line of description in caption size
// and secondary color, never wrapped; the control on the right. Every tab draws its rows with this.
struct SettingRow<Control: View>: View {
  let title: String
  var keys: String?
  var detail: String?
  @ViewBuilder var control: () -> Control

  init(_ title: String, keys: String? = nil, detail: String? = nil, @ViewBuilder control: @escaping () -> Control) {
    self.title = title
    self.keys = keys
    self.detail = detail
    self.control = control
  }

  var body: some View {
    // The description runs under the control too, so a 60-character line fits a column.
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 8) {
        keys.map { Text(title + "  ") + Text($0).foregroundColor(.secondary) } ?? Text(title)
        Spacer(minLength: 0)
        control()
      }
      if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
    }
  }
}

// A switch row; `disabled` when the row depends on one that is off.
struct SettingToggle: View {
  let title: String
  var keys: String?
  var detail: String?
  let isOn: Binding<Bool>

  init(_ title: String, keys: String? = nil, detail: String? = nil, isOn: Binding<Bool>) {
    self.title = title
    self.keys = keys
    self.detail = detail
    self.isOn = isOn
  }

  var body: some View {
    SettingRow(title, keys: keys, detail: detail) {
      Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
    }
  }
}

// A profile whose extension is talking to the app, as the Browser Profiles list shows it: the browser's
// icon, the profile's avatar, its name.
struct ConnectedProfile: Identifiable {
  let name: String
  let browser: String
  let appIcon: NSImage
  var id: String { browser + "\u{0}" + name }
}

extension ConnectedProfile {
  // nil until Chrome's window titles have told the app the profile's name.
  init?(_ connection: Connection) {
    let variant: Chrome.Variant
    if let safari = connection.safari {
      variant = Chrome.safari
      name = connection.profile ?? safari.label
    } else {
      guard let profile = connection.profile else { return nil }
      let index = Chrome.chromeVariants.firstIndex { $0.name == connection.browser } ?? 0
      variant = Chrome.chromeVariants[index]
      name = profile
    }
    browser = variant.name
    appIcon = Self.icon(variant)
  }

  static func icon(_ variant: Chrome.Variant) -> NSImage {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: variant.bundleId).map { NSWorkspace.shared.icon(forFile: $0.path) }
      ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!
  }

  // --demo-settings: three profiles, two of them Chrome's.
  static var samples: [ConnectedProfile] {
    let chrome = Chrome.chromeVariants[0]
    return [ConnectedProfile(name: "Work (acme.com)", browser: chrome.name, appIcon: icon(chrome)),
            ConnectedProfile(name: "Personal", browser: chrome.name, appIcon: icon(chrome)),
            ConnectedProfile(name: "Personal", browser: Chrome.safari.name, appIcon: icon(Chrome.safari))]
  }
}
