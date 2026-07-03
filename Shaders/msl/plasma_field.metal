#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_scale;
    float u_speed;
    float u_intensity;
    float u_time;
};

struct fx_plasma_field_out
{
    float4 frag [[color(0)]];
};

struct fx_plasma_field_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float3 hue2rgb(thread const float& h)
{
    float4 K = float4(1.0, 0.666666686534881591796875, 0.3333333432674407958984375, 3.0);
    float3 p = abs((fract(float3(h) + K.xyz) * 6.0) - K.www);
    return fast::clamp(p - K.xxx, float3(0.0), float3(1.0));
}

fragment fx_plasma_field_out fx_plasma_field(fx_plasma_field_in in [[stage_in]], constant Params& _59 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_plasma_field_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float t = _59.u_time * _59.u_speed;
    float v1 = sin((in.v_uv.x * _59.u_scale) + t);
    float v2 = sin(((in.v_uv.y * _59.u_scale) * 0.89999997615814208984375) + (t * 1.10000002384185791015625));
    float v3 = sin((((in.v_uv.x + in.v_uv.y) * _59.u_scale) * 0.699999988079071044921875) + (t * 0.800000011920928955078125));
    float v4 = sin(sqrt(((((in.v_uv.x - 0.5) * (in.v_uv.x - 0.5)) * _59.u_scale) * _59.u_scale) + ((((in.v_uv.y - 0.5) * (in.v_uv.y - 0.5)) * _59.u_scale) * _59.u_scale)) + t);
    float plasma = (((v1 + v2) + v3) + v4) * 0.25;
    float hue = (plasma * 0.5) + 0.5;
    float param = hue;
    float3 plasma_col = hue2rgb(param);
    float3 screen = float3(1.0) - ((float3(1.0) - col.xyz) * (float3(1.0) - ((plasma_col * _59.u_intensity) * 0.699999988079071044921875)));
    out.frag = float4(fast::clamp(screen, float3(0.0), float3(1.0)), col.w);
    return out;
}

