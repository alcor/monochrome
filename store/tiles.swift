// The store's promo tiles, rendered from the icon: swift store/tiles.swift <icons/128.png or .icns> <out dir>
// Small tile 440 by 280 and marquee 1400 by 560, the name beside the icon on the demo backdrop's gradient.
import AppKit

let iconPath = CommandLine.arguments[1], outDir = CommandLine.arguments[2]
guard let icon = NSImage(contentsOfFile: iconPath) else { fatalError("no icon at \(iconPath)") }

func tile(width: CGFloat, height: CGFloat, iconSize: CGFloat, nameSize: CGFloat, lineSize: CGFloat, tagline: String) -> Data {
  let image = NSImage(size: NSSize(width: width, height: height))
  image.lockFocus()
  let bounds = NSRect(x: 0, y: 0, width: width, height: height)
  NSGradient(colors: [NSColor(red: 0.85, green: 0.89, blue: 0.93, alpha: 1), NSColor(red: 0.95, green: 0.93, blue: 0.89, alpha: 1),
                      NSColor(red: 0.90, green: 0.87, blue: 0.84, alpha: 1)])!.draw(in: bounds, angle: -35)
  let title = NSAttributedString(string: "Monochrome", attributes: [.font: NSFont.systemFont(ofSize: nameSize, weight: .semibold),
                                                                      .foregroundColor: NSColor(white: 0.13, alpha: 1)])
  let line = NSAttributedString(string: tagline,
                                attributes: [.font: NSFont.systemFont(ofSize: lineSize), .foregroundColor: NSColor(white: 0.35, alpha: 1)])
  let textWidth = max(title.size().width, line.size().width)
  let gap: CGFloat = iconSize * 0.25
  let total = iconSize + gap + textWidth
  let x = (width - total) / 2
  icon.draw(in: NSRect(x: x, y: (height - iconSize) / 2, width: iconSize, height: iconSize))
  let textX = x + iconSize + gap
  let blockHeight = title.size().height + 6 + line.size().height
  let top = (height + blockHeight) / 2
  title.draw(at: NSPoint(x: textX, y: top - title.size().height))
  line.draw(at: NSPoint(x: textX, y: top - title.size().height - 6 - line.size().height))
  image.unlockFocus()
  let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
  rep.size = NSSize(width: width, height: height)
  return rep.representation(using: .png, properties: [:])!
}

// Drawn at 1x: the store wants exact pixel sizes.
NSScreen.screens.forEach { _ in }
try! tile(width: 440, height: 280, iconSize: 112, nameSize: 32, lineSize: 13, tagline: "The best Arc features in Chrome").write(to: URL(fileURLWithPath: outDir + "/small-tile.png"))
try! tile(width: 1400, height: 560, iconSize: 256, nameSize: 72, lineSize: 26, tagline: "The best Arc features in Chrome").write(to: URL(fileURLWithPath: outDir + "/marquee-tile.png"))
print("tiles written to \(outDir)")
