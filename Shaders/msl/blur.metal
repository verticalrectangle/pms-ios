#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_blur;
    float u_tex_w;
    float u_tex_h;
};

struct fx_blur_out
{
    float4 frag [[color(0)]];
};

struct fx_blur_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_blur_out fx_blur(fx_blur_in in [[stage_in]], constant Params& _11 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_blur_out out = {};
    float r = fast::clamp(_11.u_blur * 1.5, 0.0, 21.0);
    if (r < 0.5)
    {
        out.frag = u_tex.sample(u_texSmplr, in.v_uv);
        return out;
    }
    float2 px = float2(1.0) / float2(_11.u_tex_w, _11.u_tex_h);
    float4 sum = u_tex.sample(u_texSmplr, in.v_uv);
    float wsum = 1.0;
    for (int i = 1; i <= 24; i++)
    {
        float a = float(i) * 2.3999631404876708984375;
        float rad = r * sqrt(float(i) / 24.0);
        float2 off = (float2(cos(a), sin(a)) * rad) * px;
        sum += u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + off, float2(0.0), float2(1.0)));
        wsum += 1.0;
    }
    out.frag = sum / float4(wsum);
    return out;
}

