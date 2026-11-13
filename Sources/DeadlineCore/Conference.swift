import Foundation

public struct Conference: Codable, Identifiable, Equatable, Sendable {
    public let sourceID: String
    public let name: String
    public let year: String
    public let rank: String
    public let category: String
    public let deadlineText: String
    public let timezone: String
    public let dates: String
    public let place: String
    public let link: String
    public let acceptance: String
    public let deadline: Date?

    // The site's numeric row IDs may be reused for the following year's edition.
    public var id: String { "\(name)|\(year)|\(sourceID)" }
    public var title: String { "\(year) 年 \(name)" }
    public var categoryName: String { Self.categories[category] ?? category }
    public var rankLabel: String { ["A", "B", "C"].contains(rank) ? "CCF \(rank)" : "未评级" }
    public var websiteURL: URL? {
        guard let url = URL(string: link), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
    public static let categories = [
        "DS": "计算机体系结构", "NW": "计算机网络", "SC": "网络与信息安全",
        "SE": "软件工程 / 系统软件", "DB": "数据库 / 数据挖掘", "CT": "计算机科学理论",
        "CG": "图形学与多媒体", "AI": "人工智能", "HI": "人机交互与普适计算", "MX": "交叉 / 综合 / 新兴"
    ]

    public init(sourceID: String, name: String, year: String, rank: String, category: String,
                deadlineText: String, timezone: String, dates: String, place: String,
                link: String, acceptance: String) {
        self.sourceID = sourceID; self.name = name; self.year = year; self.rank = rank
        self.category = category; self.deadlineText = deadlineText; self.timezone = timezone
        self.dates = dates; self.place = place; self.link = link; self.acceptance = acceptance
        self.deadline = DeadlineDate.parse(deadlineText, timezone: timezone)
    }

    public func countdown(at now: Date, compact: Bool = false) -> String {
        guard let deadline else { return deadlineText.uppercased() == "TBD" ? "日期待定" : "时间待确认" }
        let remaining = deadline.timeIntervalSince(now)
        guard remaining > 0 else { return "已截止" }
        guard remaining >= 3600 else { return compact ? "<1h" : "不足 1 hour" }
        let hours = Int(remaining / 3600)
        if compact { return "\(hours / 24)d \(hours % 24)h" }
        return "\(hours / 24) \(hours / 24 == 1 ? "day" : "days") \(hours % 24) \(hours % 24 == 1 ? "hour" : "hours")"
    }

    public func statusTitle(at now: Date, compact: Bool) -> String {
        "\(year)年 \(name) · \(countdown(at: now, compact: compact))"
    }

    public static func ordered(_ conferences: [Conference], now: Date) -> [Conference] {
        conferences.sorted { a, b in
            func group(_ c: Conference) -> Int {
                guard let date = c.deadline else { return 1 }
                return date > now ? 0 : 2
            }
            let ga = group(a), gb = group(b)
            if ga != gb { return ga < gb }
            if a.deadline != b.deadline {
                return ga == 2 ? (a.deadline ?? .distantPast) > (b.deadline ?? .distantPast)
                    : (a.deadline ?? .distantFuture) < (b.deadline ?? .distantFuture)
            }
            return a.id < b.id
        }
    }
}

public enum DeadlineDate {
    public static func zone(_ raw: String) -> TimeZone? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased() == "aoe" { return TimeZone(secondsFromGMT: -12 * 3600) }
        if name == "PT" { return TimeZone(identifier: "America/Los_Angeles") }
        if name == "PST" { return TimeZone(secondsFromGMT: -8 * 3600) }
        if name == "PDT" { return TimeZone(secondsFromGMT: -7 * 3600) }
        if name == "UTC" || name == "GMT" { return TimeZone(secondsFromGMT: 0) }
        let pattern = #"^(?:UTC|GMT)([+-])(\d{1,2})(?::(\d{2}))?$"#
        if let r = try? NSRegularExpression(pattern: pattern),
           let m = r.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) {
            let s = name as NSString
            let hours = Int(s.substring(with: m.range(at: 2))) ?? 99
            let minutes = m.range(at: 3).location == NSNotFound ? 0 : (Int(s.substring(with: m.range(at: 3))) ?? 99)
            guard hours <= 14, minutes < 60, hours < 14 || minutes == 0 else { return nil }
            let sign = s.substring(with: m.range(at: 1)) == "-" ? -1 : 1
            return TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60))
        }
        return TimeZone(identifier: name)
    }

    public static func parse(_ text: String, timezone: String) -> Date? {
        guard let zone = zone(timezone) else { return nil }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.isLenient = false
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: normalized), formatter.string(from: date) == normalized { return date }
        }
        return nil
    }
}

public struct ConferenceSnapshot: Codable, Sendable {
    public let fetchedAt: Date
    public let conferences: [Conference]
    public init(fetchedAt: Date, conferences: [Conference]) { self.fetchedAt = fetchedAt; self.conferences = conferences }
}

public enum BarMode: String, CaseIterable, Codable, Sendable {
    case nearest, rotate, all
    public var label: String {
        switch self { case .nearest: return "最近截止"; case .rotate: return "轮播收藏"; case .all: return "全部显示" }
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var favorites: Set<String> = []
    public var pinnedID: String? = nil
    public var mode: BarMode = .nearest
    public var compact: Bool = false
    public init() {}

    public func statusConferences(from conferences: [Conference], now: Date, rotation: Int) -> [Conference] {
        let saved = Conference.ordered(conferences.filter { favorites.contains($0.id) }, now: now)
        guard !saved.isEmpty else { return [] }
        if mode == .all { return saved }
        if let pinnedID, let pinned = saved.first(where: { $0.id == pinnedID }) { return [pinned] }
        if mode == .rotate { return [saved[abs(rotation % saved.count)]] }
        return [saved[0]]
    }
}
