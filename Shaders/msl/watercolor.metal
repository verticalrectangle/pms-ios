#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_bleeding;
    float u_paper;
    float u_saturation;
};

struct fx_watercolor_out
{
    float4 frag [[color(0)]];
};

struct fx_watercolor_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_watercolor_out fx_watercolor(fx_watercolor_in in [[stage_in]], constant Params& _28 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_watercolor_out out = {};
    float2 px = float2(1.0 / _28.u_tex_w, 1.0 / _28.u_tex_h);
    float3 acc = float3(0.0);
    float wt = 0.0;
    for (int dy = -3; dy <= 3; dy++)
    {
        for (int dx = -3; dx <= 3; dx++)
        {
            float d = length(float2(float(dx), float(dy)));
            float w = exp((-d) * 0.60000002384185791015625);
            float2 uv = in.v_uv + ((float2(float(dx), float(dy)) * px) * (1.0 + (_28.u_bleeding * 30.0)));
            acc += (u_tex.sample(u_texSmplr, fast::clamp(uv, float2(0.0), float2(1.0))).xyz * w);
            wt += w;
        }
    }
    float3 wash = acc / float3(wt);
    float2 param = (in.v_uv * float2(_28.u_tex_w, _28.u_tex_h)) * 0.0500000007450580596923828125;
    float paper_n = hash(param);
    float paper_tex = mix(1.0, (paper_n * 0.300000011920928955078125) + 0.85000002384185791015625, _28.u_paper);
    float lum = dot(wash, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    wash = mix(float3(lum), wash, float3(_28.u_saturation)) * paper_tex;
    float4 orig = u_tex.sample(u_texSmplr, in.v_uv);
    out.frag = float4(fast::clamp(wash, float3(0.0), float3(1.0)), orig.w);
    return out;
}

