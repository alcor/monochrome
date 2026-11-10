import AppKit
import SwiftUI

// The Router tab: the rules as a list, first match first, with the selected one's fields beside it.
// Every change is written to routes.json, which the app re-reads as a link arrives.
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
  @ObservedObject private var prefs = PrefsObserver.shared

  private var defaultDestination: String {
    switch Prefs.routeDefault {
    case .mini: "mini browsers"
    case .front: "new tabs in the front window"
    case .sameSite: "a tab already on that site"
    }
  }

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
          // What happens to a link no rule claims: Settings → Mini Browsers → Links from other apps open as.
          Text("Links from other apps open\nas \(defaultDestination).")
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
