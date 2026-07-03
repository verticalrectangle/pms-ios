#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_strength;
};

struct fx_bleach_bypass_out
{
    float4 frag [[color(0)]];
};

struct fx_bleach_bypass_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_bleach_bypass_out fx_bleach_bypass(fx_bleach_bypass_in in [[stage_in]], constant Params& _82 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_bleach_bypass_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float luma = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float3 overlay = mix((col.xyz * 2.0) * luma, float3(1.0) - (((float3(1.0) - col.xyz) * 2.0) * (1.0 - luma)), float3(step(0.5, luma)));
    float ov_luma = dot(overlay, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float3 bypass = mix(float3(ov_luma), overlay, float3(0.25));
    bypass = fast::clamp(((bypass - float3(0.5)) * 1.39999997615814208984375) + float3(0.5), float3(0.0), float3(1.0));
    out.frag = float4(mix(col.xyz, bypass, float3(_82.u_strength)), col.w);
    return out;
}

