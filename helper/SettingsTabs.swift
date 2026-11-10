// The settings window's six forms (Settings.swift has the window and SettingRow). Each is two columns
// of grouped forms: on the left the feature's main switches, on the right what depends on them, status
// rows or a list. A row that depends on a switch that is off is disabled. A Chrome-only row says Chrome
// and stays visible, since both browsers can be in use at once; the one Safari-only row (Full Disk
// Access) shows only while Safari is in play.
import AppKit
import ServiceManagement
import SwiftUI

// What the forms read from outside the app's defaults: the login item, the default browser, the grants,
// the Dock, and the connected profiles. Refreshed every two seconds while a form is on screen.
final class GeneralModel: ObservableObject {
  @Published var launchAtLogin = false
  @Published var isDefaultBrowser = false
  @Published var accessibility = false
  @Published var fullDiskAccess = false
  @Published var dockTile = false
  @Published var browserWarning: String? // shown as a triangle by the Extension and Browser Profiles headers
  @Published var browser = Browser.current
  @Published var connected: [ConnectedProfile] = []
  let profiles: () -> [ConnectedProfile]
  let demo: Bool
  let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
  private var dockReadAt = Date.distantPast

  init(profiles: @escaping () -> [ConnectedProfile], demo: Bool = false) {
    self.profiles = profiles
    self.demo = demo
    if demo { launchAtLogin = true; isDefaultBrowser = true; accessibility = true; dockTile = true }
    refresh()
  }

  var safariInPlay: Bool { browser == .safari || connected.contains { $0.browser == Chrome.safari.name } }

  func refresh() {
    browser = Browser.current
    connected = profiles()
    guard !demo else { return }
    launchAtLogin = SMAppService.mainApp.status == .enabled
    accessibility = AXIsProcessTrusted()
    isDefaultBrowser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) == Bundle.main.bundleURL
    browserWarning = browser == .chrome && Chrome.runningWithFlags() == false
      ? "Chrome is running without its launch flags. Quit it (⌘Q) and open it from the Dock." : nil
    // Safari's history is behind Full Disk Access: readable or not.
    fullDiskAccess = SafariHistory.databaseURL(profile: "").flatMap { try? FileHandle(forReadingFrom: $0) }.map { try? $0.close(); return true } ?? false
    // The Dock's preferences are read through `defaults`, so not on every refresh.
    if Date().timeIntervalSince(dockReadAt) > 10 {
      dockReadAt = Date()
      dockTile = Install.dockHasTile(path: Bundle.main.bundleURL.path)
    }
  }

  func setLaunchAtLogin(_ on: Bool) {
    guard !demo else { launchAtLogin = on; return }
    do {
      if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    } catch {
      log.error("login item: \(error.localizedDescription, privacy: .public)")
    }
    // Registered once per app location (Install.atLaunch), so the choice holds at the next launch.
    UserDefaults.standard.set(Bundle.main.bundleURL.path, forKey: "loginItemFor")
    launchAtLogin = SMAppService.mainApp.status == .enabled
  }

  func setBrowser(_ browser: Browser) {
    Browser.current = browser
    // Safari's App Shortcuts, as the app writes them at launch; Safari applies them when it next starts.
    if browser == .safari && !Install.portable && !demo { SafariShortcuts.write() }
    refresh()
  }

  // The App Shortcuts rewritten after a Settings → Tabs switch; the browser applies them when it restarts.
  func applyShortcuts() {
    guard !demo && !Install.portable else { return }
    Install.setChromeShortcuts()
    if Browser.current == .safari { SafariShortcuts.write() }
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
    guard !demo else { return }
    Install.makeDefaultBrowser { [weak self] in self?.refresh() }
  }

  func addDockTile() {
    guard !demo else { return }
    Install.placeDockTile(path: Bundle.main.bundleURL.path)
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.dockReadAt = .distantPast; self?.refresh() }
  }

  func openExtensionShortcuts() { Chrome.open([URL(string: "chrome://extensions/shortcuts")!], activate: true) }

  static func openPrivacyPane(_ anchor: String) {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
  }
}

// Two grouped forms side by side, the left one the feature's main switches.
private struct Columns<Left: View, Right: View>: View {
  @ViewBuilder var left: () -> Left
  @ViewBuilder var right: () -> Right

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      Form { left() }
      Form { right() }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
  }
}

private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

// A status row: the state in secondary text, or the button that fixes it.
private struct StatusRow: View {
  let title: String
  var detail: String?
  var symbol: String?
  let ok: Bool
  let okText: String
  let button: String
  let action: () -> Void

  var body: some View {
    SettingRow(title, detail: detail, symbol: symbol) {
      if ok { Text(okText).foregroundStyle(.secondary) } else { Button(button, action: action) }
    }
  }
}

// A section title with the browser warning's triangle beside it, its text on hover.
private struct WarningHeader: View {
  let title: String
  let warning: String?

  var body: some View {
    HStack(spacing: 4) {
      Text(title)
      if let warning {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.yellow)
          .help(warning)
          .accessibilityLabel(warning)
      }
    }
  }
}

// MARK: General

struct GeneralSettings: View {
  @ObservedObject var model: GeneralModel
  let updates: (get: () -> Bool, set: (Bool) -> Void)
  var onCheckForUpdates: () -> Void
  @State private var automatic = true

  var body: some View {
    Columns {
      Section("Monochrome") {
        SettingToggle("Open at login", detail: "Monochrome starts with the Mac", symbol: "power",
                      isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
        SettingToggle("Check for updates automatically", detail: "Once a day, from the appcast on GitHub", symbol: "arrow.triangle.2.circlepath",
                      isOn: Binding(get: { automatic }, set: { automatic = $0; updates.set($0) }))
        SettingRow("Version " + model.version, symbol: "info.circle") { Button("Check for Updates…", action: onCheckForUpdates) }
      }
    } right: {
      Section("macOS") {
        StatusRow(title: "Default browser", detail: "Links from other apps reach Monochrome first", symbol: "link",
                  ok: model.isDefaultBrowser, okText: "Monochrome", button: "Make Default…", action: model.makeDefault)
        StatusRow(title: "Accessibility", detail: "For ⌃Tab, ⌥⌘-click, ⌘L, ⌘T and the profile hotkeys", symbol: "accessibility",
                  ok: model.accessibility, okText: "Allowed", button: "Open Settings…") { GeneralModel.openPrivacyPane("Privacy_Accessibility") }
      }
    }
    .onAppear { automatic = updates.get() }
    .onReceive(refreshTimer) { _ in model.refresh() }
  }
}

// MARK: Browser

struct BrowserSettings: View {
  @ObservedObject var model: GeneralModel
  @ObservedObject private var prefs = PrefsObserver.shared

  var body: some View {
    Columns {
      Section("Browser") {
        SettingRow("Browser", detail: "Where links from other apps open", symbol: "globe") {
          Picker("Browser", selection: Binding(get: { model.browser }, set: model.setBrowser)) {
            ForEach(Browser.allCases) { Text($0.name).tag($0) }
          }
          .labelsHidden().fixedSize()
        }
        SettingToggle("Open Chrome with Monochrome", detail: "So Chrome starts at login with its launch flags", symbol: "arrow.up.forward.app",
                      isOn: Prefs.binding(.openBrowserAtLaunch))
        SettingToggle("Address bar opens history matches", detail: "Chrome launch flag; applies when Chrome starts from the Dock", symbol: "clock.arrow.circlepath",
                      isOn: Prefs.binding(.launchFlags))
        StatusRow(title: "Dock tile", detail: "Takes Chrome's tile and starts Chrome with the flags", symbol: "dock.rectangle",
                  ok: model.dockTile, okText: "In the Dock", button: "Add to Dock", action: model.addDockTile)
      }
    } right: {
      Section {
        SettingRow(model.browser == .safari ? "Safari extension" : "Extension", detail: "Connects each browser profile to Monochrome",
                   symbol: "puzzlepiece.extension") {
          Button(model.browser == .safari ? "Extension Settings…" : "Install Extension…", action: model.installExtension)
        }
        if model.browser == .chrome {
          SettingRow("Extension shortcuts", detail: "Chrome's own page for the extension's keys", symbol: "keyboard") {
            Button("Open…", action: model.openExtensionShortcuts)
          }
        }
        if model.browserWarning != nil {
          SettingRow("Relaunch Chrome", detail: "Chrome is running without Monochrome's flags", symbol: "arrow.clockwise") {
            Button("Relaunch…", action: model.relaunchChrome)
          }
        }
      } header: {
        WarningHeader(title: "Extension", warning: model.browserWarning)
      }
    }
    .onReceive(refreshTimer) { _ in model.refresh() }
  }
}

// MARK: Tabs

struct TabsSettings: View {
  @ObservedObject var model: GeneralModel
  @ObservedObject private var prefs = PrefsObserver.shared
  @State private var group = Prefs.lockedGroup
  @FocusState private var editingGroup: Bool

  var body: some View {
    Columns {
      Section("Locked Tabs") {
        SettingToggle("Locked tabs come back when closed", detail: "Pinned tabs reopen at their locked address; ⌃R resets one", symbol: "lock",
                      isOn: Prefs.binding(.lockedTabs))
        SettingRow("Locked group", detail: "Tabs in a Chrome tab group with this title lock too", symbol: "list.bullet.rectangle") {
          TextField("Locked group", text: $group, prompt: Text("none"))
            .labelsHidden().frame(width: 110).focused($editingGroup)
            .onSubmit(saveGroup)
            .onChange(of: editingGroup) { if !$0 { saveGroup() } }
        }
        .disabled(!Prefs.lockedTabs)
        SettingToggle("New tabs open at the top", detail: "Directly under the locked tabs", symbol: "arrow.up.to.line", isOn: Prefs.binding(.newTabsAtTop))
      }
      Section("App Shortcuts") {
        SettingToggle("Collapse the tab sidebar", keys: "⌘S", detail: "Save Page As moves to ⇧⌘S; applies when the browser restarts", symbol: "sidebar.left",
                      isOn: Prefs.binding(.shortcutSidebar, then: model.applyShortcuts))
        SettingToggle("Next and previous tab", keys: "⌥⌘↓, ⌥⌘↑", detail: "Steps down and up the tab list, after a browser restart", symbol: "arrow.up.arrow.down",
                      isOn: Prefs.binding(.shortcutTabs, then: model.applyShortcuts))
      }
    } right: {
      Section("Switcher") {
        SettingToggle("⌃Tab goes to the last used tab", detail: "By recent use in this window; off leaves the browser's order", symbol: "arrow.triangle.swap",
                      isOn: Prefs.binding(.switcher))
        Group {
          SettingToggle("Switcher panel", detail: "Hold ⌃ to pick from recent tabs; release to go", symbol: "square.grid.2x2", isOn: Prefs.binding(.switcherPanel))
          Group {
            SettingToggle("Thumbnails", detail: "A picture of each tab, kept in memory only", symbol: "photo.on.rectangle", isOn: Prefs.binding(.thumbnails))
            SettingRow("Panel appears after", detail: "A quicker tap switches without the panel", symbol: "timer") {
              Picker("Panel appears after", selection: Binding(get: { Prefs.switcherDelay }, set: { Prefs.set(.switcherDelay, $0) })) {
                ForEach([0.1, 0.15, 0.3, 0.5], id: \.self) { Text("\($0.formatted()) s").tag($0) }
              }
              .labelsHidden().fixedSize()
            }
            SettingRow("Tabs shown", detail: "Fewer on a narrow screen", symbol: "rectangle.split.3x1") {
              Picker("Tabs shown", selection: Binding(get: { Prefs.switcherCount }, set: { Prefs.set(.switcherCount, $0) })) {
                ForEach(3...7, id: \.self) { Text("\($0)").tag($0) }
              }
              .labelsHidden().fixedSize()
            }
          }
          .disabled(!Prefs.switcherPanel)
        }
        .disabled(!Prefs.switcher)
      }
    }
  }

  private func saveGroup() {
    let title = group.trimmingCharacters(in: .whitespaces)
    if title != Prefs.lockedGroup { Prefs.set(.lockedGroup, title) }
  }
}

// MARK: Mini Browsers

struct MiniBrowserSettings: View {
  @ObservedObject private var prefs = PrefsObserver.shared
  private static let idle = [(0, "Never"), (1, "1 hour"), (12, "12 hours"), (24, "1 day"), (168, "1 week")]

  var body: some View {
    Columns {
      Section("Mini Browsers") {
        SettingToggle("New mini browser", keys: "⌥⇧N", detail: "From any app: a small window with a search box", symbol: "plus.rectangle.on.rectangle", isOn: Prefs.binding(.miniHotkey))
        SettingToggle("⌥⌘-click opens a mini browser", detail: "On any page in the browser", symbol: "cursorarrow.click", isOn: Prefs.binding(.miniClick))
        SettingToggle("Peek browsers from locked tabs", detail: "A link from a locked tab opens over the window, shaded", symbol: "eye", isOn: Prefs.binding(.peek))
      }
    } right: {
      Section("Opening and Closing") {
        SettingRow("Links from other apps", detail: "Open this way when no Router rule claims them", symbol: "arrow.up.right.square") {
          Picker("Links from other apps open as", selection: Binding(get: { Prefs.routeDefault }, set: { Prefs.set(.routeDefault, $0.rawValue) })) {
            ForEach(RouteDefault.allCases) { Text($0.title).tag($0) }
          }
          .labelsHidden().fixedSize()
        }
        SettingRow("Close when unused for", detail: "A mini browser left unfocused closes itself", symbol: "moon.zzz") {
          Picker("Close when unused for", selection: Binding(get: { Prefs.miniIdleHours }, set: { Prefs.set(.miniIdleHours, $0) })) {
            ForEach(Self.idle, id: \.0) { Text($0.1).tag($0.0) }
          }
          .labelsHidden().fixedSize()
        }
      }
    }
  }
}

// MARK: Command Bar

struct CommandBarSettings: View {
  @ObservedObject var model: GeneralModel
  @ObservedObject private var prefs = PrefsObserver.shared

  var body: some View {
    Columns {
      Section("Command Bar") {
        SettingToggle("⌘L edits the front tab's address", detail: "In the command bar over the window; ⌥Return opens a new tab", symbol: "command",
                      isOn: Prefs.binding(.omniboxL))
        SettingToggle("⌘T opens a new tab", detail: "From the command bar, with the most used sites listed", symbol: "plus.square",
                      isOn: Prefs.binding(.omniboxT))
      }
    } right: {
      Section("Suggestions") {
        SettingToggle("Google suggestions", detail: "What is typed goes to Google as it is typed", symbol: "text.magnifyingglass", isOn: Prefs.binding(.omniboxSuggestions))
        if model.safariInPlay {
          StatusRow(title: "Full Disk Access", detail: "For Safari's history and bookmarks", symbol: "internaldrive", ok: model.fullDiskAccess, okText: "Allowed",
                    button: "Open Settings…") { GeneralModel.openPrivacyPane("Privacy_AllFiles") }
        }
      }
    }
    .onReceive(refreshTimer) { _ in model.refresh() }
  }
}

// MARK: Player

struct PlayerSettings: View {
  @ObservedObject private var prefs = PrefsObserver.shared
  // The sites music.js runs on (manifest.json's content_scripts).
  static let sites = ["Spotify", "YouTube Music", "SoundCloud", "Apple Music", "Tidal", "Bandcamp", "Pandora", "Amazon Music", "Deezer"]

  var body: some View {
    Columns {
      Section("Mini Player") {
        SettingToggle("Mini player on the tab sidebar", detail: "Artwork, title and controls while a music tab plays behind", symbol: "play.rectangle",
                      isOn: Prefs.binding(.player))
        SettingToggle("Stop the browser's pop-out player", detail: "On the listed sites, when their tab is left", symbol: "pip.exit",
                      isOn: Prefs.binding(.playerStopPopout))
          .disabled(!Prefs.player)
      }
    } right: {
      Section("Sites") {
        // Two columns, so the nine fit beside the switches.
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
          ForEach(0..<5) { row in
            GridRow {
              ForEach([row, row + 5].filter { $0 < Self.sites.count }, id: \.self) { Text(Self.sites[$0]).foregroundStyle(.secondary) }
            }
          }
        }
        .padding(.vertical, 2)
      }
    }
  }
}

// MARK: Profiles

struct ProfilesSettings: View {
  @ObservedObject var model: GeneralModel

  var body: some View {
    Columns {
      Section {
        if model.connected.isEmpty {
          Text("No profile has connected. Install the extension on Browser.").foregroundStyle(.secondary)
        } else {
          ForEach(model.connected) { profile in
            HStack(spacing: 8) {
              Image(nsImage: profile.appIcon).resizable().frame(width: 18, height: 18).help(profile.browser)
              ProfileAvatar(name: profile.name, size: 18)
              Text(profile.name).foregroundStyle(.secondary)
            }
          }
        }
      } header: {
        WarningHeader(title: "Browser Profiles", warning: model.browserWarning)
      }
    } right: {
      Section("Profile Keys") {
        SettingToggle("Step through profiles", keys: "⌃⌥→, ⌃⌥←", detail: "Off if a window manager uses these keys", symbol: "arrow.left.arrow.right",
                      isOn: Prefs.binding(.profileArrows))
        SettingToggle("Profile by number", keys: "⌃⌥1 to ⌃⌥9", detail: "By place in the browser's profile menu", symbol: "number",
                      isOn: Prefs.binding(.profileDigits))
        SettingToggle("Profile HUD", detail: "Shows the profiles for 1.2 seconds on a switch", symbol: "person.crop.circle",
                      isOn: Prefs.binding(.profileHUD))
      }
    }
    .onReceive(refreshTimer) { _ in model.refresh() }
  }
}
