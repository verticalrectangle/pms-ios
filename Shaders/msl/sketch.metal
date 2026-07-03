#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_strength;
    float u_invert;
};

struct fx_sketch_out
{
    float4 frag [[color(0)]];
};

struct fx_sketch_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_sketch_out fx_sketch(fx_sketch_in in [[stage_in]], constant Params& _13 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_sketch_out out = {};
    float2 px = float2(1.0 / _13.u_tex_w, 1.0 / _13.u_tex_h);
    float tl = dot(u_tex.sample(u_texSmplr, (in.v_uv + float2(-px.x, px.y))).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float tc = dot(u_tex.sample(u_texSmplr, (in.v_uv + float2(0.0, px.y))).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float tr = dot(u_tex.sample(u_texSmplr, (in.v_uv + float2(px.x, px.y))).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float ml = dot(u_tex.sample(u_texSmplr, (in.v_uv + float2(-px.x, 0.0))).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float mr = dot(u_tex.sample(u_texSmplr, (in.v_uv + float2(px.x, 0.0))).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float bl = dot(u_tex.sample(u_texSmplr, (in.v_uv + float2(-px.x, -px.y))).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float bc = dot(u_tex.sample(u_texSmplr, (in.v_uv + float2(0.0, -px.y))).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float br = dot(u_tex.sample(u_texSmplr, (in.v_uv + float2(px.x, -px.y))).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float gx = (((((-tl) - (2.0 * ml)) - bl) + tr) + (2.0 * mr)) + br;
    float gy = (((((-tl) - (2.0 * tc)) - tr) + bl) + (2.0 * bc)) + br;
    float edge = fast::clamp((sqrt((gx * gx) + (gy * gy)) * _13.u_strength) * 4.0, 0.0, 1.0);
    float _190;
    if (_13.u_invert > 0.5)
    {
        _190 = 1.0 - edge;
    }
    else
    {
        _190 = edge;
    }
    float sketch = _190;
    float4 orig = u_tex.sample(u_texSmplr, in.v_uv);
    out.frag = float4(orig.xyz * sketch, orig.w);
    return out;
}

