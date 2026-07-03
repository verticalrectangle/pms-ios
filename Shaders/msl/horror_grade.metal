#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_desat;
    float u_red;
    float u_crush;
};

struct fx_horror_grade_out
{
    float4 frag [[color(0)]];
};

struct fx_horror_grade_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_horror_grade_out fx_horror_grade(fx_horror_grade_in in [[stage_in]], constant Params& _38 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_horror_grade_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float3 grey = mix(col.xyz, float3(lum), float3(_38.u_desat));
    grey.x = fast::clamp(grey.x + (_38.u_red * 0.3499999940395355224609375), 0.0, 1.0);
    grey.y = fast::clamp(grey.y - (_38.u_red * 0.100000001490116119384765625), 0.0, 1.0);
    grey.z = fast::clamp(grey.z - (_38.u_red * 0.1500000059604644775390625), 0.0, 1.0);
    grey = fast::max(grey - float3(_38.u_crush), float3(0.0)) / float3(1.0 - _38.u_crush);
    float mid = smoothstep(0.20000000298023223876953125, 0.699999988079071044921875, lum) * (1.0 - smoothstep(0.699999988079071044921875, 1.0, lum));
    grey.y += (mid * 0.039999999105930328369140625);
    out.frag = float4(fast::clamp(grey, float3(0.0), float3(1.0)), col.w);
    return out;
}

