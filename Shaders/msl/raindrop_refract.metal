#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_density;
    float u_size;
    float u_refract_str;
    float u_time;
};

struct fx_raindrop_refract_out
{
    float4 frag [[color(0)]];
};

struct fx_raindrop_refract_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_raindrop_refract_out fx_raindrop_refract(fx_raindrop_refract_in in [[stage_in]], constant Params& _32 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_raindrop_refract_out out = {};
    float2 uv = in.v_uv;
    float2 grid = floor(uv * _32.u_density);
    float2 cell = fract(uv * _32.u_density) - float2(0.5);
    float2 param = grid;
    float2 param_1 = grid + float2(7.30000019073486328125, 3.099999904632568359375);
    float2 drop_center = float2(hash(param), hash(param_1)) - float2(0.5);
    float2 param_2 = grid + float2(13.69999980926513671875, 5.900000095367431640625);
    float drop_phase = hash(param_2);
    float anim = fract((_32.u_time * 0.4000000059604644775390625) + drop_phase);
    float radius = ((_32.u_size * 0.5) * smoothstep(0.0, 0.20000000298023223876953125, anim)) * smoothstep(1.0, 0.699999988079071044921875, anim);
    float dist = length(cell - (drop_center * 0.300000011920928955078125));
    if (dist < radius)
    {
        float2 norm = (cell - (drop_center * 0.300000011920928955078125)) / float2(radius + 0.001000000047497451305389404296875);
        float z = sqrt(fast::max(0.0, 1.0 - dot(norm, norm)));
        float2 refr = ((norm * (1.0 - z)) * _32.u_refract_str) * 0.0599999986588954925537109375;
        uv = in.v_uv - refr;
    }
    out.frag = u_tex.sample(u_texSmplr, fast::clamp(uv, float2(0.0), float2(1.0)));
    return out;
}

