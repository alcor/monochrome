// Chrome profiles, from Chrome's own Profiles menu read over Accessibility: every profile by name, a
// check on the one the front window belongs to, and pressing an item is Chrome's own switch, which
// brings that profile's window forward or opens one. Nothing is read from Chrome's files, and no
// extension is needed for this part. ⌃⌥→ and ⌃⌥← cycle, ⌃⌥1 to 9 go direct; a glass HUD of letter
// avatars shows for a moment with the chosen one marked. The menu carries no images, so avatars are
// the name's initial on a color hashed from the name.
//
// On Safari the list comes from File → New Window's per-profile items instead (SafariProfiles in
// Safari.swift), and a switch goes through the app (onSafari): it brings forward a window of a profile
// whose extension is connected, or presses that profile's New Window item.
import AppKit
import SwiftUI

struct Profile {
  let name: String
  let item: AXUIElement
  let current: Bool
}

final class ProfilesModel: ObservableObject {
  @Published var profiles: [Profile] = []
  @Published var index = 0
  @Published var shown = false
}

final class Profiles {
  static let avatar: CGFloat = 64, gap: CGFloat = 20, pad: CGFloat = 24, labelHeight: CGFloat = 20, radius: CGFloat = 30
  static let shadowRoom: CGFloat = 70, linger = 1.2

  private let model = ProfilesModel()
  private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                              backing: .buffered, defer: false)
  private let hosting: NSHostingView<ProfilesView>
  private var hideTimer: Timer?
  var onSafari: (Profile) -> Void = { AXUIElementPerformAction($0.item, kAXPressAction as CFString) }

  init() {
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    hosting = NSHostingView(rootView: ProfilesView(model: model))
    panel.contentView = hosting
  }

  // The names alone, from every running Chrome, for reading window titles; the menus are walked at
  // most every five seconds.
  private static var cachedNames: [String] = [], namesRead = Date.distantPast
  static func names() -> [String] {
    if Date().timeIntervalSince(namesRead) > 5 {
      cachedNames = Array(Set(Chrome.runningApps.flatMap { read($0).map(\.name) }))
      namesRead = Date()
    }
    return cachedNames
  }

  // The Profiles menu's items up to its first separator; after that come Edit… and Add Profile….
  static func read(_ chrome: NSRunningApplication? = Chrome.running) -> [Profile] {
    if Browser.current == .safari { return SafariProfiles.read(chrome) }
    guard let chrome else { return [] }
    let app = AXUIElementCreateApplication(chrome.processIdentifier)
    func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
      var value: AnyObject?
      AXUIElementCopyAttributeValue(element, name as CFString, &value)
      return value
    }
    guard let bar = attribute(app, kAXMenuBarAttribute), let menus = attribute(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement],
          let menu = menus.first(where: { attribute($0, kAXTitleAttribute) as? String == "Profiles" }),
          let submenu = (attribute(menu, kAXChildrenAttribute) as? [AXUIElement])?.first,
          let items = attribute(submenu, kAXChildrenAttribute) as? [AXUIElement]
    else { return [] }
    var profiles: [Profile] = []
    for item in items {
      guard let title = attribute(item, kAXTitleAttribute) as? String, !title.isEmpty else { break }
      let mark = attribute(item, kAXMenuItemMarkCharAttribute) as? String ?? ""
      profiles.append(Profile(name: title, item: item, current: !mark.isEmpty))
    }
    return profiles
  }

  func cycle(_ step: Int) {
    let profiles = Self.read()
    guard profiles.count > 1 else { return }
    let current = profiles.firstIndex(where: \.current) ?? 0
    go(to: (current + step + profiles.count) % profiles.count, in: profiles)
  }

  func go(to index: Int, in list: [Profile]? = nil) {
    let profiles = list ?? Self.read()
    guard profiles.indices.contains(index) else { return }
    if Browser.current == .safari { onSafari(profiles[index]) } else { AXUIElementPerformAction(profiles[index].item, kAXPressAction as CFString) }
    show(profiles, index: index)
  }

  private func show(_ profiles: [Profile], index: Int) {
    model.profiles = profiles
    model.index = index
    let card = Self.cardSize(count: profiles.count)
    let size = NSSize(width: card.width + 2 * Self.shadowRoom, height: card.height + 2 * Self.shadowRoom)
    let anchor = Chrome.frontWindowFrame ?? NSScreen.main?.visibleFrame ?? .zero
    hosting.frame = NSRect(origin: .zero, size: size)
    panel.setFrame(NSRect(x: anchor.midX - size.width / 2, y: anchor.midY - size.height / 2, width: size.width, height: size.height), display: true)
    panel.orderFrontRegardless()
    withAnimation(Springs.appear) { model.shown = true }
    hideTimer?.invalidate()
    hideTimer = Timer.scheduledTimer(withTimeInterval: Self.linger, repeats: false) { [weak self] _ in self?.hide() }
  }

  private func hide() {
    withAnimation(Springs.vanish) { model.shown = false }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
      guard let self, !model.shown else { return }
      panel.orderOut(nil)
    }
  }

  static func cardSize(count: Int) -> CGSize {
    CGSize(width: CGFloat(count) * (avatar + 16) + CGFloat(count - 1) * gap + 2 * pad,
           height: avatar + 16 + 6 + labelHeight + 2 * pad)
  }

  // --demo-profiles: the HUD on the real profiles, nothing pressed; with --backdrop, on sample names.
  func demo(sample: Bool = false) {
    let profiles = sample
      ? ["Work (acme.com)", "Personal", "Geist"].enumerated().map { Profile(name: $1, item: AXUIElementCreateSystemWide(), current: $0 == 0) }
      : Self.read()
    guard !profiles.isEmpty else { return FileHandle.standardError.write(Data("no Profiles menu: is Chrome running with more than one profile?\n".utf8)) }
    show(profiles, index: sample ? 1 : profiles.firstIndex(where: \.current) ?? 0)
    hideTimer?.invalidate()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
      let f = panel.frame, top = (NSScreen.screens.first?.frame.height ?? 0) - f.maxY
      FileHandle.standardError.write(Data("panel \(Int(f.minX)),\(Int(top)),\(Int(f.width)),\(Int(f.height))\n".utf8))
    }
  }
}

struct ProfilesView: View {
  @ObservedObject var model: ProfilesModel
  @Environment(\.colorScheme) private var colorScheme
  private var isDark: Bool { colorScheme == .dark }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Profiles.radius, style: .continuous)
    let size = Profiles.cardSize(count: max(model.profiles.count, 1))
    ZStack {
      ZStack {
        if #available(macOS 26, *) {
          shape.fill(.clear).glassEffect(.clear, in: shape)
        } else {
          shape.fill(.ultraThinMaterial)
        }
        tint(shape)
        shape.strokeBorder(.white.opacity(isDark ? 0.14 : 0.3), lineWidth: 1.25)
      }
      .frame(width: size.width, height: size.height)
      .clipShape(shape)
      .shadow(color: .black.opacity(0.28), radius: 36, y: 22)
      .shadow(color: .black.opacity(0.12), radius: 6, y: 2)

      HStack(spacing: Profiles.gap) {
        ForEach(Array(model.profiles.enumerated()), id: \.offset) { i, profile in
          ProfileCard(profile: profile, selected: i == model.index)
        }
      }
      .frame(width: size.width, height: size.height)
    }
    .scaleEffect(model.shown ? 1 : 0.94)
    .opacity(model.shown ? 1 : 0)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder private func tint(_ shape: RoundedRectangle) -> some View {
    if isDark {
      shape.fill(LinearGradient(stops: [.init(color: .black.opacity(0.25), location: 0), .init(color: .black.opacity(0.45), location: 1)],
                                startPoint: .top, endPoint: .bottom))
    } else {
      shape.fill(LinearGradient(stops: [.init(color: .white.opacity(0), location: 0), .init(color: .white.opacity(0.33), location: 0.99)],
                                startPoint: .top, endPoint: .bottom))
      shape.fill(LinearGradient(stops: [.init(color: .white.opacity(0.5), location: 0.0097), .init(color: .white.opacity(0), location: 0.488)],
                                startPoint: UnitPoint(x: 0.58, y: 0), endPoint: UnitPoint(x: 0.42, y: 1)))
    }
  }
}

// A letter avatar on a color from the name, the name under it; the chosen one on the dark fill the
// switcher uses. "Nicholas (jitkoff.com)" shows as Nicholas with the account small beneath.
private struct ProfileCard: View {
  let profile: Profile
  let selected: Bool

  var body: some View {
    let well = RoundedRectangle(cornerRadius: 18, style: .continuous)
    let parts = profile.name.split(separator: "(", maxSplits: 1)
    let name = parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? profile.name
    let account = parts.count > 1 ? parts[1].replacingOccurrences(of: ")", with: "") : ""
    VStack(spacing: 6) {
      ZStack {
        Circle().fill(color)
        Text(String(name.prefix(1)).uppercased())
          .font(.system(size: Profiles.avatar * 0.45, weight: .semibold))
          .foregroundStyle(.white)
      }
      .frame(width: Profiles.avatar, height: Profiles.avatar)
      .padding(8)
      .background { if selected { well.fill(.black.opacity(0.5)) } }
      VStack(spacing: 1) {
        Text(name).font(.system(size: 12, weight: .medium)).lineLimit(1)
        if !account.isEmpty { Text(account).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
      }
      .frame(width: Profiles.avatar + 16 + Profiles.gap - 4, height: Profiles.labelHeight)
    }
  }

  // A hue from the name, steady across launches.
  private var color: Color {
    let hash = profile.name.unicodeScalars.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1.value) }
    return Color(hue: Double(abs(hash) % 360) / 360, saturation: 0.55, brightness: 0.75)
  }
}
