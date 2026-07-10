#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_time;
    float u_breathe;
    float u_rate;
    float u_chroma;
};

struct fx_breathe_warp_out
{
    float4 frag [[color(0)]];
};

struct fx_breathe_warp_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_breathe_warp_out fx_breathe_warp(fx_breathe_warp_in in [[stage_in]], constant Params& _23 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_breathe_warp_out out = {};
    float2 d = in.v_uv - float2(0.5);
    float r = length(d);
    float phase = (sin(_23.u_time * _23.u_rate) * 0.5) + 0.5;
    float amt = ((_23.u_breathe * 0.119999997317790985107421875) * phase) * (0.4000000059604644775390625 + (r * 1.60000002384185791015625));
    float2 uv = float2(0.5) + (d * (1.0 - amt));
    float ca = ((_23.u_chroma * 0.01200000010430812835693359375) * (r * 2.0)) * (0.5 + phase);
    float2 _76;
    if (r > 9.9999997473787516355514526367188e-05)
    {
        _76 = d / float2(r);
    }
    else
    {
        _76 = float2(0.0);
    }
    float2 dir = _76;
    float cr = u_tex.sample(u_texSmplr, fast::clamp(uv + (dir * ca), float2(0.0), float2(1.0))).x;
    float cg = u_tex.sample(u_texSmplr, fast::clamp(uv, float2(0.0), float2(1.0))).y;
    float cb = u_tex.sample(u_texSmplr, fast::clamp(uv - (dir * ca), float2(0.0), float2(1.0))).z;
    float a = u_tex.sample(u_texSmplr, fast::clamp(uv, float2(0.0), float2(1.0))).w;
    out.frag = float4(cr, cg, cb, a);
    return out;
}

