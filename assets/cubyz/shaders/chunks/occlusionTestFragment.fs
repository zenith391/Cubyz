#version 460

layout(early_fragment_tests) in;

flat in uint chunkID;

struct ChunkData {
	ivec4 position;
	vec4 minPos;
	vec4 maxPos;
	int visibilityMask;
	int voxelSize;
	uint vertexStartOpaque;
	uint lightStartOpaque;
	uint textureStartOpaque;
	uint faceCountsByNormalOpaque[7];
	uint vertexStartTransparent;
	uint lightStartTransparent;
	uint textureStartTransparent;
	uint vertexCountTransparent;
	uint visibilityState;
	uint oldVisibilityState;
};

layout(std430, binding = 6) buffer _chunks
{
	ChunkData chunks[];
};

void main() {
	chunks[chunkID].visibilityState = 1;
}