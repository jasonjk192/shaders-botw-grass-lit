#ifndef GRASS_GBUFFERLIT_HLSL
#define GRASS_GBUFFERLIT_HLSL

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityGBuffer.hlsl"
#include "./LitInput.hlsl"
#include "./Common.hlsl"

#if defined(_PARALLAXMAP) && (SHADER_TARGET >= 30)
#define REQUIRES_TANGENT_SPACE_VIEW_DIR_INTERPOLATOR
#endif

#if (defined(_NORMALMAP) || (defined(_PARALLAXMAP) && !defined(REQUIRES_TANGENT_SPACE_VIEW_DIR_INTERPOLATOR))) || defined(_DETAIL)
#define REQUIRES_WORLD_SPACE_TANGENT_INTERPOLATOR
#endif

// keep this file in sync with LitForwardPass.hlsl

struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float2 texcoord : TEXCOORD0;
    float2 staticLightmapUV : TEXCOORD1;
    float2 dynamicLightmapUV : TEXCOORD2;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float2 uv : TEXCOORD0;

#if defined(REQUIRES_WORLD_SPACE_POS_INTERPOLATOR)
    float3 positionWS               : TEXCOORD1;
#endif

    half3 normalWS : TEXCOORD2;
#if defined(REQUIRES_WORLD_SPACE_TANGENT_INTERPOLATOR)
    half4 tangentWS                 : TEXCOORD3;    // xyz: tangent, w: sign
#endif
#ifdef _ADDITIONAL_LIGHTS_VERTEX
    half3 vertexLighting            : TEXCOORD4;    // xyz: vertex lighting
#endif

#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
    float4 shadowCoord              : TEXCOORD5;
#endif

#if defined(REQUIRES_TANGENT_SPACE_VIEW_DIR_INTERPOLATOR)
    half3 viewDirTS                 : TEXCOORD6;
#endif

    DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 7);
#ifdef DYNAMICLIGHTMAP_ON
    float2  dynamicLightmapUV       : TEXCOORD8; // Dynamic lightmap UVs
#endif

float4 positionCS : SV_POSITION;
UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

void InitializeGBufferLitInputData(Varyings input, half3 normalTS, out InputData inputData)
{
    inputData = (InputData) 0;

#if defined(REQUIRES_WORLD_SPACE_POS_INTERPOLATOR)
        inputData.positionWS = input.positionWS;
#endif

    inputData.positionCS = input.positionCS;
    half3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
#if defined(_NORMALMAP) || defined(_DETAIL)
        float sgn = input.tangentWS.w;      // should be either +1 or -1
        float3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
        inputData.normalWS = TransformTangentToWorld(normalTS, half3x3(input.tangentWS.xyz, bitangent.xyz, input.normalWS.xyz));
#else
    inputData.normalWS = input.normalWS;
#endif

    inputData.normalWS = NormalizeNormalPerPixel(inputData.normalWS);
    inputData.viewDirectionWS = viewDirWS;

#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
        inputData.shadowCoord = input.shadowCoord;
#elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
        inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);
#else
    inputData.shadowCoord = float4(0, 0, 0, 0);
#endif

    inputData.fogCoord = 0.0; // we don't apply fog in the guffer pass

#ifdef _ADDITIONAL_LIGHTS_VERTEX
        inputData.vertexLighting = input.vertexLighting.xyz;
#else
    inputData.vertexLighting = half3(0, 0, 0);
#endif

#if defined(DYNAMICLIGHTMAP_ON)
    inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.dynamicLightmapUV, input.vertexSH, inputData.normalWS);
#else
    inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.vertexSH, inputData.normalWS);
#endif

    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
    inputData.shadowMask = SAMPLE_SHADOWMASK(input.staticLightmapUV);
}



Attributes vert(Attributes v)
{
    //VertexOutput o;
    //o.vertex = TransformObjectToHClip(v.vertex.xyz);
    //o.normal = v.normal;
    //o.tangent = v.tangent;
    //o.uv = TRANSFORM_TEX(v.uv, _GrassMap);
    //return o;
    v.positionOS = TransformObjectToHClip(v.positionOS.xyz);
    v.texcoord = TRANSFORM_TEX(v.texcoord, _GrassMap);
    return v;
}

// Vertex shader which just passes data to tessellation stage.
Attributes tessVert(Attributes v)
{
    return v;
}

// Vertex shader which translates from object to world space.
Attributes geomVert(Attributes v)
{
    //VertexOutput o;
    //o.vertex = float4(TransformObjectToWorld(v.vertex.xyz), 1.0f);
    //o.normal = TransformObjectToWorldNormal(v.normal).xyz;
    //o.tangent = v.tangent;
    //o.uv = TRANSFORM_TEX(v.uv, _GrassMap);
    //return o;
    v.positionOS = float4(TransformObjectToWorld(v.positionOS.xyz), 1.0f);
    v.normalOS = TransformObjectToWorldNormal(v.normalOS).xyz;
    v.texcoord = TRANSFORM_TEX(v.texcoord, _GrassMap);
    return v;
}

// This function lets us derive the tessellation factor for an edge
// from the vertices.
float tessellationEdgeFactor(Attributes vert0, Attributes vert1)
{
    float3 v0 = vert0.positionOS.xyz; //vert0.vertex.xyz;
    float3 v1 = vert1.positionOS.xyz; //vert1.vertex.xyz;
    float edgeLength = distance(v0, v1);
    return edgeLength / _TessellationGrassDistance;
}

// This is a test version of the tessellation that takes distance from the viewer
// into account. It works fine, but I think it could do with refinement.
float tessellationEdgeFactor_distanceTest(Attributes vert0, Attributes vert1)
{
    float3 v0 = vert0.positionOS.xyz; //vert0.vertex.xyz;
    float3 v1 = vert1.positionOS.xyz; //vert1.vertex.xyz;
    float edgeLength = distance(v0, v1);

    float3 edgeCenter = (v0 + v1) * 0.5f;
    float viewDist = distance(edgeCenter, _WorldSpaceCameraPos) / 10.0f;

    return edgeLength * _ScreenParams.y / (_TessellationGrassDistance * viewDist);
}

// Tessellation hull and domain shaders derived from Catlike Coding's tutorial:
// https://catlikecoding.com/unity/tutorials/advanced-rendering/tessellation/

// The patch constant function is where we create new control
// points on the patch. For the edges, increasing the tessellation
// factors adds new vertices on the edge. Increasing the inside
// will add more 'layers' inside the new triangle.
TessellationFactors patchConstantFunc(InputPatch<Attributes, 3> patch)
{
    TessellationFactors f;

    f.edge[0] = tessellationEdgeFactor(patch[1], patch[2]);
    f.edge[1] = tessellationEdgeFactor(patch[2], patch[0]);
    f.edge[2] = tessellationEdgeFactor(patch[0], patch[1]);
    f.inside = (f.edge[0] + f.edge[1] + f.edge[2]) / 3.0f;

    return f;
}

// The hull function is the first half of the tessellation shader.
// It operates on each patch (in our case, a patch is a triangle),
// and outputs new control points for the other tessellation stages.
//
// The patch constant function is where we create new control points
// (which are kind of like new vertices).
[domain("tri")]
[outputcontrolpoints(3)]
[outputtopology("triangle_cw")]
[partitioning("integer")]
[patchconstantfunc("patchConstantFunc")]
Attributes hull(InputPatch<Attributes, 3> patch, uint id : SV_OutputControlPointID)
{
    return patch[id];
}

// In between the hull shader stage and the domain shader stage, the
// tessellation stage takes place. This is where, under the hood,
// the graphics pipeline actually generates the new vertices.

// The domain function is the second half of the tessellation shader.
// It interpolates the properties of the vertices (position, normal, etc.)
// to create new vertices.
[domain("tri")]
Attributes domain(TessellationFactors factors, OutputPatch<Attributes, 3> patch, float3 barycentricCoordinates : SV_DomainLocation)
{
    Attributes i = (Attributes) 0;

#define INTERPOLATE(fieldname) i.fieldname = \
					patch[0].fieldname * barycentricCoordinates.x + \
					patch[1].fieldname * barycentricCoordinates.y + \
					patch[2].fieldname * barycentricCoordinates.z;

    INTERPOLATE(positionOS)
	INTERPOLATE(normalOS)
	INTERPOLATE(tangentOS)
	INTERPOLATE(texcoord)

    return tessVert(i);
}

// Geometry functions derived from Roystan's tutorial:
// https://roystan.net/articles/grass-shader.html

// This function applies a transformation (during the geometry shader),
// converting to clip space in the process.
Varyings TransformGeomToClip(float3 pos, float3 offset, float3x3 transformationMatrix, float2 uv, Attributes input)
{
    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
    VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
    Varyings o = (Varyings) 0;

    // Unless required, we will just pass along the uv as is so that we can lerp the color of grass blades
    o.uv = uv;
    //o.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
    o.positionWS = TransformObjectToWorld(pos + mul(transformationMatrix, offset));
    o.positionCS = TransformWorldToHClip(o.positionWS);
    o.normalWS = normalInput.normalWS;
    
#if defined(REQUIRES_WORLD_SPACE_TANGENT_INTERPOLATOR)
    o.tangentWS = normalInput.tangentWS;
#endif
    
    OUTPUT_LIGHTMAP_UV(input.lightmapUV, unity_LightmapST, o.lightmapUV);
    OUTPUT_SH(o.normalWS.xyz, o.vertexSH);
    return o;
}

// This is the geometry shader. For each vertex on the mesh, a leaf
// blade is created by generating additional vertices.
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

		// Rotate around the y-axis a random amount.
        float3x3 randRotMatrix = angleAxis3x3(rand(pos) * UNITY_TWO_PI, float3(0, 0, 1.0f));

		// Rotate around the bottom of the blade a random amount.
        float3x3 randBendMatrix = angleAxis3x3(rand(pos.zzx) * _BendDelta * UNITY_PI * 0.5f, float3(-1.0f, 0, 0));

        float2 windUV = pos.xz * _WindMap_ST.xy + _WindMap_ST.zw + normalize(_WindVelocity.xzy).xy * _WindFrequency * _Time.y;
        float2 tex2dwindsample = SAMPLE_TEXTURE2D_LOD(_WindMap, sampler_WindMap, windUV, 0).xy;
        float2 windSample = (tex2dwindsample.xy * 2 - 1).xy * length(_WindVelocity);

        float3 windAxis = normalize(float3(windSample.x, windSample.y, 0));
        float3x3 windMatrix = angleAxis3x3(UNITY_PI * windSample.x, windAxis);

		// Transform the grass blades to the correct tangent space.
        float3x3 baseTransformationMatrix = mul(tangentToLocal, randRotMatrix);
        float3x3 tipTransformationMatrix = mul(mul(mul(tangentToLocal, windMatrix), randBendMatrix), randRotMatrix);

        float falloff = smoothstep(_GrassThreshold, _GrassThreshold + _GrassFalloff, grassVisibility);

        float width = lerp(_BladeWidthMin, _BladeWidthMax, rand(pos.xzy) * falloff);
        float height = lerp(_BladeHeightMin, _BladeHeightMax, rand(pos.zyx) * falloff);
        float forward = rand(pos.yyz) * _BladeBendDistance;

		// Create blade segments by adding two vertices at once.
        for (int i = 0; i < BLADE_SEGMENTS; ++i)
        {
            float t = i / (float) BLADE_SEGMENTS;
            float3 offset = float3(width * (1 - t), pow(t, _BladeBendCurve) * forward, height * t);

            float3x3 transformationMatrix = (i == 0) ? baseTransformationMatrix : tipTransformationMatrix;

            triStream.Append(TransformGeomToClip(pos, float3(offset.x, offset.y, offset.z), transformationMatrix, float2(0, t), input[0]));
            triStream.Append(TransformGeomToClip(pos, float3(-offset.x, offset.y, offset.z), transformationMatrix, float2(1, t), input[0]));
        }

		// Add the final vertex at the tip of the grass blade.
        triStream.Append(TransformGeomToClip(pos, float3(0, forward, height), tipTransformationMatrix, float2(0.5, 1), input[0]));

        triStream.RestartStrip();
    }
}
	
// The lighting sections of the frag shader taken from this helpful post by Ben Golus:
// https://forum.unity.com/threads/water-shader-graph-transparency-and-shadows-universal-render-pipeline-order.748142/#post-5518747
// We've modified this section so that we can pass the required params to URP's functions for lighting calculations

FragmentOutput frag(Varyings IN) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(IN);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

#if defined(_PARALLAXMAP)
#if defined(REQUIRES_TANGENT_SPACE_VIEW_DIR_INTERPOLATOR)
    half3 viewDirTS = IN.viewDirTS;
#else
    half3 viewDirWS = GetWorldSpaceNormalizeViewDir(IN.positionWS);
    half3 viewDirTS = GetViewDirectionTangentSpace(IN.tangentWS, IN.normalWS, viewDirWS);
#endif
    ApplyPerPixelDisplacement(viewDirTS, IN.uv);
#endif

    SurfaceData surfaceData;
    InitializeStandardLitSurfaceData(IN.uv, surfaceData);

#ifdef LOD_FADE_CROSSFADE
    LODFadeCrossFade(IN.positionCS);
#endif

    InputData inputData;
    InitializeGBufferLitInputData(IN, surfaceData.normalTS, inputData);

    BRDFData brdfData;
    InitializeBRDFData(surfaceData.albedo, surfaceData.metallic, surfaceData.specular, surfaceData.smoothness, surfaceData.alpha, brdfData);
    half oneMinusReflectivity = half(1.0) - brdfData.reflectivity;
    brdfData.diffuse = lerp(brdfData.diffuse, _GrassTipColor.rgb * oneMinusReflectivity, IN.uv.y);
    brdfData.albedo = lerp(brdfData.albedo, _GrassTipColor.rgb, IN.uv.y);

    Light mainLight = GetMainLight(inputData.shadowCoord, inputData.positionWS, inputData.shadowMask);
    MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI, inputData.shadowMask);
    half3 color = GlobalIllumination(brdfData, inputData.bakedGI, surfaceData.occlusion, inputData.positionWS, inputData.normalWS, inputData.viewDirectionWS);
    
    return BRDFDataToGbuffer(brdfData, inputData, surfaceData.smoothness, surfaceData.emission + color, surfaceData.occlusion);
}

#endif