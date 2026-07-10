#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_brightness;
    float u_contrast;
    float u_saturation;
    float u_hue;
};

struct fx_grade_out
{
    float4 frag [[color(0)]];
};

struct fx_grade_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float3 hue_rotate(thread const float3& c, thread const float& deg)
{
    float rad = deg * 0.01745329238474369049072265625;
    float ch = cos(rad);
    float sh = sin(rad);
    float3x3 m = float3x3(float3((0.2989999949932098388671875 + (0.7009999752044677734375 * ch)) + (0.16799999773502349853515625 * sh), (0.2989999949932098388671875 - (0.2989999949932098388671875 * ch)) - (0.328000009059906005859375 * sh), (0.2989999949932098388671875 - (0.2989999949932098388671875 * ch)) + (1.25 * sh)), float3((0.58700001239776611328125 - (0.58700001239776611328125 * ch)) + (0.3300000131130218505859375 * sh), (0.58700001239776611328125 + (0.41299998760223388671875 * ch)) + (0.0350000001490116119384765625 * sh), (0.58700001239776611328125 - (0.58700001239776611328125 * ch)) - (1.0499999523162841796875 * sh)), float3((0.114000000059604644775390625 - (0.114000000059604644775390625 * ch)) - (0.4970000088214874267578125 * sh), (0.114000000059604644775390625 - (0.114000000059604644775390625 * ch)) + (0.291999995708465576171875 * sh), (0.114000000059604644775390625 + (0.885999977588653564453125 * ch)) - (0.20299999415874481201171875 * sh)));
    return fast::clamp(m * c, float3(0.0), float3(1.0));
}

fragment fx_grade_out fx_grade(fx_grade_in in [[stage_in]], constant Params& _129 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_grade_out out = {};
    float4 c = u_tex.sample(u_texSmplr, in.v_uv);
    float3 rgb = c.xyz + float3(_129.u_brightness);
    rgb = ((rgb - float3(0.5)) * _129.u_contrast) + float3(0.5);
    float lum = dot(rgb, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    rgb = mix(float3(lum), rgb, float3(_129.u_saturation));
    if (abs(_129.u_hue) > 0.100000001490116119384765625)
    {
        float3 param = rgb;
        float param_1 = _129.u_hue;
        rgb = hue_rotate(param, param_1);
    }
    out.frag = float4(fast::clamp(rgb, float3(0.0), float3(1.0)), c.w);
    return out;
}

