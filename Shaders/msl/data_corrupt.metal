#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_density;
    float u_block_size;
    float u_intensity;
    float u_time;
};

struct fx_data_corrupt_out
{
    float4 frag [[color(0)]];
};

struct fx_data_corrupt_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_data_corrupt_out fx_data_corrupt(fx_data_corrupt_in in [[stage_in]], constant Params& _40 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_data_corrupt_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float2 block_id = floor((in.v_uv * float2(_40.u_tex_w, _40.u_tex_h)) / float2(_40.u_block_size));
    float frame = floor(_40.u_time * 12.0);
    float2 param = block_id + float2(frame * 7.30000019073486328125, frame * 13.1000003814697265625);
    float rnd = hash(param);
    float2 param_1 = block_id + float2(frame * 3.7000000476837158203125, frame * 17.8999996185302734375);
    float rnd2 = hash(param_1);
    float2 param_2 = block_id + float2(frame * 11.1000003814697265625, frame * 5.30000019073486328125);
    float rnd3 = hash(param_2);
    if (rnd < _40.u_density)
    {
        float2 corrupt_block = block_id + float2((rnd2 - 0.5) * 20.0, 0.0);
        float2 corrupt_uv = fast::clamp(((corrupt_block * _40.u_block_size) + (fract((in.v_uv * float2(_40.u_tex_w, _40.u_tex_h)) / float2(_40.u_block_size)) * _40.u_block_size)) / float2(_40.u_tex_w, _40.u_tex_h), float2(0.0), float2(1.0));
        float3 corrupt_col = u_tex.sample(u_texSmplr, corrupt_uv).xyz;
        corrupt_col = float3(corrupt_col.z, corrupt_col.x, corrupt_col.y) * (0.800000011920928955078125 + (rnd3 * 0.4000000059604644775390625));
        out.frag = float4(mix(col.xyz, corrupt_col, float3(_40.u_intensity)), col.w);
    }
    else
    {
        out.frag = col;
    }
    return out;
}

