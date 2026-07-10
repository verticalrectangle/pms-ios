#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_vhs_noise;
    float u_vhs_bleed;
    float u_vhs_tracking;
    float u_time;
    float u_tex_w;
};

struct fx_vhs_out
{
    float4 frag [[color(0)]];
};

struct fx_vhs_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_vhs_out fx_vhs(fx_vhs_in in [[stage_in]], constant Params& _28 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_vhs_out out = {};
    float bleed = _28.u_vhs_bleed / _28.u_tex_w;
    float2 uv = in.v_uv;
    if (_28.u_vhs_tracking > 0.00999999977648258209228515625)
    {
        float sl = floor(uv.y * 240.0);
        float2 param = float2(sl, floor(_28.u_time * 3.0));
        float rnd = hash(param);
        if (rnd > (1.0 - (_28.u_vhs_tracking * 0.1500000059604644775390625)))
        {
            float2 param_1 = float2(sl, _28.u_time * 7.0);
            uv.x += (((hash(param_1) - 0.5) * _28.u_vhs_tracking) * 0.0500000007450580596923828125);
        }
        uv.x = fast::clamp(uv.x, 0.0, 1.0);
    }
    float r = u_tex.sample(u_texSmplr, uv).x;
    float g = u_tex.sample(u_texSmplr, fast::clamp(uv + float2(bleed * 0.5, 0.0), float2(0.0), float2(1.0))).y;
    float b = u_tex.sample(u_texSmplr, fast::clamp(uv + float2(bleed, 0.0), float2(0.0), float2(1.0))).z;
    float a = u_tex.sample(u_texSmplr, uv).w;
    float2 param_2 = uv + fract(float2(_28.u_time * 0.00999999977648258209228515625));
    float grain = (hash(param_2) * _28.u_vhs_noise) * 0.3499999940395355224609375;
    out.frag = float4(fast::clamp(float3(r, g, b) + float3(grain), float3(0.0), float3(1.0)), a);
    return out;
}

