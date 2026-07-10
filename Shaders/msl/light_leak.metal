#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_leak_intensity;
    float u_leak_speed;
    float u_time;
};

struct fx_light_leak_out
{
    float4 frag [[color(0)]];
};

struct fx_light_leak_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_light_leak_out fx_light_leak(fx_light_leak_in in [[stage_in]], constant Params& _24 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_light_leak_out out = {};
    float4 src = u_tex.sample(u_texSmplr, in.v_uv);
    float t = _24.u_time * _24.u_leak_speed;
    float2 c1 = float2(0.5 + (0.300000011920928955078125 * sin(t * 0.699999988079071044921875)), 0.300000011920928955078125 + (0.20000000298023223876953125 * cos(t * 0.5)));
    float2 c2 = float2(0.20000000298023223876953125 + (0.4000000059604644775390625 * cos(t * 0.4000000059604644775390625)), 0.699999988079071044921875 + (0.300000011920928955078125 * sin(t * 0.60000002384185791015625)));
    float d1 = 1.0 - fast::clamp(length(in.v_uv - c1) * 2.5, 0.0, 1.0);
    float d2 = 1.0 - fast::clamp(length(in.v_uv - c2) * 2.0, 0.0, 1.0);
    float3 leak = (float3(1.0, 0.60000002384185791015625, 0.20000000298023223876953125) * powr(d1, 3.0)) + (float3(0.800000011920928955078125, 0.20000000298023223876953125, 0.60000002384185791015625) * powr(d2, 3.0));
    out.frag = float4(fast::clamp(src.xyz + (leak * _24.u_leak_intensity), float3(0.0), float3(1.0)), src.w);
    return out;
}

