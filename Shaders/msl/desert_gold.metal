#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_warmth;
    float u_fade;
    float u_haze;
};

struct fx_desert_gold_out
{
    float4 frag [[color(0)]];
};

struct fx_desert_gold_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_desert_gold_out fx_desert_gold(fx_desert_gold_in in [[stage_in]], constant Params& _37 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_desert_gold_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float3 warm = col.xyz * float3(1.0 + (_37.u_warmth * 0.300000011920928955078125), 1.0 + (_37.u_warmth * 0.100000001490116119384765625), 1.0 - (_37.u_warmth * 0.300000011920928955078125));
    float lift = _37.u_fade * 0.180000007152557373046875;
    warm = (warm * (1.0 - lift)) + float3(lift);
    float3 haze_col = float3(1.0, 0.920000016689300537109375, 0.75);
    warm = mix(warm, haze_col, float3((_37.u_haze * smoothstep(0.4000000059604644775390625, 1.0, lum)) * 0.5));
    warm.x = fast::min(warm.x + (_37.u_warmth * 0.07999999821186065673828125), 1.0);
    out.frag = float4(fast::clamp(warm, float3(0.0), float3(1.0)), col.w);
    return out;
}

