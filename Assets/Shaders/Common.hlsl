#ifndef GRASS_COMMON_HLSL
#define GRASS_COMMON_HLSL

#define UNITY_PI 3.14159265359f
#define UNITY_TWO_PI 6.28318530718f
#define UNITY_E 2.718281828459045f
#define UNITY_GOLDENRATIO 1.618033988749f

#define BLADE_SEGMENTS 4

struct TessellationFactors
{
    float edge[3] : SV_TessFactor;
    float inside : SV_InsideTessFactor;
};

// Simple noise function, sourced from http://answers.unity.com/answers/624136/view.html
// Extended discussion on this function can be found at the following link:
// https://forum.unity.com/threads/am-i-over-complicating-this-random-function.454887/#post-2949326
// Returns a number in the 0...1 range.

// Modified rand function that samples a noise texture given some 3D coords, you can choose any values for uv to sample the texture
inline float rand(float3 co)
{
    float2 uv = float2(dot(co.xyz, float3(UNITY_PI, UNITY_E, UNITY_GOLDENRATIO)), (co.x + co.y + co.z) * .3333f); //(co.xy + co.yz + co.zx) * .3333f;
    float4 noise = SAMPLE_TEXTURE2D_LOD(_RandomValueMap, sampler_RandomValueMap, uv, 0);
    return (noise.r + noise.g + noise.b + noise.a) * .25f;
    //return frac(sin(dot(co.xyz, float3(12.9898, 78.233, 53.539))) * 43758.5453);
}

// Construct a rotation matrix that rotates around the provided axis, sourced from:
// https://gist.github.com/keijiro/ee439d5e7388f3aafc5296005c8c3f33
inline float3x3 angleAxis3x3(float angle, float3 axis)
{
    float c, s;
    sincos(angle, s, c);

    float t = 1 - c;
    float x = axis.x;
    float y = axis.y;
    float z = axis.z;

    return float3x3
	(
		t * x * x + c, t * x * y - s * z, t * x * z + s * y,
		t * x * y + s * z, t * y * y + c, t * y * z - s * x,
		t * x * z - s * y, t * y * z + s * x, t * z * z + c
	);
}

#endif

// Content of structs

//struct InputData
//{
//    float3 positionWS;
//    float4 positionCS;
//    float3 normalWS;
//    half3 viewDirectionWS;
//    float4 shadowCoord;
//    half fogCoord;
//    half3 vertexLighting;
//    half3 bakedGI;
//    float2 normalizedScreenSpaceUV;
//    half4 shadowMask;
//    half3x3 tangentToWorld;
//};

//struct SurfaceData
//{
//    half3 albedo;
//    half3 specular;
//    half metallic;
//    half smoothness;
//    half3 normalTS;
//    half3 emission;
//    half occlusion;
//    half alpha;
//    half clearCoatMask;
//    half clearCoatSmoothness;
//};

//struct Attributes
//{
//    float4 positionOS : POSITION;
//    float3 normalOS : NORMAL;
//    float4 tangentOS : TANGENT;
//    float2 texcoord : TEXCOORD0;
//    float2 staticLightmapUV : TEXCOORD1;
//    float2 dynamicLightmapUV : TEXCOORD2;
//    UNITY_VERTEX_INPUT_INSTANCE_ID
//};

//struct Varyings
//{
//    float2 uv : TEXCOORD0;

//#if defined(REQUIRES_WORLD_SPACE_POS_INTERPOLATOR)
//    float3 positionWS               : TEXCOORD1;
//#endif

//    float3 normalWS : TEXCOORD2;
//#if defined(REQUIRES_WORLD_SPACE_TANGENT_INTERPOLATOR)
//    half4 tangentWS                : TEXCOORD3;    // xyz: tangent, w: sign
//#endif

//#ifdef _ADDITIONAL_LIGHTS_VERTEX
//    half4 fogFactorAndVertexLight   : TEXCOORD5; // x: fogFactor, yzw: vertex light
//#else
//    half fogFactor : TEXCOORD5;
//#endif

//#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
//    float4 shadowCoord              : TEXCOORD6;
//#endif

//#if defined(REQUIRES_TANGENT_SPACE_VIEW_DIR_INTERPOLATOR)
//    half3 viewDirTS                : TEXCOORD7;
//#endif

//    DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 8);
//#ifdef DYNAMICLIGHTMAP_ON
//    float2  dynamicLightmapUV : TEXCOORD9; // Dynamic lightmap UVs
//#endif

//float4 positionCS : SV_POSITION;
//UNITY_VERTEX_INPUT_INSTANCE_ID
//    UNITY_VERTEX_OUTPUT_STEREO
//};
