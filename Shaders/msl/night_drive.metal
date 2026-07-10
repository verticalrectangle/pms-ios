#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_night;
    float u_sodium;
    float u_flare;
};

struct fx_night_drive_out
{
    float4 frag [[color(0)]];
};

struct fx_night_drive_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_night_drive_out fx_night_drive(fx_night_drive_in in [[stage_in]], constant Params& _13 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_night_drive_out out = {};
    float2 px = float2(1.0 / _13.u_tex_w, 1.0 / _13.u_tex_h);
    float4 c = u_tex.sample(u_texSmplr, in.v_uv);
    float3 flare = float3(0.0);
    for (int i = -8; i <= 8; i++)
    {
        float3 s = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + float2((float(i) * 7.0) * px.x, 0.0), float2(0.0), float2(1.0))).xyz;
        float b = fast::max(fast::max(s.x, s.y), s.z);
        flare += ((s * smoothstep(0.75, 0.980000019073486328125, b)) * (1.0 - (abs(float(i)) / 9.0)));
    }
    flare /= float3(8.0);
    float lum = dot(c.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float3 cool = c.xyz * float3(0.75, 0.85000002384185791015625, 1.2000000476837158203125);
    cool = fast::max(cool - float3(0.02999999932944774627685546875), float3(0.0)) * 1.0299999713897705078125;
    float3 sodium = float3(1.0, 0.62000000476837158203125, 0.25);
    float3 rgb = mix(c.xyz, cool, float3(_13.u_night * (1.0 - smoothstep(0.5, 0.89999997615814208984375, lum))));
    rgb = mix(rgb, (rgb * sodium) * 1.25, float3(_13.u_sodium * smoothstep(0.550000011920928955078125, 0.89999997615814208984375, lum)));
    rgb += ((flare * float3(0.5, 0.699999988079071044921875, 1.2000000476837158203125)) * _13.u_flare);
    out.frag = float4(fast::clamp(rgb, float3(0.0), float3(1.0)), c.w);
    return out;
}

