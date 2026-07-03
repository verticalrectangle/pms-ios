#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_time;
    float u_noise;
    float u_gain;
};

struct fx_night_vision_out
{
    float4 frag [[color(0)]];
};

struct fx_night_vision_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_night_vision_out fx_night_vision(fx_night_vision_in in [[stage_in]], constant Params& _48 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_night_vision_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float luma = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625)) * _48.u_gain;
    float2 param = in.v_uv + float2(_48.u_time * 13.69999980926513671875, _48.u_time * 9.1000003814697265625);
    float n = (hash(param) * _48.u_noise) * 0.300000011920928955078125;
    float2 d = in.v_uv - float2(0.5);
    float vig = 1.0 - smoothstep(0.300000011920928955078125, 0.75, length(d) * 1.2999999523162841796875);
    float g = fast::clamp(luma + n, 0.0, 1.0) * vig;
    out.frag = float4(g * 0.1500000059604644775390625, g, g * 0.07999999821186065673828125, col.w);
    return out;
}

