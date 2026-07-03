#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_time;
    float u_sepia;
    float u_scratch;
    float u_flicker;
};

struct fx_old_film_out
{
    float4 frag [[color(0)]];
};

struct fx_old_film_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_old_film_out fx_old_film(fx_old_film_in in [[stage_in]], constant Params& _41 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_old_film_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float2 param = float2(_41.u_time * 3.099999904632568359375, 0.5);
    float flick = 1.0 - ((_41.u_flicker * 0.1500000059604644775390625) * hash(param));
    float luma = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float3 sep = float3(luma * 1.07000005245208740234375, luma * 0.7400000095367431640625, luma * 0.430000007152557373046875);
    float3 c = mix(col.xyz, sep, float3(_41.u_sepia)) * flick;
    float sx = floor((in.v_uv.x * 320.0) + ((_41.u_time * 0.5) * 60.0));
    float2 param_1 = float2(sx, floor(_41.u_time * 24.0));
    float sc = hash(param_1);
    float scratch_vis = step(1.0 - (_41.u_scratch * 0.0199999995529651641845703125), sc);
    float2 param_2 = float2(sx * 1.2999999523162841796875, 0.0);
    float scratch_x = hash(param_2);
    float sdist = abs(in.v_uv.x - (((scratch_x / 320.0) * 320.0) / 320.0));
    c += float3((scratch_vis * smoothstep(0.0040000001899898052215576171875, 0.0, sdist)) * 0.800000011920928955078125);
    float2 d = in.v_uv - float2(0.5);
    float vig = 1.0 - smoothstep(0.25, 0.75, length(d) * 1.39999997615814208984375);
    out.frag = float4(c * vig, col.w);
    return out;
}

