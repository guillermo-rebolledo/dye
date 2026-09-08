#include <metal_stdlib>
using namespace metal;

// `frame` = (tile origin x, tile origin y, frame width, frame height) in pixels.
// A Preview is one Tile that is the whole frame, so its origin is zero and its
// size is the texture's own. A tiled Export renders many Tiles of one frame, and
// the two Passes whose value depends on *where* in the frame a pixel sits — Grain
// and Geometry — read their position through this rather than from the thread
// position, which is Tile-local. Everything else in the pipeline is either
// per-pixel or reaches only as far as the Apron.
//
// Passing the whole frame rather than just the origin matters for Geometry: a
// vignette is a fraction of the frame's diagonal, not of the Tile's.

kernel void passthrough(texture2d<half, access::read> input [[texture(0)]],
                        texture2d<half, access::write> output [[texture(1)]],
                        uint2 p [[thread_position_in_grid]]) {
    if (p.x < output.get_width() && p.y < output.get_height()) output.write(input.read(p), p);
}

// Pass 2. The 3×3 matrix re-illuminates the scene and adapts to the Stock Balance.
kernel void whiteBalance(texture2d<half, access::read> input [[texture(0)]],
                         texture2d<half, access::write> output [[texture(1)]],
                         constant float3x3 &matrix [[buffer(2)]],
                         uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    half4 pixel = input.read(p);
    output.write(half4(half3(matrix * float3(pixel.rgb)), pixel.a), p);
}

// Pass 3. A scalar multiply in linear light commutes with the Film Response.
kernel void exposure(texture2d<half, access::read> input [[texture(0)]],
                     texture2d<half, access::write> output [[texture(1)]],
                     constant float &gain [[buffer(3)]],
                     uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    half4 pixel = input.read(p);
    output.write(half4(half3(float3(pixel.rgb) * gain), pixel.a), p);
}

// Passes 5 and 6, Bloom and Halation. Both scatter light before the Film Response
// rather than after it, and both blur in the same pyramid, so they share these
// kernels and differ only in what they extract and how they composite it back.
// Bloom is the taking lens spreading a fraction of *all* the light across the
// frame; Halation is light that passed through the Emulsion, reflected off the
// back of the base and re-exposed it from behind.
//
// `parameters` = (threshold, knee half-width, strength, dim). The knee is the C1
// quadratic that joins zero to `x - threshold` across ±knee, so a highlight
// entering a halo does not switch on at a hard edge; Bloom sets a zero threshold
// and takes everything.
static float3 scatterKnee(float3 x, float threshold, float knee) {
    float3 d = x - threshold;
    float3 soft = (d + knee) * (d + knee) / (4.0f * knee);
    return select(select(soft, d, d >= knee), float3(0), d <= -knee);
}

kernel void scatterThreshold(texture2d<half, access::read> input [[texture(0)]],
                              texture2d<half, access::write> output [[texture(1)]],
                              constant float4 &parameters [[buffer(8)]],
                              uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    float3 excess = scatterKnee(float3(input.read(p).rgb), parameters.x, parameters.y);
    output.write(half4(half3(excess), 1.0h), p);
}

// A 2×2 box average halves the resolution between pyramid levels. Its own 0.5-texel
// sigma is part of the level's effective radius, which the renderer accounts for.
kernel void scatterDownsample(texture2d<half, access::read> input [[texture(0)]],
                               texture2d<half, access::write> output [[texture(1)]],
                               uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    uint2 limit = uint2(input.get_width() - 1, input.get_height() - 1);
    float3 sum = 0.0f;
    for (uint dy = 0; dy < 2; ++dy) {
        for (uint dx = 0; dx < 2; ++dx) sum += float3(input.read(min(p * 2 + uint2(dx, dy), limit)).rgb);
    }
    output.write(half4(half3(sum * 0.25f), 1.0h), p);
}

// One separable Gaussian per level. `SCATTER_BLUR_SIGMA` texels at every level,
// so the level scale alone sets how far the pass reaches.
constant float SCATTER_BLUR_SIGMA = 1.5f;
constant int SCATTER_BLUR_RADIUS = 5;

static void scatterBlur(texture2d<half, access::read> input, texture2d<half, access::write> output, uint2 p, int2 axis) {
    int2 limit = int2(input.get_width() - 1, input.get_height() - 1);
    float3 sum = 0.0f;
    float total = 0.0f;
    for (int i = -SCATTER_BLUR_RADIUS; i <= SCATTER_BLUR_RADIUS; ++i) {
        float weight = exp(-0.5f * float(i * i) / (SCATTER_BLUR_SIGMA * SCATTER_BLUR_SIGMA));
        sum += float3(input.read(uint2(clamp(int2(p) + axis * i, int2(0), limit))).rgb) * weight;
        total += weight;
    }
    output.write(half4(half3(sum / total), 1.0h), p);
}

kernel void scatterBlurHorizontal(texture2d<half, access::read> input [[texture(0)]],
                                   texture2d<half, access::write> output [[texture(1)]],
                                   uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    scatterBlur(input, output, p, int2(1, 0));
}

kernel void scatterBlurVertical(texture2d<half, access::read> input [[texture(0)]],
                                 texture2d<half, access::write> output [[texture(1)]],
                                 uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    scatterBlur(input, output, p, int2(0, 1));
}

// Per-channel level weighting: `weight.rgb` is how much of this level each channel
// takes, so red can resolve to a coarser level than blue from the same pyramid.
kernel void scatterScale(texture2d<half, access::read> input [[texture(0)]],
                          texture2d<half, access::write> output [[texture(1)]],
                          constant float4 &weight [[buffer(10)]],
                          uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    output.write(half4(half3(float3(input.read(p).rgb) * weight.xyz), 1.0h), p);
}

// Accumulate coarse to fine. Doubling once per level keeps the interpolation local,
// which is what stops a 32× magnification of the smallest level from banding.
//
// The coarse coordinate is an exact halving of this level's, not a ratio of the two
// textures' sizes. Those sizes round, so a ratio drifts by a texel across a level
// whose dimensions are not a clean power of two — invisible in a Preview, but in a
// tiled Export it means two neighbouring Tiles magnify the same halo by fractionally
// different amounts and their boundary shows it.
kernel void scatterUpsample(texture2d<half, access::sample> coarse [[texture(0)]],
                             texture2d<half, access::read> level [[texture(1)]],
                             texture2d<half, access::write> output [[texture(2)]],
                             constant float4 &weight [[buffer(10)]],
                             uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge, coord::normalized);
    float2 uv = (float2(p) + 0.5f) * 0.5f / float2(coarse.get_width(), coarse.get_height());
    float3 sum = float3(coarse.sample(linearSampler, uv).rgb) + float3(level.read(p).rgb) * weight.xyz;
    output.write(half4(half3(sum), 1.0h), p);
}

// The scattered light goes back into the linear signal the Film Response then
// reads. `rawWeight` is the share the unblurred extract keeps, for a radius finer
// than the smallest level's own blur. `parameters.w` is how much of the source the
// scattered light replaces rather than adds to: Halation adds, because it is a
// second exposure of the same frame, and Bloom replaces, because a lens
// redistributes the light it already had rather than creating more.
kernel void scatterComposite(texture2d<half, access::read> input [[texture(0)]],
                              texture2d<half, access::write> output [[texture(1)]],
                              texture2d<half, access::read> halo [[texture(2)]],
                              texture2d<half, access::read> raw [[texture(3)]],
                              constant float4 &parameters [[buffer(8)]],
                              constant float4 &tint [[buffer(9)]],
                              constant float4 &rawWeight [[buffer(10)]],
                              uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    half4 pixel = input.read(p);
    float3 scattered = float3(halo.read(p).rgb) + float3(raw.read(p).rgb) * rawWeight.xyz;
    float3 kept = float3(pixel.rgb) * (1.0f - parameters.w * parameters.z);
    output.write(half4(half3(kept + scattered * parameters.z * tint.xyz), pixel.a), p);
}

// Pass 7, MTF. A Stock's published response is a modulation transfer curve in
// cycles per millimetre, so it is fixed relative to the frame and converts to
// pixels through Frame Width exactly as the Halation and Grain radii do.
//
// The curve is realised as a sum of two Gaussians plus the original signal:
// a Gaussian blur of sigma s has frequency response exp(-2 pi^2 s^2 f^2), so
// c0 + c1 G(fine) + c2 G(coarse) spans both the roll-off of a fine-grained stock
// and the adjacency effect that lifts a curve above one at low frequencies. The
// renderer fits c against the published points; the shader only applies them.
struct MTFBlur { float sigma; float radius; float axisX; float axisY; };

kernel void mtfBlur(texture2d<half, access::read> input [[texture(0)]],
                    texture2d<half, access::write> output [[texture(1)]],
                    constant MTFBlur &blur [[buffer(14)]],
                    uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    int2 limit = int2(input.get_width() - 1, input.get_height() - 1);
    int2 axis = int2(int(blur.axisX), int(blur.axisY));
    int radius = int(blur.radius);
    float3 sum = 0.0f;
    float total = 0.0f;
    for (int i = -radius; i <= radius; ++i) {
        float weight = exp(-0.5f * float(i * i) / (blur.sigma * blur.sigma));
        sum += float3(input.read(uint2(clamp(int2(p) + axis * i, int2(0), limit))).rgb) * weight;
        total += weight;
    }
    output.write(half4(half3(sum / total), input.read(p).a), p);
}

// c0 + c1 + c2 = 1, so a flat field is unchanged and the pass alters micro-contrast
// only. Values stay signed: the Working Space carries out-of-gamut light, and the
// Film Response is what decides where the signal is clamped.
kernel void mtfCombine(texture2d<half, access::read> input [[texture(0)]],
                       texture2d<half, access::write> output [[texture(1)]],
                       texture2d<half, access::read> fine [[texture(4)]],
                       texture2d<half, access::read> coarse [[texture(5)]],
                       constant float4 &coefficients [[buffer(14)]],
                       uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    half4 pixel = input.read(p);
    float3 value = float3(pixel.rgb) * coefficients.x
        + float3(fine.read(p).rgb) * coefficients.y + float3(coarse.read(p).rgb) * coefficients.z;
    output.write(half4(half3(value), pixel.a), p);
}

static float3 tetrahedral(texture3d<half, access::read> cube, float3 coordinate) {
    float3 q = coordinate * float(cube.get_width() - 1);
    // Extrapolate boundary tetrahedra so identity preserves negative and HDR values.
    int3 base = int3(clamp(floor(q), 0.0f, float(cube.get_width() - 2)));
    float3 f = q - float3(base);
    uint a = 0, b = 1, c = 2;
    if (f[a] < f[b]) { uint t = a; a = b; b = t; }
    if (f[b] < f[c]) { uint t = b; b = c; c = t; }
    if (f[a] < f[b]) { uint t = a; a = b; b = t; }
    uint3 v0 = uint3(base), v1 = v0, v2;
    v1[a] += 1; v2 = v1; v2[b] += 1;
    float3 x0 = float3(cube.read(v0).rgb);
    float3 x1 = float3(cube.read(v1).rgb);
    float3 x2 = float3(cube.read(v2).rgb);
    float3 x3 = float3(cube.read(v0 + 1).rgb);
    return x0 + f[a] * (x1 - x0) + f[b] * (x2 - x1) + f[c] * (x3 - x2);
}

// Pass 8. `shaper` = (enabled, minimumLogExposure, 1 / log range, middleGrayLogExposure)
// maps scene-linear light to the spectral Colour Cube's log-exposure coordinate;
// disabled, the cube is addressed by linear [0, 1] values. `blend.x` weights the
// second Colour Cube, the neighbouring Development Offset variant.
kernel void filmResponse(texture2d<half, access::read> input [[texture(0)]],
                         texture2d<half, access::write> output [[texture(1)]],
                         texture3d<half, access::read> lower [[texture(2)]],
                         texture3d<half, access::read> upper [[texture(3)]],
                         constant float4 &shaper [[buffer(4)]],
                         constant float4 &blend [[buffer(5)]],
                         uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    half4 pixel = input.read(p);
    float3 coordinate = float3(pixel.rgb);
    if (shaper.x != 0) {
        float3 logH = log10(max(coordinate, float3(1e-6f)) / 0.18f) + shaper.w;
        coordinate = clamp((logH - shaper.y) * shaper.z, 0.0f, 1.0f);
    }
    float3 value = tetrahedral(lower, coordinate);
    if (blend.x > 0) value = mix(value, tetrahedral(upper, coordinate), blend.x);
    // IEEE additions can turn -0 into +0. Preserve the input sign when a
    // component maps zero to zero, without bypassing Colour Cube sampling.
    value = select(value, copysign(float3(0), float3(pixel.rgb)), (value == 0) & (float3(pixel.rgb) == 0));
    output.write(half4(half3(value), pixel.a), p);
}

kernel void monochromeResponse(texture2d<half, access::read> input [[texture(0)]],
                               texture2d<half, access::write> output [[texture(1)]],
                               texture1d<half, access::read> densityCurve [[texture(2)]],
                               constant float4 &spectralWeight [[buffer(1)]],
                               uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    half4 pixel = input.read(p);
    float gray = dot(float3(pixel.rgb), spectralWeight.xyz);
    float position = clamp(gray, 0.0f, 1.0f) * 1023.0f;
    uint low = min(uint(floor(position)), 1022u);
    float a = float(densityCurve.read(low).r);
    float b = float(densityCurve.read(low + 1).r);
    half density = half(a + (position - float(low)) * (b - a));
    output.write(half4(density, density, density, pixel.a), p);
}

// Pass 9, Grain. Density Space, after the Film Response and before the Output
// Stage, so the scan or print acts on the grain the way it would on real film.
//
// `cell` is the noise correlation length in pixels, derived from
// `grainRadiusMicrons` through Frame Width and never from a pixel count, and
// floored at the sampling pitch: a frame that cannot resolve a 1.2 um crystal
// records its fluctuation within one pixel rather than across several. `sigma`
// carries the corresponding Selwyn amplitude, and `mix` splits each channel
// between its own noise and the shared field so `channelCorrelation` decides how
// far the three Emulsion layers grain together.
struct GrainUniforms {
    float4 sigma;   // per-channel density sigma, already scaled by the user's intensity
    float4 cell;    // per-channel noise cell in pixels, at least one
    float4 mix;     // (independent weight, shared weight, shared cell, density space)
    float4 base;    // the Stock's base value per channel
    float4 scale;   // maps base to 0 and mid-grey to 0.5 of the Density Response
    uint4 seed;
};

static uint grainHash(uint3 v) {
    uint h = v.x * 0x9E3779B9u ^ v.y * 0x85EBCA6Bu ^ v.z * 0xC2B2AE35u;
    h ^= h >> 15; h *= 0x2C1B3C6Du; h ^= h >> 12; h *= 0x297A2D39u; h ^= h >> 15;
    return h;
}

/// Unit-variance lattice value. Global pixel coordinates, so a later tiled Export
/// samples the same field from any tile origin.
static float grainLattice(int2 cell, uint channel, uint seed) {
    uint h = grainHash(uint3(uint(cell.x + 0x8000), uint(cell.y + 0x8000), channel * 0x9E3779B9u + seed));
    return (float(h) * (1.0f / 4294967296.0f) - 0.5f) * 3.4641016f;
}

// Smoothstep-interpolated value noise loses variance to the interpolation; the
// constant restores unit variance so `sigma` is the density sigma it claims to be.
constant float GRAIN_NOISE_NORMALISATION = 1.3462f;

static float grainNoise(float2 position, float cell, uint channel, uint seed) {
    // A cell of one pixel is grain the frame cannot resolve, and one pixel then
    // holds one independent sample of it. Interpolating there would average four
    // lattice points into every pixel, correlating neighbours that share none of
    // the same crystals and costing a third of the amplitude.
    if (cell <= 1.0f) return grainLattice(int2(floor(position)), channel, seed);
    float2 q = position / cell;
    float2 corner = floor(q);
    float2 f = q - corner;
    float2 s = f * f * (3.0f - 2.0f * f);
    int2 c = int2(corner);
    float n00 = grainLattice(c, channel, seed);
    float n10 = grainLattice(c + int2(1, 0), channel, seed);
    float n01 = grainLattice(c + int2(0, 1), channel, seed);
    float n11 = grainLattice(c + int2(1, 1), channel, seed);
    return mix(mix(n00, n10, s.x), mix(n01, n11, s.x), s.y) * GRAIN_NOISE_NORMALISATION;
}

kernel void grain(texture2d<half, access::read> input [[texture(0)]],
                  texture2d<half, access::write> output [[texture(1)]],
                  constant GrainUniforms &grain [[buffer(11)]],
                  constant float *densityResponse [[buffer(12)]],
                  constant float4 &frame [[buffer(17)]],
                  uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    half4 pixel = input.read(p);
    // Image-global, not Tile-local: the lattice below is addressed by this, so a
    // Tile-local position would restart the field at every Tile origin and repeat
    // the same grain at the Tile pitch.
    float2 position = float2(p) + frame.xy + 0.5f;
    float3 value = float3(pixel.rgb);
    float shared = grainNoise(position, grain.mix.z, 3u, grain.seed.x);
    float3 result;
    for (uint c = 0; c < 3; ++c) {
        // The Density Response is loud in the midtones and quiet at both ends,
        // which is what separates emulsion from noise added to the whole frame.
        float t = clamp((value[c] - grain.base[c]) * grain.scale[c], 0.0f, 1.0f) * 31.0f;
        uint low = min(uint(t), 30u);
        float amplitude = mix(densityResponse[low], densityResponse[low + 1], t - float(low));
        float noise = grain.mix.x * grainNoise(position, grain.cell[c], c, grain.seed.x) + grain.mix.y * shared;
        float density = grain.sigma[c] * amplitude * noise;
        // A Density Space signal takes the fluctuation directly. A Colour Cube that
        // already carries the Baker's scan returns a positive, where the same extra
        // density is a transmission the light has to pass through.
        result[c] = grain.mix.w > 0.5f ? value[c] + density : value[c] * exp10(-density);
    }
    output.write(half4(half3(result), pixel.a), p);
}

// Pass 10, Scan. Inverts Density Space above the Stock's base density and
// auto-balances so its mid-grey density lands on 0.18 in every channel, with the
// same rational shoulder the Baker uses for spectral scan cubes.
kernel void scanOutput(texture2d<half, access::read> input [[texture(0)]],
                       texture2d<half, access::write> output [[texture(1)]],
                       constant float4 &grayDensity [[buffer(6)]],
                       constant float4 &baseDensity [[buffer(7)]],
                       uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    half4 pixel = input.read(p);
    float3 signal = max(exp10(float3(pixel.rgb) - baseDensity.xyz) - 1.0f, 0.0f);
    float3 gray = exp10(grayDensity.xyz - baseDensity.xyz) - 1.0f;
    float3 linear = (0.18f / 0.82f) * signal / gray;
    float3 positive = linear / (1.0f + linear);
    output.write(half4(half3(positive), pixel.a), p);
}

// Pass 11, Geometry. The lens's falloff, the gate's unsteadiness and the frame's
// own edge: everything whose value depends on where in the frame a pixel sits.
// `geometry` = (vignette, gate weave x, gate weave y, border half-width), the
// weave and the border in pixels converted from Film-Plane Microns.
kernel void geometry(texture2d<half, access::sample> input [[texture(0)]],
                     texture2d<half, access::write> output [[texture(1)]],
                     constant float4 &geometry [[buffer(16)]],
                     constant float4 &frame [[buffer(17)]],
                     uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    // The falloff and the rebate belong to the frame; the gate's displacement is a
    // read from this Tile's own texture, and the Apron is what it reads into.
    float2 size = frame.zw;
    float2 global = float2(p) + frame.xy + 0.5f;
    constexpr sampler frameSampler(filter::linear, address::clamp_to_edge, coord::normalized);
    float2 uv = (float2(p) + 0.5f + geometry.yz) / float2(output.get_width(), output.get_height());
    half4 pixel = input.sample(frameSampler, uv);
    // Radius from the frame centre, one at the corners in either orientation, so
    // the falloff is a circle on the film rather than an ellipse in pixels.
    float2 offset = (global - size * 0.5f) / (0.5f * length(size));
    float r2 = dot(offset, offset);
    // cos^4 of the angle off axis: a lens's own falloff, two stops in the corners
    // at full strength.
    float falloff = mix(1.0f, 1.0f / ((1.0f + r2) * (1.0f + r2)), geometry.x);
    // The rebate outside the exposed frame carries no image at all.
    float2 edge = min(global, size - global);
    float border = geometry.w <= 0.0f ? 1.0f
        : smoothstep(geometry.w - 0.5f, geometry.w + 0.5f, min(edge.x, edge.y));
    output.write(half4(half3(float3(pixel.rgb) * falloff * border), pixel.a), p);
}

float transfer(float x) {
    float a = abs(x);
    return copysign(a <= 0.0031308f ? 12.92f * a : 1.055f * pow(a, 1.0f / 2.4f) - 0.055f, x);
}

// Pass 12. `output` is `RenderSettings.Output`: 0 leaves the Working Space alone,
// 1 encodes Display P3 and 2 sRGB. Both share the sRGB transfer function and
// differ only in primaries, and both keep values outside 0...1 rather than
// clamping, so EDR headroom survives to the display. A file writer is where
// clipping to the format's range belongs.
kernel void outputTransform(texture2d<half, access::read> input [[texture(0)]],
                            texture2d<half, access::write> output [[texture(1)]],
                            constant uint &encoding [[buffer(0)]],
                            uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    half4 pixel = input.read(p);
    if (encoding == 0) { output.write(pixel, p); return; }
    float3 x = float3(pixel.rgb);
    float3x3 primaries = encoding == 1
        ? float3x3(float3(1.3435783f, -0.0652975f, 0.0028218f),
                   float3(-0.2821797f, 1.0757879f, -0.0195985f),
                   float3(-0.0613986f, -0.0104904f, 1.0167767f))
        : float3x3(float3(1.6604910f, -0.1245505f, -0.0181508f),
                   float3(-0.5876411f, 1.1328999f, -0.1005789f),
                   float3(-0.0728499f, -0.0083494f, 1.1187297f));
    float3 encoded = primaries * x;
    output.write(half4(transfer(encoded.r), transfer(encoded.g), transfer(encoded.b), pixel.a), p);
}
