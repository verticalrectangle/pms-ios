#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_channel_mix;
    float u_glow;
    float u_contrast;
};

struct fx_infrared_film_out
{
    float4 frag [[color(0)]];
};

struct fx_infrared_film_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_infrared_film_out fx_infrared_film(fx_infrared_film_in in [[stage_in]], constant Params& _54 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_infrared_film_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float ir = ((col.x * 0.20000000298023223876953125) + (col.y * 0.699999988079071044921875)) + (col.z * 0.100000001490116119384765625);
    float vis = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float ir_val = mix(vis, ir, _54.u_channel_mix);
    ir_val = fast::clamp(((ir_val - 0.5) * _54.u_contrast) + 0.5, 0.0, 1.0);
    float wood = smoothstep(0.4000000059604644775390625, 0.800000011920928955078125, col.y) * (1.0 - (col.x * 0.5));
    ir_val = mix(ir_val, 1.0, (wood * _54.u_channel_mix) * 0.5);
    float2 px = float2(1.0 / _54.u_tex_w, 1.0 / _54.u_tex_h);
    float glow_acc = 0.0;
    for (int i = 1; i <= 4; i++)
    {
        float r = float(i) * 2.5;
        glow_acc += u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + (float2(r, 0.0) * px), float2(0.0), float2(1.0))).y;
        glow_acc += u_tex.sample(u_texSmplr, fast::clamp(in.v_uv - (float2(r, 0.0) * px), float2(0.0), float2(1.0))).y;
        glow_acc += u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + (float2(0.0, r) * px), float2(0.0), float2(1.0))).y;
        glow_acc += u_tex.sample(u_texSmplr, fast::clamp(in.v_uv - (float2(0.0, r) * px), float2(0.0), float2(1.0))).y;
    }
    glow_acc /= 16.0;
    ir_val = fast::min(ir_val + ((glow_acc * _54.u_glow) * 0.300000011920928955078125), 1.0);
    float3 result = float3(ir_val * 1.019999980926513671875, ir_val * 0.9900000095367431640625, ir_val * 0.920000016689300537109375);
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), col.w);
    return out;
}

