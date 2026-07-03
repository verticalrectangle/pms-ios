#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_strength;
};

struct fx_fisheye_out
{
    float4 frag [[color(0)]];
};

struct fx_fisheye_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_fisheye_out fx_fisheye(fx_fisheye_in in [[stage_in]], constant Params& _35 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_fisheye_out out = {};
    float2 p = (in.v_uv * 2.0) - float2(1.0);
    float r = length(p);
    float theta = precise::atan2(p.y, p.x);
    float r2 = r * (1.0 + ((_35.u_strength * r) * r));
    float2 warped = ((float2(cos(theta), sin(theta)) * r2) * 0.5) + float2(0.5);
    bool _63 = warped.x < 0.0;
    bool _70;
    if (!_63)
    {
        _70 = warped.x > 1.0;
    }
    else
    {
        _70 = _63;
    }
    bool _77;
    if (!_70)
    {
        _77 = warped.y < 0.0;
    }
    else
    {
        _77 = _70;
    }
    bool _84;
    if (!_77)
    {
        _84 = warped.y > 1.0;
    }
    else
    {
        _84 = _77;
    }
    if (_84)
    {
        out.frag = float4(0.0, 0.0, 0.0, 1.0);
    }
    else
    {
        out.frag = u_tex.sample(u_texSmplr, warped);
    }
    return out;
}

