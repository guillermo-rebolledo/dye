import Foundation
import ImageIO
import Testing
@testable import FilmEngine

@Test func exportDateSelectionFallsBackToToday() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let original = Date(timeIntervalSince1970: 1_000_000_000)
    #expect(ExportDate.today.resolve(originalDate: original, now: now) == now)
    #expect(ExportDate.original.resolve(originalDate: original, now: now) == original)
    #expect(ExportDate.original.resolve(originalDate: nil, now: now) == now)
    #expect(ExportDate.originalDate(in: Data()) == nil)
    #expect(ExportDate.originalDate(in: [:]) == nil)
}

@Test func originalDateUsesCaptureTimeAndOffset() {
    let properties: [CFString: Any] = [kCGImagePropertyExifDictionary: [
        kCGImagePropertyExifDateTimeOriginal: "2020:01:02 03:04:05",
        kCGImagePropertyExifOffsetTimeOriginal: "-06:00",
        kCGImagePropertyExifDateTimeDigitized: "2024:01:02 03:04:05"
    ]]
    let expected = ISO8601DateFormatter().date(from: "2020-01-02T09:04:05Z")
    #expect(ExportDate.originalDate(in: properties) == expected)
}

@Test func originalDateRejectsInvalidDatesAndUsesSecondaryMetadata() {
    let invalid: [CFString: Any] = [kCGImagePropertyExifDictionary: [
        kCGImagePropertyExifDateTimeOriginal: "0000:00:00 00:00:00"
    ]]
    #expect(ExportDate.originalDate(in: invalid) == nil)
    let malformed: [CFString: Any] = [kCGImagePropertyExifDictionary: [
        kCGImagePropertyExifDateTimeOriginal: "2020:02:31 03:04:05"
    ]]
    #expect(ExportDate.originalDate(in: malformed) == nil)
    var secondary = invalid
    secondary[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFDateTime: "2020:01:02 03:04:05"]
    #expect(ExportDate.originalDate(in: secondary) != nil)
    #expect(ExportDate.originalDate(in: [kCGImagePropertyExifDictionary: [
        kCGImagePropertyExifDateTimeDigitized: "2020:01:02 03:04:05"
    ]]) != nil)
}

@Test(arguments: ExportFormat.allCases)
func exportedFilePreservesChosenDate(format: ExportFormat) throws {
    let date = Date(timeIntervalSince1970: 1_600_000_000)
    let writer = try ImageWriter(format: format, output: .displayP3, width: 16, height: 16)
    let pixels = [Float16](repeating: 1, count: 16 * 16 * 4)
    pixels.withUnsafeBufferPointer { writer.write($0, x: 0, y: 0, width: 16, height: 16) }
    let data = try writer.encode(quality: 0.9, creationDate: date)
    #expect(ExportDate.originalDate(in: data) == date)
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 16)
    #expect(image.bitsPerComponent == format.bitsPerComponent)
    #expect(image.colorSpace?.name == CGColorSpace.displayP3)
}
