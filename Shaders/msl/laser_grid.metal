#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_grid_size;
    float u_hue;
    float u_intensity;
};

struct fx_laser_grid_out
{
    float4 frag [[color(0)]];
};

struct fx_laser_grid_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_laser_grid_out fx_laser_grid(fx_laser_grid_in in [[stage_in]], constant Params& _25 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_laser_grid_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float2 uv_px = in.v_uv * float2(_25.u_tex_w, _25.u_tex_h);
    float2 grid = abs(fract(uv_px / float2(_25.u_grid_size)) - float2(0.5)) * 2.0;
    float line = 1.0 - fast::min(grid.x, grid.y);
    float laser = smoothstep(0.85000002384185791015625, 1.0, line);
    float glow = smoothstep(0.60000002384185791015625, 0.85000002384185791015625, line) * 0.300000011920928955078125;
    float4 K = float4(1.0, 0.666666686534881591796875, 0.3333333432674407958984375, 3.0);
    float3 p = abs((fract(float3(_25.u_hue) + K.xyz) * 6.0) - K.www);
    float3 lcolor = fast::clamp(p - K.xxx, float3(0.0), float3(1.0));
    float depth = 1.0 - (length(in.v_uv - float2(0.5)) * 0.800000011920928955078125);
    float3 result = (col.xyz * (1.0 - (laser * 0.699999988079071044921875))) + (((lcolor * (laser + glow)) * _25.u_intensity) * depth);
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), col.w);
    return out;
}

