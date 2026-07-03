#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_spread;
    float u_intensity;
};

struct fx_prism_disperse_out
{
    float4 frag [[color(0)]];
};

struct fx_prism_disperse_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_prism_disperse_out fx_prism_disperse(fx_prism_disperse_in in [[stage_in]], constant Params& _25 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_prism_disperse_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float2 ipx = float2(1.0 / _25.u_tex_w, 1.0 / _25.u_tex_h);
    float3 dx = u_tex.sample(u_texSmplr, (in.v_uv + float2(ipx.x, 0.0))).xyz - u_tex.sample(u_texSmplr, (in.v_uv - float2(ipx.x, 0.0))).xyz;
    float3 dy = u_tex.sample(u_texSmplr, (in.v_uv + float2(0.0, ipx.y))).xyz - u_tex.sample(u_texSmplr, (in.v_uv - float2(0.0, ipx.y))).xyz;
    float edge = length(dx) + length(dy);
    float r = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + float2(_25.u_spread * 1.0, 0.0), float2(0.0), float2(1.0))).x;
    float g = col.y;
    float b = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv - float2(_25.u_spread * 1.0, 0.0), float2(0.0), float2(1.0))).z;
    float3 prism = float3(r, g, b);
    float mask = fast::clamp(edge * 3.0, 0.0, 1.0);
    out.frag = float4(mix(col.xyz, prism, float3(mask * _25.u_intensity)), col.w);
    return out;
}

