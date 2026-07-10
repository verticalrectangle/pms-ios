#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_time;
    float u_folds;
    float u_drift;
    float u_zoom;
};

struct fx_fractal_mirror_out
{
    float4 frag [[color(0)]];
};

struct fx_fractal_mirror_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_fractal_mirror_out fx_fractal_mirror(fx_fractal_mirror_in in [[stage_in]], constant Params& _20 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_fractal_mirror_out out = {};
    float2 p = in.v_uv - float2(0.5);
    float t = _20.u_time * _20.u_drift;
    float z = 1.0 + ((sin(_20.u_time * 0.5) * 0.25) * _20.u_zoom);
    p *= z;
    int folds = int(fast::clamp(_20.u_folds, 1.0, 6.0));
    for (int i = 0; i < 6; i++)
    {
        if (i >= folds)
        {
            break;
        }
        float a = (t * (0.300000011920928955078125 + (0.12999999523162841796875 * float(i)))) + (float(i) * 0.7853000164031982421875);
        float2 ax = float2(cos(a), sin(a));
        float d = dot(p, float2(-ax.y, ax.x));
        p -= (float2(-ax.y, ax.x) * (2.0 * fast::min(0.0, d)));
        p *= 1.08000004291534423828125;
    }
    float2 uv = fract(p + float2(0.5));
    uv = abs((uv * 2.0) - float2(1.0));
    out.frag = u_tex.sample(u_texSmplr, uv);
    return out;
}

