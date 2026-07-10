#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_time;
    float u_glam;
    float u_split;
    float u_sparkle;
};

struct fx_soft_glam_out
{
    float4 frag [[color(0)]];
};

struct fx_soft_glam_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_soft_glam_out fx_soft_glam(fx_soft_glam_in in [[stage_in]], constant Params& _28 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_soft_glam_out out = {};
    float2 px = float2(1.0 / _28.u_tex_w, 1.0 / _28.u_tex_h);
    float4 c = u_tex.sample(u_texSmplr, in.v_uv);
    float3 acc = c.xyz;
    float wsum = 1.0;
    for (int i = 0; i < 10; i++)
    {
        float a = float(i) * 2.399960041046142578125;
        float r = 2.0 + (3.5 * fract(float(i) * 0.61803400516510009765625));
        float3 s = u_tex.sample(u_texSmplr, (in.v_uv + ((float2(cos(a), sin(a)) * r) * px))).xyz;
        float w = exp((-dot(s - c.xyz, s - c.xyz)) * 14.0);
        acc += (s * w);
        wsum += w;
    }
    float3 rgb = mix(c.xyz, acc / float3(wsum), float3(_28.u_glam * 0.800000011920928955078125));
    float lum = dot(rgb, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float3 shadow_tone = float3(0.85000002384185791015625, 1.0, 1.0499999523162841796875);
    float3 high_tone = float3(1.08000004291534423828125, 1.0, 0.89999997615814208984375);
    rgb *= ((mix(shadow_tone, high_tone, float3(smoothstep(0.25, 0.75, lum))) * _28.u_split) + (float3(1.0) * (1.0 - _28.u_split)));
    float spec = smoothstep(0.7799999713897705078125, 0.949999988079071044921875, lum);
    float2 cell = floor((in.v_uv * float2(_28.u_tex_w, _28.u_tex_h)) / float2(3.0));
    float2 param = cell + float2(floor(_28.u_time * 8.0));
    float g = hash(param);
    rgb += ((((float3(1.0) * step(0.98500001430511474609375, g)) * spec) * _28.u_sparkle) * 0.800000011920928955078125);
    out.frag = float4(fast::clamp(rgb, float3(0.0), float3(1.0)), c.w);
    return out;
}

