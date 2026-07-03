#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_time;
    float u_strength;
    float u_speed;
};

struct fx_holographic_out
{
    float4 frag [[color(0)]];
};

struct fx_holographic_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_holographic_out fx_holographic(fx_holographic_in in [[stage_in]], constant Params& _37 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_holographic_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float phase = ((in.v_uv.x * 4.0) + (in.v_uv.y * 2.0)) + ((_37.u_time * _37.u_speed) * 0.5);
    float hue = fract(phase);
    float4 K = float4(1.0, 0.666666686534881591796875, 0.3333333432674407958984375, 3.0);
    float3 p = abs((fract(float3(hue) + K.xyz) * 6.0) - K.www);
    float3 iris = fast::clamp(p - K.xxx, float3(0.0), float3(1.0));
    float3 screen = float3(1.0) - ((float3(1.0) - col.xyz) * (float3(1.0) - ((iris * _37.u_strength) * 0.64999997615814208984375)));
    out.frag = float4(fast::clamp(screen, float3(0.0), float3(1.0)), col.w);
    return out;
}

