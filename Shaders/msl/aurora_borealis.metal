#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_intensity;
    float u_speed;
    float u_color_shift;
    float u_time;
};

struct fx_aurora_borealis_out
{
    float4 frag [[color(0)]];
};

struct fx_aurora_borealis_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

static inline __attribute__((always_inline))
float _noise2(thread const float2& p)
{
    float2 i = floor(p);
    float2 f = fract(p);
    f = (f * f) * (float2(3.0) - (f * 2.0));
    float2 param = i;
    float2 param_1 = i + float2(1.0, 0.0);
    float2 param_2 = i + float2(0.0, 1.0);
    float2 param_3 = i + float2(1.0);
    return mix(mix(hash(param), hash(param_1), f.x), mix(hash(param_2), hash(param_3), f.x), f.y);
}

static inline __attribute__((always_inline))
float3 hue2rgb(thread const float& h)
{
    float4 K = float4(1.0, 0.666666686534881591796875, 0.3333333432674407958984375, 3.0);
    float3 p = abs((fract(float3(h) + K.xyz) * 6.0) - K.www);
    return fast::clamp(p - K.xxx, float3(0.0), float3(1.0));
}

fragment fx_aurora_borealis_out fx_aurora_borealis(fx_aurora_borealis_in in [[stage_in]], constant Params& _125 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_aurora_borealis_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float t = _125.u_time * _125.u_speed;
    float2 param = float2((in.v_uv.x * 3.0) + (t * 0.300000011920928955078125), t * 0.100000001490116119384765625);
    float n1 = _noise2(param);
    float2 param_1 = float2((in.v_uv.x * 5.0) - (t * 0.20000000298023223876953125), (t * 0.1500000059604644775390625) + 10.0);
    float n2 = _noise2(param_1);
    float curtain = smoothstep(0.699999988079071044921875, 0.100000001490116119384765625, in.v_uv.y) * smoothstep(0.0, 0.300000011920928955078125, 1.0 - in.v_uv.y);
    float wave = (sin(((in.v_uv.x * 8.0) + (t * 0.5)) + (n1 * 4.0)) * 0.5) + 0.5;
    float aurora_mask = (wave * curtain) * ((n1 * 0.699999988079071044921875) + 0.300000011920928955078125);
    float hue = fract(((_125.u_color_shift + (in.v_uv.x * 0.4000000059604644775390625)) + (n2 * 0.300000011920928955078125)) + (t * 0.0500000007450580596923828125));
    float param_2 = hue;
    float3 aurora_col = hue2rgb(param_2) * float3(0.5, 1.0, 0.800000011920928955078125);
    float3 screen = float3(1.0) - ((float3(1.0) - col.xyz) * (float3(1.0) - ((aurora_col * aurora_mask) * _125.u_intensity)));
    out.frag = float4(fast::clamp(screen, float3(0.0), float3(1.0)), col.w);
    return out;
}

