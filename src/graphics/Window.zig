const std = @import("std");

const main = @import("root");
const vec = main.vec;
const Vec2f = vec.Vec2f;
pub var lastUsedMouse = true;
pub const c = @cImport ({
	@cInclude("glad/glad.h");
	@cInclude("GLFW/glfw3.h");
});

var isFullscreen: bool = false;
pub var width: u31 = 1280;
pub var height: u31 = 720;
pub var window: *c.GLFWwindow = undefined;
pub var grabbed: bool = false;

pub var scrollOffset: f32 = 0;
var gamepadState: ?std.AutoHashMap(c_int, *c.GLFWgamepadstate) = null;
pub fn updateGamepadState() void {
	var jid: c_int = 0;
	if (gamepadState == null) {
		return;
	}
	while (jid < c.GLFW_JOYSTICK_LAST) {
		var oldGamepadState: ?[]c.GLFWgamepadstate = null;
		if (gamepadState.?.contains(jid)) {
			oldGamepadState = main.globalAllocator.dupe(c.GLFWgamepadstate, &.{gamepadState.?.get(jid).?.*});
		}
		if (c.glfwJoystickPresent(jid) != 0 and c.glfwJoystickIsGamepad(jid) != 0) {
			if (!gamepadState.?.contains(jid)) {
				gamepadState.?.put(jid, main.globalAllocator.create(c.GLFWgamepadstate)) catch unreachable;
			}
			_ = c.glfwGetGamepadState(jid, gamepadState.?.get(jid).?);
			var oldState: c.GLFWgamepadstate = std.mem.zeroes(c.GLFWgamepadstate);
			if (oldGamepadState != null) {
				oldState = oldGamepadState.?[0];
			}
			const newState = gamepadState.?.get(jid);
			for(&main.KeyBoard.keys) |*key| {
				if(key.gamepadAxis == null) {
					if(key.gamepadButton >= 0) {
						const oldPressed = oldState.buttons[@intCast(key.gamepadButton)] != 0;
						const newPressed = newState.?.*.buttons[@intCast(key.gamepadButton)] != 0;
						if(oldPressed != newPressed) {
							key.pressed = newPressed;
							if(newPressed) {
								key.value = 1.0;
							} else {
								key.value = 0.0;
							}
							if(key.pressed) {
								if(key.pressAction) |pressAction| {
									pressAction();
								}
							} else {
								if(key.releaseAction) |releaseAction| {
									releaseAction();
								}
							}
						}
					}
				} else {
					const axis = key.gamepadAxis.?.axis;
					const positive = key.gamepadAxis.?.positive;
					var newAxis = newState.?.*.axes[@intCast(axis)];
					var oldAxis = oldState.axes[@intCast(axis)];
					if(!positive) {
						newAxis *= -1;
						oldAxis *= -1;
					}
					if(newAxis < 0.0) {
						newAxis = 0.0;
					}
					if(oldAxis < 0.0) {
						oldAxis = 0.0;
					}
					const oldPressed = oldAxis > 0.5;
					const newPressed = newAxis > 0.5;
					if (oldPressed != newPressed) {
						key.pressed = newPressed;
						if (newPressed) {
							if (key.pressAction) |pressAction| {
								pressAction();
							}
						} else {
							if (key.releaseAction) |releaseAction| {
								releaseAction();
							}
						}
					}
					if (newAxis != oldAxis) {
						key.value = newAxis;
					}
				}
			}
		} else {
			if (gamepadState.?.contains(jid)) {
				main.globalAllocator.destroy(gamepadState.?.get(jid).?);
				_ = gamepadState.?.remove(jid);
			}
			if (oldGamepadState != null) {
				const oldState = oldGamepadState.?[0];
				for(&main.KeyBoard.keys) |*key| {
					if(key.gamepadAxis == null) {
						if(key.gamepadButton >= 0) {
							const oldPressed = oldState.buttons[@intCast(key.gamepadButton)] != 0;
							const newPressed = false;
							if(oldPressed != newPressed) {
								key.pressed = newPressed;
								if(newPressed) {
									key.value = 1.0;
								} else {
									key.value = 0.0;
								}
								if(key.pressed) {
									if(key.pressAction) |pressAction| {
										pressAction();
									}
								} else {
									if(key.releaseAction) |releaseAction| {
										releaseAction();
									}
								}
							}
						}
					} else {
						const axis = key.gamepadAxis.?.axis;
						const positive = key.gamepadAxis.?.positive;
						var oldAxis = oldState.axes[@intCast(axis)];
						if(!positive) {
							oldAxis *= -1;
						}
						const newAxis = 0.0;
						if(oldAxis < 0.0) {
							oldAxis = 0.0;
						}
						const oldPressed = oldAxis > 0.5;
						const newPressed = newAxis > 0.5;
						if (oldPressed != newPressed) {
							key.pressed = newPressed;
							if (newPressed) {
								if (key.pressAction) |pressAction| {
									pressAction();
								}
							} else {
								if (key.releaseAction) |releaseAction| {
									releaseAction();
								}
							}
						}
						if (newAxis != oldAxis) {
							key.value = newAxis;
						}
					}
				}
			}
		}
		if (oldGamepadState != null) {
			main.globalAllocator.free(oldGamepadState.?);
		}
		jid += 1;
	}
}
pub const GamepadAxis = struct {
	axis: c_int,
	positive: bool = true
};
pub const Key = struct { // MARK: Key
	name: []const u8,
	pressed: bool = false,
	value: f32 = 0.0,
	key: c_int = c.GLFW_KEY_UNKNOWN,
	gamepadAxis: ?GamepadAxis = null,
	gamepadButton: c_int = -1,
	mouseButton: c_int = -1,
	scancode: c_int = 0,
	releaseAction: ?*const fn() void = null,
	pressAction: ?*const fn() void = null,
	repeatAction: ?*const fn(Modifiers) void = null,

	pub const Modifiers = packed struct(u6) {
		shift: bool = false,
		control: bool = false,
		alt: bool = false,
		super: bool = false,
		capsLock: bool = false,
		numLock: bool = false,
	};
	pub fn getGamepadName(self: Key) []const u8 {
		if(self.gamepadAxis != null) {
			const positive = self.gamepadAxis.?.positive;
			return switch(self.gamepadAxis.?.axis) {
				c.GLFW_GAMEPAD_AXIS_LEFT_X => if(positive) "Left stick right" else "Left stick left",
				c.GLFW_GAMEPAD_AXIS_RIGHT_X => if(positive) "Right stick right" else "Right stick left",
				c.GLFW_GAMEPAD_AXIS_LEFT_Y => if(positive) "Left stick down" else "Left stick up",
				c.GLFW_GAMEPAD_AXIS_RIGHT_Y => if(positive) "Right stick down" else "Right stick up",
				c.GLFW_GAMEPAD_AXIS_LEFT_TRIGGER => if(positive) "Left trigger" else "Left trigger (Negative)",
				c.GLFW_GAMEPAD_AXIS_RIGHT_TRIGGER => if(positive) "Right trigger" else "Right trigger (Negative)",
				else => "(Invalid axis)"
			};
		} else {
			return switch(self.gamepadButton) {
				c.GLFW_GAMEPAD_BUTTON_A => "A",
				c.GLFW_GAMEPAD_BUTTON_B => "B",
				c.GLFW_GAMEPAD_BUTTON_X => "X",
				c.GLFW_GAMEPAD_BUTTON_Y => "Y",
				c.GLFW_GAMEPAD_BUTTON_BACK => "Back",
				c.GLFW_GAMEPAD_BUTTON_DPAD_DOWN => "Down",
				c.GLFW_GAMEPAD_BUTTON_DPAD_LEFT => "Left",
				c.GLFW_GAMEPAD_BUTTON_DPAD_RIGHT => "Right",
				c.GLFW_GAMEPAD_BUTTON_DPAD_UP => "Up",
				c.GLFW_GAMEPAD_BUTTON_GUIDE => "Guide",
				c.GLFW_GAMEPAD_BUTTON_LEFT_BUMPER => "Left bumper",
				c.GLFW_GAMEPAD_BUTTON_LEFT_THUMB => "Left stick press",
				c.GLFW_GAMEPAD_BUTTON_RIGHT_BUMPER => "Right bumper",
				c.GLFW_GAMEPAD_BUTTON_RIGHT_THUMB => "Right stick press",
				c.GLFW_GAMEPAD_BUTTON_START => "Start",
				else => "(Unrecognized button)"
			};
		}
	}

	pub fn getName(self: Key) []const u8 {
		if(self.mouseButton == -1) {
			const cName = c.glfwGetKeyName(self.key, self.scancode);
			if(cName != null) return std.mem.span(cName);
			return switch(self.key) {
				c.GLFW_KEY_SPACE => "Space",
				c.GLFW_KEY_GRAVE_ACCENT => "Grave Accent",
				c.GLFW_KEY_ESCAPE => "Escape",
				c.GLFW_KEY_ENTER => "Enter",
				c.GLFW_KEY_TAB => "Tab",
				c.GLFW_KEY_BACKSPACE => "Backspace",
				c.GLFW_KEY_INSERT => "Insert",
				c.GLFW_KEY_DELETE => "Delete",
				c.GLFW_KEY_RIGHT => "Right",
				c.GLFW_KEY_LEFT => "Left",
				c.GLFW_KEY_DOWN => "Down",
				c.GLFW_KEY_UP => "Up",
				c.GLFW_KEY_PAGE_UP => "Page Up",
				c.GLFW_KEY_PAGE_DOWN => "Page Down",
				c.GLFW_KEY_HOME => "Home",
				c.GLFW_KEY_END => "End",
				c.GLFW_KEY_CAPS_LOCK => "Caps Lock",
				c.GLFW_KEY_SCROLL_LOCK => "Scroll Lock",
				c.GLFW_KEY_NUM_LOCK => "Num Lock",
				c.GLFW_KEY_PRINT_SCREEN => "Print Screen",
				c.GLFW_KEY_PAUSE => "Pause",
				c.GLFW_KEY_F1 => "F1",
				c.GLFW_KEY_F2 => "F2",
				c.GLFW_KEY_F3 => "F3",
				c.GLFW_KEY_F4 => "F4",
				c.GLFW_KEY_F5 => "F5",
				c.GLFW_KEY_F6 => "F6",
				c.GLFW_KEY_F7 => "F7",
				c.GLFW_KEY_F8 => "F8",
				c.GLFW_KEY_F9 => "F9",
				c.GLFW_KEY_F10 => "F10",
				c.GLFW_KEY_F11 => "F11",
				c.GLFW_KEY_F12 => "F12",
				c.GLFW_KEY_F13 => "F13",
				c.GLFW_KEY_F14 => "F14",
				c.GLFW_KEY_F15 => "F15",
				c.GLFW_KEY_F16 => "F16",
				c.GLFW_KEY_F17 => "F17",
				c.GLFW_KEY_F18 => "F18",
				c.GLFW_KEY_F19 => "F19",
				c.GLFW_KEY_F20 => "F20",
				c.GLFW_KEY_F21 => "F21",
				c.GLFW_KEY_F22 => "F22",
				c.GLFW_KEY_F23 => "F23",
				c.GLFW_KEY_F24 => "F24",
				c.GLFW_KEY_F25 => "F25",
				c.GLFW_KEY_KP_ENTER => "Keypad Enter",
				c.GLFW_KEY_LEFT_SHIFT => "Left Shift",
				c.GLFW_KEY_LEFT_CONTROL => "Left Control",
				c.GLFW_KEY_LEFT_ALT => "Left Alt",
				c.GLFW_KEY_LEFT_SUPER => "Left Super",
				c.GLFW_KEY_RIGHT_SHIFT => "Right Shift",
				c.GLFW_KEY_RIGHT_CONTROL => "Right Control",
				c.GLFW_KEY_RIGHT_ALT => "Right Alt",
				c.GLFW_KEY_RIGHT_SUPER => "Right Super",
				c.GLFW_KEY_MENU => "Menu",
				else => "Unknown Key",
			};
		} else {
			return switch(self.mouseButton) {
				c.GLFW_MOUSE_BUTTON_LEFT => "Left Button",
				c.GLFW_MOUSE_BUTTON_MIDDLE => "Middle Button",
				c.GLFW_MOUSE_BUTTON_RIGHT => "Right Button",
				else => "Other Mouse Button",
			};
		}
	}
};

pub const GLFWCallbacks = struct { // MARK: GLFWCallbacks
	fn errorCallback(errorCode: c_int, description: [*c]const u8) callconv(.C) void {
		std.log.err("GLFW Error({}): {s}", .{errorCode, description});
	}
	fn keyCallback(_: ?*c.GLFWwindow, glfw_key: c_int, scancode: c_int, action: c_int, _mods: c_int) callconv(.C) void {
		const mods: Key.Modifiers = @bitCast(@as(u6, @intCast(_mods)));
		if(!mods.control and main.gui.selectedTextInput != null and c.glfwGetKeyName(glfw_key, scancode) != null) return; // Don't send events for keys that are used in writing letters.
		if(action == c.GLFW_PRESS) {
			for(&main.KeyBoard.keys) |*key| {
				if(glfw_key == key.key) {
					if(glfw_key != c.GLFW_KEY_UNKNOWN or scancode == key.scancode) {
						key.pressed = true;
						key.value = 1.0;
						if(key.pressAction) |pressAction| {
							pressAction();
						}
						if(key.repeatAction) |repeatAction| {
							repeatAction(mods);
						}
					}
				}
			}
			if(nextKeypressListener) |listener| {
				listener(glfw_key, -1, scancode);
				nextKeypressListener = null;
			}
		} else if(action == c.GLFW_RELEASE) {
			for(&main.KeyBoard.keys) |*key| {
				if(glfw_key == key.key) {
					if(glfw_key != c.GLFW_KEY_UNKNOWN or scancode == key.scancode) {
						key.pressed = false;
						key.value = 0.0;
						if(key.releaseAction) |releaseAction| {
							releaseAction();
						}
					}
				}
			}
		} else if(action == c.GLFW_REPEAT) {
			for(&main.KeyBoard.keys) |*key| {
				if(glfw_key == key.key) {
					if(glfw_key != c.GLFW_KEY_UNKNOWN or scancode == key.scancode) {
						if(key.repeatAction) |repeatAction| {
							repeatAction(mods);
						}
					}
				}
			}
		}
	}
	fn charCallback(_: ?*c.GLFWwindow, codepoint: c_uint) callconv(.C) void {
		if(!grabbed) {
			main.gui.textCallbacks.char(@intCast(codepoint));
		}
	}

	pub fn framebufferSize(_: ?*c.GLFWwindow, newWidth: c_int, newHeight: c_int) callconv(.C) void {
		std.log.info("Framebuffer: {}, {}", .{newWidth, newHeight});
		width = @intCast(newWidth);
		height = @intCast(newHeight);
		main.renderer.updateViewport(width, height, main.settings.fov);
		main.gui.updateGuiScale();
		main.gui.updateWindowPositions();
	}
	// Mouse deltas are averaged over multiple frames using a circular buffer:
	const deltasLen: u2 = 3;
	var deltas: [deltasLen]Vec2f = [_]Vec2f{Vec2f{0, 0}} ** 3;
	var deltaBufferPosition: u2 = 0;
	var currentPos: Vec2f = Vec2f{0, 0};
	var ignoreDataAfterRecentGrab: bool = true;
	fn cursorPosition(_: ?*c.GLFWwindow, x: f64, y: f64) callconv(.C) void {
		const newPos = Vec2f {
			@floatCast(x),
			@floatCast(y),
		};
		if(grabbed and !ignoreDataAfterRecentGrab) {
			deltas[deltaBufferPosition] += (newPos - currentPos)*@as(Vec2f, @splat(main.settings.mouseSensitivity));
			var averagedDelta: Vec2f = Vec2f{0, 0};
			for(deltas) |delta| {
				averagedDelta += delta;
			}
			averagedDelta /= @splat(deltasLen);
			main.game.camera.moveRotation(averagedDelta[0]*0.0089, averagedDelta[1]*0.0089);
			deltaBufferPosition = (deltaBufferPosition + 1)%deltasLen;
			deltas[deltaBufferPosition] = Vec2f{0, 0};
		}
		ignoreDataAfterRecentGrab = false;
		currentPos = newPos;
		lastUsedMouse = true;
	}
	fn mouseButton(_: ?*c.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.C) void {
		_ = mods;
		if(action == c.GLFW_PRESS) {
			for(&main.KeyBoard.keys) |*key| {
				if(button == key.mouseButton) {
					key.pressed = true;
					key.value = 1.0;
					if(key.pressAction) |pressAction| {
						pressAction();
					}
				}
			}
			if(nextKeypressListener) |listener| {
				listener(c.GLFW_KEY_UNKNOWN, button, 0);
				nextKeypressListener = null;
			}
		} else if(action == c.GLFW_RELEASE) {
			for(&main.KeyBoard.keys) |*key| {
				if(button == key.mouseButton) {
					key.pressed = false;
					key.value = 0.0;
					if(key.releaseAction) |releaseAction| {
						releaseAction();
					}
				}
			}
		}
	}
	fn scroll(_ : ?*c.GLFWwindow, xOffset: f64, yOffset: f64) callconv(.C) void {
		_ = xOffset;
		scrollOffset += @floatCast(yOffset);
	}
	fn glDebugOutput(source: c_uint, typ: c_uint, _: c_uint, severity: c_uint, length: c_int, message: [*c]const u8, _: ?*const anyopaque) callconv(.C) void {
		const sourceString: []const u8 = switch (source) {
			c.GL_DEBUG_SOURCE_API => "API",
			c.GL_DEBUG_SOURCE_APPLICATION => "Application",
			c.GL_DEBUG_SOURCE_OTHER => "Other",
			c.GL_DEBUG_SOURCE_SHADER_COMPILER => "Shader Compiler",
			c.GL_DEBUG_SOURCE_THIRD_PARTY => "Third Party",
			c.GL_DEBUG_SOURCE_WINDOW_SYSTEM => "Window System",
			else => "Unknown",
		};
		const typeString: []const u8 = switch (typ) {
			c.GL_DEBUG_TYPE_DEPRECATED_BEHAVIOR => "deprecated behavior",
			c.GL_DEBUG_TYPE_ERROR => "error",
			c.GL_DEBUG_TYPE_MARKER => "marker",
			c.GL_DEBUG_TYPE_OTHER => "other",
			c.GL_DEBUG_TYPE_PERFORMANCE => "performance",
			c.GL_DEBUG_TYPE_POP_GROUP => "pop group",
			c.GL_DEBUG_TYPE_PORTABILITY => "portability",
			c.GL_DEBUG_TYPE_PUSH_GROUP => "push group",
			c.GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR => "undefined behavior",
			else => "unknown",
		};
		switch (severity) {
			c.GL_DEBUG_SEVERITY_HIGH => {
				std.log.err("OpenGL {s} {s}: {s}", .{sourceString, typeString, message[0..@intCast(length)]});
			},
			else => {
				std.log.warn("OpenGL {s} {s}: {s}", .{sourceString, typeString, message[0..@intCast(length)]});
			},
		}
	}
};

var nextKeypressListener: ?*const fn(c_int, c_int, c_int) void = null;
pub fn setNextKeypressListener(listener: ?*const fn(c_int, c_int, c_int) void) !void {
	if(nextKeypressListener != null) return error.AlreadyUsed;
	nextKeypressListener = listener;
}

fn updateCursor() void {
	if (grabbed) {

		c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
			// Behavior seems much more intended without this line on MacOS.
			// Perhaps this is an inconsistency in GLFW due to its fresh XQuartz support?
			if(@import("builtin").target.os.tag != .macos) {
				if (c.glfwRawMouseMotionSupported() != 0)
					c.glfwSetInputMode(window, c.GLFW_RAW_MOUSE_MOTION, c.GLFW_TRUE);
			}
			GLFWCallbacks.ignoreDataAfterRecentGrab = true;
	} else {
		if (cursorVisible) {
			c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_NORMAL);
		} else {
			c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_HIDDEN);
		}
	}
}

pub fn setMouseGrabbed(grab: bool) void {
	if(grabbed != grab) {
		grabbed = grab;
		updateCursor();
	}
}

pub fn getMousePosition() Vec2f {
	return GLFWCallbacks.currentPos;
}

pub fn getWindowSize() Vec2f {
	return Vec2f{@floatFromInt(width), @floatFromInt(height)};
}

pub fn reloadSettings() void {
	c.glfwSwapInterval(@intFromBool(main.settings.vsync));
}

pub fn getClipboardString() []const u8 {
	return std.mem.span(c.glfwGetClipboardString(window) orelse @as([*c]const u8, ""));
}

pub fn setClipboardString(string: []const u8) void {
	const nullTerminatedString = main.stackAllocator.dupeZ(u8, string);
	defer main.stackAllocator.free(nullTerminatedString);
	c.glfwSetClipboardString(window, nullTerminatedString.ptr);
}

pub fn init() void { // MARK: init()
	_ = c.glfwSetErrorCallback(GLFWCallbacks.errorCallback);

	if(c.glfwInit() == 0) {
		@panic("Failed to initialize GLFW");
	}

	c.glfwWindowHint(c.GLFW_OPENGL_DEBUG_CONTEXT, 1);
	c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 4);
	c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 6);

	window = c.glfwCreateWindow(width, height, "Cubyz", null, null) orelse @panic("Failed to create GLFW window");
	iconBlock: {
		const image = main.graphics.Image.readUnflippedFromFile(main.stackAllocator, "logo.png") catch |err| {
			std.log.err("Error loading logo: {s}", .{@errorName(err)});
			break :iconBlock;
		};
		defer image.deinit(main.stackAllocator);
		const glfwImage: c.GLFWimage = .{
			.pixels = @ptrCast(image.imageData.ptr),
			.width = image.width,
			.height = image.height,
		};
		c.glfwSetWindowIcon(window, 1, &glfwImage);
	}

	_ = c.glfwSetKeyCallback(window, GLFWCallbacks.keyCallback);
	_ = c.glfwSetCharCallback(window, GLFWCallbacks.charCallback);
	_ = c.glfwSetFramebufferSizeCallback(window, GLFWCallbacks.framebufferSize);
	_ = c.glfwSetCursorPosCallback(window, GLFWCallbacks.cursorPosition);
	_ = c.glfwSetMouseButtonCallback(window, GLFWCallbacks.mouseButton);
	_ = c.glfwSetScrollCallback(window, GLFWCallbacks.scroll);

	c.glfwMakeContextCurrent(window);

	if(c.gladLoadGL() == 0) {
		@panic("Failed to load OpenGL functions from GLAD");
	}
	reloadSettings();

	c.glEnable(c.GL_DEBUG_OUTPUT);
	c.glEnable(c.GL_DEBUG_OUTPUT_SYNCHRONOUS);
	c.glDebugMessageCallback(GLFWCallbacks.glDebugOutput, null);
	c.glDebugMessageControl(c.GL_DONT_CARE, c.GL_DONT_CARE, c.GL_DONT_CARE, 0, null, c.GL_TRUE);
	if (std.fs.selfExeDirPathAlloc(main.globalAllocator.allocator) catch null) |selfExeDirPath| {
		if (std.fs.path.join(main.globalAllocator.allocator, &.{selfExeDirPath, "gamecontrollerdb.txt"}) catch null) |mappings_path| {
			if (std.fs.openFileAbsolute(mappings_path, .{.mode = .read_only}) catch null) |file| {
				const data = main.globalAllocator.alloc(u8, file.getEndPos() catch 0);
				const size = file.readAll(data) catch 0;
				if (size > 0) {
					_ = main.globalAllocator.resize(data, size);
					_ = c.glfwUpdateGamepadMappings(@ptrCast(data));
				}
				main.globalAllocator.free(data);
			}
			main.globalAllocator.free(mappings_path);
		}
		main.globalAllocator.free(selfExeDirPath);
	}
	gamepadState = std.AutoHashMap(c_int, *c.GLFWgamepadstate).init(main.globalAllocator.allocator);
	updateGamepadState();
	std.log.debug("Gamepads at init: {d}", .{gamepadState.?.count()});
}

pub fn deinit() void {
	const iter = gamepadState.?.keyIterator();
	var i: usize = 0;
	while (i < iter.len) {
		const key = iter.items[i];
		const value = gamepadState.?.get(key);
		if (value != null) {
			main.globalAllocator.destroy(value.?);
			_ = gamepadState.?.remove(key);
		}
		i += 1;
	}
	gamepadState.?.deinit();
	gamepadState = null;
	c.glfwDestroyWindow(window);
	c.glfwTerminate();
}
var cursorVisible: bool = true;
pub fn setCursorVisible(visible: bool) void {
	if (cursorVisible != visible) {
		cursorVisible = visible;
		updateCursor();
	}
}

pub fn handleEvents() void {
	scrollOffset = 0;
	c.glfwPollEvents();
	if (gamepadState == null) {
		std.log.err("gamepadState was null.", .{});
		return;
	}
	updateGamepadState();
	if (!grabbed) {
		const x = main.KeyBoard.key("uiRight").value - main.KeyBoard.key("uiLeft").value;
		const y = main.KeyBoard.key("uiDown").value - main.KeyBoard.key("uiUp").value;
		if (x != 0 and y != 0) {
			lastUsedMouse = false;
			GLFWCallbacks.currentPos[0] += x;
			GLFWCallbacks.currentPos[1] += y;
		}
	}
	setCursorVisible(!grabbed and lastUsedMouse);
}

var oldX: c_int = 0;
var oldY: c_int = 0;
var oldWidth: c_int = 0;
var oldHeight: c_int = 0;
pub fn toggleFullscreen() void {
	isFullscreen = !isFullscreen;
	if (isFullscreen) {
		c.glfwGetWindowPos(window, &oldX, &oldY);
		c.glfwGetWindowSize(window, &oldWidth, &oldHeight);
		const monitor = c.glfwGetPrimaryMonitor();
		if(monitor == null) {
			isFullscreen = false;
			return;
		}
		const vidMode = c.glfwGetVideoMode(monitor).?;
		c.glfwSetWindowMonitor(window, monitor, 0, 0, vidMode[0].width, vidMode[0].height, c.GLFW_DONT_CARE);
	} else {
		c.glfwSetWindowMonitor(window, null, oldX, oldY, oldWidth, oldHeight, c.GLFW_DONT_CARE);
		c.glfwSetWindowAttrib(window, c.GLFW_DECORATED, c.GLFW_TRUE);
	}
}
