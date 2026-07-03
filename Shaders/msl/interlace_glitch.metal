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
    float u_strength;
    float u_intensity;
    float u_speed;
    float u_time;
};

struct fx_interlace_glitch_out
{
    float4 frag [[color(0)]];
};

struct fx_interlace_glitch_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float& n)
{
    return fract(sin(n) * 43758.546875);
}

fragment fx_interlace_glitch_out fx_interlace_glitch(fx_interlace_glitch_in in [[stage_in]], constant Params& _30 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_interlace_glitch_out out = {};
    float line = floor(in.v_uv.y * _30.u_tex_h);
    float field = mod(line, 2.0);
    float t = floor((_30.u_time * _30.u_speed) * 8.0);
    float param = (line * 0.100000001490116119384765625) + t;
    float glitch = hash(param);
    float shift = (((field * 2.0) - 1.0) * _30.u_strength) * step(1.0 - (_30.u_intensity * 0.300000011920928955078125), glitch);
    float2 uv = fast::clamp(in.v_uv + float2(shift, 0.0), float2(0.0), float2(1.0));
    float4 col = u_tex.sample(u_texSmplr, uv);
    float bright = 1.0 + (((field - 0.5) * 0.0599999986588954925537109375) * _30.u_intensity);
    out.frag = float4(fast::clamp(col.xyz * bright, float3(0.0), float3(1.0)), col.w);
    return out;
}

