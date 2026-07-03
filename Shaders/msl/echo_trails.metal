#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_offset;
    float u_fade;
    float u_angle;
};

struct fx_echo_trails_out
{
    float4 frag [[color(0)]];
};

struct fx_echo_trails_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_echo_trails_out fx_echo_trails(fx_echo_trails_in in [[stage_in]], constant Params& _11 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_echo_trails_out out = {};
    float a = _11.u_angle * 0.01745329238474369049072265625;
    float2 dir = float2(cos(a), -sin(a)) * _11.u_offset;
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float4 result = col;
    float wt = 1.0;
    float w = _11.u_fade;
    for (int i = 1; i <= 5; i++)
    {
        float2 uv = fast::clamp(in.v_uv + (dir * float(i)), float2(0.0), float2(1.0));
        float4 echo = u_tex.sample(u_texSmplr, uv);
        float4 _79 = result;
        float3 _91 = float3(1.0) - ((float3(1.0) - _79.xyz) * (float3(1.0) - (echo.xyz * w)));
        result.x = _91.x;
        result.y = _91.y;
        result.z = _91.z;
        w *= _11.u_fade;
    }
    out.frag = float4(fast::clamp(result.xyz, float3(0.0), float3(1.0)), col.w);
    return out;
}

