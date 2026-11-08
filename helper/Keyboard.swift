// Keys by what they type, not where they are. The tap gets virtual keycodes, which name physical keys:
// 45 is the key that prints N on QWERTY and B on Dvorak. The active layout's table turns a keycode into
// its unmodified character and back, so ⌥⇧N is the key that prints n, and the ⌃. the tap synthesizes
// in fallback mode is the key that prints a period, whatever the layout. Tab and Escape are the same
// keycode everywhere. The table is rebuilt when the layout changes; an input source with no layout
// data (some input methods) leaves the QWERTY keycodes in place.
import Carbon

enum Keyboard {
  private static var characters: [Int64: String] = [:]
  private static var codes: [String: Int64] = [:]
  private static var stale = true
  // The table is rebuilt only after the system says the input source changed, not checked per keystroke.
  private static let layoutObserver: Void = {
    DistributedNotificationCenter.default().addObserver(forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                                                        object: nil, queue: .main) { _ in stale = true }
  }()

  static func character(_ code: Int64) -> String {
    refresh()
    return characters[code] ?? ""
  }

  static func code(for character: String, qwerty: Int64) -> Int64 {
    refresh()
    return codes[character] ?? qwerty
  }

  private static func refresh() {
    _ = layoutObserver
    guard stale, let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return }
    stale = false
    characters = [:]
    codes = [:]
    guard let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return }
    let data = Unmanaged<CFData>.fromOpaque(dataPointer).takeUnretainedValue() as Data
    data.withUnsafeBytes { bytes in
      let layout = bytes.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
      for code in 0..<128 {
        var deadKeys: UInt32 = 0
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, 4, &length, &buffer)
        guard status == noErr, length > 0 else { continue }
        let text = String(utf16CodeUnits: buffer, count: length)
        characters[Int64(code)] = text
        if codes[text] == nil { codes[text] = Int64(code) }
      }
    }
  }
}
