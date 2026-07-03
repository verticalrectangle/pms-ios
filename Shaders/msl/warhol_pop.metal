#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_levels;
    float u_hue_shift;
    float u_saturation;
};

struct fx_warhol_pop_out
{
    float4 frag [[color(0)]];
};

struct fx_warhol_pop_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_warhol_pop_out fx_warhol_pop(fx_warhol_pop_in in [[stage_in]], constant Params& _34 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_warhol_pop_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float quant_lum = floor((lum * _34.u_levels) + 0.5) / _34.u_levels;
    float4 K = float4(1.0, 0.666666686534881591796875, 0.3333333432674407958984375, 3.0);
    float hue = fract((quant_lum * 0.699999988079071044921875) + _34.u_hue_shift);
    float3 p = abs((fract(float3(hue) + K.xyz) * 6.0) - K.www);
    float3 hue_col = fast::clamp(p - K.xxx, float3(0.0), float3(1.0));
    float3 sat_orig = mix(float3(lum), col.xyz, float3(_34.u_saturation));
    float3 pop = hue_col * quant_lum;
    float3 result = mix(sat_orig, pop, float3(0.64999997615814208984375));
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), col.w);
    return out;
}

