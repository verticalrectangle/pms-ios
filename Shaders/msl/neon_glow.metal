#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_strength;
    float u_width;
};

struct fx_neon_glow_out
{
    float4 frag [[color(0)]];
};

struct fx_neon_glow_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_neon_glow_out fx_neon_glow(fx_neon_glow_in in [[stage_in]], constant Params& _13 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_neon_glow_out out = {};
    float2 px = float2(1.0 / _13.u_tex_w, 1.0 / _13.u_tex_h);
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float r = _13.u_width;
    float3 bloom = float3(0.0);
    float samples = 0.0;
    float _50 = -r;
    for (float dy = _50; dy <= r; dy += 1.0)
    {
        float _62 = -r;
        for (float dx = _62; dx <= r; dx += 1.0)
        {
            float4 s = u_tex.sample(u_texSmplr, (in.v_uv + (float2(dx, dy) * px)));
            float lum = dot(s.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
            bloom += mix(float3(lum), s.xyz, float3(2.5));
            samples += 1.0;
        }
    }
    bloom = fast::max(bloom / float3(samples), float3(0.0));
    float3 screen = float3(1.0) - ((float3(1.0) - col.xyz) * (float3(1.0) - ((bloom * _13.u_strength) * 0.800000011920928955078125)));
    out.frag = float4(fast::clamp(screen, float3(0.0), float3(1.0)), col.w);
    return out;
}

