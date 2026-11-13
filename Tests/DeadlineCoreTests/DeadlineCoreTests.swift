import Foundation
import XCTest
@testable import DeadlineCore

final class DeadlineCoreTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-13T08:00:00Z")!
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func conference(_ name: String = "CVPR", year: String = "2027", id: String = "608",
                            deadline: String = "2026-11-16 23:59:59", zone: String = "AoE") -> Conference {
        Conference(sourceID: id, name: name, year: year, rank: "A", category: "AI", deadlineText: deadline,
                   timezone: zone, dates: "June 22-25, 2027", place: "Seattle", link: "https://cvpr.thecvf.com/", acceptance: "")
    }
    private var row: String {
        #"rows.push({'type':"AI", 'shortName':"CVPR",'ccfRank':"A",'deadline':"2026-11-16 23:59:59",'timezone':'UTC-12','id':608,'date':"June 22-25, 2027",'link':'https://cvpr.thecvf.com/','place':"Seattle",'year':'2027'})"#
    }

    func testAoEIsUTCMinusTwelve() {
        XCTAssertEqual(DeadlineDate.parse("2026-11-16 23:59:59", timezone: "AoE"), date("2026-11-17T11:59:59Z"))
        XCTAssertEqual(DeadlineDate.parse("2026-11-16 23:59:59", timezone: "UTC-12"), date("2026-11-17T11:59:59Z"))
    }
    func testUTCOffsetsAndHalfHours() {
        XCTAssertEqual(DeadlineDate.parse("2026-11-13 16:00:00", timezone: "UTC+8"), now)
        XCTAssertEqual(DeadlineDate.parse("2026-11-13 13:30:00", timezone: "UTC+05:30"), now)
        XCTAssertEqual(DeadlineDate.parse("2026-11-13 08:00", timezone: "UTC"), now)
        XCTAssertNil(DeadlineDate.zone("UTC+15"))
        XCTAssertNil(DeadlineDate.zone("UTC+14:30"))
    }
    func testPacificDSTUsesDeadlineDateNotCurrentDate() {
        XCTAssertEqual(DeadlineDate.parse("2027-05-15 23:59:59", timezone: "PT"), date("2027-05-16T06:59:59Z"))
        XCTAssertEqual(DeadlineDate.parse("2027-01-15 23:59:59", timezone: "PT"), date("2027-01-16T07:59:59Z"))
        XCTAssertEqual(DeadlineDate.parse("2027-05-15 23:59:59", timezone: "UTC-8"), date("2027-05-16T07:59:59Z"))
    }
    func testInvalidAndUnpublishedDeadlinesStayUnknown() {
        XCTAssertNil(DeadlineDate.parse("TBD", timezone: "AoE"))
        XCTAssertNil(DeadlineDate.parse("2026-02-30 23:59:59", timezone: "UTC"))
        XCTAssertNil(DeadlineDate.parse("2026-11-13 08:00:00", timezone: "MYSTERY"))
        XCTAssertEqual(conference(deadline: "TBD").countdown(at: now), "日期待定")
        XCTAssertEqual(conference(zone: "MYSTERY").countdown(at: now), "时间待确认")
    }
    func testCountdownAndDeadlineBoundary() {
        let c = conference(deadline: "2026-11-15 11:00:00", zone: "UTC")
        XCTAssertEqual(c.countdown(at: now), "2 days 3 hours")
        XCTAssertEqual(c.countdown(at: now, compact: true), "2d 3h")
        XCTAssertEqual(c.countdown(at: c.deadline!.addingTimeInterval(-3599)), "不足 1 hour")
        XCTAssertEqual(c.countdown(at: c.deadline!), "已截止")
        XCTAssertEqual(c.countdown(at: c.deadline!.addingTimeInterval(1)), "已截止")
        XCTAssertEqual(c.statusTitle(at: now, compact: true), "2027年 CVPR · 2d 3h")
    }
    func testParseMixedQuotesNumbersAndUnicode() throws {
        let parsed = try WebsiteParser.parse("<script>\(row)</script>")
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].sourceID, "608")
        XCTAssertEqual(parsed[0].name, "CVPR")
        XCTAssertEqual(parsed[0].deadline, date("2026-11-17T11:59:59Z"))
        let escaped = row.replacingOccurrences(of: #""Seattle""#, with: #"'Montr\u00e9al \' \uD83D\uDCCD {x})'"#)
        XCTAssertEqual(try WebsiteParser.parse(escaped)[0].place, "Montréal ' 📍 {x})")
    }
    func testMissingFieldsAndDuplicateRowsRejected() {
        XCTAssertThrowsError(try WebsiteParser.parse(row.replacingOccurrences(of: "'id':608,", with: "")))
        XCTAssertThrowsError(try WebsiteParser.parse(row + row))
        XCTAssertThrowsError(try WebsiteParser.parse("<html>Service unavailable</html>"))
    }
    func testExecutableValuesAreNeverEvaluated() {
        let malicious = row.replacingOccurrences(of: "'id':608", with: "'id':(()=>{throw new Error('should never run')})()")
        XCTAssertThrowsError(try WebsiteParser.parse(malicious))
        XCTAssertThrowsError(try WebsiteParser.parse(String(row.dropLast(10))))
    }
    func testFavoritesDoNotJumpToNextYear() {
        XCTAssertNotEqual(conference(year: "2027").id, conference(year: "2028").id)
    }
    func testOnlySafeWebsiteSchemesOpen() {
        let unsafe = Conference(sourceID: "1", name: "Test", year: "2027", rank: "A", category: "AI", deadlineText: "TBD", timezone: "UTC", dates: "", place: "", link: "javascript:alert(1)", acceptance: "")
        XCTAssertNil(unsafe.websiteURL)
        XCTAssertNotNil(conference().websiteURL)
    }
    func testNearestFavoriteSkipsExpiredAndUnknownDeadlines() {
        let expired = conference("Old", id: "1", deadline: "2026-11-12 08:00:00", zone: "UTC")
        let next = conference("Next", id: "2", deadline: "2026-11-13 09:00:00", zone: "UTC")
        let unknown = conference("Unknown", id: "3", deadline: "TBD")
        var prefs = Preferences(); prefs.favorites = Set([expired.id, next.id, unknown.id])
        XCTAssertEqual(prefs.statusConferences(from: [expired, unknown, next], now: now, rotation: 0), [next])
        XCTAssertEqual(prefs.statusConferences(from: [expired, unknown, next], now: now.addingTimeInterval(7200), rotation: 0), [unknown])
    }
    func testPinRotationAllModesAndEmptyFavorites() {
        let a = conference(), b = conference("ACL", id: "2", deadline: "2027-01-04 23:59:59")
        var prefs = Preferences()
        XCTAssertTrue(prefs.statusConferences(from: [a,b], now: now, rotation: 0).isEmpty)
        prefs.favorites = [a.id, b.id]; prefs.mode = .rotate
        XCTAssertEqual(prefs.statusConferences(from: [a,b], now: now, rotation: 0), [a])
        XCTAssertEqual(prefs.statusConferences(from: [a,b], now: now, rotation: 1), [b])
        XCTAssertEqual(prefs.statusConferences(from: [a,b], now: now, rotation: 2), [a])
        prefs.pinnedID = b.id
        XCTAssertEqual(prefs.statusConferences(from: [a,b], now: now, rotation: 0), [b])
        prefs.mode = .all
        XCTAssertEqual(prefs.statusConferences(from: [a,b], now: now, rotation: 0), [a,b])
        prefs.favorites.remove(b.id); prefs.mode = .nearest
        XCTAssertEqual(prefs.statusConferences(from: [a,b], now: now, rotation: 0), [a])
    }
    func testSnapshotAndPreferencesRoundTrip() throws {
        let snapshot = ConferenceSnapshot(fetchedAt: now, conferences: [conference()])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ConferenceSnapshot.self, from: encoder.encode(snapshot))
        XCTAssertEqual(decoded.conferences, snapshot.conferences)
        XCTAssertEqual(decoded.fetchedAt, now)
        var prefs = Preferences(); prefs.favorites = [conference().id]; prefs.pinnedID = conference().id; prefs.compact = true; prefs.mode = .rotate
        XCTAssertEqual(try decoder.decode(Preferences.self, from: encoder.encode(prefs)), prefs)
    }
}
