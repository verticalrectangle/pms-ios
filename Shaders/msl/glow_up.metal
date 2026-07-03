#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_warmth;
    float u_brighten;
    float u_glow;
};

struct fx_glow_up_out
{
    float4 frag [[color(0)]];
};

struct fx_glow_up_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_glow_up_out fx_glow_up(fx_glow_up_in in [[stage_in]], constant Params& _13 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_glow_up_out out = {};
    float2 px = float2(1.0 / _13.u_tex_w, 1.0 / _13.u_tex_h);
    float4 src = u_tex.sample(u_texSmplr, in.v_uv);
    float3 c = src.xyz;
    float3 bsum = float3(0.0);
    for (int dy = -2; dy <= 2; dy++)
    {
        for (int dx = -2; dx <= 2; dx++)
        {
            bsum += u_tex.sample(u_texSmplr, (in.v_uv + ((float2(float(dx), float(dy)) * 3.0) * px))).xyz;
        }
    }
    bsum *= 0.039999999105930328369140625;
    float3 scr = float3(1.0) - ((float3(1.0) - c) * (float3(1.0) - bsum));
    c = mix(c, scr, float3(_13.u_glow * 0.60000002384185791015625));
    c.x *= (1.0 + (0.100000001490116119384765625 * _13.u_warmth));
    c.z *= (1.0 - (0.100000001490116119384765625 * _13.u_warmth));
    c += ((((float3(1.0) - c) * _13.u_brighten) * c) * 2.0);
    out.frag = float4(fast::clamp(c, float3(0.0), float3(1.0)), src.w);
    return out;
}

