#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_shadow_hue;
    float u_hi_hue;
    float u_strength;
};

struct fx_split_toning_out
{
    float4 frag [[color(0)]];
};

struct fx_split_toning_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_split_toning_out fx_split_toning(fx_split_toning_in in [[stage_in]], constant Params& _40 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_split_toning_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float4 K = float4(1.0, 0.666666686534881591796875, 0.3333333432674407958984375, 3.0);
    float3 ps = abs((fract(float3(_40.u_shadow_hue) + K.xyz) * 6.0) - K.www);
    float3 ph = abs((fract(float3(_40.u_hi_hue) + K.xyz) * 6.0) - K.www);
    float3 shadow_col = fast::clamp(ps - K.xxx, float3(0.0), float3(1.0));
    float3 hi_col = fast::clamp(ph - K.xxx, float3(0.0), float3(1.0));
    float shadow_wt = smoothstep(0.5, 0.0, lum);
    float hi_wt = smoothstep(0.5, 1.0, lum);
    float3 tone = ((col.xyz + (((shadow_col * shadow_wt) * _40.u_strength) * 0.4000000059604644775390625)) - ((((float3(1.0) - shadow_col) * shadow_wt) * _40.u_strength) * 0.100000001490116119384765625)) + (((hi_col * hi_wt) * _40.u_strength) * 0.3499999940395355224609375);
    out.frag = float4(fast::clamp(tone, float3(0.0), float3(1.0)), col.w);
    return out;
}

