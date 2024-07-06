const std = @import("std");

const main = @import("root");
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const GuiComponent = gui.GuiComponent;

pub var window = GuiWindow {
	.relativePosition = .{
		.{ .attachedToFrame = .{.selfAttachmentPoint = .lower, .otherAttachmentPoint = .lower} },
		.{ .attachedToFrame = .{.selfAttachmentPoint = .lower, .otherAttachmentPoint = .lower} },
	},
	.contentSize = Vec2f{128, 16},
	.isHud = false,
	.showTitleBar = false,
	.hasBackground = false,
	.hideIfMouseIsGrabbed = false,
};

fn renderLargeBufferSize(buffer: anytype, comptime fmt: []const u8, y: f32) void {
	const dataSize: usize = @sizeOf(@TypeOf(buffer).Entry);
	const size: usize = buffer.capacity*dataSize;
	const used: usize = buffer.used*dataSize;
	var largestFreeBlock: usize = 0;
	for(buffer.freeBlocks.items) |freeBlock| {
		largestFreeBlock = @max(largestFreeBlock, freeBlock.len);
	}
	const fragmentation = size - used - largestFreeBlock*dataSize;
	draw.print(fmt, .{used >> 20, size >> 20, fragmentation >> 20}, 0, y, 8, .left);
}

pub fn render() void {
	draw.setColor(0xffffffff);
	var y: f32 = 0;
	const fpsCapText = if(main.settings.fpsCap) |fpsCap| std.fmt.allocPrint(main.stackAllocator.allocator, " (limit: {d:.0} Hz)", .{fpsCap}) catch unreachable else "";
	defer main.stackAllocator.allocator.free(fpsCapText);
	const fpsLimit = std.fmt.allocPrint(main.stackAllocator.allocator, "{s}{s}", .{
		fpsCapText,
		if(main.settings.vsync) " (vsync)" else "",
	}) catch unreachable;
	defer main.stackAllocator.allocator.free(fpsLimit);
	draw.print("fps: {d:.0} Hz{s}", .{1.0/main.lastDeltaTime.load(.monotonic), fpsLimit}, 0, y, 8, .left);
	y += 8;
	draw.print("frameTime: {d:.1} ms", .{main.lastFrameTime.load(.monotonic)*1000.0}, 0, y, 8, .left);
	y += 8;
	draw.print("window size: {}×{}", .{main.Window.width, main.Window.height}, 0, y, 8, .left);
	y += 8;
	if (main.game.world != null) {
		draw.print("Pos: {d:.1}", .{main.game.Player.getPosBlocking()}, 0, y, 8, .left);
		y += 8;
		draw.print("Game Time: {}", .{main.game.world.?.gameTime.load(.monotonic)}, 0, y, 8, .left);
		y += 8;
		draw.print("Queue size: {}", .{main.threadPool.queueSize()}, 0, y, 8, .left);
		y += 8;
		draw.print("Mesh Queue size: {}", .{main.renderer.mesh_storage.updatableList.items.len}, 0, y, 8, .left);
		y += 8;
		renderLargeBufferSize(main.renderer.chunk_meshing.faceBuffer, "ChunkMesh memory: {} MiB / {} MiB (fragmentation: {} MiB)", y);
		y += 8;
		renderLargeBufferSize(main.renderer.chunk_meshing.lightBuffer, "ChunkMesh light memory: {} MiB / {} MiB (fragmentation: {} MiB)", y);
		y += 8;
		renderLargeBufferSize(main.renderer.chunk_meshing.textureBuffer, "ChunkMesh texture memory: {} MiB / {} MiB (fragmentation: {} MiB)", y);
		y += 8;
		draw.print("Biome: {s}", .{main.game.world.?.playerBiome.load(.monotonic).id}, 0, y, 8, .left);
		y += 8;
		draw.print("Opaque faces: {}, Transparent faces: {}", .{main.renderer.chunk_meshing.quadsDrawn, main.renderer.chunk_meshing.transparentQuadsDrawn}, 0, y, 8, .left);
		y += 8;
	}
}
