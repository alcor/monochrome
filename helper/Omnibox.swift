// ⌘L and ⌘T in the browser in front: a search box in Quicksilver's style (OmniboxView.swift) in place of
// the address bar, for the profile whose window is in front. ⌘L edits the front tab's address, ⌘T opens
// a new tab; ⌥Return flips which. What it draws on, as Chrome's address bar does:
// - the profile's history and bookmarks, the last 90 days of history, up to 5000 pages. On Chrome the
//   extension sends them (omnibox.js); Safari gives extensions neither, so the app reads the profile's
//   History.db and Bookmarks.plist itself, which needs Full Disk Access.
// - the profile's open tabs, offered as Switch to Tab.
// - Google's search suggestions for what has been typed. What is typed goes to Google as it is typed,
//   as with Chrome's own search suggestions.
// The top row is the inline completion when history has one (a host typed or visited before, completed
// in gray as typed: Tab or → takes it), else what was typed, as an address or a search.
import AppKit
import SQLite3

struct OmniboxPage {
  let url: String, title: String, visits: Int, typed: Int, last: Date, bookmarked: Bool
  let stripped: String // lowercased, without the scheme and www.: what typing is matched against
  let host: String

  init(url: String, title: String, visits: Int, typed: Int, last: Date, bookmarked: Bool) {
    self.url = url
    self.title = title
    self.visits = visits
    self.typed = typed
    self.last = last
    self.bookmarked = bookmarked
    stripped = Omnibox.strip(url)
    host = String(stripped.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
  }

  // Visits and typed visits, on a log scale so a page opened a thousand times does not bury everything,
  // weighted toward the last month.
  var frecency: Double {
    let days = max(0, -last.timeIntervalSinceNow / 86400)
    let recency = 1 / (1 + days / 30)
    return (log2(1 + Double(visits)) + 2 * log2(1 + Double(typed)) + (bookmarked ? 2 : 0)) * (0.3 + 0.7 * recency)
  }
}

struct OmniboxTab { let id: Int, url: String, title: String }

struct OmniboxRow: Identifiable, Equatable {
  enum Kind: Equatable { case url(String), search(String), tab(Int) }
  let kind: Kind
  let title: String
  let detail: String?
  let page: String? // the page whose favicon the row shows; nil shows `symbol`
  let symbol: String

  var id: String {
    switch kind {
    case .url(let url): "u" + Omnibox.strip(url)
    case .search(let text): "s" + text.lowercased()
    case .tab(let id): "t\(id)"
    }
  }
}

struct OmniboxSuggestion { let text: String, url: String?, description: String }

final class OmniboxModel: ObservableObject {
  @Published var rows: [OmniboxRow] = []
  @Published var selected = 0
  @Published var revealed = false
  @Published var icons: [String: NSImage] = [:] // by page URL
  @Published var newTab = true
  @Published var shown = false

  var browser = Browser.chrome
  var pages: [OmniboxPage] = [] { didSet { indexHosts() } }
  var tabs: [OmniboxTab] = []
  var current: OmniboxTab?
  private(set) var query = ""
  private var suggestions: (query: String, items: [OmniboxSuggestion]) = ("", [])
  private var hosts: [String: (score: Double, root: String?, eligible: Bool, scheme: String)] = [:]
  private var iconsAsked = Set<String>()

  var onGo: ([String: Any]) -> Void = { _ in }
  var onDismiss: () -> Void = {}
  var onNeedIcons: ([String]) -> Void = { _ in }
  var onSuggest: (String) -> Void = { _ in }
  var onCompletionChange: () -> Void = {} // the field redraws its gray text

  // The gray text after what was typed, from the top row; empty when there is none.
  private(set) var completion = ""
  private var completionURL: String?

  func reset(newTab: Bool, browser: Browser) {
    self.newTab = newTab
    self.browser = browser
    pages = []
    tabs = []
    current = nil
    query = ""
    completion = ""
    completionURL = nil
    suggestions = ("", [])
    iconsAsked = []
    selected = 0
    revealed = newTab
    rebuild()
  }

  // A new list from what is typed. allowCompletion is false right after a deletion, so deleting the
  // gray text does not bring it straight back, as in Chrome.
  func update(query text: String, allowCompletion: Bool) {
    query = text
    revealed = true
    selected = 0
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    (completion, completionURL) = allowCompletion ? inlineCompletion(for: trimmed) : ("", nil)
    rebuild()
    if !trimmed.isEmpty { onSuggest(trimmed) }
  }

  func acceptCompletion() {
    query += completion
    completion = ""
    rebuild()
    onSuggest(query.trimmingCharacters(in: .whitespaces))
  }

  func receive(suggestions items: [OmniboxSuggestion], for text: String) {
    guard text == query.trimmingCharacters(in: .whitespaces) else { return }
    suggestions = (text, items)
    let id = rows.indices.contains(selected) ? rows[selected].id : nil
    rebuild()
    if let id, let index = rows.firstIndex(where: { $0.id == id }) { selected = index }
  }

  func dataArrived() {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    if !trimmed.isEmpty, completion.isEmpty, completionURL == nil {
      (completion, completionURL) = inlineCompletion(for: trimmed)
      if !completion.isEmpty { onCompletionChange() }
    }
    rebuild()
  }

  func move(_ step: Int) {
    guard !rows.isEmpty else { return }
    revealed = true
    selected = (selected + step + rows.count) % rows.count
  }

  func commit(at index: Int? = nil, flip: Bool = false) {
    let index = index ?? selected
    guard rows.indices.contains(index) else { return onDismiss() }
    var go: [String: Any] = ["newTab": newTab != flip]
    switch rows[index].kind {
    case .url(let url): go["url"] = url
    case .search(let text): go["text"] = text
    case .tab(let id): go["tab"] = id
    }
    onGo(go)
  }

  // MARK: - Ranking

  private func indexHosts() {
    var stats: [String: (score: Double, root: String?, eligible: Bool, scheme: String)] = [:]
    for page in pages where !page.host.isEmpty {
      var stat = stats[page.host] ?? (0, nil, false, page.url.lowercased().hasPrefix("http://") ? "http" : "https")
      stat.score += page.frecency
      // A host is completed inline once it has been typed, bookmarked or visited twice: a single
      // click-through from a search is not a reason to finish someone's typing.
      stat.eligible = stat.eligible || page.typed > 0 || page.bookmarked || page.visits > 1
      let path = page.stripped.dropFirst(page.host.count)
      if path.isEmpty || path == "/" { stat.root = page.url }
      stats[page.host] = stat
    }
    hosts = stats
  }

  // What history would finish typing to: with no slash typed, the most used host it starts; with one,
  // the most used page whose address it starts.
  private func inlineCompletion(for text: String) -> (String, String?) {
    guard !text.isEmpty, !text.contains(" ") else { return ("", nil) }
    let typed = Omnibox.strip(text)
    guard !typed.isEmpty else { return ("", nil) }
    if !typed.contains("/") {
      guard let best = hosts.filter({ $0.key.hasPrefix(typed) && $0.value.eligible }).max(by: { $0.value.score < $1.value.score })
      else { return ("", nil) }
      // The host's own root page when history has it, else its root on the scheme its pages use.
      return (String(best.key.dropFirst(typed.count)), best.value.root ?? best.value.scheme + "://" + best.key + "/")
    }
    guard let best = pages.filter({ $0.stripped.hasPrefix(typed) && ($0.typed > 0 || $0.bookmarked || $0.visits > 1) })
      .max(by: { $0.frecency < $1.frecency })
    else { return ("", nil) }
    return (String(best.stripped.dropFirst(typed.count)), best.url)
  }

  private func rebuild() {
    let text = query.trimmingCharacters(in: .whitespaces)
    var rows: [OmniboxRow] = []
    var seen = Set<String>()
    func add(_ row: OmniboxRow) { if seen.insert(Self.key(row)).inserted { rows.append(row) } }

    if text.isEmpty {
      // ⌘T before typing: the most used sites, one page each.
      var hostsShown = Set<String>()
      for page in pages.sorted(by: { $0.frecency > $1.frecency }) where hostsShown.count < 6 && hostsShown.insert(page.host).inserted {
        add(pageRow(page))
      }
      publish(rows)
      return
    }

    let typedURL = Omnibox.url(from: text)
    if let url = completionURL, !completion.isEmpty {
      let page = pages.first { $0.url == url }
      add(OmniboxRow(kind: .url(url), title: page.map(Self.title) ?? Omnibox.display(url), detail: Omnibox.display(url), page: url, symbol: "globe"))
    } else if let url = typedURL {
      add(OmniboxRow(kind: .url(url), title: Omnibox.display(url), detail: nil, page: url, symbol: "globe"))
    }
    add(searchRow(text))

    let terms = text.lowercased().split(separator: " ").map(String.init)
    let current = self.current?.id
    for tab in tabs where tab.id != current && Self.matches(terms, title: tab.title, url: Omnibox.strip(tab.url)) && rows.count < 4 {
      add(OmniboxRow(kind: .tab(tab.id), title: tab.title.isEmpty ? Omnibox.display(tab.url) : tab.title,
                     detail: "Switch to tab · " + Omnibox.display(tab.url), page: tab.url, symbol: "macwindow"))
    }

    let scored = pages.compactMap { page -> (OmniboxPage, Double)? in
      guard let quality = Self.quality(terms, page) else { return nil }
      return (page, quality * (1 + page.frecency))
    }
    for (page, _) in scored.sorted(by: { $0.1 > $1.1 }).prefix(12) where rows.count < 8 { add(pageRow(page)) }

    if suggestions.query == text {
      var added = 0
      for s in suggestions.items where added < 4 && s.text.lowercased() != text.lowercased() {
        let before = rows.count
        if let url = s.url {
          add(OmniboxRow(kind: .url(url), title: s.description.isEmpty ? Omnibox.display(url) : s.description, detail: Omnibox.display(url), page: url, symbol: "globe"))
        } else {
          add(OmniboxRow(kind: .search(s.text), title: s.text, detail: nil, page: nil, symbol: "magnifyingglass"))
        }
        added += rows.count - before
      }
    }
    // A search typed as words comes first; an address typed or completed keeps the top.
    if typedURL == nil && completion.isEmpty, let index = rows.firstIndex(where: { $0.kind == .search(text) }), index > 0 {
      rows.insert(rows.remove(at: index), at: 0)
    }
    publish(rows)
  }

  private func publish(_ new: [OmniboxRow]) {
    rows = new
    if !rows.indices.contains(selected) { selected = 0 }
    let wanted = rows.compactMap(\.page).filter { icons[$0] == nil && !iconsAsked.contains($0) }
    if !wanted.isEmpty {
      iconsAsked.formUnion(wanted)
      onNeedIcons(wanted)
    }
  }

  private func searchRow(_ text: String) -> OmniboxRow {
    OmniboxRow(kind: .search(text), title: text, detail: browser == .safari ? "Search with Google" : "Search", page: nil, symbol: "magnifyingglass")
  }

  private func pageRow(_ page: OmniboxPage) -> OmniboxRow {
    OmniboxRow(kind: .url(page.url), title: Self.title(page), detail: Omnibox.display(page.url), page: page.url, symbol: page.bookmarked ? "star" : "clock")
  }

  private static func title(_ page: OmniboxPage) -> String { page.title.isEmpty ? Omnibox.display(page.url) : page.title }

  // The same page is listed once: its address without the scheme, www., fragment or a trailing slash.
  private static func key(_ row: OmniboxRow) -> String {
    guard case .url(let url) = row.kind else { return row.id }
    var s = Omnibox.strip(url)
    if let hash = s.firstIndex(of: "#") { s = String(s[..<hash]) }
    while s.hasSuffix("/") { s.removeLast() }
    return "u" + s
  }

  private static func matches(_ terms: [String], title: String, url: String) -> Bool {
    let title = title.lowercased()
    return terms.allSatisfy { title.contains($0) || url.contains($0) }
  }

  // Every term in the title or the address, or nil. A term at the start of the address counts most,
  // then one at the start of a word in the title, then anywhere.
  private static func quality(_ terms: [String], _ page: OmniboxPage) -> Double? {
    let title = page.title.lowercased()
    var total = 0.0
    for term in terms {
      if page.stripped.hasPrefix(term) || page.host.contains("." + term) { total += 3 }
      else if title.hasPrefix(term) || title.contains(" " + term) { total += 2 }
      else if title.contains(term) || page.stripped.contains(term) { total += 1 }
      else { return nil }
    }
    return total / Double(terms.count)
  }
}

enum Omnibox {
  // History with bookmarks marked, and the bookmarks never visited after it.
  static func merge(history: [OmniboxPage], bookmarks: [(url: String, title: String)]) -> [OmniboxPage] {
    let marked = Set(bookmarks.map(\.url))
    var pages = history.map { p in
      marked.contains(p.url) ? OmniboxPage(url: p.url, title: p.title, visits: p.visits, typed: p.typed, last: p.last, bookmarked: true) : p
    }
    let inHistory = Set(history.map(\.url))
    var added = Set<String>()
    pages += bookmarks.filter { !inHistory.contains($0.url) && added.insert($0.url).inserted }
      .map { OmniboxPage(url: $0.url, title: $0.title, visits: 0, typed: 0, last: .distantPast, bookmarked: true) }
    return pages
  }

  static func strip(_ url: String) -> String {
    var s = url.lowercased()
    for scheme in ["https://", "http://"] where s.hasPrefix(scheme) { s.removeFirst(scheme.count) }
    if s.hasPrefix("www.") { s.removeFirst(4) }
    return s
  }

  // An address as the rows show it: no scheme, no www., no trailing slash, percent escapes decoded.
  static func display(_ url: String) -> String {
    var s = url
    for scheme in ["https://", "http://"] where s.lowercased().hasPrefix(scheme) { s.removeFirst(scheme.count) }
    if s.lowercased().hasPrefix("www.") { s.removeFirst(4) }
    if s.hasSuffix("/") && s.filter({ $0 == "/" }).count == 1 { s.removeLast() }
    return s.removingPercentEncoding ?? s
  }

  // The rules the mini browser's address field uses (asUrl in mini-browser.js): a scheme, or no spaces
  // and a dot before a two-letter ending, localhost or an IP address.
  static func url(from text: String) -> String? {
    if text.range(of: #"^[a-zA-Z][a-zA-Z0-9+.-]*://"#, options: .regularExpression) != nil { return text }
    if text.contains(where: \.isWhitespace) { return nil }
    if text.range(of: #"^(localhost|\d{1,3}(\.\d{1,3}){3})(:\d+)?(/|$)"#, options: .regularExpression) != nil
      || text.range(of: #"^[^/]+\.[a-zA-Z]{2,}(:\d+)?(/|$)"#, options: .regularExpression) != nil {
      return (text.hasPrefix("localhost") ? "http://" : "https://") + text
    }
    return nil
  }

  // The suggestions Chrome's own address bar gets from Google: queries, and sites (NAVIGATION) with
  // their titles. ie and oe ask for UTF-8; without them the titles come back in Latin-1.
  private static var suggestTask: URLSessionDataTask?
  static func suggest(_ text: String, done: @escaping ([OmniboxSuggestion]) -> Void) {
    suggestTask?.cancel()
    var components = URLComponents(string: "https://www.google.com/complete/search")!
    components.queryItems = [.init(name: "client", value: "chrome"), .init(name: "ie", value: "utf-8"), .init(name: "oe", value: "utf-8"), .init(name: "q", value: text)]
    guard let url = components.url else { return }
    let task = URLSession.shared.dataTask(with: url) { data, _, _ in
      guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [Any], json.count > 1,
            let texts = json[1] as? [String] else { return }
      let descriptions = json.count > 2 ? json[2] as? [String] ?? [] : []
      let types = (json.count > 4 ? json[4] as? [String: Any] : nil)?["google:suggesttype"] as? [String] ?? []
      let items = texts.enumerated().map { i, s in
        OmniboxSuggestion(text: s, url: types.indices.contains(i) && types[i] == "NAVIGATION" ? s : nil,
                          description: descriptions.indices.contains(i) ? descriptions[i] : "")
      }
      DispatchQueue.main.async { done(items) }
    }
    suggestTask = task
    task.resume()
  }

  // Favicons for Safari rows, from Google's favicon service by the page's origin, as the Safari
  // extension's switcher icons are (Safari has no favicon cache an extension can read).
  static func googleFavicons(_ pages: [String], done: @escaping (String, NSImage) -> Void) {
    for page in pages {
      guard let origin = URL(string: page).flatMap({ u in u.host.map { (u.scheme ?? "https") + "://" + $0 } }),
            var components = URLComponents(string: "https://www.google.com/s2/favicons") else { continue }
      components.queryItems = [.init(name: "domain_url", value: origin), .init(name: "sz", value: "64")]
      guard let url = components.url else { continue }
      URLSession.shared.dataTask(with: url) { data, _, _ in
        guard let data, let image = NSImage(data: data) else { return }
        DispatchQueue.main.async { done(page, image) }
      }.resume()
    }
  }
}

// Safari's history and bookmarks for one profile, read from its files (databaseURL has where); the
// database is copied first, since Safari holds it open and writes to it. Kept for a minute per profile.
enum SafariHistory {
  private static var cache: [String: (read: Date, pages: [OmniboxPage])] = [:]
  private static let queue = DispatchQueue(label: "com.artifact.monochrome.safari-history")

  static func load(profile: String, done: @escaping ([OmniboxPage]) -> Void) {
    if let cached = cache[profile], Date().timeIntervalSince(cached.read) < 60 { return done(cached.pages) }
    queue.async {
      let pages = Omnibox.merge(history: readHistory(profile: profile), bookmarks: readBookmarks())
      DispatchQueue.main.async {
        cache[profile] = (Date(), pages)
        done(pages)
      }
    }
  }

  private static var library: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari") }

  private static var container: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/com.apple.Safari/Data/Library/Safari")
  }

  // The default profile's database is History.db in ~/Library/Safari; another profile's is in the
  // container's Profiles/<folder>. The folder is named for the profile's server id in SafariTabs.db,
  // not for the id Safari gives the extension, which appears in none of Safari's files. So the profile
  // is found by the folder named for the extension's id if there is one, else by the name the app learned
  // for it (SafariProfiles.learned) among SafariTabs.db's profiles, else as the only profile there is.
  static func databaseURL(profile: String) -> URL? {
    if profile.isEmpty { return library.appendingPathComponent("History.db") }
    let profiles = container.appendingPathComponent("Profiles")
    let folders = (try? FileManager.default.contentsOfDirectory(atPath: profiles.path))?.filter {
      FileManager.default.fileExists(atPath: profiles.appendingPathComponent($0).appendingPathComponent("History.db").path)
    } ?? []
    let known = safariProfiles()
    let name = SafariProfiles.learned[profile]
    let folder = folders.first { $0.caseInsensitiveCompare(profile) == .orderedSame }
      ?? name.flatMap { name in known.first { $0.title == name }?.folder }.flatMap { f in folders.first { $0.caseInsensitiveCompare(f) == .orderedSame } }
      ?? (folders.count == 1 ? folders[0] : nil)
    guard let folder else {
      log.info("omnibox: no History.db for Safari profile \(profile, privacy: .public) (\(name ?? "name not learned", privacy: .public)) among \(folders.count) profile folders")
      return nil
    }
    return profiles.appendingPathComponent(folder).appendingPathComponent("History.db")
  }

  // Safari's profiles other than the default, by title and the server id their data folder is named for.
  static func safariProfiles() -> [(title: String, folder: String)] {
    query(copyOf: container.appendingPathComponent("SafariTabs.db"),
          sql: "SELECT title, server_id FROM bookmarks WHERE type = 1 AND subtype = 2 AND server_id IS NOT NULL AND external_uuid != 'DefaultProfile'") { row in
      guard let title = text(row, 0), let folder = text(row, 1) else { return nil }
      return (title, folder)
    }
  }

  // Rows from a copy of a database Safari holds open (with its write-ahead log), or none.
  static func text(_ row: OpaquePointer?, _ column: Int32) -> String? { sqlite3_column_text(row, column).map { String(cString: $0) } }

  static func query<T>(copyOf source: URL, sql: String, bind: ((OpaquePointer?) -> Void)? = nil, _ map: (OpaquePointer?) -> T?) -> [T] {
    let fm = FileManager.default
    let folder = fm.temporaryDirectory.appendingPathComponent("omnibox-" + UUID().uuidString)
    defer { try? fm.removeItem(at: folder) }
    do {
      try fm.createDirectory(at: folder, withIntermediateDirectories: true)
      for suffix in ["", "-wal", "-shm"] where fm.fileExists(atPath: source.path + suffix) {
        try fm.copyItem(atPath: source.path + suffix, toPath: folder.appendingPathComponent(source.lastPathComponent + suffix).path)
      }
    } catch {
      log.error("omnibox: could not copy \(source.path, privacy: .public): \(error.localizedDescription, privacy: .public) (Full Disk Access?)")
      return []
    }
    var db: OpaquePointer?
    guard sqlite3_open_v2(folder.appendingPathComponent(source.lastPathComponent).path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { return [] }
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      log.error("omnibox: query on \(source.lastPathComponent, privacy: .public) failed: \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
      return []
    }
    defer { sqlite3_finalize(statement) }
    bind?(statement)
    var rows: [T] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      if let row = map(statement) { rows.append(row) }
    }
    return rows
  }

  static func readHistory(profile: String) -> [OmniboxPage] {
    guard let source = databaseURL(profile: profile) else { return [] }
    // A visit's title is the page's at that visit; MAX picks the latest visit's row, title included.
    let sql = """
      SELECT i.url, v.title, i.visit_count, MAX(v.visit_time) FROM history_items i
      JOIN history_visits v ON v.history_item = i.id
      WHERE v.visit_time > ? AND (i.url LIKE 'http://%' OR i.url LIKE 'https://%')
      GROUP BY i.id ORDER BY MAX(v.visit_time) DESC LIMIT 5000
      """
    let since = Date().addingTimeInterval(-90 * 86400).timeIntervalSinceReferenceDate
    let pages: [OmniboxPage] = query(copyOf: source, sql: sql, bind: { sqlite3_bind_double($0, 1, since) }) { row in
      guard let url = text(row, 0) else { return nil }
      return OmniboxPage(url: url, title: text(row, 1) ?? "", visits: Int(sqlite3_column_int(row, 2)), typed: 0,
                         last: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(row, 3)), bookmarked: false)
    }
    log.info("omnibox: \(pages.count) Safari history pages for \(profile.isEmpty ? "the default profile" : profile, privacy: .public) from \(source.deletingLastPathComponent().lastPathComponent, privacy: .public)")
    return pages
  }

  // Safari's bookmarks are shared by its profiles.
  static func readBookmarks() -> [(url: String, title: String)] {
    guard let data = try? Data(contentsOf: library.appendingPathComponent("Bookmarks.plist")),
          let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [] }
    var found: [(String, String)] = []
    func walk(_ node: [String: Any]) {
      if let url = node["URLString"] as? String, url.hasPrefix("http") {
        found.append((url, (node["URIDictionary"] as? [String: Any])?["title"] as? String ?? ""))
      }
      for child in node["Children"] as? [[String: Any]] ?? [] { walk(child) }
    }
    walk(root)
    return found
  }
}
