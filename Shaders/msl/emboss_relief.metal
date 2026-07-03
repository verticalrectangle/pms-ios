#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_strength;
    float u_angle;
    float u_colorize;
};

struct fx_emboss_relief_out
{
    float4 frag [[color(0)]];
};

struct fx_emboss_relief_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_emboss_relief_out fx_emboss_relief(fx_emboss_relief_in in [[stage_in]], constant Params& _13 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_emboss_relief_out out = {};
    float2 px = float2(1.0 / _13.u_tex_w, 1.0 / _13.u_tex_h);
    float a = _13.u_angle * 0.01745329238474369049072265625;
    float2 light = float2(cos(a), sin(a));
    float3 fwd = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + ((light * px) * _13.u_strength), float2(0.0), float2(1.0))).xyz;
    float3 bwd = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv - ((light * px) * _13.u_strength), float2(0.0), float2(1.0))).xyz;
    float3 orig = u_tex.sample(u_texSmplr, in.v_uv).xyz;
    float lum_fwd = dot(fwd, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float lum_bwd = dot(bwd, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float bump = ((lum_fwd - lum_bwd) * 0.5) + 0.5;
    float3 relief = float3(bump);
    float lum_orig = dot(orig, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float3 colored = mix(float3(bump), orig * (bump / fast::max(lum_orig, 0.001000000047497451305389404296875)), float3(_13.u_colorize));
    out.frag = float4(fast::clamp(colored, float3(0.0), float3(1.0)), 1.0);
    return out;
}

