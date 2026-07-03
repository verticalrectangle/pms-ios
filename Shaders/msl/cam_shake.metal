#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_intensity;
    float u_speed;
    float u_time;
};

struct fx_cam_shake_out
{
    float4 frag [[color(0)]];
};

struct fx_cam_shake_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float h1(thread const float& x)
{
    return fract(sin(x * 12.98980045318603515625) * 43758.546875);
}

static inline __attribute__((always_inline))
float vnoise(thread const float& x)
{
    float i = floor(x);
    float f = fract(x);
    float u = (f * f) * (3.0 - (2.0 * f));
    float param = i;
    float param_1 = i + 1.0;
    return (mix(h1(param), h1(param_1), u) * 2.0) - 1.0;
}

fragment fx_cam_shake_out fx_cam_shake(fx_cam_shake_in in [[stage_in]], constant Params& _57 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_cam_shake_out out = {};
    float t = _57.u_time * (1.5 + (_57.u_speed * 4.0));
    float param = t;
    float param_1 = (t * 2.2999999523162841796875) + 11.0;
    float dx = (vnoise(param) * 0.60000002384185791015625) + (vnoise(param_1) * 0.4000000059604644775390625);
    float param_2 = (t * 1.10000002384185791015625) + 5.0;
    float param_3 = (t * 2.7000000476837158203125) + 23.0;
    float dy = (vnoise(param_2) * 0.60000002384185791015625) + (vnoise(param_3) * 0.4000000059604644775390625);
    float param_4 = (t * 0.699999988079071044921875) + 31.0;
    float dr = vnoise(param_4);
    float amp = _57.u_intensity * 0.0500000007450580596923828125;
    float zoom = 1.0 + (_57.u_intensity * 0.04500000178813934326171875);
    float ang = (dr * _57.u_intensity) * 0.0500000007450580596923828125;
    float2 uv = in.v_uv - float2(0.5);
    float c = cos(ang);
    float s = sin(ang);
    uv = float2x2(float2(c, -s), float2(s, c)) * uv;
    uv /= float2(zoom);
    uv += (float2(dx, dy) * amp);
    uv += float2(0.5);
    out.frag = u_tex.sample(u_texSmplr, fast::clamp(uv, float2(0.0), float2(1.0)));
    return out;
}

