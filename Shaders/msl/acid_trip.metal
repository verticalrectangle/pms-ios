#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_time;
    float u_trip;
    float u_speed;
    float u_wobble;
};

struct fx_acid_trip_out
{
    float4 frag [[color(0)]];
};

struct fx_acid_trip_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float3 hue_rotate(thread const float3& c, thread const float& rad)
{
    float ch = cos(rad);
    float sh = sin(rad);
    float3x3 m = float3x3(float3((0.2989999949932098388671875 + (0.7009999752044677734375 * ch)) + (0.16799999773502349853515625 * sh), (0.2989999949932098388671875 - (0.2989999949932098388671875 * ch)) - (0.328000009059906005859375 * sh), (0.2989999949932098388671875 - (0.2989999949932098388671875 * ch)) + (1.25 * sh)), float3((0.58700001239776611328125 - (0.58700001239776611328125 * ch)) + (0.3300000131130218505859375 * sh), (0.58700001239776611328125 + (0.41299998760223388671875 * ch)) + (0.0350000001490116119384765625 * sh), (0.58700001239776611328125 - (0.58700001239776611328125 * ch)) - (1.0499999523162841796875 * sh)), float3((0.114000000059604644775390625 - (0.114000000059604644775390625 * ch)) - (0.4970000088214874267578125 * sh), (0.114000000059604644775390625 - (0.114000000059604644775390625 * ch)) + (0.291999995708465576171875 * sh), (0.114000000059604644775390625 + (0.885999977588653564453125 * ch)) - (0.20299999415874481201171875 * sh)));
    return fast::clamp(m * c, float3(0.0), float3(1.0));
}

fragment fx_acid_trip_out fx_acid_trip(fx_acid_trip_in in [[stage_in]], constant Params& _110 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_acid_trip_out out = {};
    float t = _110.u_time * _110.u_speed;
    float2 uv = in.v_uv;
    uv.x += ((sin((uv.y * 9.0) + (t * 1.2999999523162841796875)) * 0.0199999995529651641845703125) * _110.u_wobble);
    uv.y += ((cos((uv.x * 7.0) + (t * 1.7000000476837158203125)) * 0.0199999995529651641845703125) * _110.u_wobble);
    float4 c = u_tex.sample(u_texSmplr, fast::clamp(uv, float2(0.0), float2(1.0)));
    float lum = dot(c.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float band = floor(lum * 4.0) / 4.0;
    float rot = (((t * 0.800000011920928955078125) + (band * 2.5)) + (lum * 1.5)) * _110.u_trip;
    float3 param = c.xyz;
    float param_1 = rot;
    float3 rgb = hue_rotate(param, param_1);
    float l2 = dot(rgb, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    rgb = mix(float3(l2), rgb, float3(1.0 + (_110.u_trip * 0.60000002384185791015625)));
    out.frag = float4(fast::clamp(rgb, float3(0.0), float3(1.0)), c.w);
    return out;
}

