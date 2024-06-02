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