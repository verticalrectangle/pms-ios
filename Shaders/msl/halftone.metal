#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// Implementation of the GLSL mod() function, which is slightly different than Metal fmod()
template<typename Tx, typename Ty>
inline Tx mod(Tx x, Ty y)
{
    return x - y * floor(x / y);
}

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_size;
    float u_strength;
};

struct fx_halftone_out
{
    float4 frag [[color(0)]];
};

struct fx_halftone_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_halftone_out fx_halftone(fx_halftone_in in [[stage_in]], constant Params& _34 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_halftone_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float luma = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float2 cell = float2(_34.u_size / _34.u_tex_w, _34.u_size / _34.u_tex_h);
    float2 local = (mod(in.v_uv, cell) / cell) - float2(0.5);
    float radius = (1.0 - luma) * 0.5;
    float dot_mask = smoothstep(radius + 0.0199999995529651641845703125, radius - 0.0199999995529651641845703125, length(local));
    float halftone = mix(luma, dot_mask, _34.u_strength);
    out.frag = float4(float3(halftone), col.w);
    return out;
}

