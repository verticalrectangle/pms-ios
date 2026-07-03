#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_contrast;
    float u_blue_tint;
};

struct fx_x_ray_out
{
    float4 frag [[color(0)]];
};

struct fx_x_ray_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_x_ray_out fx_x_ray(fx_x_ray_in in [[stage_in]], constant Params& _39 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_x_ray_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float inv = 1.0 - lum;
    inv = fast::clamp(((inv - 0.5) * _39.u_contrast) + 0.5, 0.0, 1.0);
    float3 xray = mix(float3(0.550000011920928955078125, 0.64999997615814208984375, 0.85000002384185791015625), float3(0.949999988079071044921875, 0.9700000286102294921875, 1.0), float3(inv));
    xray = mix(float3(inv), xray, float3(_39.u_blue_tint));
    out.frag = float4(fast::clamp(xray, float3(0.0), float3(1.0)), col.w);
    return out;
}

