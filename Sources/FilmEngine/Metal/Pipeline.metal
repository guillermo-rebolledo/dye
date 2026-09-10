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

// Pass 4. Reciprocity Failure: below the Stock's threshold a doubled exposure
// time is exactly a doubled exposure, and above it the emulsion keeps less and
// less of what it is given. `gain` is (H_eff / H) per channel, already resolved
// from the Schwarzschild exponents and the frame's exposure time, so the shader
// is a per-channel multiply — but not the Exposure Pass's, because the three
// layers lose speed at different rates and the frame shifts colour as it darkens.
kernel void reciprocity(texture2d<half, access::read> input [[texture(0)]],
                        texture2d<half, access::write> output [[texture(1)]],
                        constant float4 &gain [[buffer(13)]],
                        uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    half4 pixel = input.read(p);
    output.write(half4(half3(float3(pixel.rgb) * gain.xyz), pixel.a), p);
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

// Pass 8 for a black & white Stock: the Monochrome Collapse, then the Density Curve.
// No Colour Cube is sampled and none is bound — a spectral sensitivity collapsing to
// one channel is both cheaper and closer to what the film does than a 3D lookup.
//
// `spectralWeight.xyz` is the Stock's own weighting for whichever Contrast Filter is
// fitted, already normalised so the glass costs tonal separation and not exposure.
// The filter itself is a spectral multiply the Baker applied before the collapse; by
// the time it reaches here it has become the collapse's weights, which is the same
// operation and one dot product instead of a pass. `shaper` matches `filmResponse`.
kernel void monochromeResponse(texture2d<half, access::read> input [[texture(0)]],
                               texture2d<half, access::write> output [[texture(1)]],
                               texture1d<half, access::read> densityCurve [[texture(2)]],
                               constant float4 &spectralWeight [[buffer(1)]],
                               constant float4 &shaper [[buffer(4)]],
                               uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    half4 pixel = input.read(p);
    float gray = dot(float3(pixel.rgb), spectralWeight.xyz);
    if (shaper.x != 0) {
        float logH = log10(max(gray, 1e-6f) / 0.18f) + shaper.w;
        gray = (logH - shaper.y) * shaper.z;
    }
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

// A dye cloud is not a silver crystal. Development leaves a cloud of dye around
// each developed grain, an order of magnitude wider and with no hard edge, so two
// things change and only these two. The field stays spatially correlated below the
// sampling pitch, where the crystal model deliberately gives each pixel its own
// independent sample: neighbouring pixels of an unresolved crystal share no
// crystals, but they do share a cloud. And the clouds clump, so a coarser octave
// rides on the first. Weights are variance-preserving, so `rmsGranularity` still
// means the density sigma it names.
constant float DYE_CLOUD_FINE = 0.8f;
constant float DYE_CLOUD_COARSE = 0.6f;  // sqrt(1 - 0.8^2): a tuned share, not a measurement
constant float DYE_CLOUD_CLUMP = 3.0f;

/// The cloud's own field plus the clump it sits in. The clump is always wider than
/// the sampling pitch, so it stays correlated across neighbouring pixels even where
/// the cloud itself is far too small for the frame to resolve — which is the whole
/// Catalogue at any practical output size, and is why this reads as mottling rather
/// than as the crystal model at a different amplitude.
static float dyeCloudNoise(float2 position, float cell, uint channel, uint seed) {
    float fine = grainNoise(position, cell, channel, seed);
    // A different lattice channel, so the clump is its own field rather than a
    // rescaling of the one it rides on.
    float coarse = grainNoise(position, max(cell, 1.0f) * DYE_CLOUD_CLUMP, channel + 4u, seed);
    return DYE_CLOUD_FINE * fine + DYE_CLOUD_COARSE * coarse;
}

kernel void grainDyeCloud(texture2d<half, access::read> input [[texture(0)]],
                          texture2d<half, access::write> output [[texture(1)]],
                          constant GrainUniforms &grain [[buffer(11)]],
                          constant float *densityResponse [[buffer(12)]],
                          constant float4 &frame [[buffer(17)]],
                          uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    half4 pixel = input.read(p);
    float2 position = float2(p) + frame.xy + 0.5f;
    float3 value = float3(pixel.rgb);
    float shared = dyeCloudNoise(position, grain.mix.z, 3u, grain.seed.x);
    float3 result;
    for (uint c = 0; c < 3; ++c) {
        float t = clamp((value[c] - grain.base[c]) * grain.scale[c], 0.0f, 1.0f) * 31.0f;
        uint low = min(uint(t), 30u);
        float amplitude = mix(densityResponse[low], densityResponse[low + 1], t - float(low));
        float noise = grain.mix.x * dyeCloudNoise(position, grain.cell[c], c, grain.seed.x) + grain.mix.y * shared;
        float density = grain.sigma[c] * amplitude * noise;
        result[c] = grain.mix.w > 0.5f ? value[c] + density : value[c] * exp10(-density);
    }
    output.write(half4(half3(result), pixel.a), p);
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

// The sRGB transfer function and its inverse, both applied through the sign so an
// out-of-gamut Working Space value survives a round trip, and both continuing the
// power curve above one so scene light past diffuse white does too. The Output
// Transform encodes with the first; the Adjustment Pass works between the two.
float transfer(float x) {
    float a = abs(x);
    return copysign(a <= 0.0031308f ? 12.92f * a : 1.055f * pow(a, 1.0f / 2.4f) - 0.055f, x);
}

static float inverseTransfer(float x) {
    float a = abs(x);
    return copysign(a <= 0.04045f ? a / 12.92f : pow((a + 0.055f) / 1.055f, 2.4f), x);
}

// Pass 11, Adjustments. What a photo editor does to the scan afterwards: the tone
// and colour controls, applied per pixel to the positive the Output Stage returned
// and never to the light before the film. Neutral settings do not run the Pass.
//
// `tone` = (black point, brightness, shadows, highlights), `colour` = (contrast,
// saturation, vibrance, unused), each −1…1, the renderer having already folded
// Brilliance into shadows, highlights and contrast and clamped those three sums
// back to ±1, which is what keeps the curve below monotone at the gains it uses.
//
// The tone controls compose one curve in the display encoding, applied to each
// channel, which is what a photo editor's RGB tone curve is. Every term is a
// polynomial in the clamped value with zeros at black and white, so the curve is
// monotone across the whole control range, holds the two ends still where a
// control says it does, and leaves a value outside 0…1 alone rather than
// extrapolating it — except highlight recovery, whose whole purpose is to bring
// light from above white back below it, and which is a knee for that reason.
struct AdjustmentUniforms {
    float4 tone;
    float4 colour;
};

static float adjustTone(float x, float4 tone, float contrast) {
    // Black point: positive moves the encoded value that reads as black up to
    // 0.15, crushing what was below it into black itself rather than past it;
    // negative lifts black to a matte grey. An out-of-gamut value below zero is
    // left where it was, because it was never a tone to crush.
    float t = 0.15f * tone.x;
    x = max((x - t) / (1.0f - t), min(x, 0.0f));
    // Brightness: the midtones, peaking at mid-grey, with black and white held.
    float c = clamp(x, 0.0f, 1.0f);
    x += 0.5f * tone.y * c * (1.0f - c);
    // Shadows: peaks a quarter of the way up, where the darkest tones a picture
    // actually has sit, and is gone well before white. The two directions are
    // geared differently because the curve's own slope bounds them differently:
    // opening the shadows is bounded at the top of the mask, which leaves room
    // for a gain above one, and closing them is bounded at black, where the
    // slope cannot go below zero. The gains are the largest each direction
    // admits with a tenth of the slope still to spare.
    c = clamp(x, 0.0f, 1.0f);
    float shadowMask = c * (1.0f - c) * (1.0f - c) * (1.0f - c);
    x += (tone.z >= 0.0f ? 2.0f : 0.9f) * tone.z * shadowMask;
    // Highlights: pushing peaks three quarters of the way up, the mirror of the
    // shadow mask, so it reaches the brights and leaves the midtones alone;
    // recovering is a C1 knee from mid-grey that compresses everything above it,
    // including light past white, back toward the range.
    if (tone.w >= 0.0f) {
        c = clamp(x, 0.0f, 1.0f);
        x += 0.9f * tone.w * c * c * c * (1.0f - c);
    } else if (x > 0.5f) {
        float d = x - 0.5f;
        x = 0.5f + d / (1.0f - 3.0f * tone.w * d);
    }
    // Contrast: an S about mid-grey, slope 1.5 there at full and 0.5 at full
    // negative, flattening into a toe and a shoulder at the ends.
    c = clamp(x, 0.0f, 1.0f);
    x += 2.0f * contrast * (c - 0.5f) * c * (1.0f - c);
    return x;
}

kernel void adjust(texture2d<half, access::read> input [[texture(0)]],
                   texture2d<half, access::write> output [[texture(1)]],
                   constant AdjustmentUniforms &adjustments [[buffer(15)]],
                   uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    half4 pixel = input.read(p);
    float3 value = float3(pixel.rgb);
    float3 encoded = float3(transfer(value.r), transfer(value.g), transfer(value.b));
    for (uint c = 0; c < 3; ++c) encoded[c] = adjustTone(encoded[c], adjustments.tone, adjustments.colour.x);
    value = float3(inverseTransfer(encoded.r), inverseTransfer(encoded.g), inverseTransfer(encoded.b));

    // Colour, in linear light about Rec.2020 luminance, which chroma scaling holds.
    float luminance = dot(value, float3(0.2627f, 0.6780f, 0.0593f));
    float3 chroma = value - luminance;
    float vibrance = adjustments.colour.z;
    if (vibrance != 0.0f) {
        float top = max(max(value.r, value.g), value.b);
        float bottom = min(min(value.r, value.g), value.b);
        float spread = top - bottom;
        // How saturated the pixel already is; a boost goes to the muted ones.
        float saturated = top > 1e-6f ? clamp(spread / top, 0.0f, 1.0f) : 0.0f;
        // Skin sits between red and yellow with red on top: about 10° to 50° of
        // hue. Those pixels are protected from most of a boost, not from a cut.
        float skin = 0.0f;
        if (value.r >= value.g && value.g >= value.b && spread > 1e-6f) {
            float hue = (value.g - value.b) / spread;
            skin = smoothstep(0.15f, 0.35f, hue) * (1.0f - smoothstep(0.65f, 0.9f, hue));
        }
        float gain = vibrance > 0.0f
            ? 1.0f + vibrance * (1.0f - saturated) * (1.0f - 0.75f * skin)
            : 1.0f + vibrance;
        chroma *= gain;
    }
    chroma *= 1.0f + adjustments.colour.y;
    output.write(half4(half3(luminance + chroma), pixel.a), p);
}

// Pass 12, Geometry. The lens's falloff, the gate's unsteadiness and the frame's
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

// Pass 13. `output` is `RenderSettings.Output`: 0 leaves the Working Space alone,
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
