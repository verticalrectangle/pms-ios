#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_flow;
    float u_metallic;
    float u_tint_r;
    float u_tint_g;
    float u_tint_b;
    float u_time;
};

struct fx_liquid_chrome_out
{
    float4 frag [[color(0)]];
};

struct fx_liquid_chrome_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.5);
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

fragment fx_liquid_chrome_out fx_liquid_chrome(fx_liquid_chrome_in in [[stage_in]], constant Params& _81 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_liquid_chrome_out out = {};
    float t = _81.u_time * 0.300000011920928955078125;
    float2 param = (in.v_uv * 3.0) + float2(t, t * 0.699999988079071044921875);
    float2 d;
    d.x = _noise2(param) - 0.5;
    float2 param_1 = (in.v_uv * 3.0) + float2((t * 0.800000011920928955078125) + 1.7000000476837158203125, (t * 1.10000002384185791015625) + 3.2999999523162841796875);
    d.y = _noise2(param_1) - 0.5;
    float2 uv = in.v_uv + ((d * _81.u_flow) * 0.039999999105930328369140625);
    float4 col = u_tex.sample(u_texSmplr, fast::clamp(uv, float2(0.0), float2(1.0)));
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float spec = smoothstep(0.5, 0.85000002384185791015625, lum) * smoothstep(1.0, 0.75, lum);
    float band = (sin((lum * 8.0) + (t * 2.0)) * 0.5) + 0.5;
    float3 tint = float3(_81.u_tint_r, _81.u_tint_g, _81.u_tint_b);
    float3 chrome = mix(float3((lum * 0.5) + 0.100000001490116119384765625), float3((lum * 0.89999997615814208984375) + 0.100000001490116119384765625), float3(band)) * tint;
    chrome += ((tint * spec) * 1.39999997615814208984375);
    float3 result = mix(col.xyz, chrome, float3(_81.u_metallic));
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), col.w);
    return out;
}

