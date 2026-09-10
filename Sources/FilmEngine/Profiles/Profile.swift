import Foundation

public struct Profile: Sendable, Identifiable {
    public var id: String { metadata.id }
    public let metadata: FilmProfile
    let source: Source
    /// Cache identity belongs to the loaded content, independent of its renameable Display Name.
    let cacheID = UUID()
    enum Source: Sendable {
        case memory([String: Data])
        case file(URL, Int, [ProfileContainer.Entry])
    }
    init(metadata: FilmProfile, source: Source) { self.metadata = metadata; self.source = source }

    public init(metadata: FilmProfile, payloads: [String: Data]) throws {
        try metadata.validate()
        self.init(metadata: metadata, source: .memory(payloads))
        let expected = metadata.payloadNames
        guard Set(payloads.keys) == expected else { throw FilmError.invalid("Profile payload references do not match") }
        for (name, bytes) in payloads {
            if name == metadata.monochrome?.densityCurve {
                guard try decodeHalfValues(bytes).count == 1024 else { throw FilmError.invalid("Density Curve must contain 1024 entries") }
            } else {
                let output = metadata.colour.densityOutput
                let outputNames = (output?.lutVariants ?? []) + (output?.printVariants ?? [])
                let size = outputNames.contains { $0.lut == name } ? output!.lutSize : metadata.colour.lutSize
                _ = try ColourCube(size: size, payload: bytes)
            }
        }
    }

    /// In-memory Colour Cube profiles are useful for renderer calibration.
    public init(colourCube: ColourCube) {
        var metadata = Self.identityMetadata
        metadata.colour.lutSize = colourCube.size
        self.init(metadata: metadata, source: .memory(["identity.lut3d": colourCube.payload]))
    }
    public static let identity = Profile(colourCube: .identity)

    func readPayload(_ name: String) throws -> Data {
        switch source {
        case .memory(let payloads):
            guard let bytes = payloads[name] else { throw FilmError.invalid("Missing payload \(name)") }
            return bytes
        case .file(let url, let offset, let entries):
            guard let entry = entries.first(where: { $0.name == name }) else { throw FilmError.invalid("Missing payload \(name)") }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset + entry.offset))
            guard let bytes = try handle.read(upToCount: entry.length), bytes.count == entry.length else {
                throw FilmError.invalid("Truncated payload \(name)")
            }
            return bytes
        }
    }

    func readPayloads() throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: metadata.payloadNames.map { ($0, try readPayload($0)) })
    }

    /// `Profile.identity` backs the very first frame the editor draws, so its metadata
    /// is compiled into the binary rather than read out of the resource bundle. A
    /// bundle lookup here could only ever fail for packaging reasons, and it would fail
    /// on launch, which is the one place there is no way to report it. `identityProfileDecodesFromItsCompiledSource`
    /// is what keeps this literal and the schema honest.
    private static let identityMetadata: FilmProfile = {
        do { return try JSONDecoder().decode(FilmProfile.self, from: Data(identitySource.utf8)) }
        catch { fatalError("The compiled-in identity Profile does not decode: \(error)") }
    }()

    /// The identity Profile's authoring metadata. Every Pass is silent, the Colour
    /// Cube is the identity cube, and the Output Stage is `none`, so a render through
    /// it returns the Working Space unchanged.
    static let identitySource = #"""
{
  "accuracy": "synthetic",
  "balance": 5500,
  "bloom": {
    "radiusMicrons": 900.0,
    "strength": 0.0
  },
  "colour": {
    "lutSize": 33,
    "lutVariants": [
      {
        "lut": "identity.lut3d",
        "pushStops": 0
      }
    ],
    "outputStage": "none"
  },
  "displayName": "No Film Stock",
  "format": "135",
  "grain": {
    "channelCorrelation": 0.15,
    "channelRadiusScale": [
      1,
      0.85,
      0.7
    ],
    "densityResponse": [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0
    ],
    "grainRadiusMicrons": 1.2,
    "model": "procedural",
    "rmsGranularity": 0
  },
  "halation": {
    "radiusMicrons": [
      220,
      90,
      45
    ],
    "strength": 0,
    "threshold": 1.6,
    "tint": [
      1,
      0.35,
      0.18
    ]
  },
  "id": "identity",
  "mtf": {
    "cyclesPerMM": [
      5,
      10,
      20,
      40,
      80
    ],
    "response": [
      1,
      1,
      1,
      1,
      1
    ]
  },
  "nominalISO": 100,
  "process": "e6",
  "provenance": {
    "balance": "artistic",
    "bloom.radiusMicrons": "artistic",
    "bloom.strength": "artistic",
    "colour.lutSize": "artistic",
    "colour.lutVariants": "artistic",
    "colour.outputStage": "artistic",
    "format": "artistic",
    "grain.channelCorrelation": "artistic",
    "grain.channelRadiusScale": "artistic",
    "grain.densityResponse": "artistic",
    "grain.grainRadiusMicrons": "artistic",
    "grain.model": "artistic",
    "grain.rmsGranularity": "artistic",
    "halation.radiusMicrons": "artistic",
    "halation.strength": "artistic",
    "halation.threshold": "artistic",
    "halation.tint": "artistic",
    "mtf.cyclesPerMM": "artistic",
    "mtf.response": "artistic",
    "nominalISO": "artistic",
    "reciprocity.schwarzschildP": "artistic",
    "reciprocity.thresholdSeconds": "artistic",
    "trueISO": "artistic"
  },
  "reciprocity": {
    "schwarzschildP": [
      1,
      1,
      1
    ],
    "thresholdSeconds": 1
  },
  "trueISO": 100
}
"""#
}
