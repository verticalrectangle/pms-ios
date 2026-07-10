#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_blush;
    float u_smooth;
    float u_tint;
};

struct fx_blush_doll_out
{
    float4 frag [[color(0)]];
};

struct fx_blush_doll_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_blush_doll_out fx_blush_doll(fx_blush_doll_in in [[stage_in]], constant Params& _13 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_blush_doll_out out = {};
    float2 px = float2(1.0 / _13.u_tex_w, 1.0 / _13.u_tex_h);
    float4 c = u_tex.sample(u_texSmplr, in.v_uv);
    float3 blur = c.xyz;
    for (int i = 0; i < 8; i++)
    {
        float a = float(i) * 0.785398006439208984375;
        blur += u_tex.sample(u_texSmplr, (in.v_uv + ((float2(cos(a), sin(a)) * 3.0) * px))).xyz;
    }
    blur /= float3(9.0);
    float lum = dot(c.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float skin = (smoothstep(0.180000007152557373046875, 0.4000000059604644775390625, lum) * (1.0 - smoothstep(0.800000011920928955078125, 0.949999988079071044921875, lum))) * smoothstep(0.0, 0.07999999821186065673828125, c.x - c.z);
    float3 rgb = mix(c.xyz, blur, float3(_13.u_smooth * skin));
    float band = 1.0 - smoothstep(0.180000007152557373046875, 0.5, abs(in.v_uv.y - 0.449999988079071044921875));
    float3 blush_col = mix(float3(1.0, 0.550000011920928955078125, 0.4199999868869781494140625), float3(1.0, 0.449999988079071044921875, 0.62000000476837158203125), float3(_13.u_tint));
    float bw = ((_13.u_blush * skin) * band) * 0.449999988079071044921875;
    rgb = mix(rgb, blush_col * ((0.4000000059604644775390625 + (0.60000002384185791015625 * lum)) + 0.300000011920928955078125), float3(bw));
    float neutral = 1.0 - smoothstep(0.0500000007450580596923828125, 0.1500000059604644775390625, abs(c.x - c.y) + abs(c.y - c.z));
    float bright = smoothstep(0.550000011920928955078125, 0.800000011920928955078125, lum);
    rgb += float3(((neutral * bright) * 0.119999997317790985107421875) * _13.u_blush);
    out.frag = float4(fast::clamp(rgb, float3(0.0), float3(1.0)), c.w);
    return out;
}

