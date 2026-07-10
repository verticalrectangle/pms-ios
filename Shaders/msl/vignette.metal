#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_vignette;
};

struct fx_vignette_out
{
    float4 frag [[color(0)]];
};

struct fx_vignette_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_vignette_out fx_vignette(fx_vignette_in in [[stage_in]], constant Params& _27 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_vignette_out out = {};
    float4 c = u_tex.sample(u_texSmplr, in.v_uv);
    float3 rgb = c.xyz;
    if (_27.u_vignette > 0.001000000047497451305389404296875)
    {
        float2 d = (in.v_uv * 2.0) - float2(1.0);
        float vig = 1.0 - smoothstep(0.5, 1.5, (length(d) * _27.u_vignette) * 1.5);
        rgb *= vig;
    }
    out.frag = float4(rgb, c.w);
    return out;
}

