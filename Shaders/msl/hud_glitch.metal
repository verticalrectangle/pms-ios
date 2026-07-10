#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_time;
    float u_hud;
    float u_dropout;
    float u_tint;
};

struct fx_hud_glitch_out
{
    float4 frag [[color(0)]];
};

struct fx_hud_glitch_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash2(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_hud_glitch_out fx_hud_glitch(fx_hud_glitch_in in [[stage_in]], constant Params& _32 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_hud_glitch_out out = {};
    float2 uv = in.v_uv;
    float tq = floor(_32.u_time * 6.0);
    float2 blk = floor((uv * float2(_32.u_tex_w, _32.u_tex_h)) / float2(24.0));
    float2 param = blk + float2(tq * 2.2999999523162841796875);
    float br = hash2(param);
    if (br < (_32.u_dropout * 0.3499999940395355224609375))
    {
        float2 param_1 = blk.yx + float2(tq);
        uv.x += ((hash2(param_1) - 0.5) * 0.07999999821186065673828125);
        uv = fast::clamp(uv, float2(0.0), float2(1.0));
    }
    float4 c = u_tex.sample(u_texSmplr, uv);
    float3 rgb = c.xyz;
    if (br < (_32.u_dropout * 0.3499999940395355224609375))
    {
        rgb = (floor(rgb * 5.0) / float3(5.0)) * float3(0.699999988079071044921875, 1.10000002384185791015625, 1.2000000476837158203125);
    }
    float lum = dot(rgb, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    rgb = mix(rgb, float3(lum) * float3(0.550000011920928955078125, 1.0, 1.10000002384185791015625), float3(_32.u_tint * 0.60000002384185791015625));
    float bord = step(fast::min(fast::min(in.v_uv.x, 1.0 - in.v_uv.x), fast::min(in.v_uv.y, 1.0 - in.v_uv.y)), 0.0040000001899898052215576171875);
    float thirds = step(abs(in.v_uv.x - 0.33329999446868896484375), 0.0007999999797903001308441162109375) + step(abs(in.v_uv.x - 0.66670000553131103515625), 0.0007999999797903001308441162109375);
    float sweep = smoothstep(0.008000000379979610443115234375, 0.0, abs(in.v_uv.y - fract(_32.u_time * 0.10999999940395355224609375)));
    float3 hud_col = float3(0.300000011920928955078125, 1.0, 0.949999988079071044921875);
    rgb += ((hud_col * (((bord * 0.89999997615814208984375) + (thirds * 0.3499999940395355224609375)) + (sweep * 0.25))) * _32.u_hud);
    out.frag = float4(fast::clamp(rgb, float3(0.0), float3(1.0)), c.w);
    return out;
}

