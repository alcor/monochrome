// The native messaging host role (--host): Chrome spawns one when the extension connects, with the
// extension's messages on stdin and ours on stdout, each JSON after its length as a 4-byte native-endian
// integer. It relays those to and from the app half over the socket, and pings the extension every 20
// seconds so its service worker, which Chrome stops after 30 idle seconds, keeps the port open. When
// stdin closes, Chrome is gone and so is this process. No AppKit here: a process from the bundle that
// registered with the window server could be mistaken for the app by Launch Services.
import Foundation

enum Host {
  static let queue = DispatchQueue(label: "host")
  static var app: LineSocket?
  static var triedLaunch = false

  static func run() -> Never {
    signal(SIGPIPE, SIG_IGN)
    Thread.detachNewThread { readStdin() }
    let ping = DispatchSource.makeTimerSource(queue: queue)
    ping.schedule(deadline: .now() + 20, repeating: 20)
    ping.setEventHandler { write(frame: #"{"ping":true}"#) }
    ping.resume()
    queue.async { connect() }
    dispatchMain()
  }

  static func connect() {
    guard app == nil else { return }
    if let fd = Socket.connect(Socket.path) {
      let peer = LineSocket(fd: fd)
      peer.onLine = { write(frame: $0) }
      peer.onClose = { app = nil; queue.asyncAfter(deadline: .now() + 2) { connect() } }
      app = peer
      peer.start(queue: queue)
      return
    }
    if !triedLaunch && ProcessInfo.processInfo.environment["MONOCHROME_NO_LAUNCH"] == nil {
      triedLaunch = true
      let open = Process()
      open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      open.arguments = ["-g", "-b", App.bundleId]
      try? open.run()
    }
    queue.asyncAfter(deadline: .now() + 2) { connect() }
  }

  // Exactly count bytes from Chrome, or nil once it has closed the connection.
  static func read(_ count: Int) -> Data? {
    var data = Data()
    while data.count < count {
      let chunk = FileHandle.standardInput.readData(ofLength: count - data.count)
      if chunk.isEmpty { return nil }
      data += chunk
    }
    return data
  }

  static func readStdin() {
    while true {
      guard let header = read(4) else { exit(0) }
      let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
      guard let body = read(Int(length)) else { exit(0) }
      let line = String(decoding: body, as: UTF8.self)
      queue.async { app?.send(line) }
    }
  }

  static func write(frame json: String) {
    let data = Data(json.utf8)
    var length = UInt32(data.count)
    FileHandle.standardOutput.write(Data(bytes: &length, count: 4) + data)
  }
}
