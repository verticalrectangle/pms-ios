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
    float u_line_width;
    float u_intensity;
    float u_rgb_sep;
};

struct fx_scanline_color_out
{
    float4 frag [[color(0)]];
};

struct fx_scanline_color_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_scanline_color_out fx_scanline_color(fx_scanline_color_in in [[stage_in]], constant Params& _29 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_scanline_color_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float line_pos = mod(in.v_uv.y * _29.u_tex_h, _29.u_line_width * 3.0);
    float sub_r = step(line_pos, _29.u_line_width);
    float sub_g = step(_29.u_line_width, line_pos) * step(line_pos, _29.u_line_width * 2.0);
    float sub_b = step(_29.u_line_width * 2.0, line_pos);
    float3 mask = mix(float3(1.0), float3(sub_r, sub_g, sub_b) * 1.5, float3(_29.u_rgb_sep));
    float gap = step(_29.u_line_width * 2.900000095367431640625, line_pos);
    mask *= (1.0 - (gap * 0.800000011920928955078125));
    float3 result = col.xyz * mix(float3(1.0), mask, float3(_29.u_intensity));
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), col.w);
    return out;
}

