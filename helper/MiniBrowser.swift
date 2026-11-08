// Mini browsers' bars and the peek browser's shade, drawn here instead of in the page. The extension sends the mini
// windows (where they are, their page, and for a peek browser the window it's over) and the places a
// mini browser can be moved to; this side finds each one's Chrome window on screen and keeps a glass bar
// on its top right: address (⌘L), Open in Chrome, and ▾ for a window or tab group. The bar's actions
// go back over the bridge. Under a peek browser sits a shade the size and shape of the window it covers,
// ordered just below the peek browser's window; a click on the shade closes the peek browser. Both only show while
// Chrome is in front, and follow their windows from the window list, like the mini player.
import AppKit
import SwiftUI

struct MiniBrowser {
  let id: Int
  let frame: CGRect // Chrome's coordinates, down from the top of the main screen
  let url, title: String
  let over: CGRect? // a peek browser: the window it covers
  let targets: [Target] // where it can be moved to: its own profile's windows and groups
  var profile: String? // the profile's name as Chrome shows it, once the app has learned it
}

struct Target {
  let windowId: Int
  let title: String
  let groups: [(id: Int, title: String, color: String)]
}

final class MiniBrowsers {
  var windows: [MiniBrowser] = []
  var shortcuts: [String: String] = [:]
  var onAction: ([String: Any]) -> Void = { _ in }
  private var bars: [Int: MiniBrowserBar] = [:]
  private let shade = PeekShade()
  private var lastFrames: [Int: CGRect] = [:]
  private var windowIds: [Int: CGWindowID] = [:] // Chrome window id -> the window server's number, once matched
  private var shadeMissing = 0 // ticks the peek browser's window hasn't been on screen

  // A drag starts with the button going down in a window's title bar: that window's bar, which would
  // trail the window, vanishes at once, and comes back with a fade when the button comes up. A window
  // that moves while the button is down counts too.
  var mouseDown = false {
    didSet {
      if mouseDown {
        let mouse = NSEvent.mouseLocation
        for (id, bar) in bars where bar.titleBarContains(mouse) { bar.vanish(); _ = id }
      } else {
        bars.values.forEach { $0.fade(out: false) }
      }
    }
  }

  func follow(_ onScreen: [Chrome.Window], front: Bool) {
    var shown = Set<Int>()
    if front {
      // Only the mini browser that is Chrome's front window gets its bar; ones behind it don't.
      for w in windows {
        guard let window = resolve(w, in: onScreen), window.id == onScreen.first?.id else { continue }
        let bar = bars[w.id] ?? MiniBrowserBar(id: w.id, action: onAction)
        bars[w.id] = bar
        bar.update(w, shortcuts: shortcuts, targets: w.targets)
        bar.place(over: Chrome.appKit(window.frame))
        if mouseDown, let last = lastFrames[w.id], last != window.frame { bar.vanish() }
        lastFrames[w.id] = window.frame
        shown.insert(w.id)
      }
    }
    for (id, bar) in bars where !shown.contains(id) {
      bar.hide()
      if !windows.contains(where: { $0.id == id }) { bars[id] = nil }
    }
    // The shade stays through a drag of the peek browser: its window is known by number once matched,
    // and a tick or two without it (a drag, a frame in flight) doesn't drop it.
    if front, let peek = windows.first(where: { $0.over != nil }), let over = Chrome.match(peek.over!, in: onScreen),
       let peekWindow = resolve(peek, in: onScreen) {
      shadeMissing = 0
      shade.show(over: Chrome.appKit(over.frame), below: peekWindow.id) { [weak self] in
        self?.onAction(["window": peek.id, "action": "closePeekBrowser"])
      }
    } else if !front || windows.first(where: { $0.over != nil }) == nil {
      shadeMissing = 0
      shade.hide()
    } else {
      shadeMissing += 1
      if shadeMissing > 8 { shade.hide() }
    }
  }

  // A mini browser's on-screen window: by the number remembered from an earlier match while that window
  // is still on screen, else by frame.
  private func resolve(_ w: MiniBrowser, in onScreen: [Chrome.Window]) -> Chrome.Window? {
    if let id = windowIds[w.id], let window = onScreen.first(where: { $0.id == id }) { return window }
    guard let window = Chrome.match(w.frame, in: onScreen) else { return nil }
    windowIds[w.id] = window.id
    return window
  }

  // The mini browser whose window is Chrome's front one.
  var frontWindow: MiniBrowser? {
    guard let front = Chrome.windows().first else { return nil }
    return windows.first { Chrome.match($0.frame, in: [front]) != nil }
  }

  func showAddress(_ id: Int) { bars[id]?.showAddress() }
  func showMenu(_ id: Int) { bars[id]?.showMenu() }

  // --demo-shade: the shade over Chrome's second window, ordered below its first, to see that a panel
  // can be ordered between another app's windows.
  func demoShade() {
    let onScreen = Chrome.windows()
    guard onScreen.count >= 2 else { return FileHandle.standardError.write(Data("needs two Chrome windows on screen\n".utf8)) }
    shade.show(over: Chrome.appKit(onScreen[1].frame), below: onScreen[0].id) {}
    let f = shade.frame, top = (NSScreen.screens.first?.frame.height ?? 0) - f.maxY
    FileHandle.standardError.write(Data("shade \(Int(f.minX)),\(Int(top)),\(Int(f.width)),\(Int(f.height))\n".utf8))
  }
}

// A panel that can take typing (for the address field) without activating the app.
final class KeyablePanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

// Takes the first click even though the panel isn't the active window.
final class FirstClickButton: NSButton {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// The glass behind the controls; clicks go to the controls, never to it.
final class GlassBackdrop<Content: View>: NSHostingView<Content> {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// The bar sits inside the window's title bar, inset so its corner is concentric with the window's:
// Chrome's popup windows have a 32-point title bar and 16-point corners.
struct PillGlass: View {
  var body: some View {
    let shape = RoundedRectangle(cornerRadius: MiniBrowserBar.radius, style: .continuous)
    ZStack {
      if #available(macOS 26, *) {
        shape.fill(.clear).glassEffect(.regular, in: shape)
      } else {
        shape.fill(.regularMaterial)
      }
      shape.strokeBorder(.primary.opacity(0.14), lineWidth: 1)
    }
  }
}

final class MiniBrowserBar: NSObject, NSTextFieldDelegate {
  static let titleBar: CGFloat = 32, windowRadius: CGFloat = 16, inset = CGPoint(x: 4, y: 4)
  static let height = titleBar - 2 * inset.y, radius = windowRadius - inset.x, addressWidth: CGFloat = 460
  static let room: CGFloat = 10 // around the pill, so the glass's own soft edge isn't cut at the panel
  let id: Int
  let action: ([String: Any]) -> Void
  let panel = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
  private let content = NSView()
  private let glass = GlassBackdrop(rootView: PillGlass())
  private let link = FirstClickButton(), open = FirstClickButton(), caret = FirstClickButton()
  private let address = NSTextField()
  private var url = "", targets: [Target] = []
  private var openWidth: CGFloat = 0 // the Open button's own width; its frame is padded from it
  private var addressShown = false

  init(id: Int, action: @escaping ([String: Any]) -> Void) {
    self.id = id
    self.action = action
    super.init()
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.contentView = content
    content.addSubview(glass)

    for (button, symbol, selector) in [(link, "link", #selector(pressedLink)), (caret, "chevron.down", #selector(pressedCaret))] {
      button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
      button.target = self
      button.action = selector
    }
    open.target = self
    open.action = #selector(pressedOpen)
    open.font = .systemFont(ofSize: 12, weight: .medium)
    for button in [link, open, caret] {
      button.isBordered = false
      button.contentTintColor = .labelColor
      content.addSubview(button)
    }
    address.delegate = self
    address.isBezeled = false
    address.drawsBackground = false
    address.font = .systemFont(ofSize: 12)
    address.focusRingType = .none
    address.isHidden = true
    address.cell?.usesSingleLineMode = true
    address.cell?.isScrollable = true
    content.addSubview(address)
    NotificationCenter.default.addObserver(self, selector: #selector(resignedKey), name: NSWindow.didResignKeyNotification, object: panel)
  }

  func update(_ w: MiniBrowser, shortcuts: [String: String], targets: [Target]) {
    url = w.url
    self.targets = targets
    // "Nicholas (jitkoff.com)" is shown as its account, jitkoff.com; a name without one is shown whole.
    let profile = w.profile.map { name in name.split(separator: "(", maxSplits: 1).last.map { $0.replacingOccurrences(of: ")", with: "").trimmingCharacters(in: .whitespaces) } ?? name }
    let title = "Open in " + (profile ?? "Chrome") + (shortcuts["mini-open"].map { "  " + $0 } ?? "")
    if open.title != title {
      open.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor])
      open.sizeToFit()
      openWidth = open.frame.width
    }
    caret.toolTip = "Open in…" + (shortcuts["mini-open-in"].map { " (" + $0 + ")" } ?? "")
    link.toolTip = "Address (⌘L)"
  }

  private var width: CGFloat { addressShown ? Self.addressWidth : 34 + openWidth + 16 + 30 }

  func place(over window: NSRect) {
    titleBar = NSRect(x: window.minX, y: window.maxY - Self.titleBar, width: window.width, height: Self.titleBar)
    let width = min(self.width, window.width - 2 * Self.inset.x)
    let pill = NSRect(x: window.maxX - width - Self.inset.x, y: window.maxY - Self.height - Self.inset.y, width: width, height: Self.height)
    let frame = pill.insetBy(dx: -Self.room, dy: -Self.room)
    if panel.frame != frame {
      panel.setFrame(frame, display: true)
      layout(width: width)
    }
    if !panel.isVisible { panel.orderFrontRegardless() }
  }

  // The pill sits `room` in from the panel's edges; the controls are laid out inside the pill.
  private func layout(width: CGFloat) {
    let h = Self.height, r = Self.room
    content.frame = NSRect(x: 0, y: 0, width: width + 2 * r, height: h + 2 * r)
    glass.frame = NSRect(x: r, y: r, width: width, height: h)
    link.frame = NSRect(x: r + 4, y: r, width: 30, height: h)
    open.frame = NSRect(x: r + 34, y: r, width: openWidth + 16, height: h)
    caret.frame = NSRect(x: r + width - 30, y: r, width: 26, height: h)
    address.frame = NSRect(x: r + 12, y: r + (h - 16) / 2, width: width - 24, height: 16)
  }

  func hide() {
    if addressShown { hideAddress() }
    panel.orderOut(nil)
  }

  private var fadedOut = false
  private var titleBar = NSRect.zero // the window's title bar, where a drag starts

  func vanish() {
    guard !fadedOut else { return }
    fadedOut = true
    panel.alphaValue = 0
  }

  func fade(out: Bool) {
    guard out != fadedOut else { return }
    fadedOut = out
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.15
      panel.animator().alphaValue = out ? 0 : 1
    }
  }

  func titleBarContains(_ point: NSPoint) -> Bool { titleBar.contains(point) && !panel.frame.contains(point) }

  // ⌘L: the page's address, selected and ready to copy; Enter goes to a URL or search, Esc closes.
  func showAddress() {
    addressShown = true
    for button in [link, open, caret] { button.isHidden = true }
    address.isHidden = false
    address.stringValue = url
    panel.makeKey()
    address.becomeFirstResponder()
    address.currentEditor()?.selectAll(nil)
  }

  private func hideAddress() {
    addressShown = false
    address.isHidden = true
    for button in [link, open, caret] { button.isHidden = false }
    if panel.isKeyWindow { panel.resignKey() }
  }

  @objc private func resignedKey() { if addressShown { hideAddress() } }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    if selector == #selector(NSResponder.insertNewline(_:)) {
      let text = address.stringValue.trimmingCharacters(in: .whitespaces)
      hideAddress()
      if !text.isEmpty && text != url { action(["window": id, "action": "go", "text": text]) }
      return true
    }
    if selector == #selector(NSResponder.cancelOperation(_:)) {
      hideAddress()
      return true
    }
    return false
  }

  @objc private func pressedLink() { showAddress() }
  @objc private func pressedOpen() { action(["window": id, "action": "open"]) }
  @objc private func pressedCaret() { showMenu() }

  // ▾: every normal window, named by the tab it's on, with its tab groups.
  func showMenu() {
    let menu = NSMenu()
    let colors: [String: NSColor] = ["grey": .systemGray, "blue": .systemBlue, "red": .systemRed, "yellow": .systemYellow, "green": .systemGreen,
                                     "pink": .systemPink, "purple": .systemPurple, "cyan": .systemCyan, "orange": .systemOrange]
    for target in targets {
      let header = NSMenuItem(title: target.title, action: nil, keyEquivalent: "")
      header.isEnabled = false
      menu.addItem(header)
      let newTab = NSMenuItem(title: "New tab", action: #selector(moveTo(_:)), keyEquivalent: "")
      newTab.target = self
      newTab.representedObject = ["windowId": target.windowId]
      newTab.indentationLevel = 1
      menu.addItem(newTab)
      for group in target.groups {
        let item = NSMenuItem(title: group.title, action: #selector(moveTo(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = ["windowId": target.windowId, "groupId": group.id]
        item.indentationLevel = 1
        let color = colors[group.color] ?? .systemGray
        item.image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
          color.setFill()
          NSBezierPath(ovalIn: rect).fill()
          return true
        }
        menu.addItem(item)
      }
      menu.addItem(.separator())
    }
    let settings = NSMenuItem(title: "Monochrome Settings…", action: #selector(openSettings), keyEquivalent: "")
    settings.target = self
    menu.addItem(settings)
    menu.popUp(positioning: nil, at: NSPoint(x: caret.frame.minX, y: Self.room), in: content)
  }

  @objc private func openSettings() { SettingsWindow.shared.show() }

  @objc private func moveTo(_ item: NSMenuItem) {
    guard let to = item.representedObject as? [String: Int] else { return }
    action(["window": id, "action": "move", "to": to])
  }
}

// Darkens the window a peek browser is over: a panel the window's size with its 16-point corners, at normal
// level and ordered just below the peek browser's window, so the peek browser stays in front of it and the window
// behind stays behind. Window numbers are global, so ordering relative to Chrome's window works
// across apps. A click on it closes the peek browser.
final class PeekShade {
  static let radius: CGFloat = 16
  private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
  private let view = ShadeView()

  init() {
    panel.level = .normal
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.contentView = view
  }

  var frame: NSRect { panel.frame }
  private var showing = false
  private var below: CGWindowID = 0

  // Fades in, and never scales; the peek browser above it is what moves. Re-ordered only when the
  // window it sits under changes, not every tick.
  func show(over window: NSRect, below peek: CGWindowID, onClick: @escaping () -> Void) {
    view.onClick = onClick
    if panel.frame != window {
      panel.setFrame(window, display: false)
      view.frame = NSRect(origin: .zero, size: window.size)
      view.needsDisplay = true
    }
    if below != peek || !panel.isVisible {
      below = peek
      panel.order(.below, relativeTo: Int(peek))
    }
    guard !showing else { return }
    showing = true
    panel.alphaValue = 0
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
      panel.animator().alphaValue = 1
    }
  }

  func hide() {
    guard showing else { return }
    showing = false
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.15
      panel.animator().alphaValue = 0
    }, completionHandler: { [panel] in if panel.alphaValue == 0 { panel.orderOut(nil) } })
  }
}

final class ShadeView: NSView {
  var onClick = {}
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) { onClick() }
  override func draw(_ dirtyRect: NSRect) {
    NSColor.black.withAlphaComponent(0.35).setFill()
    NSBezierPath(roundedRect: bounds, xRadius: PeekShade.radius, yRadius: PeekShade.radius).fill()
  }
}
