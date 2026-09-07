import Foundation

public enum FilmError: Error, LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}

/// Straight-alpha RGBA, linear Rec.2020, stored at the pipeline's float16 precision.
public struct LinearImage: Sendable {
    public let width: Int
    public let height: Int
    public let rgba: [Float16]

    public init(width: Int, height: Int, rgba: [Float16]) throws {
        guard width > 0, height > 0, width <= 16_384, height <= 16_384,
              rgba.count == width * height * 4, rgba.allSatisfy(\.isFinite) else {
            throw FilmError.invalid("Invalid image dimensions or non-finite pixels")
        }
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

public enum RenderImage: Sendable {
    case linear(LinearImage)
    case encoded(Data)
}

public struct RenderSettings: Sendable {
    public enum Output: UInt32, Sendable { case workingSpace = 0, displayP3 = 1 }
    public var output: Output
    public init(output: Output = .displayP3) { self.output = output }
}

/// Red varies fastest, then green, then blue. Each texel contains RGBA float16.
public struct ColourCube: Sendable, Equatable {
    public let size: Int
    public let rgba: [Float16]
    public init(size: Int, rgba: [Float16]) throws {
        guard (2...65).contains(size), rgba.count == size * size * size * 4,
              rgba.allSatisfy(\.isFinite) else { throw FilmError.invalid("Invalid Colour Cube") }
        self.size = size
        self.rgba = rgba
    }
    public static let identity: ColourCube = {
        let size = 33
        var rgba: [Float16] = []
        for b in 0..<size { for g in 0..<size { for r in 0..<size {
            rgba += [Float16(r) / 32, Float16(g) / 32, Float16(b) / 32, 1]
        } } }
        return try! ColourCube(size: size, rgba: rgba)
    }()
}

public struct Profile: Sendable {
    public let colourCube: ColourCube
    public init(colourCube: ColourCube) { self.colourCube = colourCube }
    public static let identity = Profile(colourCube: .identity)
}

/// Pixels returned by the renderer, tagged with the requested output encoding.
public struct RenderedPixels: Sendable {
    public let width: Int
    public let height: Int
    public let rgba: [Float16]
    public let output: RenderSettings.Output
}
