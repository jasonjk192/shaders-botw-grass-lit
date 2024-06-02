#ifndef GRASS_DEPTH_HLSL
#define GRASS_DEPTH_HLSL

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "./LitInput.hlsl"
#include "./Common.hlsl"

struct Attributes
{
    float4 positionOS   : POSITION;
    float3 normalOS     : NORMAL;
    float4 tangentOS    : TANGENT;
    float2 texcoord     : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float2 uv           : TEXCOORD0;
    float4 positionCS   : SV_POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};
Varyings vert(Attributes input)
{
    Varyings output = (Varyings) 0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

    output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
    output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
    return output;
}

Varyings TransformGeomToClip(float3 pos, float3 offset, float3x3 transformationMatrix, float2 uv, Attributes input)
{
    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
    VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
    Varyings o = (Varyings) 0;

    o.uv = uv;
    o.positionCS = TransformWorldToHClip(vertexInput.positionWS);
    
    return o;
}

[maxvertexcount(BLADE_SEGMENTS * 2 + 1)]
void geom(point Attributes input[1], inout TriangleStream<Varyings> triStream)
{
    float grassVisibility = SAMPLE_TEXTURE2D_LOD(_GrassMap, sampler_GrassMap, input[0].texcoord, 0).r;

    if (grassVisibility >= _GrassThreshold)
    {
        float3 pos = input[0].positionOS.xyz;

        float3 normal = input[0].normalOS;
        float4 tangent = input[0].tangentOS;
        float3 bitangent = cross(normal, tangent.xyz) * tangent.w;

        float3x3 tangentToLocal = float3x3
					(
						tangent.x, bitangent.x, normal.x,
						tangent.y, bitangent.y, normal.y,
						tangent.z, bitangent.z, normal.z
					);

        float3x3 randRotMatrix = angleAxis3x3(rand(pos) * UNITY_TWO_PI, float3(0, 0, 1.0f));

        float3x3 randBendMatrix = angleAxis3x3(rand(pos.zzx) * _BendDelta * UNITY_PI * 0.5f, float3(-1.0f, 0, 0));

        float2 windUV = pos.xz * _WindMap_ST.xy + _WindMap_ST.zw + normalize(_WindVelocity.xzy).xy * _WindFrequency * _Time.y;
        float2 tex2dwindsample = SAMPLE_TEXTURE2D_LOD(_WindMap, sampler_WindMap, windUV, 0).xy;
        float2 windSample = (tex2dwindsample.xy * 2 - 1).xy * length(_WindVelocity);

        float3 windAxis = normalize(float3(windSample.x, windSample.y, 0));
        float3x3 windMatrix = angleAxis3x3(UNITY_PI * windSample.x, windAxis);

        float3x3 baseTransformationMatrix = mul(tangentToLocal, randRotMatrix);
        float3x3 tipTransformationMatrix = mul(mul(mul(tangentToLocal, windMatrix), randBendMatrix), randRotMatrix);

        float falloff = smoothstep(_GrassThreshold, _GrassThreshold + _GrassFalloff, grassVisibility);

        float width = lerp(_BladeWidthMin, _BladeWidthMax, rand(pos.xzy) * falloff);
        float height = lerp(_BladeHeightMin, _BladeHeightMax, rand(pos.zyx) * falloff);
        float forward = rand(pos.yyz) * _BladeBendDistance;

        for (int i = 0; i < BLADE_SEGMENTS; ++i)
        {
            float t = i / (float) BLADE_SEGMENTS;
            float3 offset = float3(width * (1 - t), pow(t, _BladeBendCurve) * forward, height * t);

            float3x3 transformationMatrix = (i == 0) ? baseTransformationMatrix : tipTransformationMatrix;

            triStream.Append(TransformGeomToClip(pos, float3(offset.x, offset.y, offset.z), transformationMatrix, float2(0, t), input[0]));
            triStream.Append(TransformGeomToClip(pos, float3(-offset.x, offset.y, offset.z), transformationMatrix, float2(1, t), input[0]));
        }

        triStream.Append(TransformGeomToClip(pos, float3(0, forward, height), tipTransformationMatrix, float2(0.5, 1), input[0]));

        triStream.RestartStrip();
    }
}

half4 frag(Varyings input) : SV_TARGET
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    Alpha(SampleAlbedoAlpha(input.uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap)).a, _BaseColor, _Cutoff);
    return 0;
}

#endif