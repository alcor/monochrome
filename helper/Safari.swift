// The app's side of the Safari transport (see Bridge.swift): messages to the extension go through
// SFSafariApplication.dispatchMessage, which reaches the extension's open native port as
// {name, userInfo}. dispatchMessage names no profile, so a message for one Safari profile carries that
// profile's id as safariProfile and the other profiles' copies of the extension ignore it (helper.js).
import AppKit
import SafariServices

enum Safari {
  static let bundleId = "com.apple.Safari"
  static let extensionId = "com.artifact.monochrome.extension"

  static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty }

  static func dispatch(_ message: [String: Any]) {
    SFSafariApplication.dispatchMessage(withName: "monochrome", toExtensionWithIdentifier: extensionId, userInfo: message) { error in
      if let error { log.info("safari: dispatch failed: \(error.localizedDescription, privacy: .public)") }
    }
  }

  // Safari Settings → Extensions with Monochrome selected, where it is turned on and given its websites.
  static func showExtensionSettings() {
    SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionId) { error in
      if let error { log.error("safari: could not open the extension's settings: \(error.localizedDescription, privacy: .public)") }
    }
  }
}

// One Safari profile's copy of the extension, as a connection's peer. profile is Safari's id for it
// (SFExtensionProfileKey), empty when Safari gave none.
final class SafariPeer: Peer {
  let profile: String
  var lastHeard = Date()

  init(profile: String) { self.profile = profile }

  func send(_ line: String) {
    guard var message = JSONLine.decode(line) else { return }
    if !profile.isEmpty { message["safariProfile"] = profile }
    Safari.dispatch(message)
  }

  // How the settings window names it: Safari gives an id, not the profile's name.
  var label: String { profile.isEmpty ? "Safari" : "Safari profile \(profile.prefix(8))" }
}
