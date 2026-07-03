#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_dot_size;
    float u_ink_threshold;
    float u_color_levels;
};

struct fx_comic_dots_out
{
    float4 frag [[color(0)]];
};

struct fx_comic_dots_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_comic_dots_out fx_comic_dots(fx_comic_dots_in in [[stage_in]], constant Params& _13 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_comic_dots_out out = {};
    float2 px = float2(1.0 / _13.u_tex_w, 1.0 / _13.u_tex_h);
    float2 cell = (floor(in.v_uv / (px * _13.u_dot_size)) * px) * _13.u_dot_size;
    float2 cell_center = cell + ((px * _13.u_dot_size) * 0.5);
    float3 cell_col = u_tex.sample(u_texSmplr, fast::clamp(cell_center, float2(0.0), float2(1.0))).xyz;
    float lum = dot(cell_col, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float dot_r = lum * 0.550000011920928955078125;
    float2 local = (in.v_uv - cell_center) / (px * _13.u_dot_size);
    float in_dot = step(length(local), dot_r);
    cell_col = floor((cell_col * _13.u_color_levels) + float3(0.5)) / float3(_13.u_color_levels);
    float3 gx = u_tex.sample(u_texSmplr, (in.v_uv + float2(px.x, 0.0))).xyz - u_tex.sample(u_texSmplr, (in.v_uv - float2(px.x, 0.0))).xyz;
    float3 gy = u_tex.sample(u_texSmplr, (in.v_uv + float2(0.0, px.y))).xyz - u_tex.sample(u_texSmplr, (in.v_uv - float2(0.0, px.y))).xyz;
    float edge = fast::clamp(((length(gx) + length(gy)) - _13.u_ink_threshold) * 8.0, 0.0, 1.0);
    float3 result = mix(float3(1.0), cell_col, float3(in_dot)) * (1.0 - edge);
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), 1.0);
    return out;
}

