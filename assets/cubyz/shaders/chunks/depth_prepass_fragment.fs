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

layout(std430, binding = 1) buffer _animatedTexture
{
	float animatedTexture[];
};

layout(std430, binding = 11) buffer _textureData
{
	uint textureData[];
};

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

uint readTextureIndex() {
	uint x = clamp(uint(lightPosition.x), 0, lightArea.x - 2);
	uint y = clamp(uint(lightPosition.y), 0, lightArea.y - 2);
	uint index = textureIndexOffset + x*(lightArea.y - 1) + y;
	return textureData[index >> 1] >> 16*(index & 1u) & 65535u;
}

void main() {
	uint textureIndex = readTextureIndex();
	float animatedTextureIndex = animatedTexture[textureIndex];
	vec3 textureCoords = vec3(uv, animatedTextureIndex);
	float alpha = texture(texture_sampler, textureCoords).a;
	if(!passDitherTest(alpha)) discard;
}
