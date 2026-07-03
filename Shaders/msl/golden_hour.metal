#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_warmth;
    float u_glow_str;
    float u_shadow_lift;
    float u_vignette;
};

struct fx_golden_hour_out
{
    float4 frag [[color(0)]];
};

struct fx_golden_hour_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_golden_hour_out fx_golden_hour(fx_golden_hour_in in [[stage_in]], constant Params& _38 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_golden_hour_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float hi = smoothstep(0.449999988079071044921875, 0.89999997615814208984375, lum);
    float4 _50 = col;
    float3 _52 = _50.xyz + (float3(0.25, 0.119999997317790985107421875, -0.07999999821186065673828125) * (hi * _38.u_warmth));
    col.x = _52.x;
    col.y = _52.y;
    col.z = _52.z;
    float sha = smoothstep(0.4000000059604644775390625, 0.0, lum);
    float4 _77 = col;
    float3 _79 = _77.xyz + (float3(0.119999997317790985107421875, 0.100000001490116119384765625, 0.20000000298023223876953125) * (sha * _38.u_shadow_lift));
    col.x = _79.x;
    col.y = _79.y;
    col.z = _79.z;
    float bloom = fast::clamp((lum - 0.550000011920928955078125) * 2.5, 0.0, 1.0);
    float3 glow = ((col.xyz * bloom) * _38.u_glow_str) * float3(1.0, 0.85000002384185791015625, 0.5);
    float4 _108 = col;
    float3 _117 = float3(1.0) - ((float3(1.0) - _108.xyz) * (float3(1.0) - glow));
    col.x = _117.x;
    col.y = _117.y;
    col.z = _117.z;
    float2 uvc = in.v_uv - float2(0.5);
    float vig = 1.0 - ((dot(uvc, uvc) * _38.u_vignette) * 2.5);
    out.frag = float4(fast::clamp(col.xyz * vig, float3(0.0), float3(1.0)), col.w);
    return out;
}

