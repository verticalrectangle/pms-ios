#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_axis;
    float u_vertical;
    float u_strength;
};

struct fx_mirror_fold_out
{
    float4 frag [[color(0)]];
};

struct fx_mirror_fold_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_mirror_fold_out fx_mirror_fold(fx_mirror_fold_in in [[stage_in]], constant Params& _17 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_mirror_fold_out out = {};
    float2 uv = in.v_uv;
    float2 mirrored = uv;
    if (_17.u_vertical < 0.5)
    {
        if (uv.x > _17.u_axis)
        {
            mirrored.x = _17.u_axis - (uv.x - _17.u_axis);
        }
    }
    else
    {
        if (uv.y > _17.u_axis)
        {
            mirrored.y = _17.u_axis - (uv.y - _17.u_axis);
        }
    }
    float4 orig = u_tex.sample(u_texSmplr, fast::clamp(uv, float2(0.0), float2(1.0)));
    float4 fold = u_tex.sample(u_texSmplr, fast::clamp(mirrored, float2(0.0), float2(1.0)));
    out.frag = mix(orig, fold, float4(_17.u_strength));
    return out;
}

