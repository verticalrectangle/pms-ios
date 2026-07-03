#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_frequency;
    float u_amplitude;
    float u_speed;
    float u_time;
};

struct fx_ripple_out
{
    float4 frag [[color(0)]];
};

struct fx_ripple_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_ripple_out fx_ripple(fx_ripple_in in [[stage_in]], constant Params& _28 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_ripple_out out = {};
    float2 c = float2(0.5);
    float2 d = in.v_uv - c;
    float dist = length(d) + 0.001000000047497451305389404296875;
    float wave = sin((dist * _28.u_frequency) - (_28.u_time * _28.u_speed)) * _28.u_amplitude;
    float2 uv = fast::clamp(in.v_uv + (fast::normalize(d) * wave), float2(0.0), float2(1.0));
    out.frag = u_tex.sample(u_texSmplr, uv);
    return out;
}

