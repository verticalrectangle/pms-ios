#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_intensity;
    float u_speed;
    float u_time;
};

struct fx_glitch_block_out
{
    float4 frag [[color(0)]];
};

struct fx_glitch_block_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_glitch_block_out fx_glitch_block(fx_glitch_block_in in [[stage_in]], constant Params& _28 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_glitch_block_out out = {};
    float t = floor((_28.u_time * _28.u_speed) * 8.0);
    float2 block = floor(in.v_uv * float2(12.0, 20.0));
    float2 param = block + float2(t, t * 0.699999988079071044921875);
    float r = hash(param);
    float blk = step(1.0 - (_28.u_intensity * 0.800000011920928955078125), r);
    float2 param_1 = block + float2(t * 1.2999999523162841796875, 0.0);
    float shift = ((((hash(param_1) * 2.0) - 1.0) * blk) * 0.180000007152557373046875) * _28.u_intensity;
    float2 offset = float2(shift, 0.0);
    out.frag = u_tex.sample(u_texSmplr, (in.v_uv + offset));
    return out;
}

