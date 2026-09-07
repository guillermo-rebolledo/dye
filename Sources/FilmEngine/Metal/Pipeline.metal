#include <metal_stdlib>
using namespace metal;

kernel void passthrough(texture2d<half, access::read> input [[texture(0)]],
                        texture2d<half, access::write> output [[texture(1)]],
                        uint2 p [[thread_position_in_grid]]) {
    if (p.x < output.get_width() && p.y < output.get_height()) output.write(input.read(p), p);
}

kernel void filmResponse(texture2d<half, access::read> input [[texture(0)]],
                         texture2d<half, access::write> output [[texture(1)]],
                         texture3d<half, access::read> cube [[texture(2)]],
                         uint2 p [[thread_position_in_grid]]) {
    if (p.x >= output.get_width() || p.y >= output.get_height()) return;
    half4 pixel = input.read(p);
    float3 q = float3(pixel.rgb) * float(cube.get_width() - 1);
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
    float3 value = x0 + f[a] * (x1 - x0) + f[b] * (x2 - x1) + f[c] * (x3 - x2);
    // IEEE additions can turn -0 into +0. Preserve the input sign when a
    // component maps zero to zero, without bypassing Colour Cube sampling.
    value = select(value, copysign(float3(0), float3(pixel.rgb)), (value == 0) & (float3(pixel.rgb) == 0));
    output.write(half4(half3(value), pixel.a), p);
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
