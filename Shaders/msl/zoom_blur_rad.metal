#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_intensity;
    float u_cx;
    float u_cy;
};

struct fx_zoom_blur_rad_out
{
    float4 frag [[color(0)]];
};

struct fx_zoom_blur_rad_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_zoom_blur_rad_out fx_zoom_blur_rad(fx_zoom_blur_rad_in in [[stage_in]], constant Params& _12 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_zoom_blur_rad_out out = {};
    float2 focus = float2(_12.u_cx, _12.u_cy);
    float4 acc = float4(0.0);
    for (int i = 0; i < 14; i++)
    {
        float t = float(i) / 13.0;
        float scale = 1.0 - (_12.u_intensity * t);
        float2 uv = focus + ((in.v_uv - focus) * scale);
        float w = 1.0 - (t * 0.5);
        acc += (u_tex.sample(u_texSmplr, fast::clamp(uv, float2(0.0), float2(1.0))) * w);
    }
    out.frag = acc / float4(acc.w);
    return out;
}

