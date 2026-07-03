#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_strength;
    float u_scale;
    float u_speed;
    float u_time;
};

struct fx_vortex_distort_out
{
    float4 frag [[color(0)]];
};

struct fx_vortex_distort_in
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

fragment fx_vortex_distort_out fx_vortex_distort(fx_vortex_distort_in in [[stage_in]], constant Params& _81 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_vortex_distort_out out = {};
    float t = _81.u_time * _81.u_speed;
    float2 sc = in.v_uv * _81.u_scale;
    float2 param = sc + float2(t * 0.300000011920928955078125, 0.0);
    float2 param_1 = (sc * 2.0) + float2(0.0, t * 0.4000000059604644775390625);
    float nx = _noise2(param) + (_noise2(param_1) * 0.5);
    float2 param_2 = sc + float2(100.0, t * 0.25);
    float2 param_3 = (sc * 2.0) + float2(100.0, t * 0.3499999940395355224609375);
    float ny = _noise2(param_2) + (_noise2(param_3) * 0.5);
    float2 curl = float2(ny - 0.5, -(nx - 0.5)) * 2.0;
    float2 uv = fast::clamp(in.v_uv + (curl * _81.u_strength), float2(0.0), float2(1.0));
    out.frag = u_tex.sample(u_texSmplr, uv);
    return out;
}

