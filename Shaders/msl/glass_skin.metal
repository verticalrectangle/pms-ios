#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_radius;
    float u_gloss;
};

struct fx_glass_skin_out
{
    float4 frag [[color(0)]];
};

struct fx_glass_skin_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float skin_mask(thread const float3& c)
{
    float cb = ((0.5 - (0.16873599588871002197265625 * c.x)) - (0.3312639892101287841796875 * c.y)) + (0.5 * c.z);
    float cr = ((0.5 + (0.5 * c.x)) - (0.418687999248504638671875 * c.y)) - (0.081312000751495361328125 * c.z);
    float mb = smoothstep(0.2619999945163726806640625, 0.34200000762939453125, cb) * (1.0 - smoothstep(0.458000004291534423828125, 0.53799998760223388671875, cb));
    float mr = smoothstep(0.48199999332427978515625, 0.561999976634979248046875, cr) * (1.0 - smoothstep(0.638000011444091796875, 0.717999994754791259765625, cr));
    return mb * mr;
}

static inline __attribute__((always_inline))
float luma(thread const float3& c)
{
    return dot(c, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
}

fragment fx_glass_skin_out fx_glass_skin(fx_glass_skin_in in [[stage_in]], constant Params& _93 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_glass_skin_out out = {};
    float2 px = float2(1.0 / _93.u_tex_w, 1.0 / _93.u_tex_h);
    float4 src = u_tex.sample(u_texSmplr, in.v_uv);
    float3 param = src.xyz;
    float mask = skin_mask(param);
    float3 c = src.xyz;
    if (mask > 0.00999999977648258209228515625)
    {
        float3 param_1 = c;
        float lc = luma(param_1);
        float3 acc = c;
        float wsum = 1.0;
        float r = fast::max(1.0, _93.u_radius);
        for (float dy = -2.0; dy <= 2.0; dy += 1.0)
        {
            for (float dx = -2.0; dx <= 2.0; dx += 1.0)
            {
                if ((dx == 0.0) && (dy == 0.0))
                {
                    continue;
                }
                float3 s = u_tex.sample(u_texSmplr, (in.v_uv + ((float2(dx, dy) * (r * 0.5)) * px))).xyz;
                float3 param_2 = s;
                float dl = abs(luma(param_2) - lc);
                float w2 = exp(((-dl) * dl) * 60.0) * exp((-((dx * dx) + (dy * dy))) * 0.119999997317790985107421875);
                acc += (s * w2);
                wsum += w2;
            }
        }
        c = mix(c, acc / float3(wsum), float3(mask));
        float3 param_3 = c;
        float lum2 = luma(param_3);
        float spec = smoothstep(0.62000000476837158203125, 0.949999988079071044921875, lum2);
        c += float3((_93.u_gloss * mask) * ((spec * 0.2199999988079071044921875) + 0.0350000001490116119384765625));
    }
    out.frag = float4(fast::clamp(c, float3(0.0), float3(1.0)), src.w);
    return out;
}

