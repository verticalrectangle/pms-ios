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
    float u_density;
    float u_thickness;
    float u_angle;
};

struct fx_crosshatch_out
{
    float4 frag [[color(0)]];
};

struct fx_crosshatch_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_crosshatch_out fx_crosshatch(fx_crosshatch_in in [[stage_in]], constant Params& _35 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_crosshatch_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float2 uv_px = in.v_uv * float2(_35.u_tex_w, _35.u_tex_h);
    float paper = 0.949999988079071044921875;
    float ink = 0.0;
    spvUnsafeArray<float, 4> angles;
    angles[0] = _35.u_angle * 0.01745329238474369049072265625;
    angles[1] = angles[0] + 0.785000026226043701171875;
    angles[2] = angles[0] + 0.39300000667572021484375;
    angles[3] = angles[0] - 0.39300000667572021484375;
    for (int i = 0; i < 4; i++)
    {
        float thresh = float(i + 1) * 0.2199999988079071044921875;
        if (lum < thresh)
        {
            float cs = cos(angles[i]);
            float sn = sin(angles[i]);
            float proj = (cs * uv_px.x) + (sn * uv_px.y);
            float line = abs(fract(proj / _35.u_density) - 0.5) * 2.0;
            float hatch = 1.0 - smoothstep(1.0 - _35.u_thickness, 1.0, line);
            ink = fast::max(ink, hatch);
        }
    }
    float3 result = float3(paper) * (1.0 - (ink * 0.89999997615814208984375));
    result = mix(result, result * ((col.xyz * 0.4000000059604644775390625) + float3(0.699999988079071044921875)), float3(0.25));
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), col.w);
    return out;
}

