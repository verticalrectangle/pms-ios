#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_intensity;
    float u_speed;
    float u_time;
};

struct fx_rgb_split_out
{
    float4 frag [[color(0)]];
};

struct fx_rgb_split_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float& p)
{
    return fract(sin(p * 127.09999847412109375) * 43758.546875);
}

fragment fx_rgb_split_out fx_rgb_split(fx_rgb_split_in in [[stage_in]], constant Params& _24 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_rgb_split_out out = {};
    float t = _24.u_time * _24.u_speed;
    float param = floor(t);
    float ox = (((hash(param) * 2.0) - 1.0) * _24.u_intensity) * 0.0500000007450580596923828125;
    float param_1 = floor(t) + 1.0;
    float oy = (((hash(param_1) * 2.0) - 1.0) * _24.u_intensity) * 0.0199999995529651641845703125;
    float r = u_tex.sample(u_texSmplr, (in.v_uv + float2(ox, oy))).x;
    float g = u_tex.sample(u_texSmplr, in.v_uv).y;
    float b = u_tex.sample(u_texSmplr, (in.v_uv - float2(ox, oy))).z;
    out.frag = float4(r, g, b, u_tex.sample(u_texSmplr, in.v_uv).w);
    return out;
}

