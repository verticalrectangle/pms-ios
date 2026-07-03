#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_density;
    float u_size;
    float u_sparkle;
    float u_color_var;
    float u_time;
};

struct fx_glitter_dust_out
{
    float4 frag [[color(0)]];
};

struct fx_glitter_dust_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

static inline __attribute__((always_inline))
float3 hue2rgb(thread const float& h)
{
    float4 K = float4(1.0, 0.666666686534881591796875, 0.3333333432674407958984375, 3.0);
    return fast::clamp(abs((fract(float3(h) + K.xyz) * 6.0) - K.www) - K.xxx, float3(0.0), float3(1.0));
}

fragment fx_glitter_dust_out fx_glitter_dust(fx_glitter_dust_in in [[stage_in]], constant Params& _75 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_glitter_dust_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float3 glitter = float3(0.0);
    float grid_scale = sqrt(_75.u_density);
    float cell_size = 1.0 / grid_scale;
    float spark_r = (cell_size * _75.u_size) * 0.25;
    for (int layer = 0; layer < 3; layer++)
    {
        float fl = (float(layer) * 7.13000011444091796875) + 3.7000000476837158203125;
        float2 grid = floor((in.v_uv * grid_scale) + float2(fl));
        for (int gx = -1; gx <= 1; gx++)
        {
            for (int gy = -1; gy <= 1; gy++)
            {
                float2 g = grid + float2(float(gx), float(gy));
                float2 param = g;
                float2 param_1 = g + float2(5.099999904632568359375, 9.30000019073486328125);
                float2 center = ((g - float2(fl)) + float2(hash(param), hash(param_1))) / float2(grid_scale);
                float asp = _75.u_tex_w / _75.u_tex_h;
                float2 diff = (in.v_uv - center) * float2(asp, 1.0);
                float dist = length(diff);
                float2 param_2 = (g + float2(fl)) + float2(23.1000003814697265625, 41.700000762939453125);
                float phase = hash(param_2);
                float anim = abs(sin((_75.u_time * 4.0) + (phase * 6.280000209808349609375)));
                float r = spark_r * (0.300000011920928955078125 + (0.699999988079071044921875 * anim));
                float spark = (smoothstep(r, r * 0.0500000007450580596923828125, dist) * _75.u_sparkle) * anim;
                float2 adiff = abs(diff);
                float arm_len = r * 2.5;
                float star = (smoothstep(arm_len, 0.0, (fast::min(adiff.x, adiff.y) * 2.5) + (dist * 0.5)) * anim) * 0.4000000059604644775390625;
                float2 param_3 = g + float2(fl, fl * 1.7000000476837158203125);
                float hue = hash(param_3);
                float param_4 = hue;
                float3 color = mix(float3(1.0), hue2rgb(param_4), float3(_75.u_color_var));
                glitter += (color * fast::max(spark, star));
            }
        }
    }
    float3 result = float3(1.0) - ((float3(1.0) - col.xyz) * (float3(1.0) - fast::clamp(glitter, float3(0.0), float3(1.0))));
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), col.w);
    return out;
}

