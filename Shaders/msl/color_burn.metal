#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_strength;
    float u_hue;
};

struct fx_color_burn_out
{
    float4 frag [[color(0)]];
};

struct fx_color_burn_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_color_burn_out fx_color_burn(fx_color_burn_in in [[stage_in]], constant Params& _24 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_color_burn_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float h = _24.u_hue / 360.0;
    float4 K = float4(1.0, 0.666666686534881591796875, 0.3333333432674407958984375, 3.0);
    float3 p = abs((fract(float3(h) + K.xyz) * 6.0) - K.www);
    float3 tint = fast::clamp(p - K.xxx, float3(0.0), float3(1.0));
    float3 burned = float3(1.0) - ((float3(1.0) - col.xyz) / fast::max(tint, float3(0.001000000047497451305389404296875)));
    burned = fast::clamp(burned, float3(0.0), float3(1.0));
    out.frag = float4(mix(col.xyz, burned, float3(_24.u_strength)), col.w);
    return out;
}

