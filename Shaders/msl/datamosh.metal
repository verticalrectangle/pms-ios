#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_datamosh_spread;
    float u_tex_w;
};

struct fx_datamosh_out
{
    float4 frag [[color(0)]];
};

struct fx_datamosh_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_datamosh_out fx_datamosh(fx_datamosh_in in [[stage_in]], constant Params& _56 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_datamosh_out out = {};
    float3 col = u_tex.sample(u_texSmplr, in.v_uv).xyz;
    float lo = fast::min(col.x, fast::min(col.y, col.z));
    float hi = fast::max(col.x, fast::max(col.y, col.z));
    float matte = smoothstep(0.25, 0.75, hi - lo);
    float bleed = ((matte * _56.u_datamosh_spread) * 40.0) / _56.u_tex_w;
    float r = u_tex.sample(u_texSmplr, (in.v_uv + float2(bleed, 0.0))).x;
    float b = u_tex.sample(u_texSmplr, (in.v_uv - float2(bleed * 0.60000002384185791015625, 0.0))).z;
    out.frag = float4(r, col.y, b, 1.0);
    return out;
}

