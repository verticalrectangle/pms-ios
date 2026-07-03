#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_threshold;
    float u_intensity;
    float u_direction;
};

struct fx_pixel_sort_out
{
    float4 frag [[color(0)]];
};

struct fx_pixel_sort_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_pixel_sort_out fx_pixel_sort(fx_pixel_sort_in in [[stage_in]], constant Params& _35 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_pixel_sort_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float2 ipx = float2(1.0 / _35.u_tex_w, 1.0 / _35.u_tex_h);
    float2 _54;
    if (_35.u_direction < 0.5)
    {
        _54 = float2(ipx.x, 0.0);
    }
    else
    {
        _54 = float2(0.0, ipx.y);
    }
    float2 axis = _54;
    float run = 0.0;
    float max_run = 80.0 * _35.u_intensity;
    for (float i = 1.0; i <= max_run; i += 1.0)
    {
        float3 s = u_tex.sample(u_texSmplr, (in.v_uv - (axis * i))).xyz;
        float sl = dot(s, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
        if (sl < _35.u_threshold)
        {
            break;
        }
        run = i;
    }
    if ((lum >= _35.u_threshold) && (run > 0.0))
    {
        float disp = run * _35.u_intensity;
        float2 sort_uv = in.v_uv + (axis * disp);
        out.frag = u_tex.sample(u_texSmplr, fast::clamp(sort_uv, float2(0.0), float2(1.0)));
    }
    else
    {
        out.frag = col;
    }
    return out;
}

