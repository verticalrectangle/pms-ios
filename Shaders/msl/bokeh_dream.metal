#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_radius;
    float u_threshold;
    float u_intensity;
};

struct fx_bokeh_dream_out
{
    float4 frag [[color(0)]];
};

struct fx_bokeh_dream_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_bokeh_dream_out fx_bokeh_dream(fx_bokeh_dream_in in [[stage_in]], constant Params& _24 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_bokeh_dream_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float ar = _24.u_tex_w / _24.u_tex_h;
    float3 bokeh = float3(0.0);
    float total = 0.001000000047497451305389404296875;
    int steps = 12;
    for (int a = 0; a < steps; a++)
    {
        float ang = (6.28318023681640625 * float(a)) / float(steps);
        for (int r = 1; r <= 6; r++)
        {
            float rad = (float(r) / 6.0) * _24.u_radius;
            float2 uv = in.v_uv + (float2(cos(ang) / ar, sin(ang)) * rad);
            float3 s = u_tex.sample(u_texSmplr, fast::clamp(uv, float2(0.0), float2(1.0))).xyz;
            float bright = dot(s, float3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
            float wt = step(_24.u_threshold, bright) * (1.0 - (float(r) / 7.0));
            bokeh += (s * wt);
            total += wt;
        }
    }
    bokeh /= float3(total);
    float3 result = float3(1.0) - ((float3(1.0) - col.xyz) * (float3(1.0) - ((bokeh * _24.u_intensity) * 0.5)));
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), col.w);
    return out;
}

