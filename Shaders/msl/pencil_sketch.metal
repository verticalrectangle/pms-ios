#pragma clang diagnostic ignored "-Wmissing-prototypes"
#pragma clang diagnostic ignored "-Wmissing-braces"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

template<typename T, size_t Num>
struct spvUnsafeArray
{
    T elements[Num ? Num : 1];
    
    thread T& operator [] (size_t pos) thread
    {
        return elements[pos];
    }
    constexpr const thread T& operator [] (size_t pos) const thread
    {
        return elements[pos];
    }
    
    device T& operator [] (size_t pos) device
    {
        return elements[pos];
    }
    constexpr const device T& operator [] (size_t pos) const device
    {
        return elements[pos];
    }
    
    constexpr const constant T& operator [] (size_t pos) const constant
    {
        return elements[pos];
    }
    
    threadgroup T& operator [] (size_t pos) threadgroup
    {
        return elements[pos];
    }
    constexpr const threadgroup T& operator [] (size_t pos) const threadgroup
    {
        return elements[pos];
    }
};

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_line_str;
    float u_paper_tone;
    float u_hatching;
    float u_strength;
};

struct fx_pencil_sketch_out
{
    float4 frag [[color(0)]];
};

struct fx_pencil_sketch_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_pencil_sketch_out fx_pencil_sketch(fx_pencil_sketch_in in [[stage_in]], constant Params& _13 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_pencil_sketch_out out = {};
    float2 px = float2(1.0 / _13.u_tex_w, 1.0 / _13.u_tex_h);
    int idx = 0;
    spvUnsafeArray<float, 9> k;
    for (int dy = -1; dy <= 1; dy++)
    {
        for (int dx = -1; dx <= 1; dx++)
        {
            float3 c = u_tex.sample(u_texSmplr, (in.v_uv + (float2(float(dx), float(dy)) * px))).xyz;
            int _72 = idx;
            idx = _72 + 1;
            k[_72] = dot(c, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
        }
    }
    float gx = (((((-k[0]) + k[2]) - (2.0 * k[3])) + (2.0 * k[5])) - k[6]) + k[8];
    float gy = (((((-k[0]) - (2.0 * k[1])) - k[2]) + k[6]) + (2.0 * k[7])) + k[8];
    float edge = fast::clamp(sqrt((gx * gx) + (gy * gy)) * _13.u_line_str, 0.0, 1.0);
    float lum0 = k[4];
    float hatch = step(0.5 - (lum0 * 0.5), fract(((in.v_uv.x + in.v_uv.y) * _13.u_tex_w) * 0.039999999105930328369140625));
    hatch *= step(0.5 - (lum0 * 0.5), fract(((in.v_uv.x - in.v_uv.y) * _13.u_tex_w) * 0.039999999105930328369140625));
    float sketch = fast::max(edge, (((1.0 - hatch) * (1.0 - lum0)) * _13.u_hatching) * 0.800000011920928955078125);
    float3 paper = float3(_13.u_paper_tone, _13.u_paper_tone * 0.9700000286102294921875, _13.u_paper_tone * 0.920000016689300537109375);
    float3 result = mix(paper, float3(0.100000001490116119384765625, 0.07999999821186065673828125, 0.0500000007450580596923828125), float3(sketch));
    float4 orig = u_tex.sample(u_texSmplr, in.v_uv);
    out.frag = float4(fast::clamp(mix(orig.xyz, result, float3(_13.u_strength)), float3(0.0), float3(1.0)), orig.w);
    return out;
}

