// The ⌃Tab switcher: a Liquid Glass panel over Chrome's front window with that window's five most
// recently used tabs, most recent first, a thumbnail each with its favicon, like ⌘Tab for tabs. ⌃Tab moves the highlight on,
// ⌃⇧Tab back, Esc cancels, and letting go of Control activates the highlighted tab. A quick ⌃Tab that
// lets go before the panel would appear just switches, so the panel only shows up when you hold.
//
// The extension owns the list (it has the events) and sends it over the bridge whenever it changes,
// with a thumbnail per tab captured the last time that tab was in front; this side only draws. Nothing
// switches live while you walk, only the pick does.
//
// The layout: a row of thumbnails, each with its favicon and title underneath, every
// one on a well of regular glass, the highlighted one tinted. The surface follows Quicksilver's: a
// borderless non-activating panel with no shadow of its own, larger than the card so SwiftUI's shadows
// have room, and the card as clear glass on a continuous rounded shape with Quicksilver's tint, its
// hairline, and two shadows, with the wells' regular glass inside it.
import AppKit
import SwiftUI

struct TabInfo {
  let id: Int, windowId: Int, title: String
  let favicon: NSImage?
}

final class SwitcherModel: ObservableObject {
  @Published var walk: [TabInfo] = []
  @Published var thumbs: [Int: NSImage] = [:]
  @Published var index = 0
  @Published var shown = false // the card's appearance, sprung in and faded out
}

// The profile HUD springs in and fades out; the switcher shows and hides at once, and its highlight is
// ⌘Tab's, a dark fill that is simply behind the selected thumbnail.
enum Springs {
  static let appear = Animation.spring(duration: 0.35, bounce: 0.25)
  static let vanish = Animation.easeOut(duration: 0.12)
}

// A spring for the panel's own position, since AppKit's window animator has no spring: a critically
// damped-ish second-order step at 60 Hz toward the target origin.
final class FrameSpring {
  private var timer: Timer?
  private var velocity = CGPoint.zero
  private var target = NSPoint.zero
  func move(_ panel: NSPanel, to origin: NSPoint) {
    target = origin
    velocity = .zero
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self, weak panel] timer in
      guard let self, let panel else { return timer.invalidate() }
      let stiffness: CGFloat = 220, damping: CGFloat = 24, dt: CGFloat = 1 / 60
      let current = panel.frame.origin
      let dx = target.x - current.x, dy = target.y - current.y
      velocity.x += (stiffness * dx - damping * velocity.x) * dt
      velocity.y += (stiffness * dy - damping * velocity.y) * dt
      var next = NSPoint(x: current.x + velocity.x * dt, y: current.y + velocity.y * dt)
      if abs(dx) < 0.5 && abs(dy) < 0.5 && abs(velocity.x) < 1 && abs(velocity.y) < 1 {
        next = target
        timer.invalidate()
      }
      panel.setFrameOrigin(next)
    }
  }
  func stop() { timer?.invalidate() }
}

final class Switcher {
  // Concentric corners: the thumbnail's radius plus its well's padding is the well's radius, and the
  // well's radius plus the card's margin is the card's. The margin is the same on all four sides.
  static let thumb = CGSize(width: 224, height: 144), thumbRadius: CGFloat = 24, gap: CGFloat = 12
  // 40 points from the card's edge to the thumbnail on every side: the selection fill's 4 plus a margin
  // of 36 on top and the sides, and below, a 40-point band with the favicon and title centered in it.
  static let margin: CGFloat = 40
  static let cardPad: CGFloat = 4, wellRadius = thumbRadius + cardPad
  static let pad = margin - cardPad, radius = wellRadius + pad
  static let below = margin, shadowRoom: CGFloat = 70
  static let showAfter = 0.15, maxVisible = 5

  var tabs: [TabInfo] = []
  var frontWindow = -1 // Chrome's id for the window in front; the walk keeps to its tabs
  var inFront: [TabInfo] { tabs.filter { $0.windowId == frontWindow } }
  var thumbs: [Int: NSImage] {
    get { model.thumbs }
    set { model.thumbs = newValue }
  }
  var onActivate: (Int) -> Void = { _ in }

  private let model = SwitcherModel()
  private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                              backing: .buffered, defer: false)
  private let hosting: NSHostingView<SwitcherView>
  private let spring = FrameSpring()
  private var showTimer: Timer?
  private var walking = false

  var isWalking: Bool { walking }

  init() {
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false // the card draws its own, inside the panel
    panel.hidesOnDeactivate = false
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    hosting = NSHostingView(rootView: SwitcherView(model: model))
    panel.contentView = hosting
  }

  func step(back: Bool) {
    if !walking {
      let candidates = inFront
      guard candidates.count > 1 else { return }
      walking = true
      // The five most recent, or fewer on a narrow screen; the walk wraps within them.
      let width = screen?.visibleFrame.width ?? 1200
      let fit = Int((width - 2 * Self.pad - 80 + Self.gap) / (Self.thumb.width + 2 * Self.cardPad + Self.gap))
      model.walk = Array(candidates.prefix(max(2, min(Self.maxVisible, fit))))
      model.index = 0
      showTimer = Timer.scheduledTimer(withTimeInterval: Self.showAfter, repeats: false) { [weak self] _ in self?.show() }
    }
    model.index = (model.index + (back ? -1 : 1) + model.walk.count) % model.walk.count
  }

  func controlUp() {
    guard walking else { return }
    let pick = model.walk[model.index]
    hide()
    onActivate(pick.id)
  }

  func cancel() { hide() }

  func forget(tab id: Int) { model.thumbs[id] = nil }

  // --demo: the panel with sample tabs, to look at.
  func demo() {
    let colors: [NSColor] = [.systemBlue, .systemOrange, .systemGreen, .systemPink, .systemTeal, .systemIndigo, .systemBrown]
    tabs = ["Monochrome", "Liquid Glass | Apple Developer Documentation", "Inbox (3) - Gmail", "Figma", "Hacker News",
            "Chrome Extensions: chrome.tabs", "YouTube"].enumerated().map { i, title in
      let favicon = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
        colors[i].setFill(); NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill(); return true
      }
      return TabInfo(id: i, windowId: 1, title: title, favicon: favicon)
    }
    frontWindow = 1
    for i in 0..<5 { // mixed aspects: a wide capture leaves room under it, a tall one is cut at the bottom
      let height: CGFloat = [300, 200, 300, 600, 300][i]
      model.thumbs[i] = NSImage(size: NSSize(width: 480, height: height), flipped: false) { rect in
        NSGradient(starting: colors[i].blended(withFraction: 0.7, of: .white)!, ending: .white)!.draw(in: rect, angle: -70)
        NSColor.black.withAlphaComponent(0.12).setFill()
        for row in 0..<Int(height / 40) { NSRect(x: 30, y: height - 50 - CGFloat(row) * 34, width: CGFloat(260 + row * 23 % 170), height: 12).fill() }
        return true
      }
    }
    step(back: false)
    step(back: false)
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.step(back: false) } // keeps walking, to watch
    // The panel's screen rectangle, top-left origin, for screencapture -R.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
      let f = panel.frame, top = (NSScreen.screens.first?.frame.height ?? 0) - f.maxY
      FileHandle.standardError.write(Data("panel \(Int(f.minX)),\(Int(top)),\(Int(f.width)),\(Int(f.height))\n".utf8))
    }
  }

  private func show() {
    guard walking else { return }
    place()
    model.shown = true
    panel.orderFrontRegardless()
  }

  // Shown and hidden at once, no fade.
  private func hide() {
    showTimer?.invalidate()
    showTimer = nil
    walking = false
    spring.stop()
    model.shown = false
    model.walk = []
    panel.orderOut(nil)
  }

  static func cardSize(count: Int) -> CGSize {
    CGSize(width: CGFloat(count) * (thumb.width + 2 * cardPad) + CGFloat(count - 1) * gap + 2 * pad,
           height: pad + cardPad + thumb.height + below)
  }

  private var screen: NSScreen? {
    Chrome.frontWindowFrame.flatMap { frame in NSScreen.screens.first { $0.frame.intersects(frame) } } ?? NSScreen.main
  }

  // Centers the card on Chrome's window, kept on screen.
  private func place() {
    let anchor = Chrome.frontWindowFrame
    let screen = self.screen
    let card = Self.cardSize(count: model.walk.count)
    let size = NSSize(width: card.width + 2 * Self.shadowRoom, height: card.height + 2 * Self.shadowRoom)
    let center = anchor.map { NSPoint(x: $0.midX, y: $0.midY) } ?? screen.map { NSPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) } ?? .zero
    var frame = NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    // Centered on Chrome's window, but the card itself stays on screen: a window hanging off an edge
    // slides the card in rather than losing part of it. The shadow room around the card may go off.
    if let visible = screen?.visibleFrame {
      frame.origin.x = min(max(frame.minX, visible.minX - Self.shadowRoom), visible.maxX - size.width + Self.shadowRoom)
      frame.origin.y = min(max(frame.minY, visible.minY - Self.shadowRoom), visible.maxY - size.height + Self.shadowRoom)
    }
    hosting.frame = NSRect(origin: .zero, size: size)
    if panel.isVisible && panel.frame.size == frame.size {
      spring.move(panel, to: frame.origin) // Chrome's window moved under it: glide there
    } else {
      panel.setFrame(frame, display: true)
    }
  }
}

struct SwitcherView: View {
  @ObservedObject var model: SwitcherModel
  @Environment(\.colorScheme) private var colorScheme
  private var isDark: Bool { colorScheme == .dark }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Switcher.radius, style: .continuous)
    let size = Switcher.cardSize(count: model.walk.count)
    // Layered as Quicksilver's card is: the glass, its tint and hairline as one clipped layer carrying
    // the shadows, and the content stacked over it.
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

      HStack(alignment: .top, spacing: Switcher.gap) {
        ForEach(model.walk, id: \.id) { tab in
          TabCard(tab: tab, thumb: model.thumbs[tab.id], selected: tab.id == model.walk[safe: model.index]?.id)
        }
      }
      .padding(.top, Switcher.pad)
      .frame(width: size.width, height: size.height, alignment: .top)
    }
    .opacity(model.shown ? 1 : 0)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // Quicksilver's card tint: in light, a white wash rising from the bottom and a highlight falling from
  // just right of the top; in dark, a black wash deepening toward the bottom.
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

// A thumbnail with its favicon and title underneath, as Arc lays them out. Only the highlighted one has
// anything around it: a 50 percent black rounded fill, no stroke, like the dark square behind the
// selected app in ⌘Tab; nothing animated and nothing under it moving. The thumbnail is scaled to
// its width and hangs from the top, so a tall capture is cut at the bottom and a wide one leaves room.
private struct TabCard: View {
  let tab: TabInfo
  let thumb: NSImage?
  let selected: Bool

  var body: some View {
    let frame = RoundedRectangle(cornerRadius: Switcher.thumbRadius, style: .continuous)
    VStack(alignment: .leading, spacing: 0) {
      // The thumbnail area is a glass container with a default fill, the window background at 80
      // percent, so a short capture or none at all still reads as a card; the image lies over it.
      Group {
        if let thumb {
          // Sized from the capture's own ratio: scaledToFit would honor the 144-point frame below and
          // shrink a tall capture to fit its height instead.
          Image(nsImage: thumb).resizable()
            .frame(width: Switcher.thumb.width, height: Switcher.thumb.width * thumb.size.height / max(thumb.size.width, 1))
        } else if let favicon = tab.favicon {
          Image(nsImage: favicon).resizable().frame(width: 40, height: 40)
            .frame(width: Switcher.thumb.width, height: Switcher.thumb.height)
        }
      }
      .frame(width: Switcher.thumb.width, height: Switcher.thumb.height, alignment: .top)
      .background {
        if #available(macOS 26, *) {
          frame.fill(.clear).glassEffect(.regular, in: frame)
        }
        frame.fill(Color(nsColor: .windowBackgroundColor).opacity(0.8))
      }
      .clipped()
      .clipShape(frame)
      .overlay(frame.strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
      .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
      .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
      .padding(Switcher.cardPad)
      .background {
        if selected { wellShape.fill(.black.opacity(0.5)) }
      }
      HStack(spacing: 8) {
        if let favicon = tab.favicon {
          Image(nsImage: favicon).resizable().frame(width: 12, height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        Text(tab.title)
          .font(.system(size: 14, weight: .medium))
          .lineLimit(1)
          .truncationMode(.tail)
      }
      .padding(.leading, Switcher.cardPad + 20)
      .padding(.trailing, Switcher.cardPad)
      .offset(y: -2)
      .frame(width: Switcher.thumb.width + 2 * Switcher.cardPad, height: Switcher.below - Switcher.cardPad, alignment: .leading)
    }
  }

  private var wellShape: RoundedRectangle { RoundedRectangle(cornerRadius: Switcher.wellRadius, style: .continuous) }
}

extension Array {
  subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
