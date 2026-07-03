#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_freq_x;
    float u_freq_y;
    float u_amplitude;
    float u_speed;
    float u_time;
};

struct fx_wave_warp_out
{
    float4 frag [[color(0)]];
};

struct fx_wave_warp_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_wave_warp_out fx_wave_warp(fx_wave_warp_in in [[stage_in]], constant Params& _20 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_wave_warp_out out = {};
    float2 uv = in.v_uv;
    uv.x += (sin((in.v_uv.y * _20.u_freq_x) + ((_20.u_time * _20.u_speed) * 1.10000002384185791015625)) * _20.u_amplitude);
    uv.y += (sin((in.v_uv.x * _20.u_freq_y) + ((_20.u_time * _20.u_speed) * 0.89999997615814208984375)) * _20.u_amplitude);
    out.frag = u_tex.sample(u_texSmplr, fast::clamp(uv, float2(0.0), float2(1.0)));
    return out;
}

