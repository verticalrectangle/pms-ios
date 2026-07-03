#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_strength;
};

struct fx_chromatic_aberration_out
{
    float4 frag [[color(0)]];
};

struct fx_chromatic_aberration_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_chromatic_aberration_out fx_chromatic_aberration(fx_chromatic_aberration_in in [[stage_in]], constant Params& _26 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_chromatic_aberration_out out = {};
    float2 center = in.v_uv - float2(0.5);
    float dist = length(center);
    float2 offset = ((center * dist) * _26.u_strength) * 0.0599999986588954925537109375;
    float r = u_tex.sample(u_texSmplr, (in.v_uv + offset)).x;
    float g = u_tex.sample(u_texSmplr, in.v_uv).y;
    float b = u_tex.sample(u_texSmplr, (in.v_uv - offset)).z;
    out.frag = float4(r, g, b, u_tex.sample(u_texSmplr, in.v_uv).w);
    return out;
}

