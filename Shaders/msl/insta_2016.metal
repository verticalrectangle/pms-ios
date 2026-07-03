#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_fade;
    float u_pop;
    float u_warmth;
};

struct fx_insta_2016_out
{
    float4 frag [[color(0)]];
};

struct fx_insta_2016_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_insta_2016_out fx_insta_2016(fx_insta_2016_in in [[stage_in]], constant Params& _37 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_insta_2016_out out = {};
    float4 src = u_tex.sample(u_texSmplr, in.v_uv);
    float3 c = src.xyz;
    float lum = dot(c, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    c = (c * (1.0 - (_37.u_fade * 0.180000007152557373046875))) + (float3(0.100000001490116119384765625, 0.0949999988079071044921875, 0.0900000035762786865234375) * _37.u_fade);
    float hi = smoothstep(0.3499999940395355224609375, 0.89999997615814208984375, lum);
    float lo = 1.0 - smoothstep(0.100000001490116119384765625, 0.5, lum);
    c.x += ((0.070000000298023223876953125 * _37.u_warmth) * hi);
    c.y += ((0.0199999995529651641845703125 * _37.u_warmth) * hi);
    c.z -= ((0.04500000178813934326171875 * _37.u_warmth) * hi);
    c.z += ((0.039999999105930328369140625 * abs(_37.u_warmth)) * lo);
    c.y += ((0.014999999664723873138427734375 * abs(_37.u_warmth)) * lo);
    float sat = 1.0 + (_37.u_pop * 0.550000011920928955078125);
    float3 gray = float3(dot(c, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625)));
    float skin = smoothstep(0.119999997317790985107421875, 0.0, abs((c.x - c.y) - 0.100000001490116119384765625)) * step(c.z, c.y);
    c = mix(gray, c, float3(mix(sat, 1.0 + (_37.u_pop * 0.20000000298023223876953125), skin)));
    float2 d = in.v_uv - float2(0.5);
    c *= (1.0 - ((_37.u_pop * 0.2199999988079071044921875) * smoothstep(0.3499999940395355224609375, 0.75, dot(d, d) * 2.0)));
    out.frag = float4(fast::clamp(c, float3(0.0), float3(1.0)), src.w);
    return out;
}

