#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_radius;
    float u_tone;
};

struct fx_skin_smooth_out
{
    float4 frag [[color(0)]];
};

struct fx_skin_smooth_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float skin_mask(thread const float3& c, constant Params& _65)
{
    float cb = ((0.5 - (0.16873599588871002197265625 * c.x)) - (0.3312639892101287841796875 * c.y)) + (0.5 * c.z);
    float cr = ((0.5 + (0.5 * c.x)) - (0.418687999248504638671875 * c.y)) - (0.081312000751495361328125 * c.z);
    float w = 0.0199999995529651641845703125 + (0.0599999986588954925537109375 * _65.u_tone);
    float mb = smoothstep(0.301999986171722412109375 - w, 0.301999986171722412109375 + w, cb) * (1.0 - smoothstep(0.4979999959468841552734375 - w, 0.4979999959468841552734375 + w, cb));
    float mr = smoothstep(0.522000014781951904296875 - w, 0.522000014781951904296875 + w, cr) * (1.0 - smoothstep(0.677999973297119140625 - w, 0.677999973297119140625 + w, cr));
    return mb * mr;
}

static inline __attribute__((always_inline))
float luma(thread const float3& c)
{
    return dot(c, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
}

fragment fx_skin_smooth_out fx_skin_smooth(fx_skin_smooth_in in [[stage_in]], constant Params& _65 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_skin_smooth_out out = {};
    float2 px = float2(1.0 / _65.u_tex_w, 1.0 / _65.u_tex_h);
    float4 center = u_tex.sample(u_texSmplr, in.v_uv);
    float3 param = center.xyz;
    float mask = skin_mask(param, _65);
    if (mask < 0.00999999977648258209228515625)
    {
        out.frag = center;
        return out;
    }
    float3 param_1 = center.xyz;
    float lc = luma(param_1);
    float3 acc = center.xyz;
    float wsum = 1.0;
    float r = fast::max(1.0, _65.u_radius);
    for (float dy = -2.0; dy <= 2.0; dy += 1.0)
    {
        for (float dx = -2.0; dx <= 2.0; dx += 1.0)
        {
            if ((dx == 0.0) && (dy == 0.0))
            {
                continue;
            }
            float2 off = (float2(dx, dy) * (r * 0.5)) * px;
            float3 s = u_tex.sample(u_texSmplr, (in.v_uv + off)).xyz;
            float3 param_2 = s;
            float dl = abs(luma(param_2) - lc);
            float wr = exp(((-dl) * dl) * 60.0);
            float ws = exp((-((dx * dx) + (dy * dy))) * 0.119999997317790985107421875);
            float w2 = wr * ws;
            acc += (s * w2);
            wsum += w2;
        }
    }
    float3 smoothed = acc / float3(wsum);
    out.frag = float4(mix(center.xyz, smoothed, float3(mask)), center.w);
    return out;
}

