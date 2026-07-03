#pragma clang diagnostic ignored "-Wmissing-prototypes"
#pragma clang diagnostic ignored "-Wmissing-braces"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

template<typename T, size_t Num>
struct spvUnsafeArray
{
    T elements[Num ? Num : 1];
    
    thread T& operator [] (size_t pos) thread
    {
        return elements[pos];
    }
    constexpr const thread T& operator [] (size_t pos) const thread
    {
        return elements[pos];
    }
    
    device T& operator [] (size_t pos) device
    {
        return elements[pos];
    }
    constexpr const device T& operator [] (size_t pos) const device
    {
        return elements[pos];
    }
    
    constexpr const constant T& operator [] (size_t pos) const constant
    {
        return elements[pos];
    }
    
    threadgroup T& operator [] (size_t pos) threadgroup
    {
        return elements[pos];
    }
    constexpr const threadgroup T& operator [] (size_t pos) const threadgroup
    {
        return elements[pos];
    }
};

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
    float u_levels;
    float u_dither;
};

struct fx_bit_crush_out
{
    float4 frag [[color(0)]];
};

struct fx_bit_crush_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_bit_crush_out fx_bit_crush(fx_bit_crush_in in [[stage_in]], constant Params& _83 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_bit_crush_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    spvUnsafeArray<float, 16> bayer;
    bayer[0] = 0.0;
    bayer[1] = 0.5;
    bayer[2] = 0.125;
    bayer[3] = 0.625;
    bayer[4] = 0.75;
    bayer[5] = 0.25;
    bayer[6] = 0.875;
    bayer[7] = 0.375;
    bayer[8] = 0.1875;
    bayer[9] = 0.6875;
    bayer[10] = 0.0625;
    bayer[11] = 0.5625;
    bayer[12] = 0.9375;
    bayer[13] = 0.4375;
    bayer[14] = 0.8125;
    bayer[15] = 0.3125;
    int bx = int(mod(in.v_uv.x * _83.u_tex_w, 4.0));
    int by = int(mod(in.v_uv.y * _83.u_tex_h, 4.0));
    float threshold = bayer[(by * 4) + bx] - 0.5;
    float step_size = 1.0 / fast::max(_83.u_levels - 1.0, 1.0);
    float3 dithered = col.xyz + float3((threshold * step_size) * _83.u_dither);
    float3 crushed = floor((dithered / float3(step_size)) + float3(0.5)) * step_size;
    out.frag = float4(fast::clamp(crushed, float3(0.0), float3(1.0)), col.w);
    return out;
}

