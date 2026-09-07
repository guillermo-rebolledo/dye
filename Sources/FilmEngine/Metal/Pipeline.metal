#include <metal_stdlib>
using namespace metal;

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

// Pass 5, Halation. Light that passes through the Emulsion reflects off the back
// of the base and re-exposes it from behind, so this runs on scene-linear light
// before the Film Response rather than as a post effect on the developed image.
//
// `parameters` = (threshold, knee half-width, strength, unused). The knee is the
// C1 quadratic that joins zero to `x - threshold` across ±knee, so a highlight
// entering the halo does not switch on at a hard edge.
static float3 halationKnee(float3 x, float threshold, float knee) {
    float3 d = x - threshold;
    float3 soft = (d + knee) * (d + knee) / (4.0f * knee);
    return select(select(soft, d, d >= knee), float3(0), d <= -knee);
}

kernel void halationThreshold(texture2d<half, access::read> input [[texture(0)]],
                              texture2d<half, access::write> output [[texture(1)]],
                              constant float4 &parameters [[buffer(8)]],
                              uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    float3 excess = halationKnee(float3(input.read(p).rgb), parameters.x, parameters.y);
    output.write(half4(half3(excess), 1.0h), p);
}

// A 2×2 box average halves the resolution between pyramid levels. Its own 0.5-texel
// sigma is part of the level's effective radius, which the renderer accounts for.
kernel void halationDownsample(texture2d<half, access::read> input [[texture(0)]],
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

// One separable Gaussian per level. `HALATION_BLUR_SIGMA` texels at every level,
// so the level scale alone sets how far the pass reaches.
constant float HALATION_BLUR_SIGMA = 1.5f;
constant int HALATION_BLUR_RADIUS = 5;

static void halationBlur(texture2d<half, access::read> input, texture2d<half, access::write> output, uint2 p, int2 axis) {
    int2 limit = int2(input.get_width() - 1, input.get_height() - 1);
    float3 sum = 0.0f;
    float total = 0.0f;
    for (int i = -HALATION_BLUR_RADIUS; i <= HALATION_BLUR_RADIUS; ++i) {
        float weight = exp(-0.5f * float(i * i) / (HALATION_BLUR_SIGMA * HALATION_BLUR_SIGMA));
        sum += float3(input.read(uint2(clamp(int2(p) + axis * i, int2(0), limit))).rgb) * weight;
        total += weight;
    }
    output.write(half4(half3(sum / total), 1.0h), p);
}

kernel void halationBlurHorizontal(texture2d<half, access::read> input [[texture(0)]],
                                   texture2d<half, access::write> output [[texture(1)]],
                                   uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    halationBlur(input, output, p, int2(1, 0));
}

kernel void halationBlurVertical(texture2d<half, access::read> input [[texture(0)]],
                                 texture2d<half, access::write> output [[texture(1)]],
                                 uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    halationBlur(input, output, p, int2(0, 1));
}

// Per-channel level weighting: `weight.rgb` is how much of this level each channel
// takes, so red can resolve to a coarser level than blue from the same pyramid.
kernel void halationScale(texture2d<half, access::read> input [[texture(0)]],
                          texture2d<half, access::write> output [[texture(1)]],
                          constant float4 &weight [[buffer(10)]],
                          uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    output.write(half4(half3(float3(input.read(p).rgb) * weight.xyz), 1.0h), p);
}

// Accumulate coarse to fine. Doubling once per level keeps the interpolation local,
// which is what stops a 32× magnification of the smallest level from banding.
kernel void halationUpsample(texture2d<half, access::sample> coarse [[texture(0)]],
                             texture2d<half, access::read> level [[texture(1)]],
                             texture2d<half, access::write> output [[texture(2)]],
                             constant float4 &weight [[buffer(10)]],
                             uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge, coord::normalized);
    float2 uv = (float2(p) + 0.5f) / float2(output.get_width(), output.get_height());
    float3 sum = float3(coarse.sample(linearSampler, uv).rgb) + float3(level.read(p).rgb) * weight.xyz;
    output.write(half4(half3(sum), 1.0h), p);
}

// The tinted halo goes back into the linear signal the Film Response then reads.
// `rawWeight` is the share the unblurred extract keeps, for a radius finer than
// the smallest level's own blur.
kernel void halationComposite(texture2d<half, access::read> input [[texture(0)]],
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
    output.write(half4(half3(float3(pixel.rgb) + scattered * parameters.z * tint.xyz), pixel.a), p);
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

// Pass 7. `shaper` = (enabled, minimumLogExposure, 1 / log range, middleGrayLogExposure)
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

// Pass 9, Scan. Inverts Density Space above the Stock's base density and
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

float transfer(float x) {
    float a = abs(x);
    return copysign(a <= 0.0031308f ? 12.92f * a : 1.055f * pow(a, 1.0f / 2.4f) - 0.055f, x);
}

kernel void outputTransform(texture2d<half, access::read> input [[texture(0)]],
                            texture2d<half, access::write> output [[texture(1)]],
                            constant uint &displayP3 [[buffer(0)]],
                            uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    half4 pixel = input.read(p);
    if (displayP3 == 0) { output.write(pixel, p); return; }
    float3 x = float3(pixel.rgb);
    float3 p3 = float3(dot(x, float3(1.3435783f, -0.2821797f, -0.0613986f)),
                      dot(x, float3(-0.0652975f, 1.0757879f, -0.0104904f)),
                      dot(x, float3(0.0028218f, -0.0195985f, 1.0167767f)));
    output.write(half4(transfer(p3.r), transfer(p3.g), transfer(p3.b), pixel.a), p);
}
