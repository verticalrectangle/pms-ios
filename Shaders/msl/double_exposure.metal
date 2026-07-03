#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_offset_x;
    float u_offset_y;
    float u_scale2;
    float u_desaturate2;
    float u_opacity;
};

struct fx_double_exposure_out
{
    float4 frag [[color(0)]];
};

struct fx_double_exposure_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_double_exposure_out fx_double_exposure(fx_double_exposure_in in [[stage_in]], constant Params& _28 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_double_exposure_out out = {};
    float4 c1 = u_tex.sample(u_texSmplr, in.v_uv);
    float2 uv2 = (((in.v_uv - float2(0.5)) / float2(_28.u_scale2)) + float2(0.5)) + float2(_28.u_offset_x, _28.u_offset_y);
    float4 c2 = u_tex.sample(u_texSmplr, fast::clamp(uv2, float2(0.0), float2(1.0)));
    float lum2 = dot(c2.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float4 _65 = c2;
    float3 _73 = mix(_65.xyz, float3(lum2), float3(_28.u_desaturate2));
    c2.x = _73.x;
    c2.y = _73.y;
    c2.z = _73.z;
    float3 screen = float3(1.0) - ((float3(1.0) - c1.xyz) * (float3(1.0) - c2.xyz));
    float3 result = mix(c1.xyz, screen, float3(_28.u_opacity));
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), c1.w);
    return out;
}

