import AppKit
import Combine
import DeadlineCore
import Foundation

@MainActor
final class ConferenceStore: ObservableObject {
    @Published private(set) var conferences: [Conference] = []
    @Published private(set) var preferences = Preferences()
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var syncError: String?
    @Published private(set) var storageError: String?
    @Published private(set) var isBundled = false
    @Published private(set) var missingIDs: Set<String> = []
    @Published var now = Date()
    @Published var rotation = 0
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var clock: Timer?
    private var refreshClock: Timer?
    private var wakeObserver: NSObjectProtocol?

    struct Cache: Codable {
        let snapshot: ConferenceSnapshot
        let missingIDs: Set<String>
    }

    init(directory: URL? = nil, startTimers: Bool = true) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CCFDeadline", isDirectory: true)
        encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        do { try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true) }
        catch { storageError = "无法创建本地存储：\(error.localizedDescription)" }
        let prefsURL = self.directory.appendingPathComponent("preferences.json")
        if FileManager.default.fileExists(atPath: prefsURL.path) {
            do { preferences = try decoder.decode(Preferences.self, from: Data(contentsOf: prefsURL)) }
            catch { storageError = "收藏设置读取失败，原文件已保留：\(error.localizedDescription)" }
        }
        let cacheURL = self.directory.appendingPathComponent("conferences.json")
        if let data = try? Data(contentsOf: cacheURL), let cache = try? decoder.decode(Cache.self, from: data) {
            conferences = cache.snapshot.conferences; lastUpdated = cache.snapshot.fetchedAt; missingIDs = cache.missingIDs
        } else {
            // Locate SwiftPM resources relative to the executable. Bundle.module's
            // generated fallback embeds the developer's absolute build directory.
            let adjacentResources = Bundle(url: Bundle.main.bundleURL.appendingPathComponent("CCFDeadline_CCFDeadline.bundle"))
            let seedURL = Bundle.main.url(forResource: "seed", withExtension: "json")
                ?? adjacentResources?.url(forResource: "seed", withExtension: "json")
            if let seedURL, let data = try? Data(contentsOf: seedURL),
               let snapshot = try? decoder.decode(ConferenceSnapshot.self, from: data) {
                conferences = snapshot.conferences; lastUpdated = snapshot.fetchedAt; isBundled = true
            }
        }
        if startTimers {
            clock = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            refreshClock = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.refresh() }
            }
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.tick()
                    if let self, self.lastUpdated.map({ Date().timeIntervalSince($0) > 3600 }) ?? true { await self.refresh() }
                }
            }
        }
    }

    func tick() { now = Date(); rotation = (rotation + 1) % 1_000_000 }
    var favorites: [Conference] { Conference.ordered(conferences.filter { preferences.favorites.contains($0.id) }, now: now) }
    var barConferences: [Conference] { preferences.statusConferences(from: conferences, now: now, rotation: rotation) }
    var upcoming: [Conference] { conferences.filter { ($0.deadline ?? .distantPast) > now } }
    var overdueFavorites: Int { favorites.filter { ($0.deadline ?? .distantFuture) <= now }.count }

    func isFavorite(_ c: Conference) -> Bool { preferences.favorites.contains(c.id) }
    func toggleFavorite(_ c: Conference) {
        var next = preferences
        if next.favorites.contains(c.id) {
            next.favorites.remove(c.id)
            if next.pinnedID == c.id { next.pinnedID = nil }
        } else { next.favorites.insert(c.id) }
        save(next)
    }
    func pin(_ c: Conference) {
        var next = preferences
        next.favorites.insert(c.id)
        next.pinnedID = next.pinnedID == c.id ? nil : c.id
        if next.mode == .all { next.mode = .nearest }
        save(next)
    }
    func setMode(_ mode: BarMode) { var next = preferences; next.mode = mode; next.pinnedID = nil; save(next) }
    func setCompact(_ value: Bool) { var next = preferences; next.compact = value; save(next) }
    func clearPin() { var next = preferences; next.pinnedID = nil; save(next) }
    private func save(_ value: Preferences) {
        do {
            try encoder.encode(value).write(to: directory.appendingPathComponent("preferences.json"), options: .atomic)
            preferences = value; storageError = nil
        } catch { storageError = "收藏设置未能保存：\(error.localizedDescription)" }
    }

    func refresh(session: URLSession = .shared) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            var request = URLRequest(url: URL(string: "https://ccfddl.cn/")!)
            request.timeoutInterval = 30
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("CCFDeadline-macOS/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            guard data.count <= 5_000_000, let html = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
            let parsed = try await Task.detached(priority: .utility) { try WebsiteParser.parse(html) }.value
            try accept(parsed, at: Date())
            syncError = nil
        } catch {
            syncError = "同步失败，继续使用\(isBundled ? "内置快照" : "上次数据")。\(error.localizedDescription)"
        }
    }

    func accept(_ parsed: [Conference], at date: Date) throws {
        guard !parsed.isEmpty else { throw WebsiteParseError.noRecords }
        let liveIDs = Set(parsed.map(\.id))
        let retained = conferences.filter { preferences.favorites.contains($0.id) && !liveIDs.contains($0.id) }
        let snapshot = ConferenceSnapshot(fetchedAt: date, conferences: parsed + retained)
        let cache = Cache(snapshot: snapshot, missingIDs: Set(retained.map(\.id)))
        // Commit to disk first: a failed write never discards the last usable cache.
        try encoder.encode(cache).write(to: directory.appendingPathComponent("conferences.json"), options: .atomic)
        conferences = snapshot.conferences; missingIDs = cache.missingIDs
        lastUpdated = date; isBundled = false; now = Date()
    }
}
