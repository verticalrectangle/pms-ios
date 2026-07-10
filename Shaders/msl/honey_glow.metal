#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_glow;
    float u_warmth;
    float u_lift;
};

struct fx_honey_glow_out
{
    float4 frag [[color(0)]];
};

struct fx_honey_glow_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_honey_glow_out fx_honey_glow(fx_honey_glow_in in [[stage_in]], constant Params& _13 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_honey_glow_out out = {};
    float2 px = float2(1.0 / _13.u_tex_w, 1.0 / _13.u_tex_h);
    float4 c = u_tex.sample(u_texSmplr, in.v_uv);
    float3 bloom = float3(0.0);
    for (int i = 0; i < 12; i++)
    {
        float a = float(i) * 2.399960041046142578125;
        float r = 3.0 + (9.0 * fract(float(i) * 0.61803400516510009765625));
        float3 s = u_tex.sample(u_texSmplr, (in.v_uv + ((float2(cos(a), sin(a)) * r) * px))).xyz;
        float b = fast::max(fast::max(s.x, s.y), s.z);
        bloom += (s * smoothstep(0.550000011920928955078125, 0.89999997615814208984375, b));
    }
    bloom /= float3(12.0);
    float3 honey = float3(1.0, 0.7799999713897705078125, 0.449999988079071044921875);
    float3 rgb = c.xyz + (((bloom * honey) * _13.u_glow) * 0.89999997615814208984375);
    float lum = dot(rgb, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    rgb = mix(rgb, (rgb * honey) * 1.14999997615814208984375, float3(_13.u_warmth * (0.300000011920928955078125 + (0.699999988079071044921875 * lum))));
    rgb = mix(rgb, fast::max(rgb, float3(0.14000000059604644775390625, 0.0900000035762786865234375, 0.0500000007450580596923828125)), float3(_13.u_lift * (1.0 - lum)));
    out.frag = float4(fast::clamp(rgb, float3(0.0), float3(1.0)), c.w);
    return out;
}

