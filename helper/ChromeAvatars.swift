// Profile pictures for the Settings list. Chrome's Profiles menu carries no images over Accessibility,
// so they come from Chrome's own files: Local State's profile.info_cache names each profile folder,
// and a signed-in profile keeps its account picture there as "Google Profile Picture.png". A profile
// without one gets its highlight color behind its initial. macOS protects Chrome's folder as another
// app's data (kTCCServiceSystemPolicyAppDataDetailed) and refused the read on macOS 27.2 without
// showing a prompt; then every profile gets the letter avatar the profile HUD uses. Full Disk Access
// for Monochrome should allow it; that is untested.
import AppKit
import SwiftUI

struct ProfileLook {
  var image: NSImage?
  var color: Color?
}

enum ChromeAvatars {
  private struct Entry { let names: [String]; let look: ProfileLook }
  private static var cache: [String: (read: Date, entries: [Entry])] = [:]

  // folder: Chrome's folder under Application Support (Install.hostFolders). title: the profile's
  // name as Chrome's window titles and Profiles menu show it.
  static func look(folder: String, title: String) -> ProfileLook {
    entries(folder).first { $0.names.contains { title == $0 || title.hasPrefix($0 + " (") } }?.look ?? ProfileLook()
  }

  private static func entries(_ folder: String) -> [Entry] {
    if let cached = cache[folder], Date().timeIntervalSince(cached.read) < 30 { return cached.entries }
    let root = Install.support.appendingPathComponent(folder)
    var entries: [Entry] = []
    do {
      let data = try Data(contentsOf: root.appendingPathComponent("Local State"))
      let state = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      let info = (state?["profile"] as? [String: Any])?["info_cache"] as? [String: [String: Any]] ?? [:]
      entries = info.map { directory, profile in
        let names = ["name", "gaia_name", "shortcut_name"].compactMap { profile[$0] as? String }.filter { !$0.isEmpty }
        var look = ProfileLook()
        if let file = profile["gaia_picture_file_name"] as? String, !file.isEmpty, profile["use_gaia_picture"] as? Bool != false {
          look.image = NSImage(contentsOf: root.appendingPathComponent(directory).appendingPathComponent(file))
        }
        if let argb = profile["profile_highlight_color"] as? Int {
          let value = UInt32(truncatingIfNeeded: argb)
          look.color = Color(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
        }
        return Entry(names: names, look: look)
      }
    } catch {
      log.info("avatars: \(folder, privacy: .public) Local State not read: \(error.localizedDescription, privacy: .public)")
    }
    cache[folder] = (Date(), entries)
    return entries
  }
}

// A round avatar: the picture when there is one, else the name's initial on its color, or on a hue
// hashed from the name, the same one the profile HUD draws.
struct ProfileAvatar: View {
  let name: String
  var look = ProfileLook()
  let size: CGFloat

  var body: some View {
    ZStack {
      if let image = look.image {
        Image(nsImage: image).resizable().scaledToFill()
      } else {
        Circle().fill(look.color ?? Self.hue(name))
        Text(String(name.prefix(1)).uppercased())
          .font(.system(size: size * 0.45, weight: .semibold))
          .foregroundStyle(.white)
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
  }

  static func hue(_ name: String) -> Color {
    let hash = name.unicodeScalars.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1.value) }
    return Color(hue: Double(abs(hash) % 360) / 360, saturation: 0.55, brightness: 0.75)
  }
}
