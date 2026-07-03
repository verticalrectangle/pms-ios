#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_strength;
};

struct fx_thermal_out
{
    float4 frag [[color(0)]];
};

struct fx_thermal_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float3 thermal_palette(thread float& t)
{
    t = fast::clamp(t, 0.0, 1.0);
    float3 a = mix(float3(0.0), float3(0.0, 0.0, 1.0), float3(smoothstep(0.0, 0.20000000298023223876953125, t)));
    float3 b = mix(a, float3(0.0, 1.0, 1.0), float3(smoothstep(0.20000000298023223876953125, 0.4000000059604644775390625, t)));
    float3 c = mix(b, float3(1.0, 1.0, 0.0), float3(smoothstep(0.4000000059604644775390625, 0.64999997615814208984375, t)));
    float3 d = mix(c, float3(1.0, 0.0, 0.0), float3(smoothstep(0.64999997615814208984375, 0.85000002384185791015625, t)));
    return mix(d, float3(1.0), float3(smoothstep(0.85000002384185791015625, 1.0, t)));
}

fragment fx_thermal_out fx_thermal(fx_thermal_in in [[stage_in]], constant Params& _90 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_thermal_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float luma = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float param = luma;
    float3 _82 = thermal_palette(param);
    float3 heat = _82;
    out.frag = float4(mix(col.xyz, heat, float3(_90.u_strength)), col.w);
    return out;
}

