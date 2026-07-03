#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_saturation;
    float u_contrast;
    float u_warmth;
};

struct fx_technicolor_out
{
    float4 frag [[color(0)]];
};

struct fx_technicolor_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_technicolor_out fx_technicolor(fx_technicolor_in in [[stage_in]], constant Params& _38 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_technicolor_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float3 sat = mix(float3(lum), col.xyz, float3(_38.u_saturation));
    sat = fast::clamp(((sat - float3(0.5)) * _38.u_contrast) + float3(0.5), float3(0.0), float3(1.0));
    sat.x = fast::min(sat.x * (1.0 + (_38.u_warmth * 0.25)), 1.0);
    sat.z *= (1.0 - (_38.u_warmth * 0.1500000059604644775390625));
    float r = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + float2(0.00200000009499490261077880859375, 0.0), float2(0.0), float2(1.0))).x;
    float lum2 = dot(sat, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    sat.x = mix(sat.x, powr(r * (1.0 + (_38.u_warmth * 0.300000011920928955078125)), 0.89999997615814208984375), 0.300000011920928955078125);
    out.frag = float4(fast::clamp(sat, float3(0.0), float3(1.0)), col.w);
    return out;
}

