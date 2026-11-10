// The store's 128 by 128 icon from the full-bleed source: swift store/icon.swift store/icon-source.png store/icon-128.png
// The store asks for 96 by 96 artwork with 16 transparent pixels on each side.
import AppKit

let source = NSImage(contentsOfFile: CommandLine.arguments[1])!
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current!.imageInterpolation = .high
source.draw(in: NSRect(x: 16, y: 16, width: 96, height: 96))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
