// The install panel for the Chrome extension, shown from the settings window's Browser tab and the
// mini browser's bar.
import AppKit

// Install the extension: a small floating panel with the copy of the extension inside the app as a
// folder to drag onto chrome://extensions, and the steps. A standard window at a high level, so it stays
// over Chrome while the user turns on Developer mode and drops the folder, in each profile, and so it is a
// key, active window the drag can begin from. The Browser tab's Install Extension… button and the mini
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
