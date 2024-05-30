// Most of the original code in the .shader file is moved to this file
// Various structs have been replaced with Unity's one so that we can just put in the required data and pass it to Unity defined functions to calculate the lighting

#ifndef GRASS_LIT_HLSL
#define GRASS_LIT_HLSL

#include "Support.hlsl"

// Following functions from Roystan's code:
// (https://github.com/IronWarrior/UnityGrassGeometryShader)

// Regular vertex shader used by typical shaders.
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
    Attributes i = (Attributes)0;

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
    Varyings o = (Varyings)0;

    // Unless required, we will just pass along the uv as is so that we can lerp the color of grass blades
    o.uv = uv;
    //o.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
    o.positionWS = TransformObjectToWorld(pos + mul(transformationMatrix, offset));
    o.positionCS = TransformWorldToHClip(o.positionWS);
    o.normalWS = normalInput.normalWS;
    
#if defined(REQUIRES_WORLD_SPACE_TANGENT_INTERPOLATOR)
    o.tangentWS = normalInput.tangentWS;
#endif
    
#ifdef _ADDITIONAL_LIGHTS_VERTEX
    float3 vertexLight = VertexLighting(vertexInput.positionWS, normalInput.normalWS);
    float fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
    o.fogFactorAndVertexLight = float4(fogFactor, vertexLight);
#else
    o.fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
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

float4 frag(Varyings IN) : SV_Target
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
    InitializeInputData(IN, surfaceData.normalTS, inputData);
    half4 color = GrassFragmentPBR(inputData, surfaceData, IN.uv);

    #ifdef _WRITE_RENDERING_LAYERS
        uint renderingLayers = GetMeshRenderingLightLayer();
        outRenderingLayers = float4(EncodeMeshRenderingLayer(renderingLayers), 0, 0, 0);
    #endif
    
    color.rgb = MixFog(color.rgb, inputData.fogCoord);
   
    return color;
}

#endif