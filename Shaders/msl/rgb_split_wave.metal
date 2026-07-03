#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_amplitude;
    float u_frequency;
    float u_speed;
    float u_time;
};

struct fx_rgb_split_wave_out
{
    float4 frag [[color(0)]];
};

struct fx_rgb_split_wave_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_rgb_split_wave_out fx_rgb_split_wave(fx_rgb_split_wave_in in [[stage_in]], constant Params& _11 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_rgb_split_wave_out out = {};
    float t = _11.u_time * _11.u_speed;
    float pi2 = 6.28318023681640625;
    float2 offsetR = float2(sin(((in.v_uv.y * _11.u_frequency) * pi2) + t) * _11.u_amplitude, 0.0);
    float2 offsetG = float2((sin((((in.v_uv.y * _11.u_frequency) * pi2) + t) + 2.0899999141693115234375) * _11.u_amplitude) * 0.60000002384185791015625, 0.0);
    float2 offsetB = float2((sin((((in.v_uv.y * _11.u_frequency) * pi2) + t) + 4.190000057220458984375) * _11.u_amplitude) * 1.2999999523162841796875, 0.0);
    float r = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + offsetR, float2(0.0), float2(1.0))).x;
    float g = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + offsetG, float2(0.0), float2(1.0))).y;
    float b = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + offsetB, float2(0.0), float2(1.0))).z;
    float4 orig = u_tex.sample(u_texSmplr, in.v_uv);
    out.frag = float4(r, g, b, orig.w);
    return out;
}

