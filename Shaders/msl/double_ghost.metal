#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_offset;
    float u_opacity;
    float u_angle;
};

struct fx_double_ghost_out
{
    float4 frag [[color(0)]];
};

struct fx_double_ghost_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_double_ghost_out fx_double_ghost(fx_double_ghost_in in [[stage_in]], constant Params& _11 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_double_ghost_out out = {};
    float a = _11.u_angle * 0.01745329238474369049072265625;
    float2 dir = float2(cos(a), sin(a)) * _11.u_offset;
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float4 ghost = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + dir, float2(0.0), float2(1.0)));
    float3 screen = float3(1.0) - ((float3(1.0) - col.xyz) * (float3(1.0) - (ghost.xyz * _11.u_opacity)));
    float4 _76 = ghost;
    float3 _78 = _76.xyz * float3(0.699999988079071044921875, 0.89999997615814208984375, 1.2000000476837158203125);
    ghost.x = _78.x;
    ghost.y = _78.y;
    ghost.z = _78.z;
    float3 result = mix(screen, (col.xyz * (1.0 - _11.u_opacity)) + (ghost.xyz * _11.u_opacity), float3(0.5));
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), col.w);
    return out;
}

