#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_intensity;
    float u_speed;
    float u_height;
    float u_time;
};

struct fx_fire_edge_out
{
    float4 frag [[color(0)]];
};

struct fx_fire_edge_in
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
float fbm3(thread const float2& p)
{
    float2 param = p;
    float2 param_1 = p * 2.099999904632568359375;
    float2 param_2 = p * 4.30000019073486328125;
    return ((_noise2(param) * 0.5) + (_noise2(param_1) * 0.25)) + (_noise2(param_2) * 0.125);
}

fragment fx_fire_edge_out fx_fire_edge(fx_fire_edge_in in [[stage_in]], constant Params& _119 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_fire_edge_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float t = _119.u_time * _119.u_speed;
    float dist = fast::min(fast::min(in.v_uv.x, 1.0 - in.v_uv.x), fast::min(in.v_uv.y, 1.0 - in.v_uv.y));
    float2 param = float2((in.v_uv.x * 5.0) + (t * 0.300000011920928955078125), (in.v_uv.y * 5.0) - (t * 0.60000002384185791015625));
    float n = fbm3(param);
    float edge_fire = 1.0 - fast::clamp(dist / (_119.u_height * (0.5 + (n * 0.5))), 0.0, 1.0);
    float flame = (edge_fire * edge_fire) * ((n * 0.5) + 0.5);
    float f = fast::clamp(flame * _119.u_intensity, 0.0, 1.0);
    float3 fire_col;
    if (f < 0.25)
    {
        fire_col = mix(float3(0.0), float3(0.800000011920928955078125, 0.100000001490116119384765625, 0.0), float3(f * 4.0));
    }
    else
    {
        if (f < 0.5)
        {
            fire_col = mix(float3(0.800000011920928955078125, 0.100000001490116119384765625, 0.0), float3(1.0, 0.5, 0.0500000007450580596923828125), float3((f - 0.25) * 4.0));
        }
        else
        {
            if (f < 0.75)
            {
                fire_col = mix(float3(1.0, 0.5, 0.0500000007450580596923828125), float3(1.0, 0.89999997615814208984375, 0.300000011920928955078125), float3((f - 0.5) * 4.0));
            }
            else
            {
                fire_col = mix(float3(1.0, 0.89999997615814208984375, 0.300000011920928955078125), float3(1.0, 1.0, 0.89999997615814208984375), float3((f - 0.75) * 4.0));
            }
        }
    }
    float alpha = fast::clamp((flame * _119.u_intensity) * 1.5, 0.0, 1.0);
    float3 result = mix(col.xyz, fast::max(col.xyz, fire_col), float3(alpha));
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), col.w);
    return out;
}

