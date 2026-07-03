#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_intensity;
    float u_speed;
    float u_time;
};

struct fx_heat_haze_out
{
    float4 frag [[color(0)]];
};

struct fx_heat_haze_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

static inline __attribute__((always_inline))
float _noise2(thread const float2& p)
{
    float2 i = floor(p);
    float2 f = fract(p);
    f = (f * f) * (float2(3.0) - (f * 2.0));
    float2 param = i;
    float2 param_1 = i + float2(1.0, 0.0);
    float2 param_2 = i + float2(0.0, 1.0);
    float2 param_3 = i + float2(1.0);
    return mix(mix(hash(param), hash(param_1), f.x), mix(hash(param_2), hash(param_3), f.x), f.y);
}

fragment fx_heat_haze_out fx_heat_haze(fx_heat_haze_in in [[stage_in]], constant Params& _81 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_heat_haze_out out = {};
    float t = _81.u_time * _81.u_speed;
    float2 param = float2(in.v_uv.x * 5.0, (in.v_uv.y * 10.0) + t);
    float nx = _noise2(param);
    float2 param_1 = float2((in.v_uv.x * 5.0) + 100.0, (in.v_uv.y * 10.0) + (t * 1.2999999523162841796875));
    float ny = _noise2(param_1);
    float rise = smoothstep(0.0, 0.699999988079071044921875, 1.0 - in.v_uv.y);
    float2 warp = ((float2(nx - 0.5, ny - 0.5) * _81.u_intensity) * 0.0500000007450580596923828125) * rise;
    out.frag = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + warp, float2(0.0), float2(1.0)));
    return out;
}

