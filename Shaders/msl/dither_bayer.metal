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
    float u_scale;
    float u_color;
};

struct fx_dither_bayer_out
{
    float4 frag [[color(0)]];
};

struct fx_dither_bayer_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_dither_bayer_out fx_dither_bayer(fx_dither_bayer_in in [[stage_in]], constant Params& _236 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_dither_bayer_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    spvUnsafeArray<float, 64> bayer8;
    bayer8[0] = 0.0;
    bayer8[1] = 32.0;
    bayer8[2] = 8.0;
    bayer8[3] = 40.0;
    bayer8[4] = 2.0;
    bayer8[5] = 34.0;
    bayer8[6] = 10.0;
    bayer8[7] = 42.0;
    bayer8[8] = 48.0;
    bayer8[9] = 16.0;
    bayer8[10] = 56.0;
    bayer8[11] = 24.0;
    bayer8[12] = 50.0;
    bayer8[13] = 18.0;
    bayer8[14] = 58.0;
    bayer8[15] = 26.0;
    bayer8[16] = 12.0;
    bayer8[17] = 44.0;
    bayer8[18] = 4.0;
    bayer8[19] = 36.0;
    bayer8[20] = 14.0;
    bayer8[21] = 46.0;
    bayer8[22] = 6.0;
    bayer8[23] = 38.0;
    bayer8[24] = 60.0;
    bayer8[25] = 28.0;
    bayer8[26] = 52.0;
    bayer8[27] = 20.0;
    bayer8[28] = 62.0;
    bayer8[29] = 30.0;
    bayer8[30] = 54.0;
    bayer8[31] = 22.0;
    bayer8[32] = 3.0;
    bayer8[33] = 35.0;
    bayer8[34] = 11.0;
    bayer8[35] = 43.0;
    bayer8[36] = 1.0;
    bayer8[37] = 33.0;
    bayer8[38] = 9.0;
    bayer8[39] = 41.0;
    bayer8[40] = 51.0;
    bayer8[41] = 19.0;
    bayer8[42] = 59.0;
    bayer8[43] = 27.0;
    bayer8[44] = 49.0;
    bayer8[45] = 17.0;
    bayer8[46] = 57.0;
    bayer8[47] = 25.0;
    bayer8[48] = 15.0;
    bayer8[49] = 47.0;
    bayer8[50] = 7.0;
    bayer8[51] = 39.0;
    bayer8[52] = 13.0;
    bayer8[53] = 45.0;
    bayer8[54] = 5.0;
    bayer8[55] = 37.0;
    bayer8[56] = 63.0;
    bayer8[57] = 31.0;
    bayer8[58] = 55.0;
    bayer8[59] = 23.0;
    bayer8[60] = 61.0;
    bayer8[61] = 29.0;
    bayer8[62] = 53.0;
    bayer8[63] = 21.0;
    int px = int(mod((in.v_uv.x * _236.u_tex_w) / _236.u_scale, 8.0));
    int py = int(mod((in.v_uv.y * _236.u_tex_h) / _236.u_scale, 8.0));
    float threshold = (bayer8[(py * 8) + px] / 64.0) - 0.5;
    float step_sz = 1.0 / fast::max(_236.u_levels - 1.0, 1.0);
    float dith_lum = lum + (threshold * step_sz);
    float quant = floor((dith_lum / step_sz) + 0.5) * step_sz;
    float3 result = mix(float3(quant), (col.xyz * quant) / float3(fast::max(lum, 0.001000000047497451305389404296875)), float3(_236.u_color));
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), col.w);
    return out;
}

