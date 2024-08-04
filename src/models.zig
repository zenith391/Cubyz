const std = @import("std");

const chunk = @import("chunk.zig");
const Neighbors = chunk.Neighbors;
const graphics = @import("graphics.zig");
const main = @import("main.zig");
const vec = @import("vec.zig");
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;
const Vec2f = vec.Vec2f;
const Mat4f = vec.Mat4f;
const FaceData = main.renderer.chunk_meshing.FaceData;
const NeverFailingAllocator = main.utils.NeverFailingAllocator;

var quadSSBO: graphics.SSBO = undefined;

pub const QuadInfo = extern struct {
	normal: Vec3f,
	corners: [4]Vec3f,
	cornerUV: [4]Vec2f,
	textureSlot: u32,
};

const ExtraQuadInfo = struct {
	faceNeighbor: ?u3,
	isFullQuad: bool,
	hasOnlyCornerVertices: bool,
	alignedNormalDirection: ?u3,
};

const gridSize = 4096;

fn snapToGrid(x: anytype) @TypeOf(x) {
	const T = @TypeOf(x);
	const int = @as(@Vector(@typeInfo(T).Vector.len, i32), @intFromFloat(std.math.round(x*@as(T, @splat(gridSize)))));
	return @as(T, @floatFromInt(int))/@as(T, @splat(gridSize));
}

const Triangle = struct {
	vertex: [3]usize,
	normals: [3]usize,
	uvs: [3]usize,
};

const Quad = struct {
	vertex: [4]usize,
	normals: [4]usize,
	uvs: [4]usize,
};

pub const Model = struct {
	min: Vec3f,
	max: Vec3f,
	internalQuads: []u16,
	neighborFacingQuads: [6][]u16,
	isNeighborOccluded: [6]bool,
	allNeighborsOccluded: bool,
	noNeighborsOccluded: bool,
	hasNeighborFacingQuads: bool,

	fn getFaceNeighbor(quad: *const QuadInfo) ?u3 {
		var allZero: @Vector(3, bool) = .{true, true, true};
		var allOne: @Vector(3, bool) = .{true, true, true};
		for(quad.corners) |corner| {
			allZero = @select(bool, allZero, corner == @as(Vec3f, @splat(0)), allZero); // vector and TODO: #14306
			allOne = @select(bool, allOne, corner == @as(Vec3f, @splat(1)), allOne); // vector and TODO: #14306
		}
		if(allZero[0]) return Neighbors.dirNegX;
		if(allZero[1]) return Neighbors.dirNegY;
		if(allZero[2]) return Neighbors.dirDown;
		if(allOne[0]) return Neighbors.dirPosX;
		if(allOne[1]) return Neighbors.dirPosY;
		if(allOne[2]) return Neighbors.dirUp;
		return null;
	}

	fn fullyOccludesNeighbor(quad: *const QuadInfo) bool {
		var zeroes: @Vector(3, u32) = .{0, 0, 0};
		var ones: @Vector(3, u32) = .{0, 0, 0};
		for(quad.corners) |corner| {
			zeroes += @select(u32, corner == @as(Vec3f, @splat(0)), .{1, 1, 1}, .{0, 0, 0});
			ones += @select(u32, corner == @as(Vec3f, @splat(1)), .{1, 1, 1}, .{0, 0, 0});
		}
		// For full coverage there will 2 ones and 2 zeroes for two components, while the other one is constant.
		const hasTwoZeroes = zeroes == @Vector(3, u32){2, 2, 2};
		const hasTwoOnes = ones == @Vector(3, u32){2, 2, 2};
		return @popCount(@as(u3, @bitCast(hasTwoOnes))) == 2 and @popCount(@as(u3, @bitCast(hasTwoZeroes))) == 2;
	}



	pub fn init(quadInfos: []const QuadInfo) u16 {
		const adjustedQuads = main.stackAllocator.alloc(QuadInfo, quadInfos.len);
		defer main.stackAllocator.free(adjustedQuads);
		for(adjustedQuads, quadInfos) |*dest, *src| {
			dest.* = src.*;
			// Snap all values to a fixed point grid to make comparisons more accurate.
			for(&dest.corners) |*corner| {
				corner.* = snapToGrid(corner.*);
			}
			for(&dest.cornerUV) |*uv| {
				uv.* = snapToGrid(uv.*);
			}
			// Snap the normals as well:
			dest.normal = snapToGrid(dest.normal);
		}
		const modelIndex: u16 = @intCast(models.items.len);
		const self = models.addOne();
		var amounts: [6]usize = .{0, 0, 0, 0, 0, 0};
		var internalAmount: usize = 0;
		self.min = .{1, 1, 1};
		self.max = .{0, 0, 0};
		self.isNeighborOccluded = .{false} ** 6;
		for(adjustedQuads) |*quad| {
			for(quad.corners) |corner| {
				self.min = @min(self.min, corner);
				self.max = @max(self.max, corner);
			}
			if(getFaceNeighbor(quad)) |neighbor| {
				amounts[neighbor] += 1;
			} else {
				internalAmount += 1;
			}
		}

		for(0..6) |i| {
			self.neighborFacingQuads[i] = main.globalAllocator.alloc(u16, amounts[i]);
		}
		self.internalQuads = main.globalAllocator.alloc(u16, internalAmount);

		var indices: [6]usize = .{0, 0, 0, 0, 0, 0};
		var internalIndex: usize = 0;
		for(adjustedQuads) |_quad| {
			var quad = _quad;
			if(getFaceNeighbor(&quad)) |neighbor| {
				for(&quad.corners) |*corner| {
					corner.* -= quad.normal;
				}
				const quadIndex = addQuad(quad);
				self.neighborFacingQuads[neighbor][indices[neighbor]] = quadIndex;
				indices[neighbor] += 1;
			} else {
				const quadIndex = addQuad(quad);
				self.internalQuads[internalIndex] = quadIndex;
				internalIndex += 1;
			}
		}
		self.hasNeighborFacingQuads = false;
		self.allNeighborsOccluded = true;
		self.noNeighborsOccluded = true;
		for(0..6) |neighbor| {
			for(self.neighborFacingQuads[neighbor]) |quad| {
				if(fullyOccludesNeighbor(&quads.items[quad])) {
					self.isNeighborOccluded[neighbor] = true;
				}
			}
			self.hasNeighborFacingQuads = self.hasNeighborFacingQuads or self.neighborFacingQuads[neighbor].len != 0;
			self.allNeighborsOccluded = self.allNeighborsOccluded and self.isNeighborOccluded[neighbor];
			self.noNeighborsOccluded = self.noNeighborsOccluded and !self.isNeighborOccluded[neighbor];
		}
		return modelIndex;
	}

	pub fn loadModel(data: []const u8) u16 {
		var vertices = main.List(Vec3f).init(main.stackAllocator);
		defer vertices.deinit();

		var normals = main.List(Vec3f).init(main.stackAllocator);
		defer normals.deinit();

		var uvs = main.List(Vec2f).init(main.stackAllocator);
		defer uvs.deinit();

		var tris = main.List(Triangle).init(main.stackAllocator);
		defer tris.deinit();

		var quadFaces = main.List(Quad).init(main.stackAllocator);
		defer quadFaces.deinit();

		var fixed_buffer = std.io.fixedBufferStream(data);
		var buf_reader = std.io.bufferedReader(fixed_buffer.reader());
		var in_stream = buf_reader.reader();
		var buf: [128]u8 = undefined;
		while (in_stream.readUntilDelimiterOrEof(&buf, '\n') catch |e| blk: {
			std.log.err("Error reading line while loading model: {any}", .{e});
			break :blk null;
		}) |lineUntrimmed| {
			if (lineUntrimmed.len < 3)
				continue;
			
			var line = lineUntrimmed;
			if (line[line.len - 1] == '\r') {
				line = line[0..line.len - 1];
			}
			
			if (line[0] == '#')
				continue;
			
			if (std.mem.eql(u8, line[0..2], "v ")) {
				var coordsIter = std.mem.split(u8, line[2..], " ");
				var coords: Vec3f = undefined;
				var i: usize = 0;
				while (coordsIter.next()) |coord| : (i += 1) {
					coords[i] = std.fmt.parseFloat(f32, coord) catch |e| blk: { std.log.err("Failed parsing {s} into float: {any}", .{coord, e}); break :blk 0; };
				}
				const coordsCorrect: Vec3f = .{coords[0] + 0.5, -coords[2] + 0.5, coords[1]};
				vertices.append(coordsCorrect);
			} else if (std.mem.eql(u8, line[0..3], "vn ")) {
				var coordsIter = std.mem.split(u8, line[3..], " ");
				var norm: Vec3f = undefined;
				var i: usize = 0;
				while (coordsIter.next()) |coord| : (i += 1) {
					norm[i] = std.fmt.parseFloat(f32, coord) catch |e| blk: { std.log.err("Failed parsing {s} into float: {any}", .{coord, e}); break :blk 0; };
				}
				const normCorrect: Vec3f = .{norm[0], -norm[2], norm[1]};
				normals.append(normCorrect);
			} else if (std.mem.eql(u8, line[0..3], "vt ")) {
				var coordsIter = std.mem.split(u8, line[3..], " ");
				var uv: Vec2f = undefined;
				var i: usize = 0;
				while (coordsIter.next()) |coord| : (i += 1) {
					uv[i] = std.fmt.parseFloat(f32, coord) catch |e| blk: { std.log.err("Failed parsing {s} into float: {any}", .{coord, e}); break :blk 0; };
				}
				uv[0] *= 4;
				uv[1] *= 4;
				uvs.append(.{uv[0], uv[1]});
			} else if (std.mem.eql(u8, line[0..2], "f ")) {
				const n = std.mem.count(u8, line[2..], " ") + 1;
				switch (n) {
					3 => {
						var coordsIter = std.mem.split(u8, line[2..], " ");
						var faceData: [3][3]usize = undefined;
						var i: usize = 0;
						var failed = false;
						while (coordsIter.next()) |vertex| : (i += 1) {
							var d = std.mem.split(u8, vertex, "/");
							var j: usize = 0;
							if (std.mem.count(u8, vertex, "/") != 2 or std.mem.count(u8, vertex, "//") != 0) {
								failed = true;
								std.log.err("Failed loading face {s}. Each vertex must use vertex/uv/normal", .{line, n});
								break;
							}
							while (d.next()) |value| : (j += 1) {
								faceData[j][i] = std.fmt.parseUnsigned(usize, value, 10) catch |e| blk: { std.log.err("Failed parsing {s} into uint: {any}", .{value, e}); break :blk 1; };
								faceData[j][i] -= 1;
							}
						}
						if (!failed)
							tris.append(.{.vertex=faceData[0], .uvs=faceData[1], .normals=faceData[2]});
					},
					4 => {
						var coordsIter = std.mem.split(u8, line[2..], " ");
						var faceData: [3][4]usize = undefined;
						var i: usize = 0;
						var failed = false;
						while (coordsIter.next()) |vertex| : (i += 1) {
							var d = std.mem.split(u8, vertex, "/");
							var j: usize = 0;
							if (std.mem.count(u8, vertex, "/") != 2 or std.mem.count(u8, vertex, "//") != 0) {
								failed = true;
								std.log.err("Failed loading face {s}. Each vertex must use vertex/uv/normal", .{line, n});
								break;
							}
							while (d.next()) |value| : (j += 1) {
								faceData[j][i] = std.fmt.parseUnsigned(usize, value, 10) catch |e| blk: { std.log.err("Failed parsing {s} into uint: {any}", .{value, e}); break :blk 1; };
								faceData[j][i] -= 1;
							}
						}
						if (!failed)
							quadFaces.append(.{.vertex=faceData[0], .uvs=faceData[1], .normals=faceData[2]});
					},
					else => std.log.err("Failed loading face {s} with {d} vertices", .{line, n})
				}
			}
		}

		var quadInfos = main.List(QuadInfo).init(main.stackAllocator);
		defer quadInfos.deinit();

		for (tris.items) |face| {
			const normal: Vec3f = normals.items[face.normals[0]];
			
			var uvA: Vec2f = uvs.items[face.uvs[0]];
			var uvB: Vec2f = uvs.items[face.uvs[1]];
			var uvC: Vec2f = uvs.items[face.uvs[2]];

			const minUv = @floor(@min(@min(uvA, uvB), uvC));

			if (minUv[0] < 0 or minUv[0] > 4 or minUv[1] < 0 or minUv[1] > 4) {
				std.log.err("Uv value for model is outside of 0-1 range", .{});
				continue;
			}

			const textureSlot = @as(u32, @intFromFloat(@floor(minUv[1]))) * 4 + @as(u32, @intFromFloat(@floor(minUv[0])));

			uvA -= minUv;
			uvB -= minUv;
			uvC -= minUv;
			
			const cornerA: Vec3f = vertices.items[face.vertex[0]];
			var cornerB: Vec3f = vertices.items[face.vertex[1]];
			var cornerC: Vec3f = vertices.items[face.vertex[2]];

			const calcNorm: Vec3f = vec.normalize(vec.cross(cornerB - cornerA, cornerC - cornerA));

			if (vec.dot(normal, calcNorm) < 0) {
				const temp = cornerB;
				cornerB = cornerC;
				cornerC = temp;
			}
			
			quadInfos.append(.{
				.normal = normal,
				.corners = .{cornerA, cornerB, cornerC, cornerB},
				.cornerUV = .{uvA, uvB, uvC, uvB},
				.textureSlot = textureSlot,
			});
		}

		for (quadFaces.items) |face| {
			const normal: Vec3f = normals.items[face.normals[0]];
			
			var uvA: Vec2f = uvs.items[face.uvs[0]];
			var uvB: Vec2f = uvs.items[face.uvs[1]];
			var uvC: Vec2f = uvs.items[face.uvs[2]];
			var uvD: Vec2f = uvs.items[face.uvs[3]];

			const minUv = @floor(@min(@min(uvA, uvB), @min(uvC, uvD)));
			const textureSlot = @as(u32, @intFromFloat(@floor(minUv[1]))) * 4 + @as(u32, @intFromFloat(@floor(minUv[0])));
			
			if (minUv[0] < 0 or minUv[0] > 4 or minUv[1] < 0 or minUv[1] > 4) {
				std.log.err("Uv value for model is outside of 0-1 range", .{});
				continue;
			}

			uvA -= minUv;
			uvB -= minUv;
			uvC -= minUv;
			uvD -= minUv;

			const cornerA: Vec3f = vertices.items[face.vertex[0]];
			const cornerB: Vec3f = vertices.items[face.vertex[1]];
			const cornerC: Vec3f = vertices.items[face.vertex[2]];
			const cornerD: Vec3f = vertices.items[face.vertex[3]];
			
			// const lut = [_]u32{0, 2, 1, 1, 2, 3};
			
			quadInfos.append(.{
				.normal = normal,
				.corners = .{cornerA, cornerB, cornerC, cornerD},
				.cornerUV = .{uvA, uvB, uvC, uvD},
				.textureSlot = textureSlot,
			});
		}

		return Model.init(quadInfos.items);
	}

	fn deinit(self: *const Model) void {
		for(0..6) |i| {
			main.globalAllocator.free(self.neighborFacingQuads[i]);
		}
		main.globalAllocator.free(self.internalQuads);
	}

	fn getRawFaces(model: Model, quadList: *main.List(QuadInfo)) void {
		for(model.internalQuads) |quadIndex| {
			quadList.append(quads.items[quadIndex]);
		}
		for(0..6) |neighbor| {
			for(model.neighborFacingQuads[neighbor]) |quadIndex| {
				var quad = quads.items[quadIndex];
				for(&quad.corners) |*corner| {
					corner.* += quad.normal;
				}
				quadList.append(quad);
			}
		}
	}

	pub fn mergeModels(modelList: []u16) u16 {
		var quadList = main.List(QuadInfo).init(main.stackAllocator);
		defer quadList.deinit();
		for(modelList) |model| {
			models.items[model].getRawFaces(&quadList);
		}
		return Model.init(quadList.items);
	}

	pub fn transformModel(model: Model, transformFunction: anytype, transformFunctionParameters: anytype) u16 {
		var quadList = main.List(QuadInfo).init(main.stackAllocator);
		defer quadList.deinit();
		model.getRawFaces(&quadList);
		for(quadList.items) |*quad| {
			@call(.auto, transformFunction, .{quad} ++ transformFunctionParameters);
		}
		return Model.init(quadList.items);
	}

	fn appendQuadsToList(quadList: []const u16, list: *main.ListUnmanaged(FaceData), allocator: NeverFailingAllocator, block: main.blocks.Block, x: i32, y: i32, z: i32, comptime backFace: bool) void {
		for(quadList) |quadIndex| {
			const texture = main.blocks.meshes.textureIndex(block, quads.items[quadIndex].textureSlot);
			list.append(allocator, FaceData.init(texture, quadIndex, x, y, z, backFace));
		}
	}

	pub fn appendInternalQuadsToList(self: *const Model, list: *main.ListUnmanaged(FaceData), allocator: NeverFailingAllocator, block: main.blocks.Block, x: i32, y: i32, z: i32, comptime backFace: bool) void {
		appendQuadsToList(self.internalQuads, list, allocator, block, x, y, z, backFace);
	}

	pub fn appendNeighborFacingQuadsToList(self: *const Model, list: *main.ListUnmanaged(FaceData), allocator: NeverFailingAllocator, block: main.blocks.Block, neighbor: u3, x: i32, y: i32, z: i32, comptime backFace: bool) void {
		appendQuadsToList(self.neighborFacingQuads[neighbor], list, allocator, block, x, y, z, backFace);
	}
};

var nameToIndex: std.StringHashMap(u16) = undefined;

pub fn getModelIndex(string: []const u8) u16 {
	return nameToIndex.get(string) orelse {
		std.log.warn("Couldn't find voxelModel with name: {s}.", .{string});
		return 0;
	};
}

pub var quads: main.List(QuadInfo) = undefined;
pub var extraQuadInfos: main.List(ExtraQuadInfo) = undefined;
pub var models: main.List(Model) = undefined;
pub var fullCube: u16 = undefined;

var quadDeduplication: std.AutoHashMap([@sizeOf(QuadInfo)]u8, u16) = undefined;

fn addQuad(info: QuadInfo) u16 {
	if(quadDeduplication.get(std.mem.toBytes(info))) |id| {
		return id;
	}
	const index: u16 = @intCast(quads.items.len);
	quads.append(info);
	quadDeduplication.put(std.mem.toBytes(info), index) catch unreachable;

	var extraQuadInfo: ExtraQuadInfo = undefined;
	extraQuadInfo.faceNeighbor = Model.getFaceNeighbor(&info);
	extraQuadInfo.isFullQuad = Model.fullyOccludesNeighbor(&info);
	{
		var zeroes: @Vector(3, u32) = .{0, 0, 0};
		var ones: @Vector(3, u32) = .{0, 0, 0};
		for(info.corners) |corner| {
			zeroes += @select(u32, corner == @as(Vec3f, @splat(0)), .{1, 1, 1}, .{0, 0, 0});
			ones += @select(u32, corner == @as(Vec3f, @splat(1)), .{1, 1, 1}, .{0, 0, 0});
		}
		const cornerValues = @reduce(.Add, zeroes) + @reduce(.Add, ones);
		extraQuadInfo.hasOnlyCornerVertices = cornerValues == 4*3;
	}
	{
		extraQuadInfo.alignedNormalDirection = null;
		if(@reduce(.And, info.normal == Vec3f{-1, 0, 0})) extraQuadInfo.alignedNormalDirection = chunk.Neighbors.dirNegX;
		if(@reduce(.And, info.normal == Vec3f{1, 0, 0})) extraQuadInfo.alignedNormalDirection = chunk.Neighbors.dirPosX;
		if(@reduce(.And, info.normal == Vec3f{0, -1, 0})) extraQuadInfo.alignedNormalDirection = chunk.Neighbors.dirNegY;
		if(@reduce(.And, info.normal == Vec3f{0, 1, 0})) extraQuadInfo.alignedNormalDirection = chunk.Neighbors.dirPosY;
		if(@reduce(.And, info.normal == Vec3f{0, 0, -1})) extraQuadInfo.alignedNormalDirection = chunk.Neighbors.dirDown;
		if(@reduce(.And, info.normal == Vec3f{0, 0, 1})) extraQuadInfo.alignedNormalDirection = chunk.Neighbors.dirUp;
	}
	extraQuadInfos.append(extraQuadInfo);

	return index;
}

fn box(min: Vec3f, max: Vec3f, uvOffset: Vec2f) [6]QuadInfo {
	const corner000: Vec3f = .{min[0], min[1], min[2]};
	const corner001: Vec3f = .{min[0], min[1], max[2]};
	const corner010: Vec3f = .{min[0], max[1], min[2]};
	const corner011: Vec3f = .{min[0], max[1], max[2]};
	const corner100: Vec3f = .{max[0], min[1], min[2]};
	const corner101: Vec3f = .{max[0], min[1], max[2]};
	const corner110: Vec3f = .{max[0], max[1], min[2]};
	const corner111: Vec3f = .{max[0], max[1], max[2]};
	return .{
		.{
			.normal = .{-1, 0, 0},
			.corners = .{corner010, corner011, corner000, corner001},
			.cornerUV = .{uvOffset + Vec2f{1 - max[1], min[2]}, uvOffset + Vec2f{1 - max[1], max[2]}, uvOffset + Vec2f{1 - min[1], min[2]}, uvOffset + Vec2f{1 - min[1], max[2]}},
			.textureSlot = chunk.Neighbors.dirNegX,
		},
		.{
			.normal = .{1, 0, 0},
			.corners = .{corner100, corner101, corner110, corner111},
			.cornerUV = .{uvOffset + Vec2f{min[1], min[2]}, uvOffset + Vec2f{min[1], max[2]}, uvOffset + Vec2f{max[1], min[2]}, uvOffset + Vec2f{max[1], max[2]}},
			.textureSlot = chunk.Neighbors.dirPosX,
		},
		.{
			.normal = .{0, -1, 0},
			.corners = .{corner000, corner001, corner100, corner101},
			.cornerUV = .{uvOffset + Vec2f{min[0], min[2]}, uvOffset + Vec2f{min[0], max[2]}, uvOffset + Vec2f{max[0], min[2]}, uvOffset + Vec2f{max[0], max[2]}},
			.textureSlot = chunk.Neighbors.dirNegY,
		},
		.{
			.normal = .{0, 1, 0},
			.corners = .{corner110, corner111, corner010, corner011},
			.cornerUV = .{uvOffset + Vec2f{1 - max[0], min[2]}, uvOffset + Vec2f{1 - max[0], max[2]}, uvOffset + Vec2f{1 - min[0], min[2]}, uvOffset + Vec2f{1 - min[0], max[2]}},
			.textureSlot = chunk.Neighbors.dirPosY,
		},
		.{
			.normal = .{0, 0, -1},
			.corners = .{corner010, corner000, corner110, corner100},
			.cornerUV = .{uvOffset + Vec2f{min[0], 1 - max[1]}, uvOffset + Vec2f{min[0], 1 - min[1]}, uvOffset + Vec2f{max[0], 1 - max[1]}, uvOffset + Vec2f{max[0], 1 - min[1]}},
			.textureSlot = chunk.Neighbors.dirDown,
		},
		.{
			.normal = .{0, 0, 1},
			.corners = .{corner111, corner101, corner011, corner001},
			.cornerUV = .{uvOffset + Vec2f{1 - max[0], 1 - max[1]}, uvOffset + Vec2f{1 - max[0], 1 - min[1]}, uvOffset + Vec2f{1 - min[0], 1 - max[1]}, uvOffset + Vec2f{1 - min[0], 1 - min[1]}},
			.textureSlot = chunk.Neighbors.dirUp,
		},
	};
}

fn openBox(min: Vec3f, max: Vec3f, uvOffset: Vec2f, openSide: enum{x, y, z}) [4]QuadInfo {
	const fullBox = box(min, max, uvOffset);
	switch(openSide) {
		.x => return fullBox[2..6].*,
		.y => return fullBox[0..2].* ++ fullBox[4..6].*,
		.z => return fullBox[0..4].*,
	}
}

pub fn registerModel(id: []const u8, data: []const u8) u16 {
	const model = Model.loadModel(data);
	nameToIndex.put(id, model) catch unreachable;
	return model;
}

// TODO: Entity models.
pub fn init() void {
	models = main.List(Model).init(main.globalAllocator);
	quads = main.List(QuadInfo).init(main.globalAllocator);
	extraQuadInfos = main.List(ExtraQuadInfo).init(main.globalAllocator);
	quadDeduplication = std.AutoHashMap([@sizeOf(QuadInfo)]u8, u16).init(main.globalAllocator.allocator);

	nameToIndex = std.StringHashMap(u16).init(main.globalAllocator.allocator);

	nameToIndex.put("none", Model.init(&.{})) catch unreachable;

	// const cube = Model.init(&box(.{0, 0, 0}, .{1, 1, 1}, .{0, 0}));
	// nameToIndex.put("cubyz:cube", cube) catch unreachable;
	// Model.exportModel("assets/cubyz/models/cube.obj", cube) catch unreachable;
	// fullCube = cube;

	// const cross = Model.init(&.{
	// 	.{
	// 		.normal = .{-std.math.sqrt1_2, std.math.sqrt1_2, 0},
	// 		.corners = .{.{1, 1, 0}, .{1, 1, 1}, .{0, 0, 0}, .{0, 0, 1}},
	// 		.cornerUV = .{.{0, 0}, .{0, 1}, .{1, 0}, .{1, 1}},
	// 		.textureSlot = 0,
	// 	},
	// 	.{
	// 		.normal = .{std.math.sqrt1_2, -std.math.sqrt1_2, 0},
	// 		.corners = .{.{0, 0, 0}, .{0, 0, 1}, .{1, 1, 0}, .{1, 1, 1}},
	// 		.cornerUV = .{.{0, 0}, .{0, 1}, .{1, 0}, .{1, 1}},
	// 		.textureSlot = 0,
	// 	},
	// 	.{
	// 		.normal = .{-std.math.sqrt1_2, -std.math.sqrt1_2, 0},
	// 		.corners = .{.{0, 1, 0}, .{0, 1, 1}, .{1, 0, 0}, .{1, 0, 1}},
	// 		.cornerUV = .{.{0, 0}, .{0, 1}, .{1, 0}, .{1, 1}},
	// 		.textureSlot = 0,
	// 	},
	// 	.{
	// 		.normal = .{std.math.sqrt1_2, std.math.sqrt1_2, 0},
	// 		.corners = .{.{1, 0, 0}, .{1, 0, 1}, .{0, 1, 0}, .{0, 1, 1}},
	// 		.cornerUV = .{.{0, 0}, .{0, 1}, .{1, 0}, .{1, 1}},
	// 		.textureSlot = 0,
	// 	},
	// });
	// nameToIndex.put("cubyz:cross", cross) catch unreachable;
	// Model.exportModel("assets/cubyz/models/cross.obj", cross) catch unreachable;

	// const swapTopUVs = struct{fn swapTopUVs(_quadInfos: [4]QuadInfo) [4]QuadInfo {
	// 	var quadInfos = _quadInfos;
	// 	for(&quadInfos) |*quad| {
	// 		if(quad.normal[2] != 0) {
	// 			for(&quad.cornerUV) |*uv| {
	// 				std.mem.swap(f32, &uv[0], &uv[1]);
	// 			}
	// 		}
	// 	}
	// 	return quadInfos;
	// }}.swapTopUVs;
	// const fence = Model.init(&(
	// 	box(.{6.0/16.0, 6.0/16.0, 0}, .{10.0/16.0, 10.0/16.0, 1}, .{0, 0})
	// 	++ openBox(.{0, 7.0/16.0, 3.0/16.0}, .{1, 9.0/16.0, 6.0/16.0}, .{0, 0}, .x)
	// 	++ openBox(.{0, 7.0/16.0, 10.0/16.0}, .{1, 9.0/16.0, 13.0/16.0}, .{0, 0}, .x)
	// 	++ swapTopUVs(openBox(.{7.0/16.0, 0, 3.0/16.0}, .{9.0/16.0, 1, 6.0/16.0}, .{0, 0}, .y))
	// 	++ swapTopUVs(openBox(.{7.0/16.0, 0, 10.0/16.0}, .{9.0/16.0, 1, 13.0/16.0}, .{0, 0}, .y))
	// ));
	// Model.exportModel("assets/cubyz/models/fence.obj", fence) catch unreachable;
	// nameToIndex.put("cubyz:fence", fence) catch unreachable;

	// const torch = Model.init(&(openBox(.{7.0/16.0, 7.0/16.0, 0}, .{9.0/16.0, 9.0/16.0, 12.0/16.0}, .{-7.0/16.0, 4.0/16.0}, .z) ++ .{.{
	// 	.normal = .{0, 0, 1},
	// 	.corners = .{.{9.0/16.0, 9.0/16.0, 12.0/16.0}, .{9.0/16.0, 7.0/16.0, 12.0/16.0}, .{7.0/16.0, 9.0/16.0, 12.0/16.0}, .{7.0/16.0, 7.0/16.0, 12.0/16.0}},
	// 	.cornerUV = .{.{0, 2.0/16.0}, .{0, 4.0/16.0}, .{2.0/16.0, 2.0/16.0}, .{2.0/16.0, 4.0/16.0}},
	// 	.textureSlot = chunk.Neighbors.dirUp,
	// }} ++ .{.{
	// 	.normal = .{0, 0, -1},
	// 	.corners = .{.{7.0/16.0, 9.0/16.0, 0}, .{7.0/16.0, 7.0/16.0, 0}, .{9.0/16.0, 9.0/16.0, 0}, .{9.0/16.0, 7.0/16.0, 0}},
	// 	.cornerUV = .{.{0, 0}, .{0, 2.0/16.0}, .{2.0/16.0, 0}, .{2.0/16.0, 2.0/16.0}},
	// 	.textureSlot = chunk.Neighbors.dirDown,
	// }}));
	// Model.exportModel("assets/cubyz/models/torch.obj", torch) catch unreachable;
	// nameToIndex.put("cubyz:torch", torch) catch unreachable;
}

pub fn uploadModels() void {
	quadSSBO = graphics.SSBO.initStatic(QuadInfo, quads.items);
	quadSSBO.bind(4);
}

pub fn deinit() void {
	quadSSBO.deinit();
	nameToIndex.deinit();
	for(models.items) |model| {
		model.deinit();
	}
	models.deinit();
	quads.deinit();
	extraQuadInfos.deinit();
	quadDeduplication.deinit();
}