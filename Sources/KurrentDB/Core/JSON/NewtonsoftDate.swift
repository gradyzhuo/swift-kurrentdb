//
//  NewtonsoftDate.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/11/10.
//

/// How Newtonsoft.Json's `JsonTextReader` reads a string value with its default
/// `DateParseHandling.DateTime`, which is how the server reads stream metadata.
///
/// The reader tries every string value as a date, including the values the server skips. Ported
/// from `DateTimeUtils.TryParseDateTime` and `DateTimeParser`, on UTF-16 units as .NET sees them.
enum NewtonsoftDate {
    /// A String token.
    case notADate
    /// A Date token: the server's `ReadRoles` refuses it where it expects a role name.
    case date
    /// The string parses as a date, but building the `DateTime` throws, and nothing catches it:
    /// the server ignores the whole metadata object, wherever the string stands.
    case conversionFails

    /// - Parameters:
    ///   - text: The string, its escapes resolved.
    ///   - bufferIndex: Where the reader holds the string: its index in the reader's character
    ///     buffer, or 0 when the string has an escape, since the reader then copies it to a buffer
    ///     of its own. Newtonsoft's `TryReadOffset` subtracts this index from the string's length
    ///     to decide whether a `/Date(…)/` offset has minutes to check, so the same string can be a
    ///     date at one place and not at another. This reproduces it.
    static func classify(_ text: some Sequence<UInt16>, bufferIndex: Int) -> NewtonsoftDate {
        let s = Array(text)
        guard let first = s.first else {
            return .notADate
        }
        if first == UInt16(ascii: "/") {
            if s.count >= 9, s.starts(with: "/Date(".utf16), s.suffix(2).elementsEqual(")/".utf16) {
                return microsoft(s, bufferIndex: bufferIndex)
            }
        } else if s.count >= 19, s.count <= 40, digit(first) != nil, s[10] == UInt16(ascii: "T") {
            return iso(s)
        }
        return .notADate
    }

    // MARK: - /Date(ticks+offset)/

    /// `TryParseDateTimeMicrosoft`: JavaScript ticks, optionally followed by a `+hhmm` or `-hhmm` offset.
    private static func microsoft(_ s: [UInt16], bufferIndex: Int) -> NewtonsoftDate {
        // The offset sign is searched from index 7, so a sign at index 6 belongs to the ticks.
        let searched = 7 ..< s.count - 1
        var end = s.count - 2
        if let sign = s[searched].firstIndex(of: UInt16(ascii: "+")) ?? s[searched].firstIndex(of: UInt16(ascii: "-")) {
            // `TryReadOffset`: two characters of hours, then two of minutes when
            // `offsetText.Length - startIndex > 5`, where `startIndex` counts from the reader's buffer.
            guard case .success = NewtonsoftInteger.parse(s[(sign + 1) ..< (sign + 3)], digits: 10) else {
                return .notADate
            }
            if s.count - (sign + bufferIndex) > 5 {
                guard case .success = NewtonsoftInteger.parse(s[(sign + 3) ..< (sign + 5)], digits: 10) else {
                    return .notADate
                }
            }
            end = sign
        }
        guard case let .success(milliseconds) = NewtonsoftInteger.parse(s[6 ..< end], digits: 19) else {
            return .notADate
        }
        // `ConvertJavaScriptTicksToDateTime`: unchecked arithmetic, then `new DateTime(ticks)`,
        // which throws outside the years 1 to 9999.
        let ticks = milliseconds &* 10_000 &+ 621_355_968_000_000_000
        return 0 ... 3_155_378_975_999_999_999 ~= ticks ? .date : .conversionFails
    }

    // MARK: - yyyy-MM-ddTHH:mm:ss

    /// `TryParseDateTimeIso`. `DateTimeParser.Parse` decides whether the string is a date; the
    /// only conversion that throws afterwards is `24:00:00` on the last day of the year 9999,
    /// where `CreateDateTime` adds a day past `DateTime.MaxValue`.
    private static func iso(_ s: [UInt16]) -> NewtonsoftDate {
        let end = s.count
        func char(_ index: Int, _ character: Character) -> Bool {
            index < end && s[index] == character.utf16.first
        }
        func twoDigits(_ index: Int) -> Int? {
            guard index + 1 < end, let high = digit(s[index]), let low = digit(s[index + 1]) else {
                return nil
            }
            return high * 10 + low
        }

        // ParseDate
        guard 3 < end, let y1 = digit(s[0]), let y2 = digit(s[1]), let y3 = digit(s[2]), let y4 = digit(s[3]) else {
            return .notADate
        }
        let year = ((y1 * 10 + y2) * 10 + y3) * 10 + y4
        guard year >= 1, char(4, "-"), let month = twoDigits(5), 1 ... 12 ~= month,
              char(7, "-"), let day = twoDigits(8), day >= 1, day <= daysInMonth(year, month),
              char(10, "T")
        else {
            return .notADate
        }

        // ParseTime
        guard let hour = twoDigits(11), hour <= 24, char(13, ":"),
              let minute = twoDigits(14), minute < 60, char(16, ":"),
              let second = twoDigits(17), second < 60,
              hour != 24 || (minute == 0 && second == 0)
        else {
            return .notADate
        }
        var start = 19
        if char(start, ".") {
            var fraction = 0
            var digits = 0
            start += 1
            // At most seven digits are read; anything after them is left for the zone.
            while start < end, digits < 7 {
                guard let value = digit(s[start]) else {
                    break
                }
                fraction = fraction * 10 + value
                digits += 1
                start += 1
            }
            guard digits > 0, hour != 24 || fraction == 0 else {
                return .notADate
            }
        }

        // ParseZone
        if start < end {
            let sign = s[start]
            if sign == UInt16(ascii: "Z") || sign == UInt16(ascii: "z") {
                start += 1
            } else {
                if start + 2 < end, twoDigits(start + 1) != nil, sign == UInt16(ascii: "-") || sign == UInt16(ascii: "+") {
                    start += 3
                }
                if start < end {
                    if char(start, ":") {
                        start += 1
                    }
                    if twoDigits(start) != nil {
                        start += 2
                    }
                }
            }
        }
        guard start == end else {
            return .notADate
        }
        return hour == 24 && year == 9999 && month == 12 && day == 31 ? .conversionFails : .date
    }

    private static func daysInMonth(_ year: Int, _ month: Int) -> Int {
        switch month {
        case 2:
            (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11:
            30
        default:
            31
        }
    }

    private static func digit(_ unit: UInt16) -> Int? {
        UInt16(ascii: "0") ... UInt16(ascii: "9") ~= unit ? Int(unit - UInt16(ascii: "0")) : nil
    }
}

extension UInt16 {
    init(ascii scalar: Unicode.Scalar) {
        self = UInt16(UInt8(ascii: scalar))
    }
}

/// Newtonsoft's `ConvertUtils.Int64TryParse` and `Int32TryParse`: an optional `-`, then decimal
/// digits only.
enum NewtonsoftInteger {
    case success(Int64)
    /// More digits than the type can hold, or a value outside it.
    case overflow
    case invalid

    /// - Parameter digits: The most digits the type has: 19 for `Int64`, 10 for `Int32`. A longer
    ///   text overflows whatever its value, leading zeros included, as Newtonsoft decides it.
    static func parse(_ text: some Collection<UInt16>, digits: Int) -> NewtonsoftInteger {
        var text = text[...]
        let negative = text.first == UInt16(ascii: "-")
        if negative {
            text = text.dropFirst()
        }
        guard !text.isEmpty, text.allSatisfy({ UInt16(ascii: "0") ... UInt16(ascii: "9") ~= $0 }) else {
            return .invalid
        }
        guard text.count <= digits else {
            return .overflow
        }
        // Accumulate below zero, where `Int64.min` fits.
        var value: Int64 = 0
        for unit in text {
            let (shifted, shiftOverflow) = value.multipliedReportingOverflow(by: 10)
            let (next, overflow) = shifted.subtractingReportingOverflow(Int64(unit - UInt16(ascii: "0")))
            guard !shiftOverflow, !overflow else {
                return .overflow
            }
            value = next
        }
        if negative {
            return .success(value)
        }
        return value == .min ? .overflow : .success(-value)
    }
}
