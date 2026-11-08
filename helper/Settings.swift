// The settings window, laid out as Quicksilver's: tabs in the toolbar with their icons, grouped forms
// on a sidebar-material backdrop, and a footer under the first tab. General holds the app's own
// switches and what it can see of Chrome; Routes edits the link rules (Routes.swift), written back to
// routes.json as they change. Monochrome has no Dock presence of its own (LSUIElement); while this
// window is on screen it is an app in the Dock with a menu bar, so the window can be found and
// switched to, and back to a background app when the window closes.
import AppKit
import ServiceManagement
import SwiftUI

final class SettingsWindow: NSObject, NSWindowDelegate {
  static let shared = SettingsWindow()
  static let size = NSSize(width: 760, height: 464)
  var connectionsSummary: () -> String = { "" }
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
    var generalView = GeneralSettings(model: GeneralModel(connections: connectionsSummary))
    generalView.onLoadExtension = { [weak self] in self?.tabs?.selectedTabViewItemIndex = 2 }
    let general = NSHostingController(rootView: generalView)
    let rules = sampleRules ? RulesModel(sample: Rule.samples) : RulesModel()
    rulesModel = rules
    let routes = NSHostingController(rootView: RoutesSettings(model: rules))
    let extensionTab = NSHostingController(rootView: ExtensionSettings())
    general.preferredContentSize = Self.size
    routes.preferredContentSize = NSSize(width: Self.size.width, height: 500) // the rules beside the selected one's fields
    extensionTab.preferredContentSize = NSSize(width: Self.size.width, height: 420)
    let tabs = SettingsTabs()
    for (controller, label, symbol) in [(general, "General", "gearshape"), (routes, "Router", "arrow.triangle.branch"),
                                        (extensionTab, "Extension", "puzzlepiece.extension")] as [(NSViewController, String, String)] {
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
final class GeneralModel: ObservableObject {
  @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
  @Published var isDefaultBrowser = false
  @Published var accessibility = AXIsProcessTrusted()
  @Published var chrome = ""
  @Published var extensions = ""
  let connections: () -> String

  init(connections: @escaping () -> String) {
    self.connections = connections
    refresh()
  }

  func refresh() {
    launchAtLogin = SMAppService.mainApp.status == .enabled
    accessibility = AXIsProcessTrusted()
    isDefaultBrowser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) == Bundle.main.bundleURL
    switch Chrome.runningWithFlags() {
    case nil: chrome = "Not running"
    case true?: chrome = "Running with its launch flags"
    case false?: chrome = "Running without its launch flags: quit it and open it from the Dock"
    }
    extensions = connections()
  }

  func setLaunchAtLogin(_ on: Bool) {
    do {
      if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    } catch {
      log.error("login item: \(error.localizedDescription, privacy: .public)")
    }
    launchAtLogin = SMAppService.mainApp.status == .enabled
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
  private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

  var onLoadExtension: () -> Void = {}

  // Two columns: the app's own settings, and what it sees of Chrome and the extension.
  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      Form {
        Section {
          Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
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
        } header: {
          Text("Monochrome")
        } footer: {
          Text("Accessibility is how Monochrome sees ⌃Tab and the other shortcuts, and reads Chrome's Profiles menu.")
        }
      }
      Form {
        Section("Chrome") {
          Text(model.chrome).foregroundStyle(.secondary)
        }
        Section {
          if model.extensions.isEmpty {
            Text("No profile has connected").foregroundStyle(.secondary)
          } else {
            ForEach(model.extensions.components(separatedBy: ", "), id: \.self) { Text($0).foregroundStyle(.secondary) }
          }
          Button("Load in a Profile…", action: onLoadExtension)
        } header: {
          Text("Extension")
        } footer: {
          Text("The profiles whose extension is talking to the app.")
        }
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .onReceive(timer) { _ in model.refresh() }
  }
}

// Extension: the copy of the extension inside the app, for a Load unpacked in each profile. Chrome's
// extensions page takes a folder dropped on it when Developer mode is on, so the folder is a drag
// source here, with the steps beside it. Which profiles have it loaded is on the General tab.
struct ExtensionSettings: View {
  static let folder = Bundle.main.resourceURL!.appendingPathComponent("extension")

  var body: some View {
    Form {
      Section {
        HStack(spacing: 16) {
          FolderDragSource(url: Self.folder).frame(width: 120, height: 96)
          VStack(alignment: .leading, spacing: 8) {
            Text("The extension is inside the app. Chrome loads it from here as an unpacked extension, in each profile:")
            Text("1. Open chrome://extensions in the profile.\n2. Turn on Developer mode, top right.\n3. Drag this folder onto the page.")
          }
          .font(.callout)
        }
        .padding(.vertical, 4)
        LabeledContent("Chrome") {
          Button("Open chrome://extensions") {
            Chrome.open([URL(string: "chrome://extensions")!], activate: true)
            ExtensionDropPanel.shared.show()
          }
        }
        LabeledContent("Folder") { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Self.folder]) } }
      } footer: {
        Text("After an update of the app, click reload on the extension's card in each profile; Chrome does not re-read an unpacked extension on its own. The Chrome Web Store copy updates itself.")
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
  }
}

// A folder icon that starts a file drag, the way the Finder's would: the pasteboard carries the folder's
// URL, which Chrome's extensions page accepts.
struct FolderDragSource: NSViewRepresentable {
  let url: URL

  func makeNSView(context: Context) -> FolderDragView { FolderDragView(url: url) }
  func updateNSView(_ view: FolderDragView, context: Context) {}
}

final class FolderDragView: NSView, NSDraggingSource {
  let url: URL
  var onDropped: () -> Void = {}
  private let icon = NSImageView()
  private let label = NSTextField(labelWithString: "extension")

  init(url: URL) {
    self.url = url
    super.init(frame: .zero)
    icon.image = NSWorkspace.shared.icon(forFile: url.path)
    icon.imageScaling = .scaleProportionallyUpOrDown
    label.font = .systemFont(ofSize: 11)
    label.textColor = .secondaryLabelColor
    label.alignment = .center
    addSubview(icon)
    addSubview(label)
    toolTip = url.path
  }

  required init?(coder: NSCoder) { nil }

  override func layout() {
    super.layout()
    label.sizeToFit()
    label.frame = NSRect(x: 0, y: 0, width: bounds.width, height: label.frame.height)
    let side = min(bounds.width, bounds.height - label.frame.height - 4)
    icon.frame = NSRect(x: (bounds.width - side) / 2, y: label.frame.height + 4, width: side, height: side)
  }

  override func mouseDown(with event: NSEvent) {
    let item = NSDraggingItem(pasteboardWriter: url as NSURL)
    item.setDraggingFrame(icon.frame, contents: icon.image)
    beginDraggingSession(with: [item], event: event, source: self)
  }

  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

  func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    if operation.contains(.copy) { onDropped() }
  }
}

// After chrome://extensions opens, Chrome is in front and the settings window is behind it, so the folder
// comes along in a small floating panel at the top right of the screen. It closes once the folder has
// been dropped somewhere, or with its close button.
final class ExtensionDropPanel {
  static let shared = ExtensionDropPanel()
  private var panel: NSPanel?

  func show() {
    if panel == nil { panel = make() }
    guard let panel, let screen = NSScreen.main else { return }
    let visible = screen.visibleFrame
    panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 24, y: visible.maxY - panel.frame.height - 24))
    panel.orderFront(nil)
  }

  private func make() -> NSPanel {
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 150),
                        styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
    panel.title = "Monochrome extension"
    panel.level = .floating
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    let content = NSView(frame: panel.contentView!.bounds)
    let folder = FolderDragView(url: ExtensionSettings.folder)
    folder.frame = NSRect(x: 16, y: 20, width: 100, height: 96)
    folder.onDropped = { [weak panel] in panel?.close() }
    let text = NSTextField(wrappingLabelWithString: "Turn on Developer mode, top right of the page, then drag this folder onto the page.")
    text.font = .systemFont(ofSize: 12)
    text.frame = NSRect(x: 132, y: 40, width: 152, height: 76)
    content.addSubview(folder)
    content.addSubview(text)
    panel.contentView = content
    return panel
  }
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
        Picker("As", selection: $rule.destination) {
          ForEach(Rule.Destination.allCases) { Text($0.title).tag($0) }
        }
        if rule.destination == .group { TextField("Group", text: $rule.group, prompt: Text("a tab group's title")) }
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
