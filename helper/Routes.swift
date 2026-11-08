// Routes: where a link from another app goes. The app is the default browser, so every such link
// passes through here first, with the app that sent it. A rule file names destinations for links by
// URL and sender; a link no rule claims opens as a mini browser in the front profile, as before.
//
// ~/Library/Application Support/Monochrome/routes.json, an array of rules, first match wins:
//
//   [
//     { "match": { "host": "atlassian.net" },                    "to": { "profile": "Nicholas (artifact.com)", "window": "same-site" } },
//     { "match": { "from": "com.tinyspeck.slackmacgap" },        "to": { "mini": true } },
//     { "match": { "host": "zoom.us", "path": "/j/*" },          "to": { "app": "us.zoom.xos" } },
//     { "match": { "host": "github.com" },                       "to": { "group": "Code" } },
//     { "match": { "url": "https://docs.google.com/document/*" }, "to": { "window": "same-site" } }
//   ]
//
// match: host (a bare name matches it and its subdomains; * is a wildcard), path, url (whole address,
// with *), from (the sender's bundle id, with *). Every given field has to match. A rule with no match
// matches everything.
// to: app (a bundle id: the link never reaches Chrome), profile (a name as Chrome's Profiles menu
// shows it), and then what the extension does there: mini (a mini browser, the default), window
// "same-site" (a tab already on that site, else a new tab in the front window) or "front" (a new tab
// at the top of the front window), group (a tab group's title; the tab joins it, in the window that
// has it, made in the front window if none does).
// The file is re-read when it changes. `Monochrome --routes [url [sender]]` prints the rules and,
// given a URL, the rule it would take.
import Foundation

struct Route {
  let match: [String: String]
  let to: [String: Any]
  let index: Int

  func matches(_ url: URL, from sender: String?) -> Bool {
    for (field, pattern) in match {
      let value: String?
      switch field {
      case "host": value = url.host?.lowercased()
      case "path": value = url.path.isEmpty ? "/" : url.path
      case "url": value = url.absoluteString
      case "from": value = sender
      default: log.error("routes: rule \(self.index) has an unknown match field \(field, privacy: .public)"); return false
      }
      guard let value else { return false }
      let ok = field == "host" && !pattern.contains("*")
        ? value == pattern.lowercased() || value.hasSuffix("." + pattern.lowercased())
        : Routes.glob(pattern, value)
      if !ok { return false }
    }
    return true
  }

  var description: String {
    let m = match.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
    let t = to.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
    return "rule \(index): \(m.isEmpty ? "(everything)" : m) -> \(t.isEmpty ? "mini" : t)"
  }
}

enum Routes {
  static var path: String {
    (Socket.path as NSString).deletingLastPathComponent + "/routes.json"
  }

  private static var rules: [Route] = []
  private static var modified: Date?

  static func all() -> [Route] {
    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    let stamp = attributes?[.modificationDate] as? Date
    if stamp != modified {
      modified = stamp
      rules = load()
      log.info("routes: \(rules.count) rules from \(path, privacy: .public)")
    }
    return rules
  }

  static func route(_ url: URL, from sender: String?) -> Route? {
    all().first { $0.matches(url, from: sender) }
  }

  // The file's rules as written, for the settings editor.
  static func rawRules() -> [[String: Any]] {
    guard let data = FileManager.default.contents(atPath: path) else { return [] }
    let json: Any
    do { json = try JSONSerialization.jsonObject(with: data) } catch {
      log.error("routes: \(path, privacy: .public) is not JSON: \(error.localizedDescription, privacy: .public)")
      return []
    }
    return json as? [[String: Any]] ?? (json as? [String: Any])?["rules"] as? [[String: Any]] ?? []
  }

  static func write(_ rules: [[String: Any]]) {
    guard let data = try? JSONSerialization.data(withJSONObject: rules, options: [.prettyPrinted, .sortedKeys]) else { return }
    do { try data.write(to: URL(fileURLWithPath: path), options: .atomic) } catch {
      log.error("routes: could not write \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }

  private static func load() -> [Route] {
    rawRules().enumerated().compactMap { i, rule in
      let match = (rule["match"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
      let to = rule["to"] as? [String: Any] ?? [:]
      return Route(match: match, to: to, index: i + 1)
    }
  }

  // * matches any run of characters; everything else is literal; case does not matter.
  static func glob(_ pattern: String, _ text: String) -> Bool {
    let parts = pattern.lowercased().split(separator: "*", omittingEmptySubsequences: false).map(String.init)
    let text = text.lowercased()
    guard parts.count > 1 else { return text == pattern.lowercased() }
    var position = text.startIndex
    for (i, part) in parts.enumerated() {
      if part.isEmpty { continue }
      if i == 0 {
        guard text.hasPrefix(part) else { return false }
        position = text.index(position, offsetBy: part.count)
      } else if i == parts.count - 1 {
        return text[position...].hasSuffix(part)
      } else {
        guard let found = text[position...].range(of: part) else { return false }
        position = found.upperBound
      }
    }
    return true
  }

  // --routes: the rules, and for a URL the one it takes.
  static func print(url: String?, from sender: String?) {
    let rules = all()
    Swift.print("\(path): \(rules.count) rule\(rules.count == 1 ? "" : "s")")
    for rule in rules { Swift.print("  " + rule.description) }
    guard let url else { return }
    guard let parsed = URL(string: url), parsed.host != nil else { return Swift.print("not a URL: \(url)") }
    Swift.print(url + (sender.map { " from \($0)" } ?? "") + " -> " + (route(parsed, from: sender)?.description ?? "no rule: mini browser in the front profile"))
  }
}
