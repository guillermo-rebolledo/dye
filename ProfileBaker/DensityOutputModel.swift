import Foundation
import FilmEngine
import simd

/// The film and its observation are separate transforms. This keeps all spatial
/// density fluctuations before the scanner, paper or transparency viewer.
extension SpectralModel {
    func densityOutputMetadata(_ colour: FilmProfile.Colour) -> FilmProfile.DensityOutput {
        // Below base the forward model forms no dye, so put base exactly on a
        // grid node instead of interpolating across that knee. The upper padding
        // permits grain to fluctuate above the characteristic curve endpoint.
        let minimum = channels.map { $0.points.map(\.density).min()! }
        let maximum = channels.map { $0.points.map(\.density).max()! + 1 }
        func outputs(_ variants: [FilmProfile.Variant]) -> [FilmProfile.Variant] {
            variants.map { .init(pushStops: $0.pushStops, lut: "output." + $0.lut) }
        }
        return FilmProfile.DensityOutput(minimum: minimum, maximum: maximum, lutSize: 65,
                                         lutVariants: colour.lutVariants.map { .init(pushStops: $0.pushStops, lut: "output.scan.lut3d") },
                                         printVariants: colour.printVariants.map(outputs))
    }

    func outputCube(domain: FilmProfile.DensityOutput, paper: PrintModel? = nil) throws -> ColourCube {
        let size = domain.lutSize, last = Double(size - 1)
        let minimum = SIMD3(domain.minimum[0], domain.minimum[1], domain.minimum[2])
        let span = SIMD3(domain.maximum[0], domain.maximum[1], domain.maximum[2]) - minimum
        var rgba = [Float16](repeating: 1, count: size * size * size * 4)
        rgba.withUnsafeMutableBufferPointer { buffer in
            nonisolated(unsafe) let texels = buffer
            DispatchQueue.concurrentPerform(iterations: size) { b in
                for g in 0..<size { for r in 0..<size {
                    let d = minimum + SIMD3(Double(r), Double(g), Double(b)) / last * span
                    let value = paper.map { $0.print(d, negative: self) } ?? output(d)
                    let index = ((b * size + g) * size + r) * 4
                    for c in 0..<3 { texels[index + c] = Float16(value[c]) }
                } }
            }
        }
        return try ColourCube(size: size, rgba: rgba)
    }
}

/// A nomograph is a measurement of sigma(D), not a crystal radius or a guessed
/// midtone bell. Keep the independent measured channel curves in physical units.
func measuredGranularity(in directory: URL) throws -> [[FilmProfile.Grain.DensityGranularity]]? {
    guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("granularity.csv").path) else { return nil }
    let rows = try SpectralTable(directory, "granularity.csv", header: "density,red,green,blue").rows
    guard rows.count >= 2 else { throw FilmError.invalid("Granularity requires at least two densities") }
    return (1...3).map { channel in rows.map { .init(density: $0[0], rms: $0[channel]) } }
}
