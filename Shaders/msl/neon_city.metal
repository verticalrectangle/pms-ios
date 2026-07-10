#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_time;
    float u_neon;
    float u_scanline;
    float u_streak;
};

struct fx_neon_city_out
{
    float4 frag [[color(0)]];
};

struct fx_neon_city_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_neon_city_out fx_neon_city(fx_neon_city_in in [[stage_in]], constant Params& _13 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_neon_city_out out = {};
    float2 px = float2(1.0 / _13.u_tex_w, 1.0 / _13.u_tex_h);
    float4 c = u_tex.sample(u_texSmplr, in.v_uv);
    float3 streak = float3(0.0);
    for (int i = -6; i <= 6; i++)
    {
        float3 s = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + float2((float(i) * 4.0) * px.x, 0.0), float2(0.0), float2(1.0))).xyz;
        float b = fast::max(fast::max(s.x, s.y), s.z);
        streak += ((s * smoothstep(0.60000002384185791015625, 0.949999988079071044921875, b)) * (1.0 - (abs(float(i)) / 7.0)));
    }
    streak /= float3(6.0);
    float lum = dot(c.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float3 teal = float3(0.0500000007450580596923828125, 0.85000002384185791015625, 0.89999997615814208984375);
    float3 magenta = float3(1.0, 0.20000000298023223876953125, 0.85000002384185791015625);
    float3 duo = mix((teal * lum) * 1.2999999523162841796875, (magenta * lum) * 1.14999997615814208984375, float3(smoothstep(0.20000000298023223876953125, 0.800000011920928955078125, lum)));
    float3 rgb = mix(c.xyz, duo, float3(_13.u_neon * 0.75));
    rgb += (((streak * magenta) * _13.u_streak) * 0.800000011920928955078125);
    float sl = (sin(((in.v_uv.y + (_13.u_time * 0.0199999995529651641845703125)) * _13.u_tex_h) * 1.7999999523162841796875) * 0.5) + 0.5;
    rgb *= (1.0 - ((_13.u_scanline * 0.25) * sl));
    out.frag = float4(fast::clamp(rgb, float3(0.0), float3(1.0)), c.w);
    return out;
}

