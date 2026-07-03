#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_strength;
    float u_contrast;
};

struct fx_cross_process_out
{
    float4 frag [[color(0)]];
};

struct fx_cross_process_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_cross_process_out fx_cross_process(fx_cross_process_in in [[stage_in]], constant Params& _49 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_cross_process_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float3 c = col.xyz;
    float r = fast::clamp(powr(c.x * 1.2000000476837158203125, 0.699999988079071044921875) * 1.10000002384185791015625, 0.0, 1.0);
    float g = fast::clamp((((c.y - 0.5) * 1.0) * _49.u_contrast) + 0.5, 0.0, 1.0);
    float b = fast::clamp(1.0 - (powr(1.0 - c.z, 0.60000002384185791015625) * 0.89999997615814208984375), 0.0, 1.0);
    float3 xp = float3(r, g, b);
    float lum = dot(xp, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    xp = mix(float3(lum), xp, float3(2.2000000476837158203125));
    xp = fast::clamp(((xp - float3(0.5)) * _49.u_contrast) + float3(0.5), float3(0.0), float3(1.0));
    out.frag = float4(mix(col.xyz, xp, float3(_49.u_strength)), col.w);
    return out;
}

