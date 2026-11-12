// Sidebar mini player: a small floating panel over the bottom of Chrome's vertical tab sidebar, as
// Arc's is: a card with the track's artwork beside its title and artist, and under it a white bar with
// the site's icon, previous, play/pause, next and a speaker that mutes the music tab. Clicking the track
// or the icon goes to the tab. Hide Player, on the right-click menu, hides it until you've been back to
// that tab. The extension (player.js) sends what to show over the bridge and gets the presses
// back.
//
// Where the sidebar is: the extension sends the focused window's bounds and the sidebar's width; the
// panel sits on the frontmost on-screen Chrome window with the same size (so it follows while you drag)
// or the same corner (while you resize).
//
// A sidebar collapsed to its icon strip (narrower than `compactBelow`) gets the compact player instead: one
// card with the artwork, which goes to the tab, over play/pause; previous, next, mute and Hide Player are
// on its right-click menu.
//
// On Safari the sidebar is found over Accessibility instead (SafariSidebar in Safari.swift): Safari's
// vertical tabs arrive in 27.3, and their AX shape is unmeasured. With an older Safari, or no tab list
// found in the window, the panel stays hidden. Safari cannot mute a tab, so there is no speaker there.
import AppKit

struct Bounds: Decodable { let left, top, width, height: Double }
struct PlayerState: Decodable {
  let show: Bool
  let title, artist, artwork, favicon: String?
  let playing, muted: Bool?
  let sidebar: Double?
  let window: Bounds?
}

// Takes the first click even though the panel never becomes the active window.
final class PlayerButton: NSButton {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
final class ClickArea: NSView {
  var onClick = {}
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) { onClick() }
}

// A rounded shape with a soft shadow, its fill following light and dark: white in light, as in Arc.
final class Card: NSView {
  let radius: CGFloat
  var fill: (Bool) -> NSColor = { $0 ? NSColor(white: 0.18, alpha: 1) : .white }
  init(radius: CGFloat) {
    self.radius = radius
    super.init(frame: .zero)
    wantsLayer = true
  }
  required init?(coder: NSCoder) { fatalError() }
  override var wantsUpdateLayer: Bool { true }
  override func updateLayer() {
    let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    layer?.backgroundColor = fill(dark).cgColor
    layer?.cornerRadius = radius
    layer?.cornerCurve = .continuous
    layer?.borderWidth = 0.5
    layer?.borderColor = NSColor.black.withAlphaComponent(dark ? 0.4 : 0.06).cgColor
    layer?.shadowColor = NSColor.black.cgColor
    layer?.shadowOpacity = dark ? 0.35 : 0.12
    layer?.shadowRadius = 6
    layer?.shadowOffset = CGSize(width: 0, height: -2)
  }
}

final class Player: NSObject, NSMenuDelegate {
  // The track card (56 tall, 40-point artwork) sits `gap` above the 44-point bar, both the sidebar's
  // width less `inset` each side. `margin` is room around both for their shadows.
  static let bar: CGFloat = 44, track: CGFloat = 56, gap: CGFloat = 8, inset: CGFloat = 8, margin: CGFloat = 10
  // The compact player: on a sidebar narrower than this, a card with 28-point artwork over play/pause.
  static let compactBelow: CGFloat = 150, compactInset: CGFloat = 6, compactHeight: CGFloat = 76
  var onAction: (String) -> Void = { _ in }
  let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
  let barView = Card(radius: 12)
  let compactCard = Card(radius: 10)
  let compactArt = NSImageView()
  var compactPlay: PlayerButton!
  let trackCard = Card(radius: 12)
  let art = NSImageView()
  let title = NSTextField(labelWithString: "")
  let artist = NSTextField(labelWithString: "")
  let icon = NSImageView()
  var playButton: PlayerButton!, muteButton: PlayerButton!
  var state: PlayerState?
  var artworkURL: String?, faviconData: String?

  override init() {
    super.init()
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false // the cards draw their own
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    let content = NSView()
    panel.contentView = content
    let menu = NSMenu()
    menu.delegate = self
    content.menu = menu

    art.imageScaling = .scaleProportionallyUpOrDown
    art.wantsLayer = true
    art.layer?.cornerRadius = 6
    art.layer?.cornerCurve = .continuous
    art.layer?.masksToBounds = true
    title.font = .systemFont(ofSize: 13, weight: .semibold)
    artist.font = .systemFont(ofSize: 11)
    artist.textColor = .secondaryLabelColor
    for label in [title, artist] {
      label.lineBreakMode = .byTruncatingTail
      label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) // else long titles widen the panel
    }
    for view in [art, title, artist] { trackCard.addSubview(view) }
    icon.imageScaling = .scaleProportionallyUpOrDown

    playButton = button("pause.fill", "playpause")
    muteButton = button("speaker.wave.3.fill", "mute")
    let controls = NSStackView(views: [icon, button("backward.end.fill", "previoustrack"), playButton, button("forward.end.fill", "nexttrack"), muteButton])
    controls.distribution = .equalSpacing
    controls.alignment = .centerY
    barView.addSubview(controls)
    let iconClick = ClickArea(), trackClick = ClickArea()
    iconClick.onClick = { [weak self] in self?.onAction("focus") }
    trackClick.onClick = iconClick.onClick
    barView.addSubview(iconClick)
    trackCard.addSubview(trackClick)

    for view in [art, title, artist, icon, controls, iconClick, trackClick] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false }
    for view in [trackCard, barView, compactCard] { content.addSubview(view) }

    compactPlay = button("pause.fill", "playpause")
    compactArt.imageScaling = .scaleProportionallyUpOrDown
    compactArt.wantsLayer = true
    compactArt.layer?.cornerRadius = 6
    compactArt.layer?.cornerCurve = .continuous
    compactArt.layer?.masksToBounds = true
    let compactClick = ClickArea()
    compactClick.onClick = iconClick.onClick
    for view in [compactArt, compactClick, compactPlay] as [NSView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      compactCard.addSubview(view)
    }
    NSLayoutConstraint.activate([
      compactArt.centerXAnchor.constraint(equalTo: compactCard.centerXAnchor),
      compactArt.topAnchor.constraint(equalTo: compactCard.topAnchor, constant: 8),
      compactArt.widthAnchor.constraint(equalToConstant: 28),
      compactArt.heightAnchor.constraint(equalToConstant: 28),
      compactClick.leadingAnchor.constraint(equalTo: compactCard.leadingAnchor),
      compactClick.trailingAnchor.constraint(equalTo: compactCard.trailingAnchor),
      compactClick.topAnchor.constraint(equalTo: compactCard.topAnchor),
      compactClick.bottomAnchor.constraint(equalTo: compactArt.bottomAnchor, constant: 4),
      compactPlay.centerXAnchor.constraint(equalTo: compactCard.centerXAnchor),
      compactPlay.bottomAnchor.constraint(equalTo: compactCard.bottomAnchor, constant: -10),
    ])
    NSLayoutConstraint.activate([
      controls.leadingAnchor.constraint(equalTo: barView.leadingAnchor, constant: 14),
      controls.trailingAnchor.constraint(equalTo: barView.trailingAnchor, constant: -14),
      controls.centerYAnchor.constraint(equalTo: barView.centerYAnchor),
      icon.widthAnchor.constraint(equalToConstant: 22),
      icon.heightAnchor.constraint(equalToConstant: 22),
      iconClick.leadingAnchor.constraint(equalTo: barView.leadingAnchor),
      iconClick.topAnchor.constraint(equalTo: barView.topAnchor),
      iconClick.bottomAnchor.constraint(equalTo: barView.bottomAnchor),
      iconClick.trailingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
      art.leadingAnchor.constraint(equalTo: trackCard.leadingAnchor, constant: 8),
      art.centerYAnchor.constraint(equalTo: trackCard.centerYAnchor),
      art.widthAnchor.constraint(equalToConstant: 40),
      art.heightAnchor.constraint(equalToConstant: 40),
      title.leadingAnchor.constraint(equalTo: art.trailingAnchor, constant: 10),
      title.trailingAnchor.constraint(equalTo: trackCard.trailingAnchor, constant: -10),
      title.bottomAnchor.constraint(equalTo: trackCard.centerYAnchor, constant: 1),
      artist.leadingAnchor.constraint(equalTo: title.leadingAnchor),
      artist.trailingAnchor.constraint(equalTo: title.trailingAnchor),
      artist.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
      trackClick.leadingAnchor.constraint(equalTo: trackCard.leadingAnchor),
      trackClick.trailingAnchor.constraint(equalTo: trackCard.trailingAnchor),
      trackClick.topAnchor.constraint(equalTo: trackCard.topAnchor),
      trackClick.bottomAnchor.constraint(equalTo: trackCard.bottomAnchor),
    ])
  }

  func button(_ symbol: String, _ action: String) -> PlayerButton {
    let b = PlayerButton(title: "", target: self, action: #selector(pressed))
    b.identifier = NSUserInterfaceItemIdentifier(action)
    b.isBordered = false
    b.setButtonType(.momentaryChange)
    set(b, symbol)
    b.contentTintColor = .secondaryLabelColor
    return b
  }

  func set(_ button: PlayerButton, _ symbol: String) {
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: button.identifier?.rawValue)?
      .withSymbolConfiguration(.init(pointSize: 17, weight: .semibold))
  }

  @objc func pressed(_ sender: PlayerButton) { onAction(sender.identifier!.rawValue) }
  @objc func menuAction(_ item: NSMenuItem) { onAction(item.representedObject as? String ?? "") }

  // The right-click menu: the compact player's missing buttons first, then Hide Player.
  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    var items: [(String, String)] = []
    if compactCard.isHidden == false {
      items = [("Previous", "previoustrack"), ("Next", "nexttrack")]
      if let muted = state?.muted { items.append((muted ? "Unmute" : "Mute", "mute")) }
    }
    for (title, action) in items + [("Hide Player", "close")] {
      if action == "close" && !items.isEmpty { menu.addItem(.separator()) }
      let item = menu.addItem(withTitle: title, action: #selector(menuAction), keyEquivalent: "")
      item.target = self
      item.representedObject = action
    }
  }

  func apply(_ s: PlayerState?) {
    state = s
    guard let s else { return layout() }
    set(playButton, s.playing == true ? "pause.fill" : "play.fill")
    set(compactPlay, s.playing == true ? "pause.fill" : "play.fill")
    set(muteButton, s.muted == true ? "speaker.slash.fill" : "speaker.wave.3.fill")
    muteButton.isHidden = s.muted == nil
    title.stringValue = s.title ?? ""
    artist.stringValue = s.artist ?? ""
    if s.favicon != faviconData || icon.image == nil {
      faviconData = s.favicon
      icon.image = s.favicon.flatMap(Self.image) ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
    }
    if s.artwork != artworkURL {
      artworkURL = s.artwork
      art.image = nil
      compactArt.image = nil
      // Only web and inline images: the page picks this address, and this app isn't held to the page's limits.
      if let url = s.artwork.flatMap(URL.init(string:)), ["https", "data"].contains(url.scheme) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
          DispatchQueue.main.async {
            if self.artworkURL == s.artwork, let data { self.art.image = NSImage(data: data); self.compactArt.image = self.art.image }
          }
        }.resume()
      }
    }
    layout()
  }

  static func image(_ dataURL: String) -> NSImage? {
    guard dataURL.hasPrefix("data:"), let comma = dataURL.firstIndex(of: ",") else { return nil }
    return Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])).flatMap(NSImage.init(data:))
  }

  var wantsFollowing: Bool { state?.show == true }
  private var onScreen: [Chrome.Window] = []
  private var front = false

  // Each tick of the window tracker: Chrome's windows on screen and whether Chrome is in front.
  func follow(_ onScreen: [Chrome.Window], front: Bool) {
    self.onScreen = onScreen
    self.front = front
    layout()
  }

  // Keeps the panel on the bottom of the sidebar; hides it when Chrome isn't the app in front.
  private func layout() {
    guard let s = state, s.show, let w = s.window, front, let primary = NSScreen.screens.first,
          let window = Chrome.match(CGRect(x: w.left, y: w.top, width: w.width, height: w.height), in: onScreen)
    else { return panel.orderOut(nil) } // minimized, on another Space, or nothing to show
    // Chrome: the window's left edge and the sidebar width the extension measured. Safari: the tab
    // list found over Accessibility.
    let column: CGRect
    if Browser.active == .safari {
      guard let found = SafariSidebar.frame(for: window) else { return panel.orderOut(nil) }
      column = found
    } else {
      guard let sidebar = s.sidebar else { return panel.orderOut(nil) }
      column = CGRect(x: window.frame.minX, y: window.frame.minY, width: sidebar, height: window.frame.height)
    }
    // Window bounds count down from the top of the main screen; AppKit counts up from its bottom. The
    // panel reaches `margin` past the cards on every side, for their shadows.
    let compact = column.width < Self.compactBelow
    let inset = compact ? Self.compactInset : Self.inset
    let width = column.width - 2 * inset
    let height = compact ? Self.compactHeight : Self.bar + Self.gap + Self.track
    let m = Self.margin
    let rect = NSRect(x: column.minX + inset - m, y: primary.frame.height - column.maxY + inset - m,
                      width: width + 2 * m, height: height + 2 * m)
    barView.frame = NSRect(x: m, y: m, width: width, height: Self.bar)
    trackCard.frame = NSRect(x: m, y: m + Self.bar + Self.gap, width: width, height: Self.track)
    compactCard.frame = NSRect(x: m, y: m, width: width, height: height)
    barView.isHidden = compact
    trackCard.isHidden = compact
    compactCard.isHidden = !compact
    if compactArt.image == nil { compactArt.image = art.image ?? icon.image }
    if panel.frame != rect { panel.setFrame(rect, display: true) }
    if !panel.isVisible { panel.orderFrontRegardless() }
  }
}
