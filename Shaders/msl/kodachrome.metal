#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_saturation;
    float u_reds;
    float u_shadows;
};

struct fx_kodachrome_out
{
    float4 frag [[color(0)]];
};

struct fx_kodachrome_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_kodachrome_out fx_kodachrome(fx_kodachrome_in in [[stage_in]], constant Params& _38 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_kodachrome_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float3 sat = mix(float3(lum), col.xyz, float3(_38.u_saturation));
    float red_dominant = fast::max(sat.x - sat.y, fast::max(sat.x - sat.z, 0.0));
    sat.x = fast::min(sat.x + ((red_dominant * _38.u_reds) * 0.4000000059604644775390625), 1.0);
    sat.y = fast::max(sat.y - ((red_dominant * _38.u_reds) * 0.100000001490116119384765625), 0.0);
    float shadow_mask = smoothstep(0.3499999940395355224609375, 0.0, lum);
    float3 gold = float3(0.119999997317790985107421875, 0.07999999821186065673828125, 0.0);
    sat += ((gold * shadow_mask) * _38.u_shadows);
    sat.z = mix(sat.z, sat.z * 0.85000002384185791015625, _38.u_reds * 0.300000011920928955078125);
    out.frag = float4(fast::clamp(sat, float3(0.0), float3(1.0)), col.w);
    return out;
}

