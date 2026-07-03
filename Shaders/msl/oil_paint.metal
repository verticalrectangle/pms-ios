#pragma clang diagnostic ignored "-Wmissing-prototypes"
#pragma clang diagnostic ignored "-Wmissing-braces"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

template<typename T, size_t Num>
struct spvUnsafeArray
{
    T elements[Num ? Num : 1];
    
    thread T& operator [] (size_t pos) thread
    {
        return elements[pos];
    }
    constexpr const thread T& operator [] (size_t pos) const thread
    {
        return elements[pos];
    }
    
    device T& operator [] (size_t pos) device
    {
        return elements[pos];
    }
    constexpr const device T& operator [] (size_t pos) const device
    {
        return elements[pos];
    }
    
    constexpr const constant T& operator [] (size_t pos) const constant
    {
        return elements[pos];
    }
    
    threadgroup T& operator [] (size_t pos) threadgroup
    {
        return elements[pos];
    }
    constexpr const threadgroup T& operator [] (size_t pos) const threadgroup
    {
        return elements[pos];
    }
};

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_radius;
    float u_sharpness;
};

struct fx_oil_paint_out
{
    float4 frag [[color(0)]];
};

struct fx_oil_paint_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_oil_paint_out fx_oil_paint(fx_oil_paint_in in [[stage_in]], constant Params& _13 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_oil_paint_out out = {};
    float2 px = float2(1.0 / _13.u_tex_w, 1.0 / _13.u_tex_h);
    int R = int(_13.u_radius);
    spvUnsafeArray<float3, 4> mean;
    spvUnsafeArray<float, 4> var;
    for (int q = 0; q < 4; q++)
    {
        mean[q] = float3(0.0);
        var[q] = 0.0;
    }
    float cnt = 0.0;
    int _63 = -R;
    for (int dy = _63; dy <= R; dy++)
    {
        int _74 = -R;
        for (int dx = _74; dx <= R; dx++)
        {
            float2 uv = in.v_uv + (float2(float(dx), float(dy)) * px);
            float3 c = u_tex.sample(u_texSmplr, fast::clamp(uv, float2(0.0), float2(1.0))).xyz;
            if ((dx <= 0) && (dy <= 0))
            {
                mean[0] += c;
                var[0] += dot(c, c);
            }
            if ((dx >= 0) && (dy <= 0))
            {
                mean[1] += c;
                var[1] += dot(c, c);
            }
            if ((dx <= 0) && (dy >= 0))
            {
                mean[2] += c;
                var[2] += dot(c, c);
            }
            if ((dx >= 0) && (dy >= 0))
            {
                mean[3] += c;
                var[3] += dot(c, c);
            }
        }
    }
    float n = float(R + 1) * float(R + 1);
    float min_var = 1000000000.0;
    float3 result = mean[0] / float3(n);
    for (int q_1 = 0; q_1 < 4; q_1++)
    {
        mean[q_1] /= float3(n);
        var[q_1] = (var[q_1] / n) - dot(mean[q_1], mean[q_1]);
        float v = var[q_1];
        if (v < min_var)
        {
            min_var = v;
            result = mean[q_1];
        }
    }
    float3 orig = u_tex.sample(u_texSmplr, in.v_uv).xyz;
    out.frag = float4(fast::clamp(result + ((result - orig) * (_13.u_sharpness * 0.0500000007450580596923828125)), float3(0.0), float3(1.0)), 1.0);
    return out;
}

