#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_smooth;
    float u_brighten;
    float u_warmth;
};

struct fx_porcelain_skin_out
{
    float4 frag [[color(0)]];
};

struct fx_porcelain_skin_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_porcelain_skin_out fx_porcelain_skin(fx_porcelain_skin_in in [[stage_in]], constant Params& _13 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_porcelain_skin_out out = {};
    float2 px = float2(1.0 / _13.u_tex_w, 1.0 / _13.u_tex_h);
    float4 c = u_tex.sample(u_texSmplr, in.v_uv);
    float3 acc = c.xyz;
    float wsum = 1.0;
    for (int i = 0; i < 12; i++)
    {
        float a = (((float(i) * 0.52359998226165771484375) * 6.28318023681640625) / 6.28318023681640625) + (float(i) * 2.399960041046142578125);
        float r = 2.0 + (4.0 * fract(float(i) * 0.61803400516510009765625));
        float3 s = u_tex.sample(u_texSmplr, (in.v_uv + ((float2(cos(a), sin(a)) * r) * px))).xyz;
        float w = exp((-dot(s - c.xyz, s - c.xyz)) * 18.0);
        acc += (s * w);
        wsum += w;
    }
    float3 smoothed = acc / float3(wsum);
    float lum = dot(c.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float skin = ((smoothstep(0.1500000059604644775390625, 0.3499999940395355224609375, lum) * (1.0 - smoothstep(0.75, 0.949999988079071044921875, lum))) * smoothstep(0.0, 0.07999999821186065673828125, c.x - c.z)) * step(c.z, c.x);
    float3 rgb = mix(c.xyz, smoothed, float3(_13.u_smooth * fast::clamp(skin * 1.39999997615814208984375, 0.0, 1.0)));
    rgb += (((float3(1.0) - rgb) * _13.u_brighten) * (0.60000002384185791015625 + (0.4000000059604644775390625 * skin)));
    rgb.x = fast::clamp(rgb.x + (_13.u_warmth * 0.0599999986588954925537109375), 0.0, 1.0);
    rgb.z = fast::clamp(rgb.z - (_13.u_warmth * 0.0500000007450580596923828125), 0.0, 1.0);
    out.frag = float4(fast::clamp(rgb, float3(0.0), float3(1.0)), c.w);
    return out;
}

