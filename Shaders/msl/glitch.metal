#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_glitch_chroma;
    float u_glitch_jitter;
    float u_glitch_corruption;
    float u_glitch_corruption_bleed;
    float u_time;
    float u_tex_h;
    float u_tex_w;
};

struct fx_glitch_out
{
    float4 frag [[color(0)]];
};

struct fx_glitch_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float& n)
{
    return fract(sin(n) * 43758.546875);
}

static inline __attribute__((always_inline))
float hash2(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_glitch_out fx_glitch(fx_glitch_in in [[stage_in]], constant Params& _38 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_glitch_out out = {};
    float chroma = _38.u_glitch_chroma / _38.u_tex_w;
    float y_id = floor(in.v_uv.y * _38.u_tex_h);
    float param = y_id + (floor(_38.u_time * 12.0) * 31.700000762939453125);
    float rnd = hash(param);
    float jshift = 0.0;
    bool _81 = _38.u_glitch_jitter > 0.00999999977648258209228515625;
    bool _92;
    if (_81)
    {
        _92 = rnd > (1.0 - (_38.u_glitch_jitter * 0.4000000059604644775390625));
    }
    else
    {
        _92 = _81;
    }
    if (_92)
    {
        float param_1 = y_id + (floor(_38.u_time * 8.0) * 57.299999237060546875);
        float rnd2 = hash(param_1);
        jshift = ((rnd2 - 0.5) * _38.u_glitch_jitter) * 0.119999997317790985107421875;
    }
    float r = u_tex.sample(u_texSmplr, fast::clamp(float2((in.v_uv.x + jshift) + chroma, in.v_uv.y), float2(0.0), float2(1.0))).x;
    float g = u_tex.sample(u_texSmplr, fast::clamp(float2(in.v_uv.x + jshift, in.v_uv.y), float2(0.0), float2(1.0))).y;
    float b = u_tex.sample(u_texSmplr, fast::clamp(float2((in.v_uv.x + jshift) - chroma, in.v_uv.y), float2(0.0), float2(1.0))).z;
    float a = u_tex.sample(u_texSmplr, fast::clamp(float2(in.v_uv.x + jshift, in.v_uv.y), float2(0.0), float2(1.0))).w;
    out.frag = float4(r, g, b, a);
    if (_38.u_glitch_corruption > 0.00999999977648258209228515625)
    {
        float bs = 16.0;
        float2 px = float2(in.v_uv.x * _38.u_tex_w, in.v_uv.y * _38.u_tex_h);
        float2 blk = floor(px / float2(bs));
        float tq = floor(_38.u_time * 7.0);
        float2 param_2 = blk + float2(tq * 1.7000000476837158203125);
        float br = hash2(param_2);
        if (br < (_38.u_glitch_corruption * 0.60000002384185791015625))
        {
            float2 param_3 = blk.yx + float2(tq * 3.099999904632568359375);
            float sh = ((hash2(param_3) - 0.5) * 0.300000011920928955078125) * _38.u_glitch_corruption;
            float4 src = u_tex.sample(u_texSmplr, fast::clamp(float2(in.v_uv.x + sh, in.v_uv.y), float2(0.0), float2(1.0)));
            float2 param_4 = floor(px / float2(3.0)) + float2(tq);
            float n = hash2(param_4);
            float4 noisy = float4(src.xyz * (0.3499999940395355224609375 + (1.0 * n)), src.w);
            out.frag = mix(noisy, float4(0.0), float4(_38.u_glitch_corruption_bleed));
        }
    }
    return out;
}

