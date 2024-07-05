#version 430

in vec3 mvVertexPos;
in vec3 direction;
in vec2 uv;
flat in vec3 normal;
flat in uint textureIndexOffset;
flat in int isBackFace;
flat in int ditherSeed;
flat in uint lightBufferIndex;
flat in uvec2 lightArea;
in vec2 lightPosition;

uniform sampler2DArray texture_sampler;
uniform sampler2DArray emissionSampler;
uniform sampler2DArray reflectivityAndAbsorptionSampler;
uniform samplerCube reflectionMap;
uniform float reflectionMapSize;
uniform float contrast;
uniform vec3 ambientLight;

layout(location = 0) out vec4 fragColor;

layout(std430, binding = 1) buffer _animatedTexture
{
	float animatedTexture[];
};

struct FogData {
	float fogDensity;
	uint fogColor;
};

layout(std430, binding = 7) buffer _fogData
{
	FogData fogData[];
};

layout(std430, binding = 10) buffer _lightData
{
	uint lightData[];
};

layout(std430, binding = 11) buffer _textureData
{
	uint textureData[];
};

float lightVariation(vec3 normal) {
	const vec3 directionalPart = vec3(0, contrast/2, contrast);
	const float baseLighting = 1 - contrast;
	return baseLighting + dot(normal, directionalPart);
}

float ditherThresholds[16] = float[16] (
	1/17.0, 9/17.0, 3/17.0, 11/17.0,
	13/17.0, 5/17.0, 15/17.0, 7/17.0,
	4/17.0, 12/17.0, 2/17.0, 10/17.0,
	16/17.0, 8/17.0, 14/17.0, 6/17.0
);

ivec2 random1to2(int v) {
	ivec4 fac = ivec4(11248723, 105436839, 45399083, 5412951);
	int seed = v.x*fac.x ^ fac.y;
	return seed*fac.zw;
}

bool passDitherTest(float alpha) {
	ivec2 screenPos = ivec2(gl_FragCoord.xy);
	screenPos += random1to2(ditherSeed);
	screenPos &= 3;
	return alpha > ditherThresholds[screenPos.x*4 + screenPos.y];
}

vec4 fixedCubeMapLookup(vec3 v) { // Taken from http://the-witness.net/news/2012/02/seamless-cube-map-filtering/
	float M = max(max(abs(v.x), abs(v.y)), abs(v.z));
	float scale = (reflectionMapSize - 1)/reflectionMapSize;
	if (abs(v.x) != M) v.x *= scale;
	if (abs(v.y) != M) v.y *= scale;
	if (abs(v.z) != M) v.z *= scale;
	return texture(reflectionMap, v);
}

vec3 unpack15BitLight(uint val) {
	return vec3(
		val >> 10 & 31u,
		val >> 5 & 31u,
		val & 31u
	);
}

vec3 readLightValue() {
	uint x = clamp(uint(lightPosition.x), 0, lightArea.x - 1);
	uint y = clamp(uint(lightPosition.y), 0, lightArea.y - 1);
	uint light00 = lightData[lightBufferIndex + (x*lightArea.y + y)];
	uint light01 = lightData[lightBufferIndex + (x*lightArea.y + y + 1)];
	uint light10 = lightData[lightBufferIndex + ((x + 1)*lightArea.y + y)];
	uint light11 = lightData[lightBufferIndex + ((x + 1)*lightArea.y + y + 1)];
	float xFactor = lightPosition.x - x;
	float yFactor = lightPosition.y - y;
	vec3 sunLight = mix(
		mix(unpack15BitLight(light00 >> 15), unpack15BitLight(light01 >> 15), yFactor),
		mix(unpack15BitLight(light10 >> 15), unpack15BitLight(light11 >> 15), yFactor),
		xFactor
	);
	vec3 blockLight = mix(
		mix(unpack15BitLight(light00), unpack15BitLight(light01), yFactor),
		mix(unpack15BitLight(light10), unpack15BitLight(light11), yFactor),
		xFactor
	);
	return max(sunLight*ambientLight, blockLight)/31;
}

uint readTextureIndex() {
	uint x = clamp(uint(lightPosition.x), 0, lightArea.x - 2);
	uint y = clamp(uint(lightPosition.y), 0, lightArea.y - 2);
	uint index = textureIndexOffset + x*(lightArea.y - 1) + y;
	return textureData[index >> 1] >> 16*(index & 1u) & 65535u;
}

void main() {
	vec3 light = readLightValue();
	uint textureIndex = readTextureIndex();
	float animatedTextureIndex = animatedTexture[textureIndex];
	float normalVariation = lightVariation(normal);
	vec3 textureCoords = vec3(uv, animatedTextureIndex);
	float reflectivity = texture(reflectivityAndAbsorptionSampler, textureCoords).a;
	vec3 pixelLight = max(light*normalVariation, texture(emissionSampler, textureCoords).r*4);
	fragColor = texture(texture_sampler, textureCoords)*vec4(pixelLight, 1);
	fragColor.rgb += (reflectivity*fixedCubeMapLookup(reflect(direction, normal)).xyz)*pixelLight;

	if(!passDitherTest(fragColor.a)) discard;
	fragColor.a = 1;
}
