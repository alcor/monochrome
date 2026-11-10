// The settings window, laid out as Quicksilver's: tabs in the toolbar with their icons, grouped forms
// on a sidebar-material backdrop, and a footer under the first tab. General holds the app's own
// switches and what it can see of Chrome; Routes edits the link rules (Routes.swift), written back to
// routes.json as they change. Monochrome has no Dock presence of its own (LSUIElement); while this
// window is on screen it is an app in the Dock with a menu bar, so the window can be found and
// switched to, and back to a background app when the window closes.
import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class SettingsWindow: NSObject, NSWindowDelegate {
  static let shared = SettingsWindow()
  static let size = NSSize(width: 760, height: 464)
  var connectionsSummary: () -> String = { "" }
  var connectedProfiles: () -> [ConnectedProfile] = { [] }
  var checkForUpdates: () -> Void = {}
  private var window: NSWindow?
  private var tabs: SettingsTabs?
  private var rulesModel: RulesModel?
  var sampleRules = false // --demo-settings: rules shown, not the file's, and nothing written

  func show() {
    if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    if window == nil { window = make() }
    window?.center()
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    window = nil
    NSApp.setActivationPolicy(.accessory)
  }

  private func make() -> NSWindow {
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
    window.delegate = self
    window.isReleasedWhenClosed = false
    window.titlebarAppearsTransparent = true
    window.toolbarStyle = .preference
    var generalView = GeneralSettings(model: GeneralModel(connections: connectionsSummary, profiles: connectedProfiles))
    generalView.onCheckForUpdates = { [weak self] in self?.checkForUpdates() }
    let general = NSHostingController(rootView: generalView)
    let rules = sampleRules ? RulesModel(sample: Rule.samples) : RulesModel()
    rulesModel = rules
    let routes = NSHostingController(rootView: RoutesSettings(model: rules))
    general.preferredContentSize = Self.size
    routes.preferredContentSize = NSSize(width: Self.size.width, height: 500) // the rules beside the selected one's fields
    let tabs = SettingsTabs()
    for (controller, label, symbol) in [(general, "General", "gearshape"), (routes, "Router", "arrow.triangle.branch")] as [(NSViewController, String, String)] {
      let item = NSTabViewItem(viewController: controller)
      item.label = label
      item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
      tabs.addTabViewItem(item)
    }
    window.contentViewController = tabs
    window.setContentSize(Self.size)
    window.title = "General"
    self.tabs = tabs
    return window
  }

  // --demo-settings: the window up, active, on a tab, with the first sample rule selected.
  func demo(tab: Int) {
    sampleRules = true
    show()
    tabs?.selectedTabViewItemIndex = tab
    rulesModel?.selection = rulesModel?.rules.first?.id
    if let anchor = Chrome.demoAnchor, let window {
      window.setFrameOrigin(NSPoint(x: anchor.midX - window.frame.width / 2, y: anchor.midY - window.frame.height / 2))
    }
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
}

// Tabs in the toolbar, the way a Settings window draws them, over the About box's translucency.
final class SettingsTabs: NSTabViewController {
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

// General: login item, default browser, Accessibility, and what the app sees of Chrome and its extension.
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
    appIcon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: variant.bundleId).map { NSWorkspace.shared.icon(forFile: $0.path) }
      ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!
  }
}

final class GeneralModel: ObservableObject {
  @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
  @Published var isDefaultBrowser = false
  @Published var accessibility = AXIsProcessTrusted()
  @Published var browserWarning: String? // shown as a triangle by the Browser Profiles header
  @Published var browser = Browser.current
  @Published var extensions = ""
  @Published var connected: [ConnectedProfile] = []
  let connections: () -> String
  let profiles: () -> [ConnectedProfile]
  let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

  init(connections: @escaping () -> String, profiles: @escaping () -> [ConnectedProfile]) {
    self.connections = connections
    self.profiles = profiles
    refresh()
  }

  func refresh() {
    launchAtLogin = SMAppService.mainApp.status == .enabled
    accessibility = AXIsProcessTrusted()
    isDefaultBrowser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) == Bundle.main.bundleURL
    browser = Browser.current
    browserWarning = browser == .chrome && Chrome.runningWithFlags() == false
      ? "Chrome is running without its launch flags. Quit it (⌘Q) and open it from the Dock." : nil
    extensions = connections()
    connected = profiles()
  }

  func setLaunchAtLogin(_ on: Bool) {
    do {
      if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    } catch {
      log.error("login item: \(error.localizedDescription, privacy: .public)")
    }
    launchAtLogin = SMAppService.mainApp.status == .enabled
  }

  func setBrowser(_ browser: Browser) {
    Browser.current = browser
    // Safari's App Shortcuts, as the app writes them at launch; Safari applies them when it next starts.
    if browser == .safari && !Install.portable { SafariShortcuts.write() }
    refresh()
  }

  func installExtension() {
    if browser == .safari { Safari.showExtensionSettings() } else { InstallExtensionPanel.shared.show() }
  }

  func relaunchChrome() {
    let alert = NSAlert()
    alert.messageText = "Relaunch Chrome?"
    alert.informativeText = "Chrome quits and opens again with its launch flags. Its windows come back if Chrome's Settings → On startup is set to Continue where you left off."
    alert.addButton(withTitle: "Relaunch")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    Chrome.relaunchWithFlags()
  }

  func makeDefault() {
    Install.makeDefaultBrowser { [weak self] in self?.refresh() }
  }

  static func openPrivacyPane(_ anchor: String) {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
  }
}

struct GeneralSettings: View {
  @ObservedObject var model: GeneralModel
  @AppStorage("profileHotkeys") private var profileHotkeys = true // read by the tap (Tap.swift)
  private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

  var onCheckForUpdates: () -> Void = {}

  // Two columns: the app's own settings, and what it sees of Chrome and the extension.
  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      Form {
        Section {
          Picker("Browser", selection: Binding(get: { model.browser }, set: model.setBrowser)) {
            ForEach(Browser.allCases) { Text($0.name).tag($0) }
          }
          Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
          Toggle("Profile hotkeys ⌃⌥← → and ⌃⌥1–9", isOn: $profileHotkeys)
          LabeledContent("Default browser") {
            if model.isDefaultBrowser { Text("Monochrome").foregroundStyle(.secondary) } else { Button("Make Default…", action: model.makeDefault) }
          }
          LabeledContent("Accessibility") {
            if model.accessibility {
              Text("Allowed").foregroundStyle(.secondary)
            } else {
              Button("Open Settings…") { GeneralModel.openPrivacyPane("Privacy_Accessibility") }
            }
          }
          LabeledContent("Version " + model.version) { Button("Check for Updates…", action: onCheckForUpdates) }
        } header: {
          Text("Monochrome")
        } footer: {
          Text("Browser is the one the shortcuts, panels and links from other apps work with. Accessibility is how Monochrome sees ⌃Tab and the other shortcuts, and reads Chrome's Profiles menu. Turn off the profile hotkeys if a window manager such as Rectangle uses those keys.")
        }
      }
      Form {
        Section {
          if model.connected.isEmpty {
            Text("No profile has connected").foregroundStyle(.secondary)
          } else {
            ForEach(model.connected) { profile in
              HStack(spacing: 8) {
                Image(nsImage: profile.appIcon).resizable().frame(width: 18, height: 18).help(profile.browser)
                ProfileAvatar(name: profile.name, size: 18)
                Text(profile.name).foregroundStyle(.secondary)
              }
            }
          }
          HStack {
            Button(model.browser == .safari ? "Safari Extension Settings…" : "Install Extension…", action: model.installExtension)
            if model.browserWarning != nil { Button("Relaunch Chrome…", action: model.relaunchChrome) }
          }
        } header: {
          HStack(spacing: 4) {
            Text("Browser Profiles")
            if let warning = model.browserWarning {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .help(warning)
                .accessibilityLabel(warning)
            }
          }
        } footer: {
          if model.browser == .safari {
            Text("The Safari profiles whose extension is talking to the app. Turn Monochrome on in Safari's Extensions settings and allow it on every website.")
          } else {
            Text("The profiles whose extension is talking to the app. Install Extension… has the folder to drag onto chrome://extensions, once per profile.")
          }
        }
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .onReceive(timer) { _ in model.refresh() }
  }
}

// Install the extension: a small floating panel with the copy of the extension inside the app as a
// folder to drag onto chrome://extensions, and the steps. A standard window at a high level, so it stays
// over Chrome while the user turns on Developer mode and drops the folder, in each profile, and so it is a
// key, active window the drag can begin from. The General tab's Install Extension… button and the mini
// browser's bar show it. The folder is dragged by writing its real file URL to the pasteboard (not a copy,
// which Load unpacked needs); the standard key window is what lets that drag begin.
final class InstallExtensionPanel {
  static let shared = InstallExtensionPanel()
  // Built as a directory file URL: a URL from appendingPathComponent wrote no pasteboard types here, so
  // the drag carried nothing a drop target could take.
  static let folder = URL(fileURLWithPath: Bundle.main.resourcePath! + "/extension", isDirectory: true)
  private var window: NSWindow?

  func show() {
    if window == nil { window = make() }
    guard let window, let screen = NSScreen.main else { return }
    let visible = screen.visibleFrame
    if !window.isVisible {
      window.setFrameOrigin(NSPoint(x: visible.maxX - window.frame.width - 24, y: visible.maxY - window.frame.height - 24))
    }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func make() -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Install the Monochrome extension"
    window.level = .floating
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    let content = window.contentView!
    let folder = FolderDragView(url: Self.folder)
    folder.frame = NSRect(x: 20, y: 86, width: 100, height: 96)
    let text = NSTextField(wrappingLabelWithString:
      "1. Open chrome://extensions in the profile.\n2. Turn on Developer mode, top right.\n3. Drag this folder onto the page.\n\nOnce per profile.")
    text.font = .systemFont(ofSize: 13)
    text.frame = NSRect(x: 140, y: 56, width: 260, height: 126)
    let open = NSButton(title: "Open chrome://extensions", target: self, action: #selector(openExtensionsPage))
    open.bezelStyle = .rounded
    open.frame = NSRect(x: 136, y: 16, width: 220, height: 28)
    [folder, text, open].forEach(content.addSubview)
    return window
  }

  @objc private func openExtensionsPage() { Chrome.open([URL(string: "chrome://extensions")!], activate: true) }
}

// The folder icon in the install window, a drag source that puts the folder's real file URL on the
// pasteboard, so Chrome's Load unpacked reads the extension from inside the app bundle, not a copy.
final class FolderDragView: NSView, NSDraggingSource {
  let url: URL
  private let icon = NSImageView()
  private let label = NSTextField(labelWithString: "extension")

  init(url: URL) {
    self.url = url
    super.init(frame: .zero)
    // A puzzle-piece mark with the extension's icon, so it reads as a browser extension being dragged.
    icon.image = Bundle.main.url(forResource: "install-drag-icon", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
      ?? NSImage(contentsOf: url.appendingPathComponent("icons/128.png")) ?? NSWorkspace.shared.icon(forFile: url.path)
    icon.imageScaling = .scaleProportionallyUpOrDown
    label.font = .systemFont(ofSize: 11)
    label.textColor = .secondaryLabelColor
    label.alignment = .center
    addSubview(icon)
    addSubview(label)
    toolTip = url.path
  }

  required init?(coder: NSCoder) { nil }

  // The whole view is the drag handle; without this the image view inside swallows the mouse-down.
  override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

  override func layout() {
    super.layout()
    label.sizeToFit()
    label.frame = NSRect(x: 0, y: 0, width: bounds.width, height: label.frame.height)
    let side = min(bounds.width, bounds.height - label.frame.height - 4)
    icon.frame = NSRect(x: (bounds.width - side) / 2, y: label.frame.height + 4, width: side, height: side)
  }

  // The folder's file URL, the same pasteboard a Finder drag of the folder carries. The helper's event tap
  // is off for the drag (Tap.enable), or the drop never lands.
  override func mouseDown(with event: NSEvent) {
    Tap.shared?.enable(false)
    let item = NSDraggingItem(pasteboardWriter: url as NSURL)
    item.setDraggingFrame(icon.frame, contents: icon.image)
    beginDraggingSession(with: [item], event: event, source: self)
  }

  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
  func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { Tap.shared?.enable(true) }
}

// Routes: the rules as a list, first match first, with the selected one's fields under it. Every
// change is written to routes.json, which the app re-reads as a link arrives.
struct Rule: Identifiable, Equatable {
  enum Destination: String, CaseIterable, Identifiable {
    case mini, front, sameSite, group, app
    var id: String { rawValue }
    var title: String {
      switch self {
      case .mini: "Mini browser"
      case .front: "New tab in the front window"
      case .sameSite: "Tab already on that site"
      case .group: "Tab group"
      case .app: "Another app"
      }
    }
  }

  var id = UUID()
  var host = "", path = "", url = "", from = ""
  var destination = Destination.mini
  var group = "", app = "", profile = ""

  init() {}

  init(json: [String: Any]) {
    let match = json["match"] as? [String: Any] ?? [:]
    host = match["host"] as? String ?? ""
    path = match["path"] as? String ?? ""
    url = match["url"] as? String ?? ""
    from = match["from"] as? String ?? ""
    let to = json["to"] as? [String: Any] ?? [:]
    profile = to["profile"] as? String ?? ""
    if let app = to["app"] as? String { destination = .app; self.app = app }
    else if let group = to["group"] as? String { destination = .group; self.group = group }
    else if to["window"] as? String == "same-site" { destination = .sameSite }
    else if to["window"] as? String == "front" { destination = .front }
  }

  var json: [String: Any] {
    var match: [String: String] = [:]
    if !host.isEmpty { match["host"] = host }
    if !path.isEmpty { match["path"] = path }
    if !url.isEmpty { match["url"] = url }
    if !from.isEmpty { match["from"] = from }
    var to: [String: Any] = [:]
    switch destination {
    case .mini: to["mini"] = true
    case .front: to["window"] = "front"
    case .sameSite: to["window"] = "same-site"
    case .group: to["group"] = group
    case .app: to["app"] = app
    }
    if !profile.isEmpty && destination != .app { to["profile"] = profile }
    return ["match": match, "to": to]
  }

  var matchSummary: String {
    let parts = [host.isEmpty ? nil : host, path.isEmpty ? nil : path, url.isEmpty ? nil : url, from.isEmpty ? nil : "from " + from].compactMap { $0 }
    return parts.isEmpty ? "Every link" : parts.joined(separator: " ")
  }

  var destinationSummary: String {
    let inside: String
    switch destination {
    case .mini: inside = "mini browser"
    case .front: inside = "new tab in the front window"
    case .sameSite: inside = "tab on the same site"
    case .group: inside = "group " + (group.isEmpty ? "…" : group)
    case .app: return "opens in " + (app.isEmpty ? "…" : appName(app))
    }
    return (profile.isEmpty ? "" : profile + ": ") + inside
  }

  static var samples: [Rule] {
    func rule(_ edit: (inout Rule) -> Void) -> Rule { var r = Rule(); edit(&r); return r }
    return [
      rule { $0.host = "atlassian.net"; $0.profile = "Work (acme.com)"; $0.destination = .group; $0.group = "Work" },
      rule { $0.host = "github.com"; $0.destination = .sameSite },
      rule { $0.host = "zoom.us"; $0.path = "/j/*"; $0.destination = .app; $0.app = "us.zoom.xos" },
      rule { $0.url = "https://docs.google.com/document/*"; $0.destination = .front },
      rule { $0.from = "com.tinyspeck.slackmacgap"; $0.destination = .mini },
    ]
  }

  private func appName(_ bundleId: String) -> String {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId).map { FileManager.default.displayName(atPath: $0.path) } ?? bundleId
  }
}

final class RulesModel: ObservableObject {
  @Published var rules: [Rule] = [] { didSet { if rules != oldValue { save() } } }
  @Published var selection: Rule.ID?
  private let persists: Bool

  init() {
    persists = true
    rules = Routes.rawRules().map(Rule.init(json:))
  }

  init(sample: [Rule]) {
    persists = false
    rules = sample
  }

  private func save() {
    if persists { Routes.write(rules.map(\.json)) }
  }

  func add() {
    let rule = Rule()
    rules.append(rule)
    selection = rule.id
  }

  func removeSelected() {
    guard let selection else { return }
    rules.removeAll { $0.id == selection }
    self.selection = rules.last?.id
  }

  var selected: Binding<Rule>? {
    guard let selection, let index = rules.firstIndex(where: { $0.id == selection }) else { return nil }
    return Binding(get: { self.rules[index] }, set: { self.rules[index] = $0 })
  }
}

struct RoutesSettings: View {
  @ObservedObject var model: RulesModel

  var body: some View {
    HStack(spacing: 0) {
      rulesList.frame(width: 280)
      Divider()
      if let rule = model.selected {
        RuleForm(rule: rule)
      } else {
        Text(model.rules.isEmpty ? "Add a rule to send some links elsewhere." : "Select a rule to edit it.")
          .foregroundStyle(.secondary).font(.callout).frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .padding(.top, 8)
  }

  private var rulesList: some View {
    VStack(spacing: 0) {
      List(selection: $model.selection) {
        ForEach(model.rules) { rule in
          VStack(alignment: .leading, spacing: 2) {
            Text(rule.matchSummary).lineLimit(1)
            Text(rule.destinationSummary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
          .padding(.vertical, 2)
          .tag(rule.id)
        }
        .onMove { from, to in model.rules.move(fromOffsets: from, toOffset: to) }
      }
      .scrollContentBackground(.hidden)
      .overlay(alignment: .center) {
        if model.rules.isEmpty {
          Text("Links from other apps\nopen as mini browsers.")
            .multilineTextAlignment(.center).foregroundStyle(.secondary).font(.callout)
        }
      }
      HStack(spacing: 0) {
        Button(action: model.add) { Image(systemName: "plus").frame(width: 24, height: 20) }
        Button(action: model.removeSelected) { Image(systemName: "minus").frame(width: 24, height: 20) }.disabled(model.selection == nil)
        Spacer()
        Text("First match wins").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Show File") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Routes.path)]) }
          .font(.caption)
      }
      .buttonStyle(.borderless)
      .padding(.horizontal, 12)
      .padding(.bottom, 4)
    }
  }
}

private struct RuleForm: View {
  @Binding var rule: Rule

  var body: some View {
    Form {
      Section("Link") {
        TextField("Host", text: $rule.host, prompt: Text("github.com, or *.atlassian.net"))
        TextField("Path", text: $rule.path, prompt: Text("/j/*"))
        TextField("Address", text: $rule.url, prompt: Text("the whole address, with *"))
        LabeledContent("From") {
          HStack(spacing: 6) {
            TextField("", text: $rule.from, prompt: Text("any app")).labelsHidden()
            Menu {
              ForEach(runningApps, id: \.bundleIdentifier) { app in
                Button(app.localizedName ?? app.bundleIdentifier ?? "") { rule.from = app.bundleIdentifier ?? "" }
              }
            } label: { Image(systemName: "chevron.down") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
          }
        }
      }
      Section("Opens") {
        Picker("In profile", selection: $rule.profile) {
          Text("The front one").tag("")
          ForEach(profiles, id: \.self) { Text($0).tag($0) }
        }
        .disabled(rule.destination == .app)
        // Safari has no tab groups: a rule already sending to one keeps it (it opens as a new tab in the
        // front window there), but it is not offered.
        Picker("As", selection: $rule.destination) {
          ForEach(Rule.Destination.allCases.filter { $0 != .group || Browser.current == .chrome || rule.destination == .group }) { Text($0.title).tag($0) }
        }
        if rule.destination == .group {
          TextField("Group", text: $rule.group, prompt: Text("a tab group's title"))
          if Browser.current == .safari { Text("Safari has no tab groups: this opens a new tab in the front window.").font(.caption).foregroundStyle(.secondary) }
        }
        if rule.destination == .app {
          LabeledContent("App") {
            HStack(spacing: 6) {
              TextField("", text: $rule.app, prompt: Text("bundle id")).labelsHidden()
              Menu {
                ForEach(runningApps, id: \.bundleIdentifier) { app in
                  Button(app.localizedName ?? app.bundleIdentifier ?? "") { rule.app = app.bundleIdentifier ?? "" }
                }
              } label: { Image(systemName: "chevron.down") }
              .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
          }
        }
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
  }

  private var runningApps: [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
      .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
  }

  // The names Chrome's Profiles menu shows, when Chrome is running, plus the rule's own if it is not among them.
  private var profiles: [String] {
    var names = Profiles.read().map(\.name)
    if !rule.profile.isEmpty && !names.contains(rule.profile) { names.append(rule.profile) }
    return names
  }
}
