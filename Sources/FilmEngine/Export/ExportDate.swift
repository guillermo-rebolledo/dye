import Foundation
import ImageIO

/// The date assigned to the exported file and its Photos asset.
public enum ExportDate: String, CaseIterable, Sendable, Identifiable {
    case today, original

    public var id: String { rawValue }
    public var displayName: String { self == .today ? "Today" : "Original date" }

    public func resolve(originalDate: Date?, now: Date = .now) -> Date {
        self == .original ? originalDate ?? now : now
    }

    public static func originalDate(in data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        return originalDate(in: properties)
    }

    static func originalDate(in properties: [CFString: Any]) -> Date? {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let candidates: [(Any?, Any?)] = [
            (exif[kCGImagePropertyExifDateTimeOriginal], exif[kCGImagePropertyExifOffsetTimeOriginal]),
            (exif[kCGImagePropertyExifDateTimeDigitized], exif[kCGImagePropertyExifOffsetTimeDigitized]),
            (tiff[kCGImagePropertyTIFFDateTime], exif[kCGImagePropertyExifOffsetTime])
        ]
        for (value, offset) in candidates {
            guard let value = value as? String else { continue }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = .current
            formatter.isLenient = false
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            // Require a complete, valid EXIF date. Undated images often contain zeros.
            guard value.count == 19, let local = formatter.date(from: value),
                  formatter.string(from: local) == value else { continue }
            if let offset = offset as? String {
                formatter.dateFormat = "yyyy:MM:dd HH:mm:ssxxx"
                if let date = formatter.date(from: value + offset) { return date }
            }
            // EXIF without an offset is interpreted in the device's time zone.
            return local
        }
        return nil
    }

    static func properties(for date: Date) -> [CFString: Any] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let stamp = formatter.string(from: date)
        return [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: stamp,
                kCGImagePropertyExifDateTimeDigitized: stamp,
                kCGImagePropertyExifOffsetTimeOriginal: "+00:00",
                kCGImagePropertyExifOffsetTimeDigitized: "+00:00",
                kCGImagePropertyExifOffsetTime: "+00:00"
            ],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFDateTime: stamp]
        ]
    }
}
