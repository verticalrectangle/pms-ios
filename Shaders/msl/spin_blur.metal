#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_angle;
};

struct fx_spin_blur_out
{
    float4 frag [[color(0)]];
};

struct fx_spin_blur_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_spin_blur_out fx_spin_blur(fx_spin_blur_in in [[stage_in]], constant Params& _34 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_spin_blur_out out = {};
    float2 c = float2(0.5);
    float4 acc = float4(0.0);
    for (int i = 0; i < 14; i++)
    {
        float a = _34.u_angle * ((float(i) / 13.0) - 0.5);
        float cs = cos(a);
        float sn = sin(a);
        float2 d = in.v_uv - c;
        float2 rot = float2((cs * d.x) - (sn * d.y), (sn * d.x) + (cs * d.y)) + c;
        acc += u_tex.sample(u_texSmplr, fast::clamp(rot, float2(0.0), float2(1.0)));
    }
    out.frag = acc / float4(14.0);
    return out;
}

