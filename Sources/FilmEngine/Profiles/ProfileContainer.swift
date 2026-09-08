import Foundation

/// Version 1: 8-byte magic, little-endian UInt32 version and JSON length, UTF-8
/// header, then contiguous little-endian float16 payloads. Offsets are relative
/// to the first payload byte; metadata can be read without touching the payloads.
public enum ProfileContainer {
    private static let magic = Data("FILMPROF".utf8)
    private static let maximumHeader = 4 * 1024 * 1024
    private static let maximumFile = 128 * 1024 * 1024

    struct Entry: Codable, Sendable {
        let name: String
        let offset: Int
        let length: Int
    }
    struct Header: Codable, Sendable {
        let profile: FilmProfile
        let payloads: [Entry]
    }

    public static func encode(_ profile: Profile) throws -> Data {
        try profile.metadata.validate()
        let payloads = try profile.readPayloads()
        var bytes = Data()
        var entries: [Entry] = []
        for name in payloads.keys.sorted() {
            let payload = payloads[name]!
            entries.append(Entry(name: name, offset: bytes.count, length: payload.count))
            bytes.append(payload)
        }
        let header = Header(profile: profile.metadata, payloads: entries)
        try validate(header, payloadLength: bytes.count)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = try encoder.encode(header)
        guard json.count <= maximumHeader, bytes.count <= maximumFile - json.count - 16 else {
            throw FilmError.invalid("Profile exceeds container size limits")
        }
        var result = magic
        appendUInt32(1, to: &result)
        appendUInt32(UInt32(json.count), to: &result)
        result.append(json)
        result.append(bytes)
        return result
    }

    public static func decode(_ bytes: Data) throws -> Profile {
        let count = try headerLength(Data(bytes.prefix(16)))
        guard bytes.count <= maximumFile, bytes.count >= 16 + count else { throw FilmError.invalid("Truncated profile") }
        let header = try JSONDecoder().decode(Header.self, from: bytes.subdata(in: 16..<(16 + count)))
        try validate(header, payloadLength: bytes.count - 16 - count)
        var payloads: [String: Data] = [:]
        for entry in header.payloads {
            let start = 16 + count + entry.offset
            payloads[entry.name] = bytes.subdata(in: start..<(start + entry.length))
        }
        return try Profile(metadata: header.profile, payloads: payloads)
    }

    /// Reads just the header and file length. Payload bytes are fetched on demand.
    public static func load(from url: URL) throws -> Profile {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let count = try headerLength(handle.read(upToCount: 16) ?? Data())
        guard let json = try handle.read(upToCount: count), json.count == count else { throw FilmError.invalid("Truncated profile header") }
        let header = try JSONDecoder().decode(Header.self, from: json)
        let length = try handle.seekToEnd()
        guard length <= maximumFile, length >= 16 + count else { throw FilmError.invalid("Invalid profile length") }
        try validate(header, payloadLength: Int(length) - 16 - count)
        return Profile(metadata: header.profile, source: .file(url, 16 + count, header.payloads))
    }

    private static func headerLength(_ prefix: Data) throws -> Int {
        guard prefix.count == 16, prefix.prefix(8) == magic, uint32(prefix, at: 8) == 1 else {
            throw FilmError.invalid("Unsupported .filmprofile magic or version")
        }
        let length = Int(uint32(prefix, at: 12))
        guard length > 0, length <= maximumHeader else { throw FilmError.invalid("Invalid profile header length") }
        return length
    }

    private static func validate(_ header: Header, payloadLength: Int) throws {
        try header.profile.validate()
        var expected: [String: Int] = [:]
        let size = header.profile.colour.lutSize
        for variant in header.profile.colour.lutVariants + (header.profile.colour.printVariants ?? []) {
            expected[variant.lut] = size * size * size * 8
        }
        if let mono = header.profile.monochrome { expected[mono.densityCurve] = 1024 * 2 }
        guard Set(header.payloads.map(\.name)).count == header.payloads.count,
              Set(expected.keys) == Set(header.payloads.map(\.name)) else { throw FilmError.invalid("Profile payload references do not match") }
        var end = 0
        for entry in header.payloads.sorted(by: { $0.offset < $1.offset }) {
            guard entry.offset == end, entry.length == expected[entry.name], entry.length <= payloadLength - end else {
                throw FilmError.invalid("Invalid payload length or overlapping offsets")
            }
            end += entry.length
        }
        guard end == payloadLength else { throw FilmError.invalid("Unexpected trailing profile bytes") }
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(data[offset + $1]) << ($1 * 8) }
    }
    private static func appendUInt32(_ value: UInt32, to bytes: inout Data) {
        for shift in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8(truncatingIfNeeded: value >> shift)) }
    }
}

extension ColourCube {
    public var payload: Data { encodeHalfValues(rgba) }
    public init(size: Int, payload: Data) throws { try self.init(size: size, rgba: decodeHalfValues(payload)) }
}

func encodeHalfValues(_ values: [Float16]) -> Data {
    var bytes = Data(capacity: values.count * 2)
    for value in values {
        bytes.append(UInt8(truncatingIfNeeded: value.bitPattern))
        bytes.append(UInt8(truncatingIfNeeded: value.bitPattern >> 8))
    }
    return bytes
}

func decodeHalfValues(_ bytes: Data) throws -> [Float16] {
    guard bytes.count % 2 == 0 else { throw FilmError.invalid("Truncated float16 payload") }
    let data = [UInt8](bytes)
    let values = stride(from: 0, to: data.count, by: 2).map { Float16(bitPattern: UInt16(data[$0]) | UInt16(data[$0 + 1]) << 8) }
    guard values.allSatisfy(\.isFinite) else { throw FilmError.invalid("Non-finite profile payload") }
    return values
}
