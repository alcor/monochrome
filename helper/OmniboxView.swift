// The ⌘L and ⌘T box (Omnibox.swift has what fills it): the lower half of Quicksilver's panel, its search
// field and the results that open under it, with Quicksilver's measurements (alchemy's CommandView.swift,
// from its Figma file): a 72-point capsule of clear glass carrying the label scrim, a magnifying glass 26
// in, 22-point text; rows 62 tall with 48-point icons, favicons on a wash of their own colors, a semibold
// 17-point title over a 15-point address, and one selection fill that slides between rows.
// The panel is non-activating, as Quicksilver's is: the browser stays the app in front, the box takes
// the typing while it is key, and it closes when it stops being key.
import AppKit
import SwiftUI

final class OmniboxPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

final class OmniboxController: NSObject, NSWindowDelegate {
  static let width: CGFloat = 640, shadowRoom: CGFloat = 60, maxRows = 8
  let model = OmniboxModel()
  let field = OmniboxField()
  private let panel = OmniboxPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                   backing: .buffered, defer: false)
  private var hideWork: DispatchWorkItem?

  override init() {
    super.init()
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.hidesOnDeactivate = false
    panel.delegate = self
    field.model = model
    let size = NSSize(width: Self.width + 2 * Self.shadowRoom, height: Self.shadowRoom + OmniboxView.fieldHeight + OmniboxView.rowsHeight(Self.maxRows) + 2 * Self.shadowRoom)
    let hosting = NSHostingView(rootView: OmniboxView(model: model, field: field))
    hosting.frame = NSRect(origin: .zero, size: size)
    panel.setContentSize(size)
    panel.contentView = hosting
    model.onCompletionChange = { [weak self] in self?.field.showCompletion() }
  }

  var isVisible: Bool { panel.isVisible && hideWork == nil }
  var isKey: Bool { panel.isKeyWindow }

  // Over the browser window, centered across it, the field's top a fifth of the way down (at most 140).
  func show(newTab: Bool, browser: Browser, over window: NSRect?) {
    hideWork?.cancel()
    hideWork = nil
    model.reset(newTab: newTab, browser: browser)
    field.reset(text: "")
    let anchor = window ?? NSScreen.main?.visibleFrame ?? .zero
    let size = panel.frame.size
    let fieldTop = anchor.maxY - min(140, anchor.height / 5)
    var origin = NSPoint(x: anchor.midX - size.width / 2, y: fieldTop + Self.shadowRoom - size.height)
    if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main {
      origin.x = min(max(origin.x, screen.visibleFrame.minX - Self.shadowRoom), screen.visibleFrame.maxX - size.width + Self.shadowRoom)
      origin.y = max(origin.y, screen.visibleFrame.minY - Self.shadowRoom)
    }
    panel.setFrameOrigin(origin)
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(field)
    model.shown = false
    DispatchQueue.main.async { withAnimation(.spring(duration: 0.18, bounce: 0.2)) { self.model.shown = true } }
  }

  // ⌘L: the front tab's address, all of it selected, the list closed until something is typed.
  func showCurrent(_ url: String) {
    guard !model.newTab, model.query.isEmpty, field.stringValue.isEmpty else { return }
    field.reset(text: url, selectAll: true)
  }

  func hide() {
    guard panel.isVisible, hideWork == nil else { return }
    withAnimation(.easeOut(duration: 0.14)) { model.shown = false }
    let work = DispatchWorkItem { [weak self] in
      self?.hideWork = nil
      self?.panel.orderOut(nil)
    }
    hideWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
  }

  func windowDidResignKey(_ notification: Notification) { hide() }

  // --omnibox-snapshot: the panel as the window server draws it, glass included, from the app's own
  // window (an app may read its own windows without the Screen Recording grant).
  func snapshot(to path: String) {
    guard panel.isVisible,
          let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(panel.windowNumber), [.boundsIgnoreFraming, .bestResolution])
    else { return log.info("omnibox: snapshot: no panel on screen") }
    try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    log.info("omnibox: snapshot \(image.width)x\(image.height) to \(path, privacy: .public)")
  }

  // --demo-omnibox: sample history typed into, drawn into a PNG at `out` from the view itself (no
  // screen recording, and the panel never takes the keyboard). Glass does not draw this way; the scrim
  // and everything on it does.
  func demo(out: String, dark: Bool) {
    let now = Date()
    model.reset(newTab: true, browser: .chrome)
    model.pages = [
      OmniboxPage(url: "https://github.com/", title: "GitHub", visits: 120, typed: 30, last: now, bookmarked: true),
      OmniboxPage(url: "https://github.com/arfct/monochrome/pulls", title: "Pull requests · arfct/monochrome", visits: 40, typed: 0, last: now, bookmarked: false),
      OmniboxPage(url: "https://github.com/arfct/alchemy", title: "arfct/alchemy: Quicksilver, rebuilt", visits: 25, typed: 2, last: now.addingTimeInterval(-86400), bookmarked: false),
      OmniboxPage(url: "https://git-scm.com/docs/git-rebase", title: "Git - git-rebase Documentation", visits: 6, typed: 0, last: now.addingTimeInterval(-5 * 86400), bookmarked: false),
    ]
    model.tabs = [OmniboxTab(id: 7, url: "https://github.com/arfct/monochrome/pull/15", title: "Omnibox for ⌘L and ⌘T by arfct · Pull Request #15")]
    model.update(query: "git", allowCompletion: true)
    model.receive(suggestions: [OmniboxSuggestion(text: "github copilot", url: nil, description: ""), OmniboxSuggestion(text: "gitlab", url: nil, description: "")], for: "git")
    model.selected = 1
    field.stringValue = "git" + model.completion
    model.shown = true
    panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    panel.setFrameOrigin(NSPoint(x: -10000, y: -10000))
    panel.orderFrontRegardless()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
      guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
      view.cacheDisplay(in: view.bounds, to: rep)
      try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
      print(out)
      exit(0)
    }
  }
}

// The field. Its text is what was typed plus the inline completion, the completion selected and drawn
// in tertiary gray with no selection color, so it reads as Quicksilver's gray completion and the next
// key typed replaces it. Return, Escape, Tab and the arrows go to the model.
final class OmniboxField: NSTextField, NSTextFieldDelegate {
  weak var model: OmniboxModel?
  private var typed = ""
  private var defaultSelection: [NSAttributedString.Key: Any]?

  init() {
    super.init(frame: .zero)
    isBordered = false
    isBezeled = false
    drawsBackground = false
    focusRingType = .none
    font = .systemFont(ofSize: 22)
    usesSingleLineMode = true
    cell?.lineBreakMode = .byTruncatingTail
    cell?.isScrollable = true
    placeholderString = "Search or enter address"
    delegate = self
  }

  required init?(coder: NSCoder) { fatalError() }

  private var editor: NSTextView? { currentEditor() as? NSTextView }

  func reset(text: String, selectAll: Bool = false) {
    typed = text
    stringValue = text
    plainSelection()
    if selectAll { editor?.selectAll(nil) } else { editor?.setSelectedRange(NSRange(location: (text as NSString).length, length: 0)) }
  }

  func controlTextDidChange(_ notification: Notification) {
    let text = stringValue
    let shown = typed + (model?.completion ?? "")
    // Shorter than what was typed, or the gray text alone removed: a deletion.
    let deleting = text.count < typed.count || (text == typed && shown != typed)
    typed = text
    model?.update(query: text, allowCompletion: !deleting)
    showCompletion()
  }

  func showCompletion() {
    guard let editor, let model else { return }
    let completion = model.selected == 0 ? model.completion : ""
    let start = (typed as NSString).length
    if editor.string != typed + completion { editor.string = typed + completion }
    if completion.isEmpty {
      plainSelection()
      if editor.selectedRange().location > start || editor.selectedRange().upperBound > start { editor.setSelectedRange(NSRange(location: start, length: 0)) }
      return
    }
    if defaultSelection == nil { defaultSelection = editor.selectedTextAttributes }
    editor.selectedTextAttributes = [.foregroundColor: NSColor.tertiaryLabelColor, .backgroundColor: NSColor.clear]
    editor.setSelectedRange(NSRange(location: start, length: (completion as NSString).length))
  }

  private func plainSelection() {
    if let editor, let defaultSelection { editor.selectedTextAttributes = defaultSelection }
  }

  private static let acceptKeys: Set<Selector> = [#selector(NSResponder.insertTab(_:)), #selector(NSResponder.moveRight(_:)),
    #selector(NSResponder.moveToEndOfLine(_:)), #selector(NSResponder.moveToRightEndOfLine(_:)), #selector(NSResponder.moveToEndOfDocument(_:))]

  // Tab, →, or End takes the gray completion; with none, Tab moves down the list as ↓ does.
  // --omnibox ... show: text typed through the field editor, as keys would, a character at a time.
  func typeForTest(_ text: String) {
    guard let editor else { return log.info("omnibox test: the field is not being edited") }
    for character in text {
      editor.insertText(String(character), replacementRange: editor.selectedRange())
    }
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    guard let model else { return false }
    if Self.acceptKeys.contains(selector) && !model.completion.isEmpty && model.selected == 0 {
      typed += model.completion
      model.acceptCompletion()
      plainSelection()
      textView.setSelectedRange(NSRange(location: (typed as NSString).length, length: 0))
      return true
    }
    switch selector {
    case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.insertTab(_:)): model.move(1)
    case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.insertBacktab(_:)): model.move(-1)
    case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)):
      model.commit(flip: NSEvent.modifierFlags.contains(.option))
      return true
    case #selector(NSResponder.cancelOperation(_:)):
      model.onDismiss()
      return true
    default:
      return false
    }
    showCompletion()
    return true
  }
}

struct OmniboxView: View {
  @ObservedObject var model: OmniboxModel
  let field: OmniboxField
  @Environment(\.colorScheme) private var colorScheme
  @Namespace private var selection

  static let fieldHeight: CGFloat = 72, rowHeight: CGFloat = 62, rowGap: CGFloat = 1, rowsBottomMargin: CGFloat = 7
  static let resultsInset: CGFloat = 8, selectionInset: CGFloat = 8, rowRadius: CGFloat = 25
  static func rowsHeight(_ count: Int) -> CGFloat {
    count == 0 ? 0 : CGFloat(count) * (rowHeight + rowGap) - rowGap + rowsBottomMargin
  }

  private var isDark: Bool { colorScheme == .dark }
  private var scrim: Color { isDark ? .black : .white }
  private var visibleRows: Int { model.revealed ? min(model.rows.count, OmniboxController.maxRows) : 0 }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Self.fieldHeight / 2, style: .continuous)
    VStack(spacing: 0) {
      searchField
      ScrollViewReader { proxy in
        ScrollView(showsIndicators: false) {
          VStack(spacing: Self.rowGap) {
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
              OmniboxRowView(row: row, icon: row.page.flatMap { model.icons[$0] }, isSelected: index == model.selected, selection: selection)
                .id(row.id)
                .onTapGesture { model.commit(at: index) }
            }
          }
          .padding(.bottom, Self.rowsBottomMargin)
          .animation(.easeInOut(duration: 0.22), value: model.selected)
        }
        .frame(height: Self.rowsHeight(visibleRows))
        .onChange(of: model.selected) { index in
          if model.rows.indices.contains(index) { proxy.scrollTo(model.rows[index].id) }
        }
      }
      .clipped()
    }
    .frame(width: OmniboxController.width)
    .mask { shape }
    .background {
      background(shape).shadow(color: .black.opacity(0.2), radius: 24, y: 14)
    }
    .animation(.spring(duration: 0.15, bounce: 0.2), value: visibleRows)
    // Quicksilver's entrance: blurred, faded, smaller and higher, then clear.
    .blur(radius: model.shown ? 0 : 14)
    .opacity(model.shown ? 1 : 0)
    .scaleEffect(model.shown ? 1 : 0.92, anchor: .top)
    .offset(y: model.shown ? 0 : -18)
    .padding(.top, OmniboxController.shadowRoom)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var searchField: some View {
    HStack(spacing: 19) {
      Image(systemName: model.newTab ? "magnifyingglass" : "link")
        .font(.system(size: 21.806))
        .foregroundStyle(.secondary)
        .frame(width: 26)
      FieldHost(field: field)
    }
    .padding(.horizontal, 26)
    .frame(height: Self.fieldHeight)
  }

  // Clear glass carrying the label scrim, 80 percent of the page color at the top to all of it at the
  // bottom, and a hairline border: Quicksilver's results card.
  @ViewBuilder private func background(_ shape: RoundedRectangle) -> some View {
    ZStack {
      if #available(macOS 26, *) {
        shape.fill(.clear).glassEffect(.clear, in: shape)
      } else {
        shape.fill(.ultraThinMaterial)
      }
      shape.fill(LinearGradient(colors: [scrim.opacity(0.8), scrim], startPoint: .top, endPoint: .bottom))
      shape.strokeBorder(.white.opacity(isDark ? 0.14 : 0.3), lineWidth: 1.25)
    }
  }
}

private struct FieldHost: NSViewRepresentable {
  let field: OmniboxField
  func makeNSView(context: Context) -> OmniboxField { field }
  func updateNSView(_ nsView: OmniboxField, context: Context) {}
}

private struct OmniboxRowView: View {
  let row: OmniboxRow
  let icon: NSImage?
  let isSelected: Bool
  let selection: Namespace.ID

  var body: some View {
    HStack(spacing: 6) {
      Group {
        if let icon {
          FaviconTile(image: icon, side: 48 * 206 / 256)
        } else {
          Image(systemName: row.symbol).font(.system(size: 22)).foregroundStyle(.secondary)
        }
      }
      .frame(width: 48, height: 48)
      VStack(alignment: .leading, spacing: 2) {
        Text(row.title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
        if let detail = row.detail {
          Text(detail).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, OmniboxView.resultsInset + OmniboxView.selectionInset)
    .frame(height: OmniboxView.rowHeight)
    .background {
      if isSelected {
        RoundedRectangle(cornerRadius: OmniboxView.rowRadius, style: .continuous)
          .fill(Color.primary.opacity(0.08))
          .padding(.horizontal, OmniboxView.resultsInset)
          .matchedGeometryEffect(id: "selection", in: selection)
      }
    }
    .contentShape(Rectangle())
  }
}

// A favicon as Quicksilver draws one in a row: a tile with an app icon's corner (54 on 206), filled with
// a soft wash of the favicon's own colors, the favicon centered and sharp on it.
private struct FaviconTile: View {
  let image: NSImage
  let side: CGFloat

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: side * 54 / 206, style: .continuous)
    ZStack {
      Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
        .frame(width: side * 1.4, height: side * 1.4)
        .blur(radius: side * 0.16)
        .saturation(1.3)
      shape.fill(.white.opacity(0.42))
      Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
        .frame(width: side * 0.5, height: side * 0.5)
        .shadow(color: .black.opacity(0.18), radius: side * 0.025, y: side * 0.012)
    }
    .frame(width: side, height: side)
    .clipShape(shape)
    .overlay(shape.strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
  }
}
