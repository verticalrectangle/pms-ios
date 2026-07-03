#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_block_size;
    float u_color_steps;
    float u_strength;
};

struct fx_pixel_mosaic_out
{
    float4 frag [[color(0)]];
};

struct fx_pixel_mosaic_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_pixel_mosaic_out fx_pixel_mosaic(fx_pixel_mosaic_in in [[stage_in]], constant Params& _12 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_pixel_mosaic_out out = {};
    float2 px = float2(_12.u_tex_w, _12.u_tex_h);
    float2 block = (floor((in.v_uv * px) / float2(_12.u_block_size)) * _12.u_block_size) / px;
    float2 center = block + (float2(_12.u_block_size * 0.5) / px);
    float4 orig = u_tex.sample(u_texSmplr, in.v_uv);
    float4 c = u_tex.sample(u_texSmplr, fast::clamp(center, float2(0.0), float2(1.0)));
    float4 _69 = c;
    float3 _81 = floor((_69.xyz * _12.u_color_steps) + float3(0.5)) / float3(_12.u_color_steps);
    c.x = _81.x;
    c.y = _81.y;
    c.z = _81.z;
    out.frag = float4(mix(orig.xyz, c.xyz, float3(_12.u_strength)), orig.w);
    return out;
}

