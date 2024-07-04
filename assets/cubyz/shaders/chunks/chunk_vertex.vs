#version 460

out vec3 mvVertexPos;
out vec3 direction;
out vec3 light;
out vec2 uv;
flat out vec3 normal;
flat out int textureIndex;
flat out int isBackFace;
flat out int ditherSeed;

uniform vec3 ambientLight;
uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform ivec3 playerPositionInteger;
uniform vec3 playerPositionFraction;
uniform bool transparent; // TODO: Make this a macro constant

struct FaceData {
	int encodedPosition;
	int textureAndQuad;
	uint lightBufferIndex;
};
layout(std430, binding = 3) buffer _faceData
{
	FaceData faceData[];
};
layout(std430, binding = 10) buffer _lightData
{
	uint lightData[];
};

struct QuadInfo {
	vec3 normal;
	vec3 corners[4];
	vec2 cornerUV[4];
	uint textureSlot;
};

layout(std430, binding = 4) buffer _quads
{
	QuadInfo quads[];
};

struct ChunkData {
	ivec4 position;
	vec4 minPos;
	vec4 maxPos;
	int visibilityMask;
	int voxelSize;
	uint vertexStartOpaque;
	uint lightStartOpaque;
	uint faceCountsByNormalOpaque[7];
	uint vertexStartTransparent;
	uint lightStartTransparent;
	uint vertexCountTransparent;
	uint visibilityState;
	uint oldVisibilityState;
};

layout(std430, binding = 6) buffer _chunks
{
	ChunkData chunks[];
};

const vec3[6] normals = vec3[6](
	vec3(0, 0, 1),
	vec3(0, 0, -1),
	vec3(1, 0, 0),
	vec3(-1, 0, 0),
	vec3(0, 1, 0),
	vec3(0, -1, 0)
);
const ivec3[6] textureX = ivec3[6](
	ivec3(1, 0, 0),
	ivec3(-1, 0, 0),
	ivec3(0, -1, 0),
	ivec3(0, 1, 0),
	ivec3(1, 0, 0),
	ivec3(-1, 0, 0)
);
const ivec3[6] textureY = ivec3[6](
	ivec3(0, 1, 0),
	ivec3(0, 1, 0),
	ivec3(0, 0, -1),
	ivec3(0, 0, -1),
	ivec3(0, 0, -1),
	ivec3(0, 0, -1)
);

void main() {
	int faceID = gl_VertexID >> 2;
	int vertexID = gl_VertexID & 3;
	int chunkID = gl_BaseInstance;
	int visibilityMask = chunks[chunkID].visibilityMask;
	int voxelSize = chunks[chunkID].voxelSize;
	vec3 modelPosition = vec3(chunks[chunkID].position.xyz - playerPositionInteger) - playerPositionFraction;
	int encodedPosition = faceData[faceID].encodedPosition;
	int textureAndQuad = faceData[faceID].textureAndQuad;
	uint fullLight = lightData[(transparent ? chunks[chunkID].lightStartTransparent : chunks[chunkID].lightStartOpaque) + faceData[faceID].lightBufferIndex + vertexID];
//	int fullLight = faceData[faceID].light[vertexID];
	vec3 sunLight = vec3(
		fullLight >> 25 & 31u,
		fullLight >> 20 & 31u,
		fullLight >> 15 & 31u
	);
	vec3 blockLight = vec3(
		fullLight >> 10 & 31u,
		fullLight >> 5 & 31u,
		fullLight >> 0 & 31u
	);
	light = max(sunLight*ambientLight, blockLight)/31;
	isBackFace = encodedPosition>>19 & 1;
	ditherSeed = encodedPosition & 15;

	textureIndex = textureAndQuad & 65535;
	int quadIndex = textureAndQuad >> 16;

	vec3 position = vec3(
		encodedPosition & 31,
		encodedPosition >> 5 & 31,
		encodedPosition >> 10 & 31
	);
	int octantIndex = (int(position.x) >> 4) | (int(position.y) >> 4)<<1 | (int(position.z) >> 4)<<2;
	if((visibilityMask & 1<<octantIndex) == 0) { // discard face
		gl_Position = vec4(-2, -2, -2, 1);
		return;
	}

	normal = quads[quadIndex].normal;
	
	position += quads[quadIndex].corners[vertexID];
	position *= voxelSize;
	position += modelPosition;

	direction = position;

	vec4 mvPos = viewMatrix*vec4(position, 1);
	gl_Position = projectionMatrix*mvPos;
	mvVertexPos = mvPos.xyz;
	uv = quads[quadIndex].cornerUV[vertexID]*voxelSize;
}