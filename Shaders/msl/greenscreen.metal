#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_key_r;
    float u_key_g;
    float u_key_b;
    float u_similarity;
    float u_smoothness;
    float u_spill;
};

struct fx_greenscreen_out
{
    float4 frag [[color(0)]];
};

struct fx_greenscreen_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_greenscreen_out fx_greenscreen(fx_greenscreen_in in [[stage_in]], constant Params& _25 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_greenscreen_out out = {};
    float4 c = u_tex.sample(u_texSmplr, in.v_uv);
    float3 key = float3(_25.u_key_r, _25.u_key_g, _25.u_key_b);
    float yk = dot(key, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float yp = dot(c.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float2 ck = float2(key.x - yk, key.z - yk);
    float2 cp = float2(c.x - yp, c.z - yp);
    float dist = length(cp - ck);
    float a = smoothstep(_25.u_similarity, _25.u_similarity + fast::max(_25.u_smoothness, 0.001000000047497451305389404296875), dist);
    float3 rgb = c.xyz;
    float ds = _25.u_spill * (1.0 - a);
    bool _110 = key.y >= key.x;
    bool _118;
    if (_110)
    {
        _118 = key.y >= key.z;
    }
    else
    {
        _118 = _110;
    }
    if (_118)
    {
        rgb.y = mix(rgb.y, fast::min(rgb.y, fast::max(rgb.x, rgb.z)), ds);
    }
    else
    {
        bool _139 = key.z >= key.x;
        bool _147;
        if (_139)
        {
            _147 = key.z >= key.y;
        }
        else
        {
            _147 = _139;
        }
        if (_147)
        {
            rgb.z = mix(rgb.z, fast::min(rgb.z, fast::max(rgb.x, rgb.y)), ds);
        }
        else
        {
            rgb.x = mix(rgb.x, fast::min(rgb.x, fast::max(rgb.y, rgb.z)), ds);
        }
    }
    out.frag = float4(rgb, a * c.w);
    return out;
}

