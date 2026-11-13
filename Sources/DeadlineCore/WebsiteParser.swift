import Foundation

public enum WebsiteParseError: LocalizedError {
    case noRecords, malformed(String), duplicate(String)
    public var errorDescription: String? {
        switch self {
        case .noRecords: return "没有找到会议数据，网站格式可能已变更。"
        case .malformed(let field): return "会议数据格式不完整（\(field)），已保留上次数据。"
        case .duplicate(let id): return "网站含重复会议（\(id)），已保留上次数据。"
        }
    }
}

/// Reads only literal key/value records; never executes downloaded JavaScript.
public enum WebsiteParser {
    public static func parse(_ html: String) throws -> [Conference] {
        let regex = try NSRegularExpression(pattern: #"\brows\s*\.\s*push\s*\(\s*\{"#)
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { throw WebsiteParseError.noRecords }
        var result: [Conference] = []
        var ids: Set<String> = []
        for match in matches {
            let start = match.range.location + match.range.length - 1
            var reader = LiteralReader(text: ns.substring(from: start))
            let row = try reader.object()
            func required(_ key: String) throws -> String {
                guard let value = row[key], !value.isEmpty else { throw WebsiteParseError.malformed(key) }
                return value
            }
            let conference = try Conference(
                sourceID: required("id"), name: required("shortName"), year: required("year"),
                rank: required("ccfRank"), category: required("type"), deadlineText: required("deadline"),
                timezone: required("timezone"), dates: row["date"] ?? "待公布", place: row["place"] ?? "待公布",
                link: row["link"] ?? "", acceptance: row["accept_rate"] ?? ""
            )
            guard ids.insert(conference.id).inserted else { throw WebsiteParseError.duplicate(conference.id) }
            result.append(conference)
        }
        return result
    }
}

private struct LiteralReader {
    let characters: [Character]
    var index = 0
    init(text: String) { characters = Array(text.prefix(16000)) }
    var current: Character? { index < characters.count ? characters[index] : nil }
    mutating func skipSpace() { while let c = current, c.isWhitespace { index += 1 } }
    mutating func take(_ character: Character) throws {
        skipSpace()
        guard current == character else { throw WebsiteParseError.malformed("字符 \(character)") }
        index += 1
    }
    mutating func string() throws -> String {
        skipSpace()
        guard let quote = current, quote == "\"" || quote == "'" else { throw WebsiteParseError.malformed("字符串") }
        index += 1
        var value = ""
        while let c = current {
            index += 1
            if c == quote { return value }
            guard c == "\\" else { value.append(c); continue }
            guard let escaped = current else { throw WebsiteParseError.malformed("转义") }
            index += 1
            switch escaped {
            case "n": value.append("\n")
            case "r": value.append("\r")
            case "t": value.append("\t")
            case "b": value.append("\u{8}")
            case "f": value.append("\u{c}")
            case "u":
                guard index + 4 <= characters.count else { throw WebsiteParseError.malformed("Unicode") }
                let hex = String(characters[index..<(index + 4)])
                guard let n = UInt32(hex, radix: 16) else { throw WebsiteParseError.malformed("Unicode") }
                index += 4
                if (0xD800...0xDBFF).contains(n) {
                    guard index + 6 <= characters.count, characters[index] == "\\", characters[index + 1] == "u",
                          let low = UInt32(String(characters[(index + 2)..<(index + 6)]), radix: 16),
                          (0xDC00...0xDFFF).contains(low),
                          let scalar = UnicodeScalar(0x10000 + (n - 0xD800) * 0x400 + low - 0xDC00) else {
                        throw WebsiteParseError.malformed("Unicode surrogate")
                    }
                    value.unicodeScalars.append(scalar); index += 6
                } else if let scalar = UnicodeScalar(n) { value.unicodeScalars.append(scalar) }
                else { throw WebsiteParseError.malformed("Unicode") }
            case "x":
                guard index + 2 <= characters.count,
                      let n = UInt32(String(characters[index..<(index + 2)]), radix: 16),
                      let scalar = UnicodeScalar(n) else { throw WebsiteParseError.malformed("十六进制转义") }
                value.unicodeScalars.append(scalar); index += 2
            case "\n": break
            case "'", "\"", "\\", "/": value.append(escaped)
            default: throw WebsiteParseError.malformed("不支持的转义")
            }
        }
        throw WebsiteParseError.malformed("未闭合字符串")
    }
    mutating func object() throws -> [String: String] {
        try take("{")
        var fields: [String: String] = [:]
        while true {
            skipSpace()
            if current == "}" { index += 1; break }
            let key = try string()
            try take(":"); skipSpace()
            let value: String
            if current == "'" || current == "\"" { value = try string() }
            else {
                let start = index
                while let c = current, c.isNumber || c == "-" || c == "." { index += 1 }
                guard index > start else { throw WebsiteParseError.malformed("非字面量值") }
                value = String(characters[start..<index])
            }
            guard fields[key] == nil else { throw WebsiteParseError.malformed("重复字段") }
            fields[key] = value
            skipSpace()
            if current == "}" { index += 1; break }
            try take(",")
        }
        try take(")")
        return fields
    }
}
