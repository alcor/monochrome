// The link between the two halves of the helper. Chrome spawns this binary as a native messaging host
// (--host, see Host.swift) for the extension's one open port; the app half (App.swift) is launched by
// the login item and owns the event tap and the panels. They meet on a Unix socket the app listens on,
// one JSON object per line in each direction. The host is a relay and understands none of it.
//
// Safari has no hosts: the extension's port reaches the app extension inside Monochrome.app
// (safari/SafariWebExtensionHandler.swift), a sandboxed process of its own, which writes each message
// to a second socket the app listens on in the app group's container (SafariSocket), one line per
// message wrapped with the Safari profile it came from. The app answers through
// SFSafariApplication.dispatchMessage (Safari.swift). This file is compiled into both targets.
import Foundation
import os

let log = Logger(subsystem: "com.artifact.monochrome", category: "helper")

enum Socket {
  static var path: String {
    if let p = ProcessInfo.processInfo.environment["MONOCHROME_SOCKET"] { return p }
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = support.appendingPathComponent("Monochrome")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("helper.sock").path
  }

  static func address(_ path: String) -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    _ = withUnsafeMutablePointer(to: &addr.sun_path) {
      $0.withMemoryRebound(to: CChar.self, capacity: capacity) { strncpy($0, path, capacity - 1) }
    }
    return addr
  }

  static func connect(_ path: String) -> Int32? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var addr = address(path)
    let ok = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    if ok != 0 { close(fd); return nil }
    return fd
  }
}

// Where the app's messages to one copy of the extension go: Chrome's host socket, or Safari (SafariPeer).
protocol Peer: AnyObject {
  func send(_ line: String)
}

// The Safari relay's socket, in the app group's container: the one place both the sandboxed app
// extension and the app can reach. Lines on it are {"profile": "<Safari profile UUID or empty>",
// "message": <the extension's message>}.
enum SafariSocket {
  static let appGroup = "TVA9Z8LD95.com.artifact.monochrome"

  static var path: String {
    if let p = ProcessInfo.processInfo.environment["MONOCHROME_SAFARI_SOCKET"] { return p }
    // The app extension is sandboxed and gets its container from the entitlement; the app is not, and an
    // unsigned build has no entitlement, so it falls back to where macOS puts group containers.
    let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Group Containers/\(appGroup)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("safari.sock").path
  }
}

// One connected peer: lines in through onLine, lines out through send.
final class LineSocket: Peer {
  let fd: Int32
  var onLine: (String) -> Void = { _ in }
  var onClose: () -> Void = {}
  private var buffer = Data()
  private var source: DispatchSourceRead?

  init(fd: Int32) { self.fd = fd }

  func start(queue: DispatchQueue) {
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
    source.setEventHandler { [weak self] in self?.readAvailable() }
    source.setCancelHandler { [weak self] in
      guard let self else { return }
      close(self.fd)
      self.onClose()
    }
    self.source = source
    source.resume()
  }

  private func readAvailable() {
    var chunk = [UInt8](repeating: 0, count: 1 << 16)
    let n = read(fd, &chunk, chunk.count)
    if n <= 0 { return source?.cancel() ?? () }
    buffer.append(chunk, count: n)
    while let newline = buffer.firstIndex(of: 10) {
      let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
      buffer.removeSubrange(buffer.startIndex...newline)
      onLine(line)
    }
  }

  func send(_ line: String) {
    var data = Data(line.utf8)
    data.append(10)
    data.withUnsafeBytes { bytes in
      var sent = 0
      while sent < data.count {
        let n = write(fd, bytes.baseAddress! + sent, data.count - sent)
        if n <= 0 { return }
        sent += n
      }
    }
  }

  func stop() { source?.cancel() }
}

final class SocketServer {
  var onConnection: (LineSocket) -> Void = { _ in }
  private var source: DispatchSourceRead?

  init?(path: String, queue: DispatchQueue) {
    unlink(path)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var addr = Socket.address(path)
    let bound = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard bound == 0, listen(fd, 4) == 0 else { close(fd); return nil }
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
    source.setEventHandler { [weak self] in
      let client = accept(fd, nil, nil)
      guard client >= 0, let self else { return }
      let peer = LineSocket(fd: client)
      self.onConnection(peer)
      peer.start(queue: queue)
    }
    self.source = source
    source.resume()
  }
}

enum JSONLine {
  static func encode(_ object: Any) -> String? {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
    return String(decoding: data, as: UTF8.self)
  }
  static func decode(_ line: String) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
  }
}
