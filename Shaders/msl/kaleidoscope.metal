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
    float u_segments;
    float u_rotation;
    float u_zoom;
};

struct fx_kaleidoscope_out
{
    float4 frag [[color(0)]];
};

struct fx_kaleidoscope_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_kaleidoscope_out fx_kaleidoscope(fx_kaleidoscope_in in [[stage_in]], constant Params& _20 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_kaleidoscope_out out = {};
    float2 c = float2(0.5);
    float2 d = (in.v_uv - c) / float2(_20.u_zoom);
    float angle = precise::atan2(d.y, d.x) + _20.u_rotation;
    float radius = length(d);
    float sector = 6.283185482025146484375 / fast::max(_20.u_segments, 2.0);
    angle = mod(angle, sector);
    if (angle > (sector * 0.5))
    {
        angle = sector - angle;
    }
    float2 uv = c + (float2(cos(angle), sin(angle)) * radius);
    uv = abs((fract(uv * 0.5) * 2.0) - float2(1.0));
    out.frag = u_tex.sample(u_texSmplr, uv);
    return out;
}

