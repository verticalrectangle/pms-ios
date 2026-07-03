#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_hue1;
    float u_hue2;
    float u_strength;
};

struct fx_gradient_map_out
{
    float4 frag [[color(0)]];
};

struct fx_gradient_map_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_gradient_map_out fx_gradient_map(fx_gradient_map_in in [[stage_in]], constant Params& _40 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_gradient_map_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float4 K = float4(1.0, 0.666666686534881591796875, 0.3333333432674407958984375, 3.0);
    float3 p1 = abs((fract(float3(_40.u_hue1) + K.xyz) * 6.0) - K.www);
    float3 p2 = abs((fract(float3(_40.u_hue2) + K.xyz) * 6.0) - K.www);
    float3 c1 = fast::clamp(p1 - K.xxx, float3(0.0), float3(1.0));
    float3 c2 = fast::clamp(p2 - K.xxx, float3(0.0), float3(1.0));
    float3 mapped = mix(c1, c2, float3(lum));
    float3 result = mix(col.xyz, mapped, float3(_40.u_strength));
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), col.w);
    return out;
}

