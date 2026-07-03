#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_time;
    float u_intensity;
    float u_size;
};

struct fx_film_grain_out
{
    float4 frag [[color(0)]];
};

struct fx_film_grain_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_film_grain_out fx_film_grain(fx_film_grain_in in [[stage_in]], constant Params& _44 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_film_grain_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float2 gp = floor((in.v_uv * float2(640.0, 360.0)) / float2(_44.u_size));
    float2 param = gp + float2(_44.u_time * 7.30000019073486328125, _44.u_time * 3.099999904632568359375);
    float g = (hash(param) * 2.0) - 1.0;
    float luma = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float w = 1.0 - abs((luma * 2.0) - 1.0);
    out.frag = float4(col.xyz + float3(((g * _44.u_intensity) * w) * 0.3499999940395355224609375), col.w);
    return out;
}

