#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_glow;
    float u_fade;
    float u_blush;
};

struct fx_retro_beauty_out
{
    float4 frag [[color(0)]];
};

struct fx_retro_beauty_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_retro_beauty_out fx_retro_beauty(fx_retro_beauty_in in [[stage_in]], constant Params& _13 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_retro_beauty_out out = {};
    float2 px = float2(1.0 / _13.u_tex_w, 1.0 / _13.u_tex_h);
    float4 src = u_tex.sample(u_texSmplr, in.v_uv);
    float3 c = src.xyz;
    float3 bsum = float3(0.0);
    for (int dy = -2; dy <= 2; dy++)
    {
        for (int dx = -2; dx <= 2; dx++)
        {
            bsum += u_tex.sample(u_texSmplr, (in.v_uv + ((float2(float(dx), float(dy)) * 4.0) * px))).xyz;
        }
    }
    bsum *= 0.039999999105930328369140625;
    float3 scr = float3(1.0) - ((float3(1.0) - c) * (float3(1.0) - bsum));
    c = mix(c, scr, float3(_13.u_glow * 0.699999988079071044921875));
    c = (c * (1.0 - (_13.u_fade * 0.2199999988079071044921875))) + float3(_13.u_fade * 0.1599999964237213134765625);
    c = mix(c, smoothstep(float3(0.0), float3(1.0499999523162841796875), c), float3(_13.u_fade * 0.5));
    float lum = dot(c, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float mids = (4.0 * lum) * (1.0 - lum);
    c.x += ((_13.u_blush * 0.054999999701976776123046875) * mids);
    c.y += ((_13.u_blush * 0.01200000010430812835693359375) * mids);
    c.z += ((_13.u_blush * 0.02999999932944774627685546875) * (1.0 - lum));
    out.frag = float4(fast::clamp(c, float3(0.0), float3(1.0)), src.w);
    return out;
}

