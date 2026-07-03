#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_blur;
    float u_noise;
    float u_tint;
};

struct fx_frosted_glass_out
{
    float4 frag [[color(0)]];
};

struct fx_frosted_glass_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_frosted_glass_out fx_frosted_glass(fx_frosted_glass_in in [[stage_in]], constant Params& _28 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_frosted_glass_out out = {};
    float2 px = float2(1.0 / _28.u_tex_w, 1.0 / _28.u_tex_h);
    float2 param = in.v_uv * 300.0;
    float n1 = hash(param) - 0.5;
    float2 param_1 = (in.v_uv * 300.0) + float2(71.3000030517578125, 37.09999847412109375);
    float n2 = hash(param_1) - 0.5;
    float2 scatter = (float2(n1, n2) * _28.u_noise) * 0.5;
    float4 acc = float4(0.0);
    float wt = 0.0;
    float radius = _28.u_blur / px.x;
    for (int dy = -4; dy <= 4; dy++)
    {
        for (int dx = -4; dx <= 4; dx++)
        {
            float d = length(float2(float(dx), float(dy)));
            float w = exp(((-d) * d) * 0.119999997317790985107421875);
            float2 uv = in.v_uv + ((((float2(float(dx), float(dy)) + (scatter * d)) * px) * radius) * 0.25);
            acc += (u_tex.sample(u_texSmplr, fast::clamp(uv, float2(0.0), float2(1.0))) * w);
            wt += w;
        }
    }
    float3 blur = acc.xyz / float3(wt);
    float3 frost = mix(blur, float3(0.85000002384185791015625, 0.89999997615814208984375, 1.0), float3(_28.u_tint * 0.25));
    float lines = (sin(((in.v_uv.x * _28.u_tex_w) * 0.5) + (n1 * 20.0)) * 0.00999999977648258209228515625) * _28.u_noise;
    frost += float3(lines);
    out.frag = float4(fast::clamp(frost, float3(0.0), float3(1.0)), acc.w / wt);
    return out;
}

