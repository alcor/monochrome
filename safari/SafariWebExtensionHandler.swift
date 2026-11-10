// The Safari extension's native side: what the extension's runtime.connectNative port and
// sendNativeMessage reach in Safari, in place of Chrome's native messaging host. Safari starts this app
// extension (a sandboxed process inside Monochrome.app) and hands it each message from the extension as
// one request. It understands two cases:
//   {"whoami": true}  answered here with the Safari profile the request came from, so the extension can
//                     tell which of the app's messages are for it (helper.js);
//   anything else     written to the app's Safari socket (SafariSocket in Bridge.swift) with that
//                     profile, one line per message, and answered with nothing.
// The app answers over SFSafariApplication.dispatchMessage, not through here. When the app is not
// listening, the containing app is opened in the background, at most every ten seconds, the way Chrome's
// host does with `open -g`; the message that found it down is dropped, and the app asks the extension
// to send everything again once it is up.
import AppKit
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
  func beginRequest(with context: NSExtensionContext) {
    let request = context.inputItems.first as? NSExtensionItem
    var profile = ""
    if #available(macOS 14.0, *) {
      profile = (request?.userInfo?[SFExtensionProfileKey] as? UUID)?.uuidString ?? ""
    }
    let message = request?.userInfo?[SFExtensionMessageKey]
    let response = NSExtensionItem()
    if let ask = message as? [String: Any], ask["whoami"] != nil {
      response.userInfo = [SFExtensionMessageKey: ["profile": profile]]
    } else if let message, let line = JSONLine.encode(["profile": profile, "message": message]) {
      Relay.send(line)
    }
    context.completeRequest(returningItems: [response], completionHandler: nil)
  }
}

// The connection to the app, kept for as long as Safari keeps this process.
enum Relay {
  private static let queue = DispatchQueue(label: "relay")
  private static var fd: Int32 = -1
  private static var launched = Date.distantPast

  static func send(_ line: String) {
    queue.sync {
      if write(line) { return }
      reconnect()
      if !write(line) { launchApp() }
    }
  }

  private static func reconnect() {
    if fd >= 0 { close(fd); fd = -1 }
    guard let socket = Socket.connect(SafariSocket.path) else { return }
    var on: Int32 = 1
    setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    fd = socket
  }

  private static func write(_ line: String) -> Bool {
    guard fd >= 0 else { return false }
    var data = Data(line.utf8)
    data.append(10)
    return data.withUnsafeBytes { bytes in
      var sent = 0
      while sent < data.count {
        let n = Darwin.write(fd, bytes.baseAddress! + sent, data.count - sent)
        if n <= 0 { return false }
        sent += n
      }
      return true
    }
  }

  // Monochrome.app/Contents/PlugIns/<this>.appex: three folders up.
  private static func launchApp() {
    guard Date().timeIntervalSince(launched) > 10 else { return }
    launched = Date()
    let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
      if let error { log.error("relay: could not open \(app.path, privacy: .public): \(error.localizedDescription, privacy: .public)") }
    }
  }
}
