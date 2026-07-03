#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_threshold;
    float u_glow;
    float u_hue;
};

struct fx_neon_edge_glow_out
{
    float4 frag [[color(0)]];
};

struct fx_neon_edge_glow_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_neon_edge_glow_out fx_neon_edge_glow(fx_neon_edge_glow_in in [[stage_in]], constant Params& _13 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_neon_edge_glow_out out = {};
    float2 px = float2(1.0 / _13.u_tex_w, 1.0 / _13.u_tex_h);
    float3 tl = u_tex.sample(u_texSmplr, (in.v_uv + float2(-px.x, -px.y))).xyz;
    float3 tc = u_tex.sample(u_texSmplr, (in.v_uv + float2(0.0, -px.y))).xyz;
    float3 tr = u_tex.sample(u_texSmplr, (in.v_uv + float2(px.x, -px.y))).xyz;
    float3 ml = u_tex.sample(u_texSmplr, (in.v_uv + float2(-px.x, 0.0))).xyz;
    float3 mr = u_tex.sample(u_texSmplr, (in.v_uv + float2(px.x, 0.0))).xyz;
    float3 bl = u_tex.sample(u_texSmplr, (in.v_uv + float2(-px.x, px.y))).xyz;
    float3 bc = u_tex.sample(u_texSmplr, (in.v_uv + float2(0.0, px.y))).xyz;
    float3 br = u_tex.sample(u_texSmplr, (in.v_uv + float2(px.x, px.y))).xyz;
    float3 gx = (((((-tl) - (ml * 2.0)) - bl) + tr) + (mr * 2.0)) + br;
    float3 gy = (((((-tl) - (tc * 2.0)) - tr) + bl) + (bc * 2.0)) + br;
    float edge = length(float2(length(gx), length(gy)));
    edge = smoothstep(_13.u_threshold, _13.u_threshold + 0.20000000298023223876953125, edge);
    float4 K = float4(1.0, 0.666666686534881591796875, 0.3333333432674407958984375, 3.0);
    float3 p = abs((fract(float3(_13.u_hue) + K.xyz) * 6.0) - K.www);
    float3 neon_col = fast::clamp(p - K.xxx, float3(0.0), float3(1.0));
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float dark = 0.1500000059604644775390625;
    float3 result = (col.xyz * dark) + ((neon_col * edge) * _13.u_glow);
    float3 bloom = float3(0.0);
    for (int i = 1; i <= 4; i++)
    {
        float r = float(i) * 2.0;
        bloom += ((neon_col * edge) / float3((r * r) + 1.0));
    }
    result += ((bloom * _13.u_glow) * 0.300000011920928955078125);
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), col.w);
    return out;
}

