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
    float u_tex_h;
    float u_density;
    float u_strength;
};

struct fx_scanlines_out
{
    float4 frag [[color(0)]];
};

struct fx_scanlines_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_scanlines_out fx_scanlines(fx_scanlines_in in [[stage_in]], constant Params& _29 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_scanlines_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float line = mod((in.v_uv.y * _29.u_tex_h) / _29.u_density, 2.0);
    float _47;
    if (line < 1.0)
    {
        _47 = 1.0;
    }
    else
    {
        _47 = 1.0 - _29.u_strength;
    }
    float mask = _47;
    out.frag = float4(col.xyz * mask, col.w);
    return out;
}

