#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_shadow_teal;
    float u_hi_orange;
    float u_contrast;
};

struct fx_cyberpunk_grade_out
{
    float4 frag [[color(0)]];
};

struct fx_cyberpunk_grade_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_cyberpunk_grade_out fx_cyberpunk_grade(fx_cyberpunk_grade_in in [[stage_in]], constant Params& _31 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_cyberpunk_grade_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float3 c = col.xyz;
    c = ((c - float3(0.5)) * _31.u_contrast) + float3(0.5);
    float lum = dot(c, float3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    float3 shadow_col = float3(0.0199999995529651641845703125, 0.0599999986588954925537109375, 0.180000007152557373046875);
    float shadow_mask = smoothstep(0.449999988079071044921875, 0.0, lum);
    c = mix(c, shadow_col + (c * 0.4000000059604644775390625), float3(shadow_mask * _31.u_shadow_teal));
    float3 hi_col = float3(1.0, 0.699999988079071044921875, 0.3499999940395355224609375);
    float hi_mask = smoothstep(0.64999997615814208984375, 1.0, lum);
    c = mix(c, hi_col * lum, float3((hi_mask * _31.u_hi_orange) * 0.60000002384185791015625));
    float3 mid_teal = float3(0.0, 0.89999997615814208984375, 1.0);
    float mid_mask = (1.0 - shadow_mask) - hi_mask;
    float lum2 = dot(c, float3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    c = mix(c, mix(float3(lum2), c, float3(1.0)) * mix(float3(1.0), mid_teal, float3(0.20000000298023223876953125)), float3((mid_mask * _31.u_shadow_teal) * 0.4000000059604644775390625));
    out.frag = float4(fast::clamp(c, float3(0.0), float3(1.0)), col.w);
    return out;
}

