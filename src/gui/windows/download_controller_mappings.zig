const std = @import("std");

const main = @import("root");
const files = main.files;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const CheckBox = @import("../components/CheckBox.zig");
const Label = @import("../components/Label.zig");
const VerticalList = @import("../components/VerticalList.zig");
const HorizontalList = @import("../components/HorizontalList.zig");

pub var window = GuiWindow {
	.contentSize = Vec2f{128, 64},
	.pos = Vec2f{0, 0},
	.showTitleBar = false,
	.hasBackground = true,
	.closeable = false
};

const padding: f32 = 8;
pub fn update() void {
	window.relativePosition[0].ratio = 1.0;
	window.relativePosition[1].ratio = 1.0;
	if (main.Window.Gamepad.wereControllerMappingsDownloaded()) {
		gui.closeWindowFromRef(&window);
	}
}
pub fn onOpen() void {
	const label = Label.init(.{padding, 16 + padding}, 128, "Downloading controller mappings...", .center);
	window.rootComponent = label.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	window.pos[1] = 0.0;
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}
