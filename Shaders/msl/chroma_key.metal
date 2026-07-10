#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_chroma_key_r;
    float u_chroma_key_g;
    float u_chroma_key_b;
    float u_chroma_key_threshold;
    float u_chroma_key_softness;
    float u_tex_w;
    float u_tex_h;
};

struct fx_chroma_key_out
{
    float4 frag [[color(0)]];
};

struct fx_chroma_key_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_chroma_key_out fx_chroma_key(fx_chroma_key_in in [[stage_in]], constant Params& _12 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_chroma_key_out out = {};
    float3 key = float3(_12.u_chroma_key_r, _12.u_chroma_key_g, _12.u_chroma_key_b);
    float4 c = u_tex.sample(u_texSmplr, in.v_uv);
    float2 tx = float2(1.0) / float2(_12.u_tex_w, _12.u_tex_h);
    float3 kc = ((((c.xyz + u_tex.sample(u_texSmplr, (in.v_uv + float2(2.0 * tx.x, 0.0))).xyz) + u_tex.sample(u_texSmplr, (in.v_uv + float2((-2.0) * tx.x, 0.0))).xyz) + u_tex.sample(u_texSmplr, (in.v_uv + float2(0.0, 2.0 * tx.y))).xyz) + u_tex.sample(u_texSmplr, (in.v_uv + float2(0.0, (-2.0) * tx.y))).xyz) * 0.20000000298023223876953125;
    float lum_k = dot(key, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float3 ck = key - float3(lum_k);
    float lum_p = dot(kc, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float3 cp = kc - float3(lum_p);
    float dist = length(cp - ck);
    float soft = fast::max(_12.u_chroma_key_softness, 0.001000000047497451305389404296875);
    float t = fast::clamp((dist - _12.u_chroma_key_threshold) / soft, 0.0, 1.0);
    float alpha = (t * t) * (3.0 - (2.0 * t));
    float3 rgb = c.xyz;
    if (alpha < 1.0)
    {
        float spill = 1.0 - alpha;
        bool _166 = key.y > key.x;
        bool _175;
        if (_166)
        {
            _175 = key.y > key.z;
        }
        else
        {
            _175 = _166;
        }
        if (_175)
        {
            rgb.y = mix(rgb.y, (rgb.x + rgb.z) * 0.5, spill);
        }
        else
        {
            bool _195 = key.z > key.x;
            bool _203;
            if (_195)
            {
                _203 = key.z > key.y;
            }
            else
            {
                _203 = _195;
            }
            if (_203)
            {
                rgb.z = mix(rgb.z, (rgb.x + rgb.y) * 0.5, spill);
            }
        }
    }
    out.frag = float4(rgb, alpha * c.w);
    return out;
}

